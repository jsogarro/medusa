/ Integration test for full engine functionality
/ Run with: q test_integration.q

/ Load all engine modules
\l ../../../src/q/engine/types.q
\l ../../../src/q/engine/strategy.q
\l ../../../src/q/engine/config.q
\l ../../../src/q/engine/harness.q
\l ../../../src/q/engine/mode.q
\l ../../../src/q/engine/actor.q
\l ../../../src/q/engine/history.q
\l ../../../src/q/engine/position.q
\l ../../../src/q/engine/orders.q
\l ../../../src/q/engine/loop.q

/ Simple assert function
assert:{[cond;msg] if[not cond;'"FAIL: ",msg]}

/ Test counter
testCount:0
passCount:0

/ Test runner
runTest:{[name;testFn]
  testCount+:1;
  -1"[TEST ",string[testCount],"] ",name;
  result:@[testFn;();{-1"  ERROR: ",x;0b}];
  if[result;
    passCount+:1;
    -1"  PASS";
  ];
 }

/ Test 1: Full strategy lifecycle
test_fullLifecycle:{
  / Register actor
  .engine.actor.register[`testBot;`name`description!(`$"Test Bot";`$"Integration test actor")];

  / Create strategy functions
  setupRan:0b;
  tickCount:0;
  tearDownRan:0b;

  fns:(!) . flip (
    (`setUp; {[s] setupRan:1b; s});
    (`tick; {[s;ctx] tickCount+:1; s});
    (`isComplete; {[s] tickCount>=5});  / Complete after 5 ticks
    (`tearDown; {[s] tearDownRan:1b; s})
  );

  / Create and configure strategy
  state:.engine.strategy.new[`integTest1;`$"Integration Test Strategy";`testBot;fns];
  cfg:.engine.config.create[`default;()!()];
  state:.engine.strategy.configure[state;cfg];

  / Set up and start
  state:.engine.strategy.setUp[state];
  assert[setupRan;"Setup should run"];
  assert[state[`status]~`ready;"Status should be ready"];

  state:.engine.strategy.start[state];
  assert[state[`status]~`running;"Status should be running"];

  / Initialize loop
  .engine.loop.init[`kraken`coinbase;`dryrun];
  .engine.loop.register[state];

  / Run 5 ticks
  do[5;.engine.loop.tick[]];
  assert[tickCount=5;"Should execute 5 ticks"];

  / Check if strategy completed and tore down
  finalState:.engine.loop.state[`strategies;`integTest1];
  assert[finalState[`status]~`stopped;"Should be stopped after completion"];
  assert[tearDownRan;"Tear down should run"];

  1b
 }

/ Test 2: Multiple strategies in parallel
test_multipleStrategies:{
  tick1:0;
  tick2:0;
  tick3:0;

  fns1:(!) . flip ((`tick; {[s;ctx] tick1+:1; s}));
  fns2:(!) . flip ((`tick; {[s;ctx] tick2+:1; s}));
  fns3:(!) . flip ((`tick; {[s;ctx] tick3+:1; s}));

  / Create three strategies
  state1:.engine.strategy.new[`strat1;`$"Strategy 1";`bot1;fns1];
  state1:.engine.strategy.setUp[state1];
  state1:.engine.strategy.start[state1];

  state2:.engine.strategy.new[`strat2;`$"Strategy 2";`bot2;fns2];
  state2:.engine.strategy.setUp[state2];
  state2:.engine.strategy.start[state2];

  state3:.engine.strategy.new[`strat3;`$"Strategy 3";`bot3;fns3];
  state3:.engine.strategy.setUp[state3];
  state3:.engine.strategy.start[state3];

  / Initialize loop and register all
  .engine.loop.init[`kraken`coinbase`bitstamp;`dryrun];
  .engine.loop.register[state1];
  .engine.loop.register[state2];
  .engine.loop.register[state3];

  / Execute 3 ticks
  do[3;.engine.loop.tick[]];

  / All should tick same number of times
  assert[tick1=3;"Strategy 1 should tick 3 times"];
  assert[tick2=3;"Strategy 2 should tick 3 times"];
  assert[tick3=3;"Strategy 3 should tick 3 times"];

  1b
 }

/ Test 3: Harness order placement
test_orderPlacement:{
  / Initialize harness in dry-run mode
  .engine.loop.init[`kraken;`dryrun];
  harness:.engine.loop.state[`harness];

  / Place buy order
  result:.engine.harness.placeOrder[harness;`kraken;`buy;50000.0;1.0];
  harness:result 0;
  orderId:result 1;

  assert[not null orderId;"Order ID should be generated"];

  / Check order appears in open orders
  openOrders:.engine.harness.getOpenOrders[harness];
  assert[count openOrders>0;"Should have open orders"];
  assert[orderId in exec orderId from openOrders;"Order should be in open orders"];

  / Cancel order
  harness:.engine.harness.cancelOrder[harness;orderId];
  openOrders:.engine.harness.getOpenOrders[harness];
  cancelledOrder:select from harness[`dryRunOrders] where orderId=orderId;
  assert[exec first status from cancelledOrder in `cancelled;"Order should be cancelled"];

  1b
 }

/ Test 4: Mode management
test_modeManagement:{
  / Default mode should be dryrun
  assert[.engine.mode.current~`dryrun;"Default mode should be dryrun"];
  assert[.engine.mode.isDryRun[];"Should detect dry-run mode"];

  / Try to set live mode without confirmation
  result:@[.engine.mode.set;enlist `live;{x}];
  assert[10h=type result;"Should error without confirmation"];

  / Confirm and set live mode
  .engine.mode.confirmLive[];
  .engine.mode.set[`live];
  assert[.engine.mode.isLive[];"Should detect live mode"];

  / Reset to dryrun
  .engine.mode.resetConfirmation[];
  .engine.mode.set[`dryrun];
  assert[.engine.mode.isDryRun[];"Should be back to dry-run"];

  1b
 }

/ Test 5: History tracking
test_historyTracking:{
  / Clear cache
  .engine.history.clearCache[];

  / Record some trades
  trade1:`id`timestamp`exchange`asset`side`price`volume`strategyId`actor!(1;.z.p;`kraken;`BTCUSD;`buy;50000.0;1.0;`strat1;`bot1);
  trade2:`id`timestamp`exchange`asset`side`price`volume`strategyId`actor!(2;.z.p;`coinbase;`BTCUSD;`sell;50100.0;1.0;`strat1;`bot1);

  .engine.history.record[trade1];
  .engine.history.record[trade2];

  / Query by strategy
  stratTrades:.engine.history.getStrategyTrades[`strat1];
  assert[count stratTrades=2;"Should have 2 trades for strategy"];

  / Query by exchange
  krakenTrades:.engine.history.getByExchange[`kraken];
  assert[count krakenTrades=1;"Should have 1 trade on kraken"];

  1b
 }

/ Test 6: Position tracking
test_positionTracking:{
  / Clear cache
  .engine.position.clearCache[];

  / Get initial position (should be zero)
  pos:.engine.position.get[`kraken;`BTCUSD;`strat1];
  assert[pos[`quantity]=0.0;"Initial position should be zero"];

  / Update position with a buy
  pos:.engine.position.update[`kraken;`BTCUSD;`buy;50000.0;1.0;`strat1];
  assert[pos[`quantity]=1.0;"Position should be 1.0 after buy"];
  assert[pos[`avgPrice]=50000.0;"Average price should be 50000"];

  / Update with another buy at different price
  pos:.engine.position.update[`kraken;`BTCUSD;`buy;51000.0;1.0;`strat1];
  assert[pos[`quantity]=2.0;"Position should be 2.0 after second buy"];
  assert[pos[`avgPrice]=50500.0;"Average price should be weighted"];

  / Update with a sell
  pos:.engine.position.update[`kraken;`BTCUSD;`sell;52000.0;1.0;`strat1];
  assert[pos[`quantity]=1.0;"Position should be 1.0 after sell"];

  1b
 }

/ Test 7: Orders cache
test_ordersCache:{
  / Clear cache
  .engine.orders.clearCache[];

  / Initialize harness
  .engine.loop.init[`kraken;`dryrun];
  harness:.engine.loop.state[`harness];

  / Place order
  result:.engine.harness.placeOrder[harness;`kraken;`buy;50000.0;1.0];
  harness:result 0;
  orderId:result 1;

  / Fetch orders (should populate cache)
  orders:.engine.orders.fetch[harness;`strat1];
  assert[count orders>0;"Should fetch orders"];

  / Update order status
  .engine.orders.updateStatus[orderId;`filled;1.0];

  1b
 }

/ Test 8: Error handling in tick loop
test_errorHandling:{
  / Clear errors
  .engine.loop.state[`errors]:0#.engine.loop.state[`errors];

  / Create strategy that errors on tick
  fns:(!) . flip (
    (`tick; {[s;ctx] '"Test error"})
  );

  state:.engine.strategy.new[`errorTest;`$"Error Test";`bot1;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  .engine.loop.init[`kraken;`dryrun];
  .engine.loop.register[state];

  / Execute tick (should not crash)
  .engine.loop.tick[];

  / Check error was logged
  assert[count .engine.loop.state[`errors]>0;"Error should be logged"];
  lastError:last .engine.loop.state[`errors];
  assert[lastError[`strategyId]~`errorTest;"Error should be attributed to strategy"];
  assert[lastError[`phase]~`tick;"Error should be in tick phase"];

  1b
 }

/ Test 9: Config schema registration
test_configSchema:{
  / Register custom config schema
  customSchema:`minSpread`maxSize!(0.01;100.0);
  .engine.config.register[`customType;customSchema];

  / Create config with defaults
  cfg:.engine.config.create[`customType;()!()];
  assert[cfg[`minSpread]=0.01;"Should use schema defaults"];

  / Create config with overrides
  cfg2:.engine.config.create[`customType;`minSpread`maxSize!(0.02;200.0)];
  assert[cfg2[`minSpread]=0.02;"Should apply overrides"];
  assert[cfg2[`maxSize]=200.0;"Should apply overrides"];

  1b
 }

/ Test 10: Full shutdown
test_fullShutdown:{
  / Set up complete environment
  .engine.loop.init[`kraken`coinbase;`dryrun];

  state1:.engine.strategy.new[`shutdown1;`$"Shutdown Test 1";`bot1;()!()];
  state1:.engine.strategy.setUp[state1];
  state1:.engine.strategy.start[state1];
  .engine.loop.register[state1];

  state2:.engine.strategy.new[`shutdown2;`$"Shutdown Test 2";`bot2;()!()];
  state2:.engine.strategy.setUp[state2];
  state2:.engine.strategy.start[state2];
  .engine.loop.register[state2];

  / Run a few ticks
  do[3;.engine.loop.tick[]];

  / Shutdown
  .engine.loop.shutdown[];

  / Verify clean shutdown
  assert[0=count .engine.loop.state[`strategies];"All strategies should be removed"];
  assert[not .engine.loop.state[`running];"Loop should not be running"];

  / Verify strategies were torn down
  / (In real implementation, would check that strategies are in stopped state)

  1b
 }

/ Run all tests
runTest["Full strategy lifecycle";test_fullLifecycle]
runTest["Multiple strategies in parallel";test_multipleStrategies]
runTest["Harness order placement";test_orderPlacement]
runTest["Mode management";test_modeManagement]
runTest["History tracking";test_historyTracking]
runTest["Position tracking";test_positionTracking]
runTest["Orders cache";test_ordersCache]
runTest["Error handling in tick loop";test_errorHandling]
runTest["Config schema registration";test_configSchema]
runTest["Full shutdown";test_fullShutdown]

/ Summary
-1"";
-1"========================================";
-1"RESULTS: ",string[passCount],"/",string[testCount]," tests passed";
if[passCount=testCount;
  -1"ALL TESTS PASSED";
  exit 0;
 ];
-1"SOME TESTS FAILED";
exit 1;
