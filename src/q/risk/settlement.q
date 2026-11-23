/ ============================================================================
/ settlement.q - T+1 Settlement and Freeriding Prevention
/ ============================================================================
/ // Provides:
/   - T+1 settlement tracking for equities (updated May 2024)
/   - Unsettled cash monitoring
/   - Freeriding violation detection (buy with unsettled funds, sell before settlement)
/   - Good faith violation detection (buy, sell, buy cycle with unsettled funds)
/   - Integration with trade execution
/ // Regulatory Context:
/   - SEC Rule T+1: Equities settle 1 business day after trade date (since May 28, 2024)
/   - Reg T: Prohibits freeriding (buying with unsettled funds then selling before settlement)
/   - 3 good faith violations in 12 months = 90-day cash-only restriction
/ // Settlement Timeline:
/   - Trade Date (T): Order executed
/   - Settlement Date (T+1): 1 business day after trade date
/   - Funds available for withdrawal on settlement date
/ // Dependencies:
/   - .exchange.calendar (business day calculation)
/   - .schema.isEquity (asset class detection)
/ // Functions:
/   - initSettlement: Initialize settlement tracking
/   - recordSettlement: Track unsettled cash from trade
/   - checkFreeridingViolation: Pre-trade check for freeriding
/   - getUnsettledCash: Get total unsettled cash
/   - processSettlements: Process settlements (called daily)
/ ============================================================================

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Settlement Configuration and State
/ ═══════════════════════════════════════════════════════════════════

/ Settlement configuration (single-row table)
settlementConfig:([]
  enabled:enlist 1b;
  settlementDays:enlist 1i;  / T+1 for equities (since May 2024)
  maxGoodFaithViolations:enlist 3i;  / 3 violations in 12 months
  violationWindow:enlist 365i;  / Days to track violations
  lastUpdate:enlist .z.p
 );

/ Settlement tracking (append-only)
/ Records all trades with their settlement dates
settlementTracking:([]
  time:`timestamp$();
  tradeDate:`date$();
  settleDate:`date$();
  sym:`symbol$();
  side:`symbol$();  / `buy or `sell
  qty:`float$();
  price:`float$();
  cashProceeds:`float$();  / Cash from sale (negative for purchases)
  settled:`boolean$();  / True once settled
  settledAt:`timestamp$()  / Timestamp when settled
 );

/ Add grouped attribute to sym column for O(1) lookup
update `g#sym from `.risk.settlementTracking;

/ Unsettled cash by settle date (keyed by settleDate)
/ Aggregated view for quick queries
unsettledCash:([settleDate:`date$()]
  totalUnsettled:`float$();
  tradeCount:`int$();
  lastUpdate:`timestamp$()
 );

/ Freeriding violations (append-only)
freeridingViolations:([]
  time:`timestamp$();
  violationType:`symbol$();  / `freeriding, `goodFaith
  sym:`symbol$();
  buyDate:`date$();
  sellDate:`date$();
  settleDate:`date$();
  cashUsed:`float$();
  violation:`boolean$()
 );

/ Good faith violation summary (keyed)
goodFaithSummary:([]
  violationCount:`int$();
  firstViolation:`timestamp$();
  lastViolation:`timestamp$();
  restricted:`boolean$();  / True if 3+ violations in 12 months
  restrictedUntil:`date$()  / 90 days from 3rd violation
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

/ Initialize settlement tracking
/ @return void
initSettlement:{[]
  / Reset state
  delete from `.risk.settlementTracking;
  delete from `.risk.unsettledCash;
  delete from `.risk.freeridingViolations;
  delete from `.risk.goodFaithSummary;

  / Set default config
  update enabled:1b, settlementDays:1i, maxGoodFaithViolations:3i,
         violationWindow:365i, lastUpdate:.z.p from `.risk.settlementConfig;

  / Initialize good faith summary
  `.risk.goodFaithSummary upsert (0i;0Np;0Np;0b;0Nd);

  -1 "  Settlement tracking initialized (T+1)";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Settlement Recording
/ ═══════════════════════════════════════════════════════════════════

/ Record a settlement (call on fill)
/ @param tradeDate date - Trade execution date
/ @param sym symbol - Trading symbol
/ @param side symbol - Order side (`buy or `sell)
/ @param qty float - Quantity
/ @param price float - Execution price
/ @return void
recordSettlement:{[tradeDate;sym;side;qty;price]
  / Only track equities (crypto settles instantly)
  if[not .schema.isEquity[sym]; :()];

  config:first .risk.settlementConfig;

  / Calculate settlement date (T+1 business days)
  settleDate:getSettlementDate[tradeDate;config`settlementDays];

  / Calculate cash proceeds (negative for buys, positive for sells)
  cashProceeds:$[side=`buy; neg qty*price; qty*price];

  / Insert into tracking
  `.risk.settlementTracking insert (.z.p;tradeDate;settleDate;sym;side;qty;price;cashProceeds;0b;0Np);

  / Update unsettled cash aggregate
  updateUnsettledCash[settleDate;cashProceeds];
 };

/ Update unsettled cash aggregate
/ @param settleDate date - Settlement date
/ @param cashChange float - Cash amount (signed)
/ @return void
updateUnsettledCash:{[settleDate;cashChange]
  existing:select from .risk.unsettledCash where settleDate=settleDate;

  if[0=count existing;
    / First entry for this settle date
    `.risk.unsettledCash upsert (settleDate;cashChange;1i;.z.p);
    :();
  ];

  / Update existing
  update totalUnsettled:totalUnsettled+cashChange, tradeCount:tradeCount+1i, lastUpdate:.z.p
    from `.risk.unsettledCash where settleDate=settleDate;
 };

/ Calculate settlement date (T+N business days)
/ @param tradeDate date - Trade date
/ @param days int - Business days to add
/ @return date - Settlement date
getSettlementDate:{[tradeDate;days]
  dt:tradeDate;
  dayCount:0;

  / Move forward N business days
  while[dayCount < days;
    dt:.exchange.calendar.getNextTradingDay[dt];
    dayCount+:1;
  ];

  dt
 };

/ ═══════════════════════════════════════════════════════════════════
/ Daily Settlement Processing
/ ═══════════════════════════════════════════════════════════════════

/ Process settlements (call daily at EOD or BOD)
/ Marks settled trades and removes from unsettled cash
/ @return void
processSettlements:{[]
  today:.z.d;

  / Mark all trades settling today as settled
  update settled:1b, settledAt:.z.p from `.risk.settlementTracking
    where (settleDate <= today) and not settled;

  / Remove settled entries from unsettled cash
  delete from `.risk.unsettledCash where settleDate <= today;

  -1 "Settlements processed for ",string[today];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Freeriding Violation Detection
/ ═══════════════════════════════════════════════════════════════════

/ Check for freeriding violation (pre-trade)
/ Detects: buying with unsettled funds, then selling before settlement
/ @param sym symbol - Trading symbol
/ @param side symbol - Order side (`buy or `sell)
/ @param qty float - Order quantity
/ @param price float - Order price
/ @return (boolean; reason; details) - (pass; reason; details dict)
checkFreeridingViolation:{[sym;side;qty;price]
  config:first .risk.settlementConfig;

  / Skip if disabled
  if[not config`enabled; :(1b;`;())];

  / Only applies to equities
  if[not .schema.isEquity[sym]; :(1b;`;())];

  / Only check on sell orders (freeriding is sell before settlement)
  if[not side=`sell; :(1b;`;())];

  / Get recent buys for this symbol (last 5 days)
  recentBuys:select from .risk.settlementTracking
    where sym=sym, side=`buy, tradeDate >= .z.d-5, not settled;

  / If no unsettled buys, no violation possible
  if[0=count recentBuys; :(1b;`;())];

  / Check if selling quantity exceeds settled position
  / (This is a simplified check — full implementation would track position state)
  unsettledBuyQty:sum exec qty from recentBuys;

  if[qty > unsettledBuyQty;
    / Potential freeriding: selling more than unsettled position
    details:`sym`unsettledBuyQty`sellQty!(sym;unsettledBuyQty;qty);
    `.risk.freeridingViolations insert (.z.p;`freeriding;sym;.z.d;.z.d;0Nd;qty*price;1b);
    :(0b;`freeridingViolation;details)
  ];

  / Pass
  (1b;`;())
 };

/ ═══════════════════════════════════════════════════════════════════
/ Good Faith Violation Detection
/ ═══════════════════════════════════════════════════════════════════

/ Check for good faith violation
/ Pattern: buy, sell, buy again using proceeds from unsettled sale
/ @param sym symbol - Trading symbol
/ @param side symbol - Order side
/ @param qty float - Order quantity
/ @param price float - Order price
/ @return (boolean; reason; details) - (pass; reason; details dict)
checkGoodFaithViolation:{[sym;side;qty;price]
  config:first .risk.settlementConfig;

  / Skip if disabled
  if[not config`enabled; :(1b;`;())];

  / Only applies to equities
  if[not .schema.isEquity[sym]; :(1b;`;())];

  / Only check on buy orders (good faith is buying with unsettled proceeds)
  if[not side=`buy; :(1b;`;())];

  / Get total unsettled cash from sales
  unsettled:getUnsettledCash[];

  / If no unsettled cash, no violation possible
  if[unsettled <= 0.0; :(1b;`;())];

  / Get current cash balance (from margin state)
  cashBalance:first .risk.marginState`cash;

  / If cash balance sufficient to cover purchase, allow
  purchaseCost:.money.mul[.money.new[qty;`USD]; price]`amount;
  if[cashBalance >= purchaseCost; :(1b;`;())];

  / Potential good faith violation: buying with unsettled funds
  `.risk.freeridingViolations insert (.z.p;`goodFaith;sym;.z.d;0Nd;0Nd;purchaseCost;1b);

  / Update good faith summary
  recordGoodFaithViolation[];

  / Check if restricted (3+ violations in 12 months)
  summary:first .risk.goodFaithSummary;
  if[summary`restricted;
    details:`violationCount`restrictedUntil!(summary`violationCount;summary`restrictedUntil);
    :(0b;`goodFaithRestricted;details)
  ];

  / Warn but allow (until 3rd violation)
  -1 "WARNING: Good faith violation detected (",string[summary`violationCount]," violations)";
  (1b;`;())
 };

/ Record good faith violation and check for restriction
/ @return void
recordGoodFaithViolation:{[]
  config:first .risk.settlementConfig;
  summary:first .risk.goodFaithSummary;

  / Count violations in last 12 months
  window:config`violationWindow;
  cutoff:.z.p - window * 24 * 60 * 60 * 1000000000;  / Convert days to nanos
  recentViolations:count select from .risk.freeridingViolations
    where violationType=`goodFaith, time > cutoff;

  / Update summary
  update violationCount:recentViolations, lastViolation:.z.p from `.risk.goodFaithSummary;
  if[summary[`firstViolation] = 0Np; update firstViolation:.z.p from `.risk.goodFaithSummary];

  / Check for restriction (3+ violations)
  if[recentViolations >= config`maxGoodFaithViolations;
    update restricted:1b, restrictedUntil:.z.d + 90 from `.risk.goodFaithSummary;
    -1 "GOOD FAITH RESTRICTION: 3+ violations in 12 months. Cash-only for 90 days.";
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Queries
/ ═══════════════════════════════════════════════════════════════════

/ Get total unsettled cash
/ @return float - Total unsettled cash (positive=from sales, negative=from buys)
getUnsettledCash:{[]
  sum exec totalUnsettled from .risk.unsettledCash
 };

/ Get settlement status summary
/ @return dict - Settlement status
settlementStatus:{[]
  config:first .risk.settlementConfig;
  summary:first .risk.goodFaithSummary;
  unsettled:getUnsettledCash[];

  `enabled`settlementDays`unsettledCash`goodFaithViolations`restricted`restrictedUntil!(
    config`enabled;
    config`settlementDays;
    unsettled;
    summary`violationCount;
    summary`restricted;
    summary`restrictedUntil
  )
 };

\d .

/ Export namespace
-1 "  Settlement tracking loaded (T+1): .risk.recordSettlement, .risk.checkFreeridingViolation, .risk.getUnsettledCash";
