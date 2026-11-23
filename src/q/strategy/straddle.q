/ ============================================================================
/ straddle.q - Straddle Strategy
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Buy ATM call + ATM put to profit from large moves in either direction.
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Buy ATM call option
/   - Buy ATM put option (same strike, same expiry)
/   - Profit if stock moves significantly up or down
/ ----------------------------------------------------------------------------
/ Risk:
/   - Max loss: Total premium paid (if stock stays at strike)
/   - Max profit: Unlimited upside, large downside (strike - premium)
/   - Breakevens: Strike +/- total premium
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - strategy/optionsCommon.q (BS pricing, Greeks)
/   - schema/options.q (option tables)
/ ----------------------------------------------------------------------------
/ Functions:
/   - buildStraddle: Construct ATM straddle (2 legs)
/   - calculateBreakevens: Upper and lower breakeven prices
/ ============================================================================

\d .strategy

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Default configuration
straddle.defaultConfig:{[]
  `underlying`maxPremium`maxDaysToExpiry`strikeATMTolerance`enabled!(
    `;         / underlying symbol
    500.0;     / max total premium ($)
    60;        / maximum days to expiration
    2.0;       / strike ATM tolerance (% from current price)
    1b         / enabled flag
  )
 };

// ============================================================================
// STRADDLE CONSTRUCTION
// ============================================================================

/ Build straddle structure (buy ATM call + ATM put)
/ @param underlying symbol - Underlying equity symbol
/ @param currentPrice float - Current stock price
/ @param expiry date - Target expiration date
/ @param atmTolerance float - % tolerance for ATM strike
/ @return dict - 2-leg structure with contracts
straddle.buildStraddle:{[underlying;currentPrice;expiry;atmTolerance]
  / Calculate ATM strike (round to nearest standard strike)
  atmStrike:floor currentPrice + 0.5;

  / ATM tolerance range
  minStrike:atmStrike * 1.0 - atmTolerance % 100.0;
  maxStrike:atmStrike * 1.0 + atmTolerance % 100.0;

  / Find ATM contracts (call and put with same strike)
  contracts:select from .schema.optionContract where
    underlying=underlying,
    expiry=expiry,
    status=`active;

  / Convert ATM strike to fixed-precision
  atmStrikeFixed:floor atmStrike * 1000000;
  minStrikeFixed:floor minStrike * 1000000;
  maxStrikeFixed:floor maxStrike * 1000000;

  / Look up call and put with matching strike
  callContract:first exec contractId from contracts where
    optionType=`call,
    strike>=minStrikeFixed,
    strike<=maxStrikeFixed;

  putContract:first exec contractId from contracts where
    optionType=`put,
    strike>=minStrikeFixed,
    strike<=maxStrikeFixed;

  / Validate both legs found
  if[any null (callContract;putContract);
    :`status`reason!(`incomplete;`missingContracts)
  ];

  / Build legs table
  legs:([] contractId:(callContract;putContract);
           side:(`buy;`buy);
           qty:(1;1);
           optionType:(`call;`put));

  `status`legs`strike`underlying!(
    `complete;
    legs;
    atmStrike;
    underlying
  )
 };

// ============================================================================
// BREAKEVEN CALCULATION
// ============================================================================

/ Calculate breakeven prices for straddle
/ @param strike float - ATM strike price
/ @param callPremium float - Call option premium (per share)
/ @param putPremium float - Put option premium (per share)
/ @return dict - Upper and lower breakeven prices
straddle.calculateBreakevens:{[strike;callPremium;putPremium]
  / Total premium paid per share
  totalPremium:callPremium + putPremium;

  / Breakevens: strike +/- total premium
  upperBreakeven:strike + totalPremium;
  lowerBreakeven:strike - totalPremium;

  / Max loss: total premium paid
  maxLoss:totalPremium * 100.0;  / Per contract = 100 shares

  `upperBreakeven`lowerBreakeven`maxLoss`totalPremium!(
    upperBreakeven;
    lowerBreakeven;
    maxLoss;
    totalPremium
  )
 };

\d .

/ Export namespace
-1 "  Straddle strategy loaded: buildStraddle, calculateBreakevens";
