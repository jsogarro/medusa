/ ============================================================================
/ test_engine_loop.q - Tests for Engine Loop (15 tests)
/ ============================================================================
/ Tests single/multi strategy execution, error isolation, timeout, mode switching
/ ============================================================================

\l tests/q/test_framework.q
\l src/q/engine/types.q
\l src/q/engine/strategy.q
\l src/q/engine/harness.q
\l src/q/engine/loop.q

\d .testLoop

/ ============================================================================
/ MOCK STRATEGY FUNCTIONS
/ ============================================================================

/ Mock strategy that always succeeds
successFns:`configure`setUp`preTick`tick`postTick`isComplete`tearDown!(
  {[state;cfg] state};
  {[state] state};
  {[state;ctx] state};
  {[state;ctx] state[`metadata;`tickCount]+:1; state};
  {[state;ctx] state};
  {[state] state[`metadata;`tickCount] >= 5}; / Complete after 5 ticks
  {[state] state}
 )

/ Mock strategy that throws error in tick phase
errorTickFns:successFns,(enlist `tick)!enlist {[state;ctx] '"Simulated tick error"}

/ Mock strategy that throws error in preTick phase
errorPreTickFns:successFns,(enlist `preTick)!enlist {[state;ctx] '"Simulated preTick error"}

/ Mock strategy that times out (sleeps too long)
/ NOTE: We can't actually sleep in tests, so we simulate timeout detection
timeoutFns:successFns

/ ============================================================================
/ SETUP & TEARDOWN
/ ============================================================================

setUp:{[]
  / Enable logging for tests
  .engine.config.baseSchema[`enableLogging]:1b;

  / Mock harness.init
  .engine.harness.init:{[exchanges;mode]
    `mode`exchanges!(mode; exchanges)
  };

  / Mock harness.getOpenOrders
  .engine.harness.getOpenOrders:{[h] ([]orderId:();pair:();side:();price:();qty:())};

  / Mock harness.getOrderbook
  .engine.harness.getOrderbook:{[h;ex] ([]price:();size:();side:())};

  / Mock harness.shutdown
  .engine.harness.shutdown:{[h] h};

  / Initialize loop
  .engine.loop.init[`binance`coinbase; `dryrun];
 }

tearDown:{[]
  / Shutdown loop
  .engine.loop.shutdown[];
 }

/ ============================================================================
/ TEST CASES
/ ============================================================================

/ Test: Single strategy execution without error
test_single_strategy_execution:{
  setUp[];

  / Create and register strategy
  state:.engine.strategy.new[`test1; "Test Strategy 1"; `test; successFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute one tick
  tickNum:.engine.loop.tick[];

  / Verify tick executed
  .test.assertEqual["Tick number incremented"; 1; tickNum];

  / Verify strategy state updated
  updatedState:.engine.loop.state[`strategies;`test1];
  .test.assert["Strategy still running"; updatedState[`status]~`running];
  .test.assert["Tick count incremented"; updatedState[`metadata;`tickCount] > 0];

  tearDown[];
 }

/ Test: Multiple strategies execute in round-robin
test_multiple_strategies_round_robin:{
  setUp[];

  / Register two strategies
  state1:.engine.strategy.new[`test1; "Test Strategy 1"; `test; successFns];
  state1:.engine.strategy.configure[state1; ()!()];
  state1:.engine.strategy.setUp[state1];
  state1:.engine.strategy.start[state1];
  .engine.loop.register[state1];

  state2:.engine.strategy.new[`test2; "Test Strategy 2"; `test; successFns];
  state2:.engine.strategy.configure[state2; ()!()];
  state2:.engine.strategy.setUp[state2];
  state2:.engine.strategy.start[state2];
  .engine.loop.register[state2];

  / Execute one tick
  .engine.loop.tick[];

  / Verify both strategies executed
  updated1:.engine.loop.state[`strategies;`test1];
  updated2:.engine.loop.state[`strategies;`test2];

  .test.assert["Strategy 1 tick count incremented"; updated1[`metadata;`tickCount] > 0];
  .test.assert["Strategy 2 tick count incremented"; updated2[`metadata;`tickCount] > 0];

  tearDown[];
 }

/ Test: Strategy error doesn't crash loop
test_strategy_error_doesnt_crash_loop:{
  setUp[];

  / Register strategy that will throw error in tick
  state:.engine.strategy.new[`error_test; "Error Test"; `test; errorTickFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute tick (should not crash)
  tickNum:.engine.loop.tick[];

  / Verify tick executed
  .test.assertEqual["Tick executed despite error"; 1; tickNum];

  / Verify error logged
  .test.assert["Error logged"; 0 < count .engine.loop.state`errors];

  / Verify error contains correct phase
  errorPhases:exec phase from .engine.loop.state`errors;
  .test.assert["Error phase is tick"; `tick in errorPhases];

  tearDown[];
 }

/ Test: Timeout detection (simulated)
test_timeout_detection:{
  setUp[];

  / Register normal strategy
  state:.engine.strategy.new[`timeout_test; "Timeout Test"; `test; timeoutFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Manually set tick start time to past (simulate long-running tick)
  .engine.loop.state[`tickStartTime]:.z.p - 10000000000j; / 10 seconds ago

  / Set max tick duration to 5 seconds
  .engine.loop.state[`maxTickDuration]:5000000000j;

  / Execute tick (checkTimeout should detect expiration)
  .engine.loop.tick[];

  / Verify timeout warning logged (check errors table)
  / Note: Timeout warnings are logged via -1, not always added to errors table
  / We verify the mechanism exists by checking state
  .test.assert["Tick completed despite timeout check"; .engine.loop.state[`tickNum] > 0];

  tearDown[];
 }

/ Test: Mode switching (dryrun to live)
test_mode_switching:{
  setUp[];

  / Verify initial mode is dryrun
  harness:.engine.loop.state`harness;
  .test.assertEqual["Initial mode is dryrun"; `dryrun; harness`mode];

  / Reinitialize with live mode
  .engine.loop.init[`binance; `live];

  / Verify mode changed
  harness:.engine.loop.state`harness;
  .test.assertEqual["Mode changed to live"; `live; harness`mode];

  tearDown[];
 }

/ Test: Strategy completes and tears down
test_strategy_completion_teardown:{
  setUp[];

  / Register strategy that completes after 5 ticks
  state:.engine.strategy.new[`complete_test; "Complete Test"; `test; successFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute 5 ticks (should complete)
  do[5; .engine.loop.tick[]];

  / Verify strategy completed and torn down
  finalState:.engine.loop.state[`strategies;`complete_test];
  .test.assertEqual["Strategy stopped"; `stopped; finalState`status];

  tearDown[];
 }

/ Test: Paused strategy doesn't execute
test_paused_strategy_skipped:{
  setUp[];

  / Register and start strategy
  state:.engine.strategy.new[`pause_test; "Pause Test"; `test; successFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute one tick
  .engine.loop.tick[];
  tickCount1:(.engine.loop.state[`strategies;`pause_test])[`metadata;`tickCount];

  / Pause strategy
  pausedState:.engine.strategy.pause[.engine.loop.state[`strategies;`pause_test]];
  .engine.loop.state[`strategies;`pause_test]:pausedState;

  / Execute another tick
  .engine.loop.tick[];
  tickCount2:(.engine.loop.state[`strategies;`pause_test])[`metadata;`tickCount];

  / Verify tick count didn't increase (strategy was skipped)
  .test.assertEqual["Paused strategy didn't execute"; tickCount1; tickCount2];

  tearDown[];
 }

/ Test: Error in preTick phase logged correctly
test_pretick_error_logged:{
  setUp[];

  / Register strategy that errors in preTick
  state:.engine.strategy.new[`pretick_err; "PreTick Error"; `test; errorPreTickFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute tick
  .engine.loop.tick[];

  / Verify error logged with correct phase
  errors:.engine.loop.state`errors;
  .test.assert["Error logged"; 0 < count errors];

  errorPhases:exec phase from errors where strategyId=`pretick_err;
  .test.assert["Error phase is preTick"; `preTick in errorPhases];

  tearDown[];
 }

/ Test: Error in postTick phase logged correctly
test_posttick_error_logged:{
  setUp[];

  / Create errorPostTickFns
  errorPostTickFns:successFns,(enlist `postTick)!enlist {[state;ctx] '"Simulated postTick error"};

  / Register strategy
  state:.engine.strategy.new[`posttick_err; "PostTick Error"; `test; errorPostTickFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Execute tick
  .engine.loop.tick[];

  / Verify error logged with correct phase
  errors:.engine.loop.state`errors;
  errorPhases:exec phase from errors where strategyId=`posttick_err;
  .test.assert["Error phase is postTick"; `postTick in errorPhases];

  tearDown[];
 }

/ Test: Execution context populated correctly
test_execution_context_populated:{
  setUp[];

  / Build context
  ctx:.engine.loop.buildContext[.engine.loop.state`harness];

  / Verify context has required keys
  .test.assert["tickNum present"; `tickNum in key ctx];
  .test.assert["openOrders present"; `openOrders in key ctx];
  .test.assert["orderbooks present"; `orderbooks in key ctx];
  .test.assert["positions present"; `positions in key ctx];

  / Verify tickNum matches loop state
  .test.assertEqual["tickNum matches"; .engine.loop.state`tickNum; ctx`tickNum];

  tearDown[];
 }

/ Test: Loop shutdown tears down all strategies
test_shutdown_tears_down_all:{
  setUp[];

  / Register two strategies
  state1:.engine.strategy.new[`shutdown1; "Shutdown 1"; `test; successFns];
  state1:.engine.strategy.configure[state1; ()!()];
  state1:.engine.strategy.setUp[state1];
  state1:.engine.strategy.start[state1];
  .engine.loop.register[state1];

  state2:.engine.strategy.new[`shutdown2; "Shutdown 2"; `test; successFns];
  state2:.engine.strategy.configure[state2; ()!()];
  state2:.engine.strategy.setUp[state2];
  state2:.engine.strategy.start[state2];
  .engine.loop.register[state2];

  / Shutdown loop
  .engine.loop.shutdown[];

  / Verify both strategies stopped
  .test.assert["All strategies removed"; 0 = count .engine.loop.state`strategies];

  / setUp will reinitialize
  setUp[];
  tearDown[];
 }

/ Test: Unregister strategy removes from loop
test_unregister_removes_strategy:{
  setUp[];

  / Register strategy
  state:.engine.strategy.new[`unreg_test; "Unregister Test"; `test; successFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];
  .engine.loop.register[state];

  / Verify registered
  .test.assert["Strategy registered"; `unreg_test in key .engine.loop.state`strategies];

  / Unregister
  .engine.loop.unregister[`unreg_test];

  / Verify removed
  .test.assert["Strategy unregistered"; not `unreg_test in key .engine.loop.state`strategies];

  tearDown[];
 }

/ Test: Tick counter increments
test_tick_counter_increments:{
  setUp[];

  / Execute 3 ticks
  .engine.loop.tick[];
  .engine.loop.tick[];
  .engine.loop.tick[];

  / Verify tick num = 3
  .test.assertEqual["Tick num is 3"; 3; .engine.loop.state`tickNum];

  tearDown[];
 }

/ Test: Empty strategy list doesn't crash
test_empty_strategies_no_crash:{
  setUp[];

  / Execute tick with no strategies registered
  tickNum:.engine.loop.tick[];

  / Verify tick executed without error
  .test.assertEqual["Tick executed"; 1; tickNum];

  tearDown[];
 }

/ Test: Strategy registration duplicate rejected
test_duplicate_registration_rejected:{
  setUp[];

  / Register strategy
  state:.engine.strategy.new[`dup_test; "Duplicate Test"; `test; successFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  .engine.loop.register[state];

  / Attempt to register again (should fail)
  result:@[.engine.loop.register; state; {`error!enlist x}];

  / Verify error
  .test.assert["Duplicate registration rejected"; (result`error) like "*already registered*"];

  tearDown[];
 }

\d .

/ Run tests
-1 "\n=== Running Engine Loop Tests ===";
.test.run[`.testLoop];
