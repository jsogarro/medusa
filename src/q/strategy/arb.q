/ ============================================================================
/ arb.q - Arbitrage Detection Library
/ ============================================================================
/
/ Provides:
/   - Cross-exchange price comparison
/   - Spread calculation with fees
/   - Arbitrage opportunity detection
/   - Executable volume calculation
/   - Opportunity scoring and ranking
/
/ Dependencies:
/   - exchange/base.q (orderbook access)
/   - lib/money.q (currency handling)
/
/ Functions:
/   - detectDirectionalCross: One-way cross detection
/   - detectCross: Bidirectional cross detection
/   - detectCrossesMany: All-pairs cross detection with ranking
/   - getExecutableVolume: Max tradeable volume given balances
/   - maxBuyVolume: Max purchasable volume accounting for slippage
/   - calculateSpread: Spread calculation with fees
/   - scoreOpportunity: Score arbitrage opportunity by profit/risk
/ ============================================================================

\d .strategy.arb

// ============================================================================
/ CORE DETECTION FUNCTIONS
// ============================================================================

/ Detect directional cross (buy from buyOb, sell to sellOb)
/ @param buyOb table - Buy orderbook (asks sorted ascending)
/ @param sellOb table - Sell orderbook (bids sorted descending)
/ @param buyExchange symbol - Exchange to buy from
/ @param sellExchange symbol - Exchange to sell to
/ @param pair symbol - Trading pair
/ @return dict - Cross result or null if no cross
detectDirectionalCross:{[buyOb;sellOb;buyExchange;sellExchange;pair]
  / Input validation
  if[0=count buyOb; :()];
  if[0=count sellOb; :()];
  if[null buyOb; :()];
  if[null sellOb; :()];
  if[not `price in cols buyOb; :()];
  if[not `volume in cols buyOb; :()];
  if[not `price in cols sellOb; :()];
  if[not `volume in cols sellOb; :()];

  / Extract sorted levels (asks ascending, bids descending)
  asks:`price xasc select from buyOb where side=`ask;
  bids:`price xdesc select from sellOb where side=`bid;

  / Check if there's any overlap
  if[0=count asks; :()];
  if[0=count bids; :()];
  if[first asks`price >= first bids`price; :()];

  / Initialize accumulators
  totalVolume:0.0;
  totalRevenue:0.0;
  totalFees:0.0;

  / Iterate through price levels
  i:0; j:0;
  askVolRemaining:first asks`volume;
  bidVolRemaining:first bids`volume;

  while[(i < count asks) and (j < count bids) and (asks[i;`price] < bids[j;`price]);
    askPrice:asks[i;`price];
    bidPrice:bids[j;`price];

    / Volume at this level is min of available on both sides
    levelVolume:min[askVolRemaining;bidVolRemaining];

    / Accumulate totals
    totalVolume+:levelVolume;
    totalRevenue+:levelVolume * (bidPrice - askPrice);

    / Calculate fees (assume 0.1% taker fee for now - should integrate with fee module)
    buyFee:levelVolume * askPrice * 0.001;
    sellFee:levelVolume * bidPrice * 0.001;
    totalFees+:buyFee + sellFee;

    / Update remaining volumes
    askVolRemaining-:levelVolume;
    bidVolRemaining-:levelVolume;

    / Move to next level if current exhausted
    if[askVolRemaining <= 0; i+:1; if[i<count asks; askVolRemaining:asks[i;`volume]]];
    if[bidVolRemaining <= 0; j+:1; if[j<count bids; bidVolRemaining:bids[j;`volume]]];
  ];

  / Return cross dictionary (empty if no overlap)
  if[totalVolume = 0.0; :()];

  `volume`revenue`fees`profit`buyExchange`sellExchange`pair!(
    totalVolume;
    totalRevenue;
    totalFees;
    totalRevenue - totalFees;
    buyExchange;
    sellExchange;
    pair
  )
 };

/ Detect cross in both directions and return most profitable
/ @param ob1 table - First orderbook
/ @param ob2 table - Second orderbook
/ @param ex1 symbol - First exchange
/ @param ex2 symbol - Second exchange
/ @param pair symbol - Trading pair
/ @return dict - Most profitable cross or null
detectCross:{[ob1;ob2;ex1;ex2;pair]
  / Try both directions
  cross1:detectDirectionalCross[ob1;ob2;ex1;ex2;pair];
  cross2:detectDirectionalCross[ob2;ob1;ex2;ex1;pair];

  / Return most profitable (or first found)
  if[null cross1; :cross2];
  if[null cross2; :cross1];
  $[cross1[`profit] > cross2[`profit]; cross1; cross2]
 };

/ Detect crosses across many exchanges
/ @param orderbooks dict - Exchange -> orderbook table
/ @param pair symbol - Trading pair
/ @return table - Crosses sorted by profit desc
detectCrossesMany:{[orderbooks;pair]
  / Get list of exchanges
  exchanges:key orderbooks;

  / Generate all pairs of exchanges
  crossPairs:raze {[exchanges;ex1]
    otherExchanges:exchanges where exchanges <> ex1;
    {[ex1;ex2] (ex1;ex2)} [ex1] each otherExchanges
  }[exchanges] each exchanges;

  / Detect crosses for each pair
  crosses:{[orderbooks;pair;exPair]
    ex1:exPair 0;
    ex2:exPair 1;

    cross:detectDirectionalCross[
      orderbooks[ex1];
      orderbooks[ex2];
      ex1;
      ex2;
      pair
    ];

    / Return cross if found
    $[null cross; (); enlist cross]
  }[orderbooks;pair] each crossPairs;

  / Filter out nulls and convert to table
  validCrosses:raze crosses where {0<count x} each crosses;

  if[0=count validCrosses;
    :([]volume:();revenue:();fees:();profit:();buyExchange:();sellExchange:();pair:())
  ];

  / Convert to table and sort by profit
  crossTable:flip validCrosses;
  `profit xdesc crossTable
 };

// ============================================================================
/ VOLUME CALCULATION FUNCTIONS
// ============================================================================

/ Calculate max volume purchasable given balance and orderbook
/ @param balance float - Available balance in quote currency
/ @param buyOb table - Buy orderbook (asks)
/ @return float - Max purchasable volume
maxBuyVolume:{[balance;buyOb]
  / Extract asks sorted ascending
  asks:`price xasc select from buyOb where side=`ask;

  if[0=count asks; :0.0];

  / Initialize
  remainingBalance:balance;
  totalVolume:0.0;

  / Iterate through price levels
  i:0;
  while[(i < count asks) and (remainingBalance > 0);
    askPrice:asks[i;`price];
    askVol:asks[i;`volume];

    / How much can we afford at this price level?
    affordableVolume:remainingBalance % askPrice;
    levelVolume:min[askVol;affordableVolume];

    totalVolume+:levelVolume;
    remainingBalance-:levelVolume * askPrice;

    i+:1;
  ];

  totalVolume
 };

/ Get executable volume for a cross given balance constraints
/ @param cross dict - Cross result from detectDirectionalCross
/ @param buyBalance float - Available balance on buy exchange (quote currency)
/ @param sellBalance float - Available balance on sell exchange (base currency)
/ @param buyOb table - Buy orderbook
/ @return float - Max executable volume
getExecutableVolume:{[cross;buyBalance;sellBalance;buyOb]
  if[null cross; :0.0];

  / Max we can buy given our balance and orderbook
  maxBuyable:maxBuyVolume[buyBalance;buyOb];

  / Max we can sell is our balance
  maxSellable:sellBalance;

  / Executable volume is minimum of all constraints
  min[cross`volume;maxBuyable;maxSellable]
 };

// ============================================================================
/ SPREAD CALCULATION
// ============================================================================

/ Calculate spread between two exchanges with fees
/ @param buyPrice float - Best ask on buy exchange
/ @param sellPrice float - Best bid on sell exchange
/ @param feeRate float - Trading fee rate (e.g., 0.001 for 0.1%)
/ @return dict - Spread analysis
calculateSpread:{[buyPrice;sellPrice;feeRate]
  / Guard against division by zero
  if[buyPrice = 0; '"Invalid buyPrice: cannot be zero"];

  / Gross spread
  grossSpread:sellPrice - buyPrice;
  grossSpreadPct:(grossSpread % buyPrice) * 100;

  / Trading fees
  buyFee:buyPrice * feeRate;
  sellFee:sellPrice * feeRate;
  totalFees:buyFee + sellFee;

  / Net spread
  netSpread:grossSpread - totalFees;
  netSpreadPct:(netSpread % buyPrice) * 100;

  `buyPrice`sellPrice`grossSpread`grossSpreadPct`totalFees`netSpread`netSpreadPct!(
    buyPrice;
    sellPrice;
    grossSpread;
    grossSpreadPct;
    totalFees;
    netSpread;
    netSpreadPct
  )
 };

// ============================================================================
/ OPPORTUNITY SCORING
// ============================================================================

/ Score arbitrage opportunity by profit potential and risk
/ @param cross dict - Cross result
/ @param executableVolume float - Executable volume
/ @return dict - Scored opportunity
scoreOpportunity:{[cross;executableVolume]
  / Guard against zero volume
  if[cross[`volume] = 0; '"Invalid cross volume: cannot be zero"];

  / Calculate metrics
  profitPerUnit:cross[`profit] % cross[`volume];
  totalProfit:profitPerUnit * executableVolume;
  profitPct:(cross[`profit] % cross[`revenue]) * 100;

  / Risk factors (higher is riskier)
  volumeRisk:1.0 - (executableVolume % cross[`volume]);  / Can we execute full volume?

  / Composite score (higher is better)
  / Weight: 60% profit, 40% volume utilization
  score:(profitPct * 0.6) + ((1.0 - volumeRisk) * 40);

  / Return scored opportunity
  cross,`executableVolume`totalProfit`profitPerUnit`profitPct`volumeRisk`score!(
    executableVolume;
    totalProfit;
    profitPerUnit;
    profitPct;
    volumeRisk;
    score
  )
 };

/ Rank opportunities by score
/ @param opportunities table - Table of scored opportunities
/ @return table - Opportunities sorted by score descending
rankOpportunities:{[opportunities]
  `score xdesc opportunities
 };

// ============================================================================
/ EXECUTION LOGIC (helpers for strategy)
// ============================================================================

/ Generate execution plan for arbitrage opportunity
/ @param opportunity dict - Scored opportunity
/ @return dict - Execution plan with buy/sell orders and rollback guidance
generateExecutionPlan:{[opportunity]
  buyExchange:opportunity`buyExchange;
  sellExchange:opportunity`sellExchange;
  pair:opportunity`pair;
  volume:opportunity`executableVolume;

  / Buy order (market order on buy exchange)
  buyOrder:`exchange`pair`side`orderType`quantity`price!(
    buyExchange;
    pair;
    `buy;
    `market;
    volume;
    0n  / Market order has no price
  );

  / Sell order (market order on sell exchange)
  sellOrder:`exchange`pair`side`orderType`quantity`price!(
    sellExchange;
    pair;
    `sell;
    `market;
    volume;
    0n  / Market order has no price
  );

  / Rollback plan: what to do if one leg fails
  rollbackPlan:`buyLegFails`sellLegFails!(
    "If buy leg fails, no action needed (no position opened)";
    "If sell leg fails after buy succeeds, immediately cancel/hedge buy position on ",string[buyExchange]," to avoid one-sided risk"
  );

  `buyOrder`sellOrder`expectedProfit`risk`rollbackPlan!(
    buyOrder;
    sellOrder;
    opportunity`totalProfit;
    opportunity`volumeRisk;
    rollbackPlan
  )
 };

\d .

/ Export namespace
-1 "  Arbitrage library loaded: .strategy.arb namespace";
