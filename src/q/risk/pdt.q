/ ============================================================================
/ pdt.q - Pattern Day Trader Rule (Reg T)
/ ============================================================================
/ // Provides:
/   - Day trade tracking (round-trip buy+sell same symbol same day)
/   - PDT rule enforcement (4+ day trades in 5 business days)
/   - Account balance threshold ($25,000 minimum)
/   - Warning at 3 day trades (before 4th triggers restriction)
/ // Regulatory Context:
/   - FINRA Rule 4210: Pattern Day Trader
/   - Applies to margin accounts with equity < $25,000
/   - Day trade = buy then sell (or sell short then buy to cover) same symbol same day
/   - 4+ day trades in 5 business days triggers PDT restriction
/ // Dependencies:
/   - .exchange.calendar (business day calculation)
/   - .schema.isEquity (asset class detection)
/ // Functions:
/   - initPDT: Initialize PDT tracking tables
/   - recordDayTrade: Record a day trade after fill
/   - checkPDT: Pre-trade PDT rule check
/   - getDayTradeCount: Get count for last 5 business days
/   - resetDayTrades: Manual reset (for testing)
/ ============================================================================

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ PDT State Tables
/ ═══════════════════════════════════════════════════════════════════

/ PDT configuration (single-row table)
pdtConfig:([]
  enabled:enlist 1b;
  accountValue:enlist 10000.0;  / Current account value
  minAccountValue:enlist 25000.0;  / PDT threshold
  dayTradeWindow:enlist 5i;  / Rolling business days
  maxDayTrades:enlist 3i;  / Allowed before restriction (4 triggers PDT)
  lastUpdate:enlist .z.p
 );

/ Cache for last 5 trading days (recalculate daily, not per-order)
pdt.cachedTradingDays:();
pdt.cacheDate:0Nd;

/ Clock seam — tests override to a known trading date so day-trade
/ records aren't stamped on weekends or holidays. Production keeps .z.d.
pdt.today:{.z.d};

/ Day trade history (append-only)
/ Records each day trade (round-trip same symbol same day)
dayTradeHistory:([]
  time:`timestamp$();
  date:`date$();
  sym:`symbol$();
  openSide:`symbol$();  / `buy or `sell (opening leg)
  closeSide:`symbol$();  / `sell or `buy (closing leg)
  openQty:`float$();
  closeQty:`float$();
  pnl:`float$()  / Realized P&L from this day trade
 );

/ Day trade summary (keyed by date)
/ Aggregated count per day for quick lookup
dayTradeSummary:([date:`date$()]
  dayTradeCount:`int$();
  firstTrade:`timestamp$();
  lastTrade:`timestamp$()
 );

/ Add grouped attribute for O(1) lookups
update `g#date from `.risk.dayTradeSummary;

/ PDT alert log (append-only)
pdtAlerts:([]
  time:`timestamp$();
  alertType:`symbol$();  / `warning (3 trades), `breach (4+ trades)
  dayTradeCount:`int$();
  accountValue:`float$();
  minAccountValue:`float$();
  message:()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

/ Initialize PDT tracking system
/ @return void
initPDT:{[]
  / Reset state tables
  delete from `.risk.dayTradeHistory;
  delete from `.risk.dayTradeSummary;
  delete from `.risk.pdtAlerts;

  / Set default config
  update enabled:1b, accountValue:10000.0, minAccountValue:25000.0,
         dayTradeWindow:5i, maxDayTrades:3i, lastUpdate:.z.p from `.risk.pdtConfig;

  -1 "  PDT tracking initialized";
 };

/ Update account value (called from account sync)
/ @param value float - Current account value
/ @return void
updateAccountValue:{[val]
  update accountValue:val, lastUpdate:.z.p from `.risk.pdtConfig;
 };

/ ═══════════════════════════════════════════════════════════════════
/ Day Trade Detection and Recording
/ ═══════════════════════════════════════════════════════════════════

/ Record a day trade (call on fill when round-trip detected)
/ @param sym symbol - Trading symbol
/ @param openSide symbol - Opening side (`buy or `sell)
/ @param closeSide symbol - Closing side (`sell or `buy)
/ @param openQty float - Opening quantity
/ @param closeQty float - Closing quantity
/ @param pnl float - Realized P&L from this day trade
/ @return void
recordDayTrade:{[sym;openSide;closeSide;openQty;closeQty;pnl]
  dt:pdt.today[];

  / Insert into history
  `.risk.dayTradeHistory insert (.z.p;dt;sym;openSide;closeSide;openQty;closeQty;pnl);

  / Update summary
  summaryRows:0!.risk.dayTradeSummary;
  if[not dt in summaryRows`date;
    / First day trade for this date
    summaryRows,:enlist `date`dayTradeCount`firstTrade`lastTrade!(dt;1i;.z.p;.z.p);
    `.risk.dayTradeSummary set `date xkey summaryRows;
    checkThresholds[];
    :();
  ];

  / Increment count
  existing:first select from summaryRows where date=dt;
  newCount:1+first existing`dayTradeCount;
  summaryRows:update dayTradeCount:newCount, lastTrade:.z.p from summaryRows where date=dt;
  `.risk.dayTradeSummary set `date xkey summaryRows;

  / Check if warning or breach threshold reached
  checkThresholds[];
 };

/ Check thresholds and generate alerts
/ @return void
checkThresholds:{[]
  config:first .risk.pdtConfig;
  count5day:getDayTradeCount[];

  / Warning at 3 day trades (approaching 4 limit)
  if[(count5day = config`maxDayTrades) and config`enabled;
    msg:"WARNING: ",string[count5day]," day trades in 5 business days. One more triggers PDT restriction.";
    `.risk.pdtAlerts insert (.z.p;`warning;count5day;config`accountValue;config`minAccountValue;msg);
    -1 msg;
  ];

  / Breach at 4+ day trades
  if[(count5day > config`maxDayTrades) and config`enabled;
    msg:"PDT BREACH: ",string[count5day]," day trades in 5 business days. Account restricted.";
    `.risk.pdtAlerts insert (.z.p;`breach;count5day;config`accountValue;config`minAccountValue;msg);
    -1 msg;
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Day Trade Count Query
/ ═══════════════════════════════════════════════════════════════════

/ Get day trade count for last N business days
/ @return int - Total day trade count
getDayTradeCount:{[]
  config:first .risk.pdtConfig;
  window:config`dayTradeWindow;  / 5 business days

  / Get last 5 business days
  tradingDays:getLast5TradingDays[];

  / Sum day trades across those days
  sum exec dayTradeCount from .risk.dayTradeSummary where date in tradingDays
 };

/ Get last 5 trading days (business days only)
/ @return date list - Last 5 trading days
getLast5TradingDays:{[]
  today:pdt.today[];

  / Return cached result if date hasn't changed
  if[today = .risk.pdt.cacheDate; :.risk.pdt.cachedTradingDays];

  / Recalculate when date changes
  dt:today;
  result:();
  dayCount:0;

  / Walk backward, collecting trading days
  while[dayCount<5;
    if[.exchange.calendar.isTradingDay[dt];
      result,:dt;
      dayCount+:1;
    ];
    dt-:1;
  ];

  / Update cache
  .risk.pdt.cachedTradingDays:result;
  .risk.pdt.cacheDate:today;

  result
 };

/ ═══════════════════════════════════════════════════════════════════
/ Pre-Trade PDT Check
/ ═══════════════════════════════════════════════════════════════════

/ Check PDT rule (pre-trade validation)
/ @param sym symbol - Trading symbol
/ @param side symbol - Order side (`buy or `sell)
/ @param qty float - Order quantity
/ @return (boolean; reason; details) - (pass; reason; details dict)
checkPDT:{[sym;side;qty]
  config:first .risk.pdtConfig;

  / Skip if PDT rule disabled
  if[not config`enabled; :(1b;`;())];

  / Skip if account value >= $25,000 (exempt from PDT rule)
  if[config[`accountValue] >= config`minAccountValue; :(1b;`;())];

  / Only applies to equities (crypto is 24/7, no PDT)
  if[not .schema.isEquity[sym]; :(1b;`;())];

  / Check day trade count
  count5day:getDayTradeCount[];

  / If already at or above limit, reject
  if[count5day > config`maxDayTrades;
    details:`dayTradeCount`accountValue`minAccountValue!(count5day;config`accountValue;config`minAccountValue);
    :(0b;`pdtBreach;details)
  ];

  / Warning if at threshold (but allow)
  if[count5day = config`maxDayTrades;
    details:`dayTradeCount`accountValue!(count5day;config`accountValue);
    -1 "WARNING: At PDT threshold (",string[count5day]," day trades). One more triggers restriction.";
    / Allow but warn
  ];

  / Pass
  (1b;`;())
 };

/ ═══════════════════════════════════════════════════════════════════
/ Utilities
/ ═══════════════════════════════════════════════════════════════════

/ Reset day trades (for testing or manual override)
/ @return void
resetDayTrades:{[]
  delete from `.risk.dayTradeHistory;
  delete from `.risk.dayTradeSummary;
  delete from `.risk.pdtAlerts;
  -1 "Day trades reset";
 };

/ Get PDT status summary
/ @return dict - PDT status
pdtStatus:{[]
  config:first .risk.pdtConfig;
  count5day:getDayTradeCount[];

  `enabled`accountValue`minAccountValue`dayTradeWindow`maxDayTrades`currentDayTrades`isRestricted!(
    config`enabled;
    config`accountValue;
    config`minAccountValue;
    config`dayTradeWindow;
    config`maxDayTrades;
    count5day;
    (count5day > config`maxDayTrades) and config`enabled
  )
 };

\d .

/ Export namespace
-1 "  PDT rule loaded: .risk.checkPDT, .risk.recordDayTrade, .risk.getDayTradeCount";
