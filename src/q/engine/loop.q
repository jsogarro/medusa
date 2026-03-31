/ Tick loop orchestration
/ Load order: 5 - loop.q (depends on types.q, strategy.q, harness.q)

\d .engine

/ Loop state
loop.state:`strategies`harness`running`tickNum`errors!(
  ()!();                                           / strategies dict
  (::);                                            / harness (uninitialized)
  0b;                                              / not running
  0;                                               / tick counter
  ([]timestamp:();strategyId:();phase:();error:()) / errors log
 )

/ Register a strategy with the loop
/ @param state dict - strategy state
loop.register:{[state]
  strategyId:state[`id];

  / Check if already registered
  if[strategyId in key loop.state[`strategies];
    '"Strategy already registered: ",string strategyId];

  / Add to strategies dict
  loop.state[`strategies;strategyId]:state;

  / Log registration
  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Registered strategy: ",string strategyId;
  ];
 }

/ Unregister a strategy from the loop
/ @param strategyId symbol - strategy identifier
loop.unregister:{[strategyId]
  / Check if registered
  if[not strategyId in key loop.state[`strategies];
    '"Strategy not registered: ",string strategyId];

  / Remove from strategies dict
  loop.state[`strategies]:loop.state[`strategies] _ strategyId;

  / Log unregistration
  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Unregistered strategy: ",string strategyId;
  ];
 }

/ Initialize loop with harness
/ @param exchanges list of symbols - exchange identifiers
/ @param mode symbol - `live or `dryrun
loop.init:{[exchanges;mode]
  / Initialize harness
  loop.state[`harness]:harness.init[exchanges;mode];
  loop.state[`tickNum]:0;
  loop.state[`running]:0b;

  / Clear errors
  loop.state[`errors]:0#loop.state[`errors];

  / Log initialization
  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Initialized with mode: ",string mode;
    -1"[LOOP] Exchanges: ",", " sv string exchanges;
  ];
 }

/ Build execution context for current tick
/ @param harness dict - harness state
/ @return dict - execution context
loop.buildContext:{[harness]
  ctx:types.newExecContext[loop.state[`tickNum];harness];

  / Populate with current market data
  ctx[`openOrders]:harness.getOpenOrders[harness];

  / Get orderbooks for all exchanges
  exchanges:key harness[`exchanges];
  ctx[`orderbooks]:exchanges!{[h;ex] harness.getOrderbook[h;ex]}[harness] each exchanges;

  / Positions would come from .engine.position namespace
  / For now, leave empty
  ctx[`positions]:([]exchange:();asset:();quantity:();avgPrice:());

  ctx
 }

/ Execute one tick for one strategy (with error isolation)
/ @param strategyId symbol - strategy identifier
/ @param ctx dict - execution context
/ @return dict - updated strategy state (or original on error)
loop.tickOne:{[strategyId;ctx]
  state:loop.state[`strategies;strategyId];

  / Only process if strategy is running
  if[not state[`status]~`running;:state];

  / Execute pre-tick with error handling
  result:@[{(1b;.engine.strategy.preTick[x;y])};(state;ctx);{(0b;x)}];
  if[not result 0;
    loop.logError[strategyId;`preTick;result 1];
    :state;
  ];
  state:result 1;

  / Execute main tick with error handling
  result:@[{(1b;.engine.strategy.tick[x;y])};(state;ctx);{(0b;x)}];
  if[not result 0;
    loop.logError[strategyId;`tick;result 1];
    :state;
  ];
  state:result 1;

  / Execute post-tick with error handling
  result:@[{(1b;.engine.strategy.postTick[x;y])};(state;ctx);{(0b;x)}];
  if[not result 0;
    loop.logError[strategyId;`postTick;result 1];
    :state;
  ];
  state:result 1;

  / Check if complete
  if[strategy.isComplete[state];
    if[.engine.config.baseSchema[`enableLogging];
      -1"[LOOP] Strategy complete, tearing down: ",string strategyId;
    ];
    state:strategy.tearDown[state];
  ];

  state
 }

/ Log execution error
/ @param strategyId symbol - strategy identifier
/ @param phase symbol - execution phase (preTick, tick, postTick)
/ @param error string - error message
loop.logError:{[strategyId;phase;error]
  / Append to errors table
  newError:(.z.p;strategyId;phase;error);
  loop.state[`errors],:flip `timestamp`strategyId`phase`error!newError;

  / Log to console
  -1"[ERROR] Strategy: ",string[strategyId]," Phase: ",string[phase]," Error: ",error;
 }

/ Execute one complete tick across all strategies
loop.tick:{
  / Increment tick counter
  loop.state[`tickNum]:loop.state[`tickNum]+1;

  / Build execution context
  ctx:loop.buildContext[loop.state[`harness]];

  / Execute tick for each registered strategy
  strategyIds:key loop.state[`strategies];
  {[ctx;sid]
    / Tick one strategy and update state
    newState:loop.tickOne[sid;ctx];
    loop.state[`strategies;sid]:newState;
  }[ctx] each strategyIds;

  / Return tick number
  loop.state[`tickNum]
 }

/ Main loop runner
/ @param intervalMs int - tick interval in milliseconds
loop.run:{[intervalMs]
  / Set running flag
  loop.state[`running]:1b;

  / Log start
  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Starting main loop with interval: ",string[intervalMs],"ms";
  ];

  / Run loop until stopped
  while[loop.state[`running];
    / Execute tick
    loop.tick[];

    / Sleep until next tick
    system"sleep ",string intervalMs % 1000.0;
  ];

  / Log stop
  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Main loop stopped";
  ];
 }

/ Stop the main loop
loop.stop:{
  loop.state[`running]:0b;

  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Stop requested";
  ];
 }

/ Shutdown loop and cleanup
loop.shutdown:{
  / Stop loop if running
  if[loop.state[`running];
    loop.stop[];
  ];

  / Tear down all strategies
  strategyIds:key loop.state[`strategies];
  {[sid]
    state:loop.state[`strategies;sid];
    if[not state[`status]~`stopped;
      loop.state[`strategies;sid]:strategy.tearDown[state];
    ];
  } each strategyIds;

  / Shutdown harness
  if[not (::)~loop.state[`harness];
    loop.state[`harness]:harness.shutdown[loop.state[`harness]];
  ];

  / Clear strategies
  loop.state[`strategies]:()!();

  if[.engine.config.baseSchema[`enableLogging];
    -1"[LOOP] Shutdown complete";
  ];
 }

\d .
