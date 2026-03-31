/ Engine type definitions and schemas
/ Load order: 1 - types.q (first, no dependencies)

\d .engine

/ Strategy state schema
types.strategyState:`id`name`actor`mode`status`config`state`exchanges`metadata!()

/ Default strategy state constructor
types.newStrategyState:{[id;name;actor]
  `id`name`actor`mode`status`config`state`exchanges`metadata!(
    id;
    name;
    actor;
    `dryrun;                    / default mode
    `init;                      / initial status
    ()!();                      / empty config
    ()!();                      / empty state
    ();                         / empty exchanges list
    (enlist[`created]!enlist .z.p) / creation timestamp
  )
 }

/ Strategy lifecycle statuses
/ init -> ready -> running -> paused -> running -> stopped
/ init -> ready -> running -> stopped
types.validStatuses:`init`ready`running`paused`stopped

/ Strategy modes
types.validModes:`live`dryrun

/ Strategy function signatures (default no-ops)
types.strategyFns:`configure`setUp`preTick`tick`postTick`isComplete`tearDown!()

/ Default strategy functions
types.defaultFns:(!) . flip (
  (`configure;   {[state;cfg] state});                   / configure: apply config
  (`setUp;       {[state] state});                       / setUp: one-time initialization
  (`preTick;     {[state;ctx] state});                   / preTick: pre-tick hook
  (`tick;        {[state;ctx] state});                   / tick: main strategy logic
  (`postTick;    {[state;ctx] state});                   / postTick: post-tick hook
  (`isComplete;  {[state] 0b});                          / isComplete: termination check
  (`tearDown;    {[state] state})                        / tearDown: cleanup
 )

/ Execution context schema
types.execContext:`timestamp`tickNum`openOrders`orderbooks`positions`harness!()

/ Execution context constructor
types.newExecContext:{[tickNum;harness]
  `timestamp`tickNum`openOrders`orderbooks`positions`harness!(
    .z.p;
    tickNum;
    ([]orderId:();exchange:();side:();price:();volume:();status:());  / empty orders
    ()!();                                                              / empty orderbooks
    ([]exchange:();asset:();quantity:();avgPrice:());                 / empty positions
    harness
  )
 }

/ Error schema for tick execution
types.tickError:`timestamp`strategyId`phase`error!()

\d .
