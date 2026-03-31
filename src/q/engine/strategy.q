/ Strategy lifecycle management
/ Load order: 2 - strategy.q (depends on types.q)

\d .engine

/ Create new strategy instance
/ @param id symbol - unique strategy identifier
/ @param name string - human-readable name
/ @param actor symbol - actor identifier for trade association
/ @param fns dict - custom strategy functions (merged with defaults)
/ @return dict - initialized strategy state
strategy.new:{[id;name;actor;fns]
  state:types.newStrategyState[id;name;actor];

  / Merge custom functions with defaults (defaults first, then custom overrides)
  customFns:types.defaultFns,fns;  / custom fns override defaults
  state[`metadata;`fns]:customFns;

  state
 }

/ Configure strategy with validated config
/ @param state dict - strategy state
/ @param cfg dict - configuration dictionary
/ @return dict - updated strategy state
strategy.configure:{[state;cfg]
  / Only allow configuration in init status
  if[not state[`status]~`init;
    '"Cannot configure strategy in status: ",string state[`status]];

  / Basic config validation - check for required keys if defined
  if[`requiredKeys in key cfg;
    missing:cfg[`requiredKeys] except key cfg;
    if[count missing;
      '"Missing required config keys: ",", " sv string missing];
  ];

  / Apply configuration
  state[`config]:cfg;

  / Call custom configure function if provided
  configureFn:state[`metadata;`fns;`configure];
  state:configureFn[state;cfg];

  state
 }

/ One-time strategy initialization
/ @param state dict - strategy state
/ @return dict - updated strategy state with status=ready
strategy.setUp:{[state]
  / Only allow setup from init status
  if[not state[`status]~`init;
    '"Cannot setUp strategy in status: ",string state[`status]];

  / Call custom setUp function
  setUpFn:state[`metadata;`fns;`setUp];
  state:setUpFn[state];

  / Transition to ready status
  state[`status]:`ready;
  state[`metadata;`setUpAt]:.z.p;

  state
 }

/ Start strategy execution
/ @param state dict - strategy state
/ @return dict - updated strategy state with status=running
strategy.start:{[state]
  / Can start from ready or paused status
  if[not state[`status] in `ready`paused;
    '"Cannot start strategy in status: ",string state[`status]];

  state[`status]:`running;
  state[`metadata;`startedAt]:.z.p;

  state
 }

/ Pause strategy execution
/ @param state dict - strategy state
/ @return dict - updated strategy state with status=paused
strategy.pause:{[state]
  / Can only pause from running status
  if[not state[`status]~`running;
    '"Cannot pause strategy in status: ",string state[`status]];

  state[`status]:`paused;
  state[`metadata;`pausedAt]:.z.p;

  state
 }

/ Set strategy execution mode (live or dryrun)
/ @param state dict - strategy state
/ @param mode symbol - `live or `dryrun
/ @return dict - updated strategy state
strategy.setMode:{[state;mode]
  / Only allow mode change in init status
  if[not state[`status]~`init;
    '"Cannot change mode in status: ",string state[`status]];

  / Validate mode
  if[not mode in types.validModes;
    '"Invalid mode: ",string[mode],". Must be one of: ",", " sv string types.validModes];

  state[`mode]:mode;
  state[`metadata;`modeSetAt]:.z.p;

  state
 }

/ Execute pre-tick hook
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated strategy state
strategy.preTick:{[state;ctx]
  / Only execute in running status
  if[not state[`status]~`running;:state];

  preFn:state[`metadata;`fns;`preTick];
  state:preFn[state;ctx];

  state
 }

/ Execute main tick logic
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated strategy state
strategy.tick:{[state;ctx]
  / Only execute in running status
  if[not state[`status]~`running;:state];

  tickFn:state[`metadata;`fns;`tick];
  state:tickFn[state;ctx];

  / Increment tick counter
  state[`metadata;`tickCount]:1+state[`metadata;`tickCount];
  state[`metadata;`lastTickAt]:.z.p;

  state
 }

/ Execute post-tick hook
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated strategy state
strategy.postTick:{[state;ctx]
  / Only execute in running status
  if[not state[`status]~`running;:state];

  postFn:state[`metadata;`fns;`postTick];
  state:postFn[state;ctx];

  state
 }

/ Check if strategy execution is complete
/ @param state dict - strategy state
/ @return boolean - true if strategy should terminate
strategy.isComplete:{[state]
  / Never complete if not running
  if[not state[`status]~`running;:0b];

  completeFn:state[`metadata;`fns;`isComplete];
  completeFn[state]
 }

/ Tear down strategy and cleanup
/ @param state dict - strategy state
/ @return dict - updated strategy state with status=stopped
strategy.tearDown:{[state]
  / Can tear down from any status except already stopped
  if[state[`status]~`stopped;
    '"Strategy already stopped"];

  / Call custom tearDown function
  tearDownFn:state[`metadata;`fns;`tearDown];
  state:tearDownFn[state];

  / Transition to stopped status
  state[`status]:`stopped;
  state[`metadata;`stoppedAt]:.z.p;

  state
 }

\d .
