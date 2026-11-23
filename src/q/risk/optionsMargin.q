/ Risk Management — Options Margin Requirements
/ SPAN-like margin calculation for options positions

\d .risk

// ============================================================================
// MARGIN CALCULATION CONSTANTS
// ============================================================================

/ Margin parameters (aligned with broker requirements)
NAKED_CALL_MARGIN_PCT:0.20;   / 20% of underlying value
NAKED_PUT_MARGIN_PCT:0.20;    / 20% of strike value
MIN_NAKED_MARGIN:2000.0;      / Minimum margin for naked positions ($)
SPREAD_MARGIN_MULTIPLIER:1.0; / Use max loss for spreads

// ============================================================================
// MARGIN SCHEMA
// ============================================================================

/ Margin requirements by position (keyed by contractId)
marginRequirements:([contractId:`symbol$()]
  positionType:`symbol$();      / `longCall, `shortCall, `longPut, `shortPut, `spread
  quantity:`long$();            / Position size (signed)
  underlyingPrice:`long$();     / Current underlying price (fixed-precision)
  strike:`long$();              / Strike price (fixed-precision)
  marginRequired:`long$();      / Margin required (fixed-precision, .money)
  cashRequired:`long$();        / Cash required for long options (premium paid)
  lastUpdate:`timestamp$()      / Last calculation timestamp
 );

/ Total margin summary (single-row table)
marginSummary:([]
  totalMarginRequired:enlist 0.0;
  totalCashUsed:enlist 0.0;
  availableCash:enlist 100000.0;  / Default cash balance
  marginUtilization:enlist 0.0;   / % of available cash used
  lastUpdate:enlist .z.p
 );

// ============================================================================
// MARGIN CALCULATION FUNCTIONS
// ============================================================================

/ Calculate margin for long call option
/ @param qty long - Quantity (contracts)
/ @param premium long - Premium paid per share (fixed-precision)
/ @return long - Margin required (fixed-precision)
calculateLongCallMargin:{[qty;premium]
  / Long options: margin = premium paid
  qty * premium * 100  / 100 shares per contract
 };

/ Calculate margin for long put option
/ @param qty long - Quantity (contracts)
/ @param premium long - Premium paid per share (fixed-precision)
/ @return long - Margin required (fixed-precision)
calculateLongPutMargin:{[qty;premium]
  / Long options: margin = premium paid
  qty * premium * 100
 };

/ Calculate margin for short call option
/ @param qty long - Quantity (contracts)
/ @param underlyingPrice long - Current underlying price (fixed-precision)
/ @param strike long - Strike price (fixed-precision)
/ @param premium long - Premium received per share (fixed-precision)
/ @return long - Margin required (fixed-precision)
calculateShortCallMargin:{[qty;underlyingPrice;strike;premium]
  / Short naked call: 20% of underlying + premium - OTM amount
  / OTM amount = max(0, strike - underlying)
  otmAmount:max[0; strike - underlyingPrice];

  / Margin per share
  marginPerShare:max[
    (NAKED_CALL_MARGIN_PCT * underlyingPrice) + premium - otmAmount;
    floor MIN_NAKED_MARGIN * 1000000 % 100  / Min margin per contract
  ];

  / Total margin
  qty * marginPerShare * 100
 };

/ Calculate margin for short put option
/ @param qty long - Quantity (contracts)
/ @param strike long - Strike price (fixed-precision)
/ @param underlyingPrice long - Current underlying price (fixed-precision)
/ @param premium long - Premium received per share (fixed-precision)
/ @return long - Margin required (fixed-precision)
calculateShortPutMargin:{[qty;strike;underlyingPrice;premium]
  / Short naked put: 20% of strike - OTM amount + premium
  / OTM amount = max(0, underlying - strike)
  otmAmount:max[0; underlyingPrice - strike];

  / Margin per share
  marginPerShare:max[
    (NAKED_PUT_MARGIN_PCT * strike) - otmAmount + premium;
    floor MIN_NAKED_MARGIN * 1000000 % 100
  ];

  / Total margin
  qty * marginPerShare * 100
 };

/ Calculate margin for spread (vertical spread, iron condor, etc.)
/ @param legs table - Table with columns: contractId, side, qty, strike, premium
/ @return long - Margin required (fixed-precision)
calculateSpreadMargin:{[legs]
  / For spreads: margin = max loss = spread width - net credit (or + net debit)
  / This is dramatically lower than naked margin (typically 5x less)

  / Find max and min strikes
  strikes:exec strike from legs;
  maxStrike:max strikes;
  minStrike:min strikes;
  spreadWidth:(maxStrike - minStrike) % 1000000.0;  / Convert to dollars

  / Calculate net credit/debit (sell = credit, buy = debit)
  netCredit:sum exec $[side=`sell; premium; neg premium] from legs;
  netCreditFloat:netCredit % 1000000.0;

  / Max loss per spread = spread width - net credit received
  / For debit spreads, max loss = debit paid (netCredit is negative)
  maxLossPerSpread:spreadWidth - netCreditFloat;
  if[maxLossPerSpread < 0.0; maxLossPerSpread:0.0];  / Credit spreads can't have negative margin

  / Total margin (per contract = 100 shares)
  qty:first exec qty from legs;
  floor maxLossPerSpread * 100.0 * qty * 1000000  / Convert back to fixed-precision
 };

/ Detect if positions form a spread (opposing sides, same expiry/underlying, different strikes)
/ @param positions table - Option positions
/ @return table - Spread groups with columns: spreadId, legs
detectSpreads:{[positions]
  / Group positions by underlying + expiry
  grouped:select contractId, side, quantity, strike, avgEntryPrice, underlying, expiry
    by underlying, expiry from positions;

  / For each group, check if opposing sides exist (spread pattern)
  spreads:();
  {[grp]
    legs:grp[`data];
    / Spread requires: 2+ legs, at least 1 buy and 1 sell, different strikes
    if[(count legs) >= 2;
      hasBuy:any legs[`side] = `buy;
      hasSell:any legs[`side] = `sell;
      uniqueStrikes:count distinct legs[`strike];
      if[hasBuy and hasSell and uniqueStrikes > 1;
        spreadId:`$"spread_",string[grp`underlying],"_",string grp`expiry;
        spreads,:enlist `spreadId`legs!(spreadId;legs);
      ];
    ];
   } each grouped;

  spreads
 };

/ Calculate total margin for all positions
/ @param positions table - Option positions (from .schema.optionPosition)
/ @return long - Total margin required (fixed-precision)
calculateMargin:{[positions]
  / If no positions, return zero
  if[0 = count positions; :0j];

  / Detect spread positions
  spreads:detectSpreads[positions];
  spreadContractIds:raze exec contractId from legs from spreads;

  / Calculate margin for spread positions
  spreadMargin:sum {[spread]
    calculateSpreadMargin[spread`legs]
   } each spreads;

  / Calculate margin for non-spread positions (standalone legs)
  standalonePositions:select from positions where not contractId in spreadContractIds;

  / Calculate margin per position
  margins:standalonePositions lj ([] contractId:standalonePositions`contractId; margin:0j);

  / Iterate over standalone positions and calculate margin
  margins:update margin:{[row]
    / Look up contract details
    contract:.schema.optionContract[row`contractId];
    if[()~contract; :0j];  / Skip if contract not found

    / Determine position type
    qty:abs row`quantity;
    isLong:row[`side] = `long;
    optType:contract`optionType;
    strike:contract`strike;
    underlyingPrice:row`underlyingPrice;
    premium:row`avgEntryPrice;

    / Calculate margin based on type
    $[isLong;
      / Long options: premium paid
      qty * premium * 100;
    optType=`call;
      / Short call
      calculateShortCallMargin[qty;underlyingPrice;strike;premium];
    optType=`put;
      / Short put
      calculateShortPutMargin[qty;strike;underlyingPrice;premium];
    / else
      0j
    ]
   }[;] each flip margins;

  / Sum total margin (spreads + standalone)
  spreadMargin + sum exec margin from margins
 };

// ============================================================================
// PRE-TRADE VALIDATION
// ============================================================================

/ Check if margin is available for new position
/ @param newPosition dict - New position with contractId, side, qty, avgEntryPrice
/ @param cashAvailable float - Available cash
/ @return tuple - (pass:boolean; reason:symbol; detail:dict)
checkMarginAvailable:{[newPosition;cashAvailable]
  / Look up contract details
  contract:.schema.optionContract[newPosition`contractId];
  if[()~contract;
    :(0b;`contractNotFound;`contractId!newPosition`contractId)
  ];

  / Get current underlying price (from latest quote)
  latestQuote:first select from .schema.optionQuote where contractId=newPosition`contractId;
  if[0 = count latestQuote;
    :(0b;`noQuoteAvailable;`contractId!newPosition`contractId)
  ];
  underlyingPrice:latestQuote`underlyingPrice;

  / Extract position details
  qty:newPosition`qty;
  side:newPosition`side;
  premium:newPosition`avgEntryPrice;
  strike:contract`strike;
  optType:contract`optionType;

  / Calculate margin required for this position
  marginRequired:$[side=`buy;
    / Long option: premium paid
    qty * premium * 100;
  optType=`call;
    / Short call
    calculateShortCallMargin[qty;underlyingPrice;strike;premium];
  optType=`put;
    / Short put
    calculateShortPutMargin[qty;strike;underlyingPrice;premium];
  / else
    0j
  ];

  / Convert to float for comparison
  marginFloat:marginRequired % 1000000.0;

  / Check if cash available
  if[marginFloat > cashAvailable;
    :(0b;`insufficientMargin;`required`available!(marginFloat;cashAvailable))
  ];

  / All checks passed
  (1b;`;`marginRequired`cashAvailable!(marginFloat;cashAvailable))
 };

// ============================================================================
// POST-FILL UPDATES
// ============================================================================

/ Update margin requirements after fill
updateMarginRequirements:{[]
  / Recalculate margin for all positions
  positions:select from .schema.optionPosition;
  totalMargin:calculateMargin[positions];

  / Update summary
  .risk.marginSummary[`totalMarginRequired]:totalMargin % 1000000.0;
  .risk.marginSummary[`lastUpdate]:.z.p;

  / Calculate utilization
  availCash:first .risk.marginSummary`availableCash;
  .risk.marginSummary[`marginUtilization]:
    (first .risk.marginSummary`totalMarginRequired) % availCash;

  -1 "Margin requirements updated: Total=",
     string[first .risk.marginSummary`totalMarginRequired],
     " Utilization=",string[100.0 * first .risk.marginSummary`marginUtilization],"%";
 };

\d .

/ Export namespace
-1 "  Options margin loaded: calculateMargin, checkMarginAvailable, updateMarginRequirements";
