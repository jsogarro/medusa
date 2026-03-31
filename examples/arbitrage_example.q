/ ============================================================================
/ arbitrage_example.q - Example Usage of Arbitrage Detection Library
/ ============================================================================

/ Load dependencies
\l src/q/strategy/arb.q

-1 "";
-1 "Arbitrage Detection Example";
-1 "============================";
-1 "";

/ ============================================================================
/ 1. Create Sample Orderbooks
/ ============================================================================

-1 "1. Creating sample orderbooks...";

/ GDAX orderbook (lower asks)
gdaxOb:([]
  price:100.0 100.2 100.5 100.8 101.0;
  volume:0.5 1.0 1.5 2.0 1.0;
  side:`ask`ask`ask`bid`bid
 );

-1 "  GDAX Orderbook:";
show gdaxOb;

/ Kraken orderbook (higher bids)
krakenOb:([]
  price:99.5 99.8 100.1 100.6 101.2;
  volume:0.3 0.8 1.2 1.5 0.8;
  side:`ask`ask`ask`bid`bid
 );

-1 "  Kraken Orderbook:";
show krakenOb;
-1 "";

/ ============================================================================
/ 2. Detect Directional Cross
/ ============================================================================

-1 "2. Detecting directional cross (buy GDAX, sell Kraken)...";

cross:.strategy.arb.detectDirectionalCross[gdaxOb;krakenOb;`GDAX;`Kraken;`BTCUSD];

if[not null cross;
  -1 "  Cross detected!";
  show cross;
];
if[null cross;
  -1 "  No cross detected";
];
-1 "";

/ ============================================================================
/ 3. Detect Bidirectional Cross
/ ============================================================================

-1 "3. Detecting bidirectional cross...";

biCross:.strategy.arb.detectCross[gdaxOb;krakenOb;`GDAX;`Kraken;`BTCUSD];

if[not null biCross;
  -1 "  Best cross:";
  show biCross;
];
-1 "";

/ ============================================================================
/ 4. Multi-Exchange Detection
/ ============================================================================

-1 "4. Detecting crosses across multiple exchanges...";

/ Create orderbooks for 3 exchanges
orderbooks:`GDAX`Kraken`Bitstamp!(
  gdaxOb;
  krakenOb;
  ([] price:99.8 100.0 100.3 100.7 101.1; volume:0.6 1.1 1.4 1.8 0.9; side:`ask`ask`ask`bid`bid)
 );

/ Detect all crosses
allCrosses:.strategy.arb.detectCrossesMany[orderbooks;`BTCUSD];

-1 "  All detected crosses:";
show allCrosses;
-1 "";

/ ============================================================================
/ 5. Calculate Executable Volume
/ ============================================================================

-1 "5. Calculating executable volume with balance constraints...";

if[not null cross;
  / Assume we have balances
  buyBalance:500.0;    / 500 USD on buy exchange
  sellBalance:0.8;     / 0.8 BTC on sell exchange

  execVol:.strategy.arb.getExecutableVolume[cross;buyBalance;sellBalance;gdaxOb];

  -1 "  Buy balance: $",string[buyBalance];
  -1 "  Sell balance: ",string[sellBalance]," BTC";
  -1 "  Executable volume: ",string[execVol]," BTC";
];
-1 "";

/ ============================================================================
/ 6. Calculate Spread
/ ============================================================================

-1 "6. Calculating spread with fees...";

/ Best ask on GDAX, best bid on Kraken
bestAsk:exec min price from gdaxOb where side=`ask;
bestBid:exec max price from krakenOb where side=`bid;

spread:.strategy.arb.calculateSpread[bestAsk;bestBid;0.001];

-1 "  Spread analysis:";
show spread;
-1 "";

/ ============================================================================
/ 7. Score Opportunity
/ ============================================================================

-1 "7. Scoring arbitrage opportunity...";

if[not null cross;
  / Score with executable volume
  execVol:.strategy.arb.getExecutableVolume[cross;500.0;0.8;gdaxOb];
  scored:.strategy.arb.scoreOpportunity[cross;execVol];

  -1 "  Scored opportunity:";
  show scored;
];
-1 "";

/ ============================================================================
/ 8. Generate Execution Plan
/ ============================================================================

-1 "8. Generating execution plan...";

if[not null cross;
  / Create scored opportunity
  execVol:.strategy.arb.getExecutableVolume[cross;500.0;0.8;gdaxOb];
  scored:.strategy.arb.scoreOpportunity[cross;execVol];

  / Generate plan
  plan:.strategy.arb.generateExecutionPlan[scored];

  -1 "  Execution plan:";
  -1 "  Buy order:";
  show plan`buyOrder;
  -1 "  Sell order:";
  show plan`sellOrder;
  -1 "  Expected profit: $",string[plan`expectedProfit];
  -1 "  Risk factor: ",string[plan`risk];
];
-1 "";

-1 "Example complete!";
-1 "";

/ Exit
\\
