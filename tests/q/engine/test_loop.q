/ Test tick loop orchestration
/ Run with: q test_loop.q

/ Load engine modules
\l ../../../src/q/engine/types.q
\l ../../../src/q/engine/strategy.q
\l ../../../src/q/engine/config.q
\l ../../../src/q/engine/harness.q
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

/ Test 1: Initialize loop
test_initLoop:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  assert[not (::)~.engine.loop.state[`harness];"Harness should be initialized"];
  assert[.engine.loop.state[`tickNum]=0;"Tick number should be 0"];
  assert[not .engine.loop.state[`running];"Loop should not be running"];

  1b
 }

/ Test 2: Register strategy
test_registerStrategy:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  state:.engine.strategy.new[`test1;`$"Test Strategy";`testActor;()!()];
  .engine.loop.register[state];

  assert[`test1 in key .engine.loop.state[`strategies];"Strategy should be registered"];

  1b
 }

/ Test 3: Unregister strategy
test_unregisterStrategy:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  state:.engine.strategy.new[`test2;`$"Test Strategy";`testActor;()!()];
  .engine.loop.register[state];
  .engine.loop.unregister[`test2];

  assert[not `test2 in key .engine.loop.state[`strategies];"Strategy should be unregistered"];

  1b
 }

/ Test 4: Build execution context
test_buildContext:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  ctx:.engine.loop.buildContext[.engine.loop.state[`harness]];

  assert[`timestamp in key ctx;"Context should have timestamp"];
  assert[`tickNum in key ctx;"Context should have tickNum"];
  assert[`openOrders in key key ctx;"Context should have openOrders"];
  assert[`orderbooks in key ctx;"Context should have orderbooks"];
  assert[count ctx[`orderbooks]=2;"Should have orderbooks for both exchanges"];

  1b
 }

/ Test 5: Tick one strategy
test_tickOne:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  tickRan:0b;
  fns:(!) . flip (
    (`tick; {[s;ctx] tickRan:1b; s})
  );

  state:.engine.strategy.new[`test3;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  ctx:.engine.loop.buildContext[.engine.loop.state[`harness]];
  newState:.engine.loop.tickOne[`test3;ctx];

  assert[tickRan;"Tick should execute"];
  assert[newState[`status]~`running;"Status should remain running"];

  1b
 }

/ Test 6: Error isolation in tick
test_errorIsolation:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  fns:(!) . flip (
    (`tick; {[s;ctx] '"Intentional error"})
  );

  state:.engine.strategy.new[`test4;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  ctx:.engine.loop.buildContext[.engine.loop.state[`harness]];

  / Tick should not crash, just log error
  newState:.engine.loop.tickOne[`test4;ctx];

  assert[count .engine.loop.state[`errors]>0;"Error should be logged"];
  assert[newState[`id]~`test4;"Original state should be returned on error"];

  1b
 }

/ Test 7: Full tick execution
test_fullTick:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  tickCount1:0;
  tickCount2:0;

  fns1:(!) . flip (
    (`tick; {[s;ctx] tickCount1+:1; s})
  );
  fns2:(!) . flip (
    (`tick; {[s;ctx] tickCount2+:1; s})
  );

  state1:.engine.strategy.new[`test5a;`$"Test Strategy 1";`testActor;fns1];
  state1:.engine.strategy.setUp[state1];
  state1:.engine.strategy.start[state1];
  .engine.loop.register[state1];

  state2:.engine.strategy.new[`test5b;`$"Test Strategy 2";`testActor;fns2];
  state2:.engine.strategy.setUp[state2];
  state2:.engine.strategy.start[state2];
  .engine.loop.register[state2];

  / Execute one full tick
  tickNum:.engine.loop.tick[];

  assert[tickNum=1;"Tick number should increment"];
  assert[tickCount1=1;"First strategy should tick"];
  assert[tickCount2=1;"Second strategy should tick"];

  1b
 }

/ Test 8: Auto tear down on completion
test_autoTearDown:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  tickCount:0;
  fns:(!) . flip (
    (`tick; {[s;ctx] tickCount+:1; s});
    (`isComplete; {[s] tickCount>=2});  / Complete after 2 ticks
    (`tearDown; {[s] s[`status]:`stopped; s})
  );

  state:.engine.strategy.new[`test6;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / First tick - not complete
  .engine.loop.tick[];
  currentState:.engine.loop.state[`strategies;`test6];
  assert[currentState[`status]~`running;"Should still be running after tick 1"];

  / Second tick - complete, should auto tear down
  .engine.loop.tick[];
  currentState:.engine.loop.state[`strategies;`test6];
  assert[currentState[`status]~`stopped;"Should be stopped after completion"];

  1b
 }

/ Test 9: Stop loop
test_stopLoop:{
  .engine.loop.init[`kraken`coinbase;`dryrun];
  .engine.loop.state[`running]:1b;
  .engine.loop.stop[];

  assert[not .engine.loop.state[`running];"Loop should stop"];

  1b
 }

/ Test 10: Shutdown loop
test_shutdown:{
  .engine.loop.init[`kraken`coinbase;`dryrun];

  state:.engine.strategy.new[`test7;`$"Test Strategy";`testActor;()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  .engine.loop.shutdown[];

  assert[0=count .engine.loop.state[`strategies];"All strategies should be removed"];
  assert[not .engine.loop.state[`running];"Loop should not be running"];

  1b
 }

/ Run all tests
runTest["Initialize loop";test_initLoop]
runTest["Register strategy";test_registerStrategy]
runTest["Unregister strategy";test_unregisterStrategy]
runTest["Build execution context";test_buildContext]
runTest["Tick one strategy";test_tickOne]
runTest["Error isolation in tick";test_errorIsolation]
runTest["Full tick execution";test_fullTick]
runTest["Auto tear down on completion";test_autoTearDown]
runTest["Stop loop";test_stopLoop]
runTest["Shutdown loop";test_shutdown]

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
