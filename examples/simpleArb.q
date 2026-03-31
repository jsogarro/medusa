/ Simple arbitrage strategy example
/ Demonstrates the full strategy engine usage

/ Load engine modules (assumes they're already loaded in order)
/ In practice, these would be loaded via init.q

\d .simpleArb

/ Strategy configuration schema
configSchema:`minSpreadPercent`maxOrderSize`exchanges!(
  0.005;      / 0.5% minimum spread
  1.0;        / max 1.0 BTC per order
  `kraken`coinbase
 )

/ Register config schema
.engine.config.register[`simpleArb;configSchema]

/ Strategy state (custom fields beyond base)
state:`lastOrderTime`totalOrders`totalProfit!(.z.p;0;0.0)

/ Configure function - validate exchanges
configure:{[state;cfg]
  / Check that required exchanges are available
  if[not all cfg[`exchanges] in key state[`exchanges];
    '"Required exchanges not available"];

  / Store config in state
  state[`config]:cfg;
  state
 }

/ Set up function - initialize custom state
setUp:{[state]
  / Initialize custom state fields
  state[`state;`lastOrderTime]:.z.p;
  state[`state;`totalOrders]:0;
  state[`state;`totalProfit]:0.0;

  / Log setup
  -1"[SimpleArb] Strategy set up for exchanges: ",", " sv string state[`config;`exchanges];

  state
 }

/ Pre-tick function - log tick start
preTick:{[state;ctx]
  if[state[`config;`enableLogging];
    -1"[SimpleArb] Pre-tick ",string ctx[`tickNum];
  ];
  state
 }

/ Main tick function - execute arbitrage logic
tick:{[state;ctx]
  cfg:state[`config];
  exchanges:cfg[`exchanges];

  / Get orderbooks for both exchanges
  ob1:ctx[`orderbooks;exchanges 0];
  ob2:ctx[`orderbooks;exchanges 1];

  / Get best bid/ask on each exchange
  bestBid1:exec first price from `price xdesc ob1[`bids];
  bestAsk1:exec first price from `price xasc ob1[`asks];
  bestBid2:exec first price from `price xdesc ob2[`bids];
  bestAsk2:exec first price from `price xasc ob2[`asks];

  / Calculate spreads
  / Opportunity 1: buy on ex1, sell on ex2
  spread1:(bestBid2 - bestAsk1) % bestAsk1;

  / Opportunity 2: buy on ex2, sell on ex1
  spread2:(bestBid1 - bestAsk2) % bestAsk2;

  / Check if either spread exceeds minimum
  minSpread:cfg[`minSpreadPercent];

  / Execute arbitrage if spread is sufficient
  if[spread1 > minSpread;
    / Buy on ex1, sell on ex2
    volume:cfg[`maxOrderSize];

    / Place buy order using global harness
    result:.engine.harness.placeOrder[.engine.loop.state[`harness];exchanges 0;`buy;bestAsk1;volume];
    .engine.loop.state[`harness]:result 0;
    buyOrderId:result 1;

    / Place sell order using global harness
    result:.engine.harness.placeOrder[.engine.loop.state[`harness];exchanges 1;`sell;bestBid2;volume];
    .engine.loop.state[`harness]:result 0;
    sellOrderId:result 1;

    / Update state
    state[`state;`totalOrders]:state[`state;`totalOrders]+2;
    state[`state;`totalProfit]:state[`state;`totalProfit]+(volume * (bestBid2 - bestAsk1));
    state[`state;`lastOrderTime]:.z.p;

    -1"[SimpleArb] Executed arb: buy ",string[volume]," @ ",string[bestAsk1]," on ",string[exchanges 0],", sell @ ",string[bestBid2]," on ",string[exchanges 1];
  ];

  if[spread2 > minSpread;
    / Buy on ex2, sell on ex1
    volume:cfg[`maxOrderSize];

    / Place buy order using global harness
    result:.engine.harness.placeOrder[.engine.loop.state[`harness];exchanges 1;`buy;bestAsk2;volume];
    .engine.loop.state[`harness]:result 0;
    buyOrderId:result 1;

    / Place sell order using global harness
    result:.engine.harness.placeOrder[.engine.loop.state[`harness];exchanges 0;`sell;bestBid1;volume];
    .engine.loop.state[`harness]:result 0;
    sellOrderId:result 1;

    / Update state
    state[`state;`totalOrders]:state[`state;`totalOrders]+2;
    state[`state;`totalProfit]:state[`state;`totalProfit]+(volume * (bestBid1 - bestAsk2));
    state[`state;`lastOrderTime]:.z.p;

    -1"[SimpleArb] Executed arb: buy ",string[volume]," @ ",string[bestAsk2]," on ",string[exchanges 1],", sell @ ",string[bestBid1]," on ",string[exchanges 0];
  ];

  state
 }

/ Post-tick function - log statistics
postTick:{[state;ctx]
  / Every 10 ticks, log stats
  if[0=ctx[`tickNum] mod 10;
    -1"[SimpleArb] Stats: totalOrders=",string[state[`state;`totalOrders]],", totalProfit=",string state[`state;`totalProfit];
  ];
  state
 }

/ Is complete function - never complete (run forever)
isComplete:{[state]
  0b  / never complete
 }

/ Tear down function - log final stats
tearDown:{[state]
  -1"[SimpleArb] Tearing down. Final stats:";
  -1"  Total orders: ",string state[`state;`totalOrders];
  -1"  Total profit: ",string state[`state;`totalProfit];
  state
 }

/ Helper function to create and run the strategy
run:{[mode;intervalMs]
  / Create strategy functions dict
  fns:`configure`setUp`preTick`tick`postTick`isComplete`tearDown!(
    configure;setUp;preTick;tick;postTick;isComplete;tearDown
  );

  / Create strategy instance
  state:.engine.strategy.new[`simpleArb1;`$"Simple Arbitrage";`arbBot;fns];

  / Set mode
  state:.engine.strategy.setMode[state;mode];

  / Create config
  cfg:.engine.config.create[`simpleArb;()!()];  / use defaults

  / Configure strategy
  state:.engine.strategy.configure[state;cfg];

  / Set up strategy
  state:.engine.strategy.setUp[state];

  / Initialize loop
  .engine.loop.init[cfg[`exchanges];mode];

  / Register strategy
  .engine.loop.register[state];

  / Start strategy
  state:.engine.strategy.start[state];
  .engine.loop.state[`strategies;`simpleArb1]:state;

  / Run loop
  -1"[SimpleArb] Starting execution loop...";
  .engine.loop.run[intervalMs];
 }

/ Quick start function (dry-run mode, 1 second intervals)
start:{
  run[`dryrun;1000]
 }

\d .
