/ ============================================================================
/ verticalSpread.q - Vertical Spread Strategies
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Bull/bear call/put spreads to profit from directional moves with defined risk.
/ ----------------------------------------------------------------------------
/ Strategies:
/   - Bull call spread: Buy lower strike call, sell higher strike call (bullish)
/   - Bear call spread: Sell lower strike call, buy higher strike call (bearish)
/   - Bull put spread: Sell higher strike put, buy lower strike put (bullish)
/   - Bear put spread: Buy higher strike put, sell lower strike put (bearish)
/ ----------------------------------------------------------------------------
/ Risk:
/   - Debit spreads (bull call, bear put): Max loss = debit paid
/   - Credit spreads (bull put, bear call): Max loss = spread width - credit
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - strategy/optionsCommon.q (BS pricing, Greeks)
/   - schema/options.q (option tables)
/ ----------------------------------------------------------------------------
/ Functions:
/   - buildSpread: Construct vertical spread (2 legs)
/   - execute: Execute vertical spread
/ ============================================================================

\d .strategy

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Default configuration
verticalSpread.defaultConfig:{[]
  `underlying`spreadType`strikeWidth`maxDebit`minCredit`maxDaysToExpiry`enabled!(
    `;           / underlying symbol
    `;           / spread type (`bullCall, `bearCall, `bullPut, `bearPut)
    5.0;         / strike width ($)
    150.0;       / max debit for debit spreads
    50.0;        / min credit for credit spreads
    45;          / maximum days to expiration
    1b           / enabled flag
  )
 };

// ============================================================================
// SPREAD CONSTRUCTION
// ============================================================================

/ Build vertical spread structure
/ @param underlying symbol - Underlying equity symbol
/ @param currentPrice float - Current stock price
/ @param spreadType symbol - `bullCall, `bearCall, `bullPut, or `bearPut
/ @param strikeWidth float - Distance between strikes ($)
/ @param expiry date - Target expiration date
/ @return dict - 2-leg structure with contracts
verticalSpread.buildSpread:{[underlying;currentPrice;spreadType;strikeWidth;expiry]
  / Determine strikes based on spread type
  strikes:$[spreadType=`bullCall;
    / Bull call: Buy ATM call, sell OTM call
    (floor currentPrice + 0.5; floor currentPrice + strikeWidth + 0.5);
  spreadType=`bearCall;
    / Bear call: Sell OTM call, buy further OTM call
    (floor currentPrice + strikeWidth + 0.5; floor currentPrice + strikeWidth * 2.0 + 0.5);
  spreadType=`bullPut;
    / Bull put: Sell OTM put, buy further OTM put
    (floor currentPrice - strikeWidth + 0.5; floor currentPrice - strikeWidth * 2.0 + 0.5);
  spreadType=`bearPut;
    / Bear put: Buy ATM put, sell OTM put
    (floor currentPrice + 0.5; floor currentPrice - strikeWidth + 0.5);
  / else
    '"Invalid spread type"
  ];

  lowerStrike:first strikes;
  upperStrike:last strikes;

  / Determine option type
  optType:$[spreadType in `bullCall`bearCall; `call; `put];

  / Find contracts
  contracts:select from .schema.optionContract where
    underlying=underlying,
    expiry=expiry,
    optionType=optType,
    status=`active;

  / Convert float strikes to fixed-precision
  lowerStrikeFixed:floor lowerStrike * 1000000;
  upperStrikeFixed:floor upperStrike * 1000000;

  / Look up legs
  lowerContract:first exec contractId from contracts where strike=lowerStrikeFixed;
  upperContract:first exec contractId from contracts where strike=upperStrikeFixed;

  / Validate both legs found
  if[any null (lowerContract;upperContract);
    :`status`reason!(`incomplete;`missingContracts)
  ];

  / Determine sides based on spread type
  sides:$[spreadType in `bullCall`bearPut;
    / Debit spreads: buy lower (call) or higher (put), sell higher (call) or lower (put)
    $[spreadType=`bullCall; (`buy;`sell); (`sell;`buy)];
  / else
    / Credit spreads: sell lower (call) or higher (put), buy higher (call) or lower (put)
    $[spreadType=`bearCall; (`sell;`buy); (`buy;`sell)]
  ];

  / Build legs table
  legs:([] contractId:(lowerContract;upperContract);
           side:sides;
           qty:(1;1));

  `status`legs`lowerStrike`upperStrike`spreadType!(
    `complete;
    legs;
    lowerStrike;
    upperStrike;
    spreadType
  )
 };

// ============================================================================
// EXECUTION
// ============================================================================

/ Execute vertical spread
/ @param spread dict - Spread structure from buildSpread
/ @param qty int - Number of spreads
/ @return dict - Execution result with orders
verticalSpread.execute:{[spread;qty]
  / Validate spread status
  if[spread[`status] <> `complete;
    :`status`reason!(spread`status;spread`reason)
  ];

  / Extract legs
  legs:spread`legs;

  / Create orders for each leg
  orders:legs lj ([] contractId:legs`contractId; orderQty:qty);

  `status`orders`spreadType`qty!(
    `pending;
    orders;
    spread`spreadType;
    qty
  )
 };

\d .

/ Export namespace
-1 "  Vertical spread strategy loaded: buildSpread, execute";
