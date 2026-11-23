/ Tests for .engine namespace (engine/*.q)

\l tests/q/test_framework.q
\l src/q/engine/types.q
\l src/q/engine/strategy.q
\l src/q/engine/mode.q

/ ========================================
/ Mode management tests
/ ========================================

test_mode_default_dryrun:{
  .test.assertEqual["Default mode is dryrun"; `dryrun; .engine.mode.current];
 }

test_mode_set_dryrun:{
  .engine.mode.set[`dryrun];
  .test.assert["isDryRun returns true"; .engine.mode.isDryRun[]];
  .test.assert["isLive returns false"; not .engine.mode.isLive[]];
 }

test_mode_set_live_requires_confirmation:{
  / Reset confirmation
  .engine.mode.liveConfirmed:0b;

  / Attempt to set live without confirmation
  .test.assertError["Live without confirm throws"; {.engine.mode.set[`live]}];
 }

test_mode_set_live_with_confirmation:{
  / Confirm
  .engine.mode.confirmLive[];
  .test.assert["Confirmation flag set"; .engine.mode.liveConfirmed];

  / Set live
  .engine.mode.set[`live];
  .test.assert["isLive returns true"; .engine.mode.isLive[]];

  / Confirmation reset after use
  .test.assert["Confirmation reset"; not .engine.mode.liveConfirmed];

  / Reset to dryrun
  .engine.mode.current:`dryrun;
 }

test_mode_guard_dryrun:{
  .engine.mode.set[`dryrun];

  / Define test function
  testFn:{[x] x * 2};

  / Guard with correct mode
  result:.engine.mode.guard[`dryrun; testFn; enlist 5];
  .test.assertEqual["Function executed in dryrun"; 10; result];

  / Guard with wrong mode
  result:.engine.mode.guard[`live; testFn; enlist 5];
  .test.assert["Function not executed in wrong mode"; ()~result];
 }

/ ========================================
/ Strategy lifecycle tests
/ ========================================

test_strategy_new:{
  state:.engine.strategy.new[`test1; "Test Strategy"; `actor1; ()!()];

  .test.assert["State is dict"; 99h = type state];
  .test.assertEqual["ID set"; `test1; state`id];
  .test.assertEqual["Name set"; "Test Strategy"; state`name];
  .test.assertEqual["Actor set"; `actor1; state`actor];
  .test.assertEqual["Status is init"; `init; state`status];
  .test.assertEqual["Mode is dryrun"; `dryrun; state`mode];
 }

test_strategy_configure:{
  state:.engine.strategy.new[`test2; "Test Strategy"; `actor2; ()!()];

  cfg:`tick_sleep`max_position!(100; 1000000);
  state:.engine.strategy.configure[state; cfg];

  .test.assertEqual["Config applied"; cfg; state`config];
 }

test_strategy_setUp:{
  state:.engine.strategy.new[`test3; "Test Strategy"; `actor3; ()!()];
  cfg:`tick_sleep!(100);
  state:.engine.strategy.configure[state; cfg];

  state:.engine.strategy.setUp[state];

  .test.assertEqual["Status is ready"; `ready; state`status];
  .test.assert["setUpAt timestamp set"; not null state[`metadata;`setUpAt]];
 }

test_strategy_start_pause:{
  state:.engine.strategy.new[`test4; "Test Strategy"; `actor4; ()!()];
  state:.engine.strategy.configure[state; `tick_sleep!(100)];
  state:.engine.strategy.setUp[state];

  / Start
  state:.engine.strategy.start[state];
  .test.assertEqual["Status is running"; `running; state`status];

  / Pause
  state:.engine.strategy.pause[state];
  .test.assertEqual["Status is paused"; `paused; state`status];
 }

test_strategy_setMode:{
  state:.engine.strategy.new[`test5; "Test Strategy"; `actor5; ()!()];

  / Set mode in init status
  state:.engine.strategy.setMode[state; `dryrun];
  .test.assertEqual["Mode set to dryrun"; `dryrun; state`mode];

  / Cannot change mode after setUp
  state:.engine.strategy.setUp[state];
  .test.assertError["Cannot change mode after setUp"; {.engine.strategy.setMode[state; `live]}];
 }

test_strategy_tick:{
  / Define custom tick function
  customFns:(enlist `tick)!(enlist {[state;ctx]
    state
  });

  state:.engine.strategy.new[`test6; "Test Strategy"; `actor6; customFns];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  / Execute tick
  ctx:()!();
  state:.engine.strategy.tick[state; ctx];

  .test.assertEqual["Tick count incremented"; 1; state[`metadata;`tickCount]];
  .test.assert["lastTickAt set"; not null state[`metadata;`lastTickAt]];
 }

test_strategy_tearDown:{
  state:.engine.strategy.new[`test7; "Test Strategy"; `actor7; ()!()];
  state:.engine.strategy.configure[state; ()!()];
  state:.engine.strategy.setUp[state];
  state:.engine.strategy.start[state];

  / Tear down
  state:.engine.strategy.tearDown[state];

  .test.assertEqual["Status is stopped"; `stopped; state`status];
  .test.assert["stoppedAt timestamp set"; not null state[`metadata;`stoppedAt]];
 }

-1 "Engine tests loaded";
