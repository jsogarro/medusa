/ Test strategy lifecycle and execution
/ Run with: q test_strategy.q

/ Load engine modules
\l ../../../src/q/engine/types.q
\l ../../../src/q/engine/strategy.q
\l ../../../src/q/engine/config.q

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

/ Test 1: Create new strategy
test_newStrategy:{
  fns:(!) . flip (
    (`configure; {[s;c] s});
    (`setUp; {[s] s});
    (`tick; {[s;ctx] s})
  );

  state:.engine.strategy.new[`test1;`$"Test Strategy";`testActor;fns];

  assert[state[`id]~`test1;"Strategy ID should be test1"];
  assert[state[`name]~`$"Test Strategy";"Strategy name should match"];
  assert[state[`actor]~`testActor;"Actor should be testActor"];
  assert[state[`status]~`init;"Initial status should be init"];
  assert[state[`mode]~`dryrun;"Default mode should be dryrun"];

  1b
 }

/ Test 2: Configure strategy
test_configure:{
  fns:(!) . flip (
    (`configure; {[s;c] s[`config]:c; s});
    (`setUp; {[s] s})
  );

  state:.engine.strategy.new[`test2;`$"Test Strategy";`testActor;fns];
  cfg:`tickInterval`maxPositionSize!(100;5000.0);

  state:.engine.strategy.configure[state;cfg];

  assert[state[`config;`tickInterval]=100;"Config should be applied"];
  assert[state[`status]~`init;"Status should remain init after configure"];

  1b
 }

/ Test 3: Set up strategy
test_setUp:{
  fns:(!) . flip (
    (`setUp; {[s] s[`state;`initialized]:1b; s})
  );

  state:.engine.strategy.new[`test3;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];

  assert[state[`status]~`ready;"Status should be ready after setUp"];
  assert[state[`state;`initialized]~1b;"Custom setUp should run"];
  assert[`setUpAt in key state[`metadata];"Metadata should have setUpAt"];

  1b
 }

/ Test 4: Start strategy
test_start:{
  state:.engine.strategy.new[`test4;`$"Test Strategy";`testActor;()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  assert[state[`status]~`running;"Status should be running after start"];
  assert[`startedAt in key state[`metadata];"Metadata should have startedAt"];

  1b
 }

/ Test 5: Pause and resume strategy
test_pauseResume:{
  state:.engine.strategy.new[`test5;`$"Test Strategy";`testActor;()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  state:.engine.strategy.pause[state];

  assert[state[`status]~`paused;"Status should be paused"];

  state:.engine.strategy.start[state];
  assert[state[`status]~`running;"Status should be running after resume"];

  1b
 }

/ Test 6: Set mode
test_setMode:{
  state:.engine.strategy.new[`test6;`$"Test Strategy";`testActor;()!()];
  state:.engine.strategy.setMode[state;`dryrun];

  assert[state[`mode]~`dryrun;"Mode should be dryrun"];

  / Can only set mode in init status
  state:.engine.strategy.setUp[state];
  result:@[.engine.strategy.setMode;(state;`live);{x}];
  assert[10h=type result;"Should error when setting mode after init"];

  1b
 }

/ Test 7: Tick execution
test_tick:{
  tickCount:0;
  fns:(!) . flip (
    (`tick; {[s;ctx] tickCount+:1; s[`state;`lastTick]:ctx[`tickNum]; s})
  );

  state:.engine.strategy.new[`test7;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  / Create execution context
  ctx:.engine.types.newExecContext[1;(::)];

  / Execute tick
  state:.engine.strategy.tick[state;ctx];

  assert[tickCount=1;"Tick function should execute"];
  assert[state[`state;`lastTick]=1;"Tick context should be passed"];
  assert[state[`metadata;`tickCount]=1;"Tick count should increment"];

  1b
 }

/ Test 8: Pre-tick and post-tick hooks
test_hooks:{
  preTickRan:0b;
  postTickRan:0b;

  fns:(!) . flip (
    (`preTick; {[s;ctx] preTickRan:1b; s});
    (`tick; {[s;ctx] s});
    (`postTick; {[s;ctx] postTickRan:1b; s})
  );

  state:.engine.strategy.new[`test8;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  ctx:.engine.types.newExecContext[1;(::)];

  state:.engine.strategy.preTick[state;ctx];
  assert[preTickRan;"Pre-tick hook should run"];

  state:.engine.strategy.tick[state;ctx];
  state:.engine.strategy.postTick[state;ctx];
  assert[postTickRan;"Post-tick hook should run"];

  1b
 }

/ Test 9: Is complete check
test_isComplete:{
  tickCount:0;
  fns:(!) . flip (
    (`tick; {[s;ctx] tickCount+:1; s});
    (`isComplete; {[s] tickCount>=3})  / Complete after 3 ticks
  );

  state:.engine.strategy.new[`test9;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  ctx:.engine.types.newExecContext[1;(::)];

  assert[not .engine.strategy.isComplete[state];"Should not be complete initially"];

  state:.engine.strategy.tick[state;ctx];
  state:.engine.strategy.tick[state;ctx];
  assert[not .engine.strategy.isComplete[state];"Should not be complete after 2 ticks"];

  state:.engine.strategy.tick[state;ctx];
  assert[.engine.strategy.isComplete[state];"Should be complete after 3 ticks"];

  1b
 }

/ Test 10: Tear down strategy
test_tearDown:{
  tearDownRan:0b;
  fns:(!) . flip (
    (`tearDown; {[s] tearDownRan:1b; s})
  );

  state:.engine.strategy.new[`test10;`$"Test Strategy";`testActor;fns];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  state:.engine.strategy.tearDown[state];

  assert[tearDownRan;"Tear down function should run"];
  assert[state[`status]~`stopped;"Status should be stopped"];
  assert[`stoppedAt in key state[`metadata];"Metadata should have stoppedAt"];

  1b
 }

/ Test 11: Invalid state transitions
test_invalidTransitions:{
  / Cannot pause from init status
  state:.engine.strategy.new[`test11a;`$"Test Strategy";`testActor;()!()];
  result:@[.engine.strategy.pause;state;{x}];
  assert[10h=type result;"Should error when pausing from init status"];

  / Cannot start from init without setUp
  state:.engine.strategy.new[`test11b;`$"Test Strategy";`testActor;()!()];
  result:@[.engine.strategy.start;state;{x}];
  assert[10h=type result;"Should error when starting from init without setUp"];

  / Cannot start after tearDown
  state:.engine.strategy.new[`test11c;`$"Test Strategy";`testActor;()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  state:.engine.strategy.tearDown[state];
  result:@[.engine.strategy.start;state;{x}];
  assert[10h=type result;"Should error when starting after tearDown"];

  1b
 }

/ Run all tests
runTest["Create new strategy";test_newStrategy]
runTest["Configure strategy";test_configure]
runTest["Set up strategy";test_setUp]
runTest["Start strategy";test_start]
runTest["Pause and resume strategy";test_pauseResume]
runTest["Set mode";test_setMode]
runTest["Tick execution";test_tick]
runTest["Pre-tick and post-tick hooks";test_hooks]
runTest["Is complete check";test_isComplete]
runTest["Tear down strategy";test_tearDown]
runTest["Invalid state transitions";test_invalidTransitions]

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
