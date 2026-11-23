/ ============================================================================
/ coveredCall.q - Covered Call Strategy
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Buy shares + sell OTM call options to generate income while capped upside.
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Buy 100 shares of underlying
/   - Sell 1 OTM call option (strike > current price)
/   - Collect premium, limit upside to strike price
/ ----------------------------------------------------------------------------
/ Risk:
/   - Max profit: Premium + (Strike - Entry Price) * 100
/   - Max loss: Entry Price * 100 - Premium (if stock goes to zero)
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - strategy/optionsCommon.q (BS pricing, Greeks)
/   - schema/options.q (option tables)
/   - schema/equity.q (equity tables)
/ ----------------------------------------------------------------------------
/ Functions:
/   - detectOpportunity: Find viable covered call setups
/   - calculateMaxProfit: Calculate max profit at expiry
/   - execute: Execute covered call position
/ ============================================================================

\d .strategy

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Default configuration
coveredCall.defaultConfig:{[]
  `underlying`minPremiumYield`maxDaysToExpiry`strikeOTMPct`enabled!(
    `;         / underlying symbol (e.g., `AAPL)
    2.0;       / minimum annualized premium yield (%)
    45;        / maximum days to expiration
    5.0;       / strike % above current price (OTM)
    1b         / enabled flag
  )
 };

// ============================================================================
// OPPORTUNITY DETECTION
// ============================================================================

/ Detect covered call opportunities
/ @param underlying symbol - Underlying equity symbol
/ @param currentPrice float - Current stock price
/ @param minYield float - Minimum annualized premium yield (%)
/ @param maxDTE int - Maximum days to expiration
/ @param strikeOTMPct float - Strike % above current price
/ @return table - Viable opportunities with contractId, strike, premium, yield
coveredCall.detectOpportunity:{[underlying;currentPrice;minYield;maxDTE;strikeOTMPct]
  / Calculate target strike range
  minStrike:currentPrice * 1.0 + strikeOTMPct % 100.0;

  / Query option contracts for OTM calls
  contracts:select from .schema.optionContract where
    underlying=underlying,
    optionType=`call,
    status=`active,
    strike >= minStrike * 1000000,  / Convert to fixed-precision
    expiry <= .z.d + maxDTE;

  / If no contracts, return empty
  if[0 = count contracts; :0#contracts];

  / Get latest quotes for these contracts
  quotes:select last bidPrice, last askPrice by contractId from .schema.optionQuote where
    contractId in exec contractId from contracts;

  / Join contracts with quotes
  opps:contracts lj `contractId xkey quotes;

  / Calculate mid price (premium per contract)
  opps:update midPrice:(bidPrice + askPrice) % 2 from opps;

  / Calculate annualized yield: (premium / stock price) * (365 / DTE)
  opps:update
    daysToExpiry:expiry - .z.d,
    premium:midPrice % 1000000.0  / Convert from fixed-precision
  from opps;

  opps:update
    annualizedYield:(premium % currentPrice) * 365.0 % daysToExpiry
  from opps;

  / Filter by minimum yield
  opps:select from opps where annualizedYield >= minYield;

  / Sort by yield descending
  `annualizedYield xdesc opps
 };

// ============================================================================
// PROFIT CALCULATION
// ============================================================================

/ Calculate max profit for covered call
/ @param entryPrice float - Stock entry price
/ @param strike float - Call strike price
/ @param premium float - Premium received per share
/ @param qty int - Number of contracts (each = 100 shares)
/ @return dict - Max profit, max loss, breakeven
coveredCall.calculateMaxProfit:{[entryPrice;strike;premium;qty]
  / Max profit: (Strike - Entry) + Premium, per share * 100 * qty
  maxProfit:((strike - entryPrice) + premium) * 100.0 * qty;

  / Max loss: (Entry - Premium) * 100 * qty (if stock goes to zero)
  maxLoss:(entryPrice - premium) * 100.0 * qty;

  / Breakeven: Entry - Premium
  breakeven:entryPrice - premium;

  `maxProfit`maxLoss`breakeven!(maxProfit;maxLoss;breakeven)
 };

// ============================================================================
// EXECUTION
// ============================================================================

/ Execute covered call strategy
/ @param underlying symbol - Underlying equity symbol
/ @param contractId symbol - Call option contract ID
/ @param qty int - Number of contracts
/ @param stockPrice float - Current stock price
/ @param optionPrice float - Option premium (per share)
/ @return dict - Execution result with orders
coveredCall.execute:{[underlying;contractId;qty;stockPrice;optionPrice]
  / Step 1: Buy stock (100 shares per contract)
  stockQty:qty * 100;
  stockOrder:`underlying`orderType`side`qty`price!(
    underlying;
    `market;
    `buy;
    stockQty;
    0N  / Market order, no limit price
  );

  / Step 2: Sell call option
  optionOrder:`contractId`orderType`side`qty`price!(
    contractId;
    `limit;
    `sell;
    qty;
    optionPrice * 1000000  / Convert to fixed-precision
  );

  / Return execution plan (orders to be placed)
  `status`stockOrder`optionOrder`expectedPremium!(
    `pending;
    stockOrder;
    optionOrder;
    optionPrice * 100.0 * qty
  )
 };

\d .

/ Export namespace
-1 "  Covered call strategy loaded: detectOpportunity, calculateMaxProfit, execute";
