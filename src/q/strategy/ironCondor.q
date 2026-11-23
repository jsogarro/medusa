/ ============================================================================
/ ironCondor.q - Iron Condor Strategy
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Sell OTM call spread + sell OTM put spread to profit from low volatility.
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Sell OTM call spread (sell lower strike call, buy higher strike call)
/   - Sell OTM put spread (sell higher strike put, buy lower strike put)
/   - Collect net premium, profit if stock stays within inner strikes
/ ----------------------------------------------------------------------------
/ Risk:
/   - Max profit: Net premium collected
/   - Max loss: (Spread width - Net premium) per spread
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - strategy/optionsCommon.q (BS pricing, Greeks)
/   - schema/options.q (option tables)
/ ----------------------------------------------------------------------------
/ Functions:
/   - buildCondor: Construct 4-leg iron condor
/   - calculateMaxProfit: Max profit and max loss
/   - calculateProbability: Probability of profit
/ ============================================================================

\d .strategy

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Default configuration
ironCondor.defaultConfig:{[]
  `underlying`wingWidth`innerStrikeOTMPct`minPremium`maxDaysToExpiry`enabled!(
    `;         / underlying symbol
    5.0;       / wing width ($5 between strikes)
    5.0;       / inner strikes % OTM
    200.0;     / minimum net premium ($)
    45;        / maximum days to expiration
    1b         / enabled flag
  )
 };

// ============================================================================
// CONDOR CONSTRUCTION
// ============================================================================

/ Build iron condor structure
/ @param underlying symbol - Underlying equity symbol
/ @param currentPrice float - Current stock price
/ @param wingWidth float - Distance between strikes ($)
/ @param innerOTMPct float - Inner strikes % OTM
/ @param expiry date - Target expiration date
/ @return dict - 4-leg structure with contracts
ironCondor.buildCondor:{[underlying;currentPrice;wingWidth;innerOTMPct;expiry]
  / Calculate strike prices
  innerCallStrike:currentPrice * 1.0 + innerOTMPct % 100.0;
  outerCallStrike:innerCallStrike + wingWidth;
  innerPutStrike:currentPrice * 1.0 - innerOTMPct % 100.0;
  outerPutStrike:innerPutStrike - wingWidth;

  / Round strikes to nearest dollar (standard options)
  innerCallStrike:floor innerCallStrike + 0.5;
  outerCallStrike:floor outerCallStrike + 0.5;
  innerPutStrike:floor innerPutStrike + 0.5;
  outerPutStrike:floor outerPutStrike + 0.5;

  / Find contracts matching strikes
  contracts:select from .schema.optionContract where
    underlying=underlying,
    expiry=expiry,
    status=`active;

  / Convert float strikes to fixed-precision for comparison
  innerCallStrikeFixed:floor innerCallStrike * 1000000;
  outerCallStrikeFixed:floor outerCallStrike * 1000000;
  innerPutStrikeFixed:floor innerPutStrike * 1000000;
  outerPutStrikeFixed:floor outerPutStrike * 1000000;

  / Look up each leg
  sellCallContract:first exec contractId from contracts where optionType=`call, strike=innerCallStrikeFixed;
  buyCallContract:first exec contractId from contracts where optionType=`call, strike=outerCallStrikeFixed;
  sellPutContract:first exec contractId from contracts where optionType=`put, strike=innerPutStrikeFixed;
  buyPutContract:first exec contractId from contracts where optionType=`put, strike=outerPutStrikeFixed;

  / Validate all legs found
  if[any null (sellCallContract;buyCallContract;sellPutContract;buyPutContract);
    :`status`reason!(`incomplete;`missingContracts)
  ];

  / Build legs table
  legs:([] contractId:(sellCallContract;buyCallContract;sellPutContract;buyPutContract);
           side:(`sell;`buy;`sell;`buy);
           qty:(1;1;1;1));

  `status`legs`wingWidth`innerCallStrike`innerPutStrike!(
    `complete;
    legs;
    wingWidth;
    innerCallStrike;
    innerPutStrike
  )
 };

// ============================================================================
// PROFIT CALCULATION
// ============================================================================

/ Calculate max profit and max loss for iron condor
/ @param netPremium float - Net premium collected (sell premium - buy premium)
/ @param wingWidth float - Distance between strikes
/ @return dict - Max profit, max loss, breakevens
ironCondor.calculateMaxProfit:{[netPremium;wingWidth]
  / Max profit: Net premium collected (if stock stays between inner strikes)
  maxProfit:netPremium * 100.0;  / Per contract = 100 shares

  / Max loss: (Wing width - Net premium) * 100
  maxLoss:(wingWidth - netPremium) * 100.0;

  / Breakevens: Inner strikes +/- net premium
  / (Calculated by caller since strikes are in their context)

  `maxProfit`maxLoss`profitProbability!(maxProfit;maxLoss;0N)
 };

// ============================================================================
// PROBABILITY CALCULATION
// ============================================================================

/ Calculate probability of profit (stock stays within inner strikes)
/ @param currentPrice float - Current stock price
/ @param innerCallStrike float - Inner call strike
/ @param innerPutStrike float - Inner put strike
/ @param daysToExpiry int - Days to expiration
/ @param volatility float - Implied volatility (annual, decimal)
/ @return float - Probability of profit (0.0 to 1.0)
ironCondor.calculateProbability:{[currentPrice;innerCallStrike;innerPutStrike;daysToExpiry;volatility]
  / Calculate one standard deviation move
  T:daysToExpiry % 252.0;  / Convert to years
  stdDevMove:currentPrice * volatility * sqrt T;

  / Probability within range (simple approximation using normal distribution)
  / Assume stock price is lognormally distributed
  upperBound:innerCallStrike;
  lowerBound:innerPutStrike;

  / Z-scores for upper and lower bounds
  zUpper:(log[upperBound % currentPrice]) % (volatility * sqrt T);
  zLower:(log[lowerBound % currentPrice]) % (volatility * sqrt T);

  / Probability between bounds
  probUpper:.strategy.options.cumulativeNormal[zUpper];
  probLower:.strategy.options.cumulativeNormal[zLower];

  probWithinRange:probUpper - probLower;

  probWithinRange
 };

\d .

/ Export namespace
-1 "  Iron condor strategy loaded: buildCondor, calculateMaxProfit, calculateProbability";
