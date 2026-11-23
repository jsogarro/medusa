/ Risk Management — Circuit Breaker
/ Consecutive loss tracking with exponential backoff pause
/ Performance: <5μs per check

\d .risk

/ Initialize circuit breakers with default configurations
initCircuitBreakers:{[]
  / Clear existing state
  delete from `.risk.circuitBreakerConfig;
  delete from `.risk.circuitBreakerState;
  delete from `.risk.globalCircuitBreaker;
  delete from `.risk.circuitBreakerEvents;

  / Default circuit breaker configuration (per strategy)
  / 5 consecutive losses → 5min pause, exponential backoff, max 1hr
  `.risk.circuitBreakerConfig set 1!flip `strategy`consecutiveLossThreshold`basePauseDuration`maxPauseDuration!(
    `symbol$();
    `int$();
    `int$();
    `int$()
  );

  / Initialize circuit breaker state (per strategy)
  `.risk.circuitBreakerState set 1!flip `strategy`consecutiveLosses`breachCount`active`pausedUntil`lastTradeResult`lastUpdate!(
    `symbol$();
    `int$();
    `int$();
    `boolean$();
    `timestamp$();
    `symbol$();
    `timestamp$()
  );

  / Global circuit breaker state (single-row table)
  / Triggers if too many strategies breach simultaneously
  `.risk.globalCircuitBreaker set ([]
    active:enlist 0b;
    strategyBreachThreshold:enlist 10i; / Halt all if 10+ strategies paused
    currentBreaches:enlist 0i;
    pausedUntil:enlist 0Np;
    lastUpdate:enlist .z.p
  );

  -1 "Circuit breakers initialized";
 };

/ Record trade result and update circuit breaker state (post-fill)
recordTradeResult:{[strategy;pnl]
  / Determine if trade was a win or loss
  result:$[pnl >= 0.0;`win;`loss];

  / SAFETY CHECK: Ensure strategy entry exists
  if[not strategy in key .risk.circuitBreakerState;
    / Auto-create with defaults
    `.risk.circuitBreakerConfig upsert ([] strategy:enlist strategy; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
    `.risk.circuitBreakerState upsert ([] strategy:enlist strategy; consecutiveLosses:enlist 0i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);
  ];

  / Use keyed table indexing for O(1) lookup
  state:.risk.circuitBreakerState[strategy];
  config:.risk.circuitBreakerConfig[strategy];

  / Update consecutive loss counter
  newLosses:$[result=`loss;state[`consecutiveLosses]+1;0i];

  / Check if threshold breached
  breached:newLosses >= config`consecutiveLossThreshold;

  / If breached, trigger circuit breaker
  if[breached;
    triggerCircuitBreaker[strategy];
  ];

  / Update state
  update consecutiveLosses:newLosses, lastTradeResult:result, lastUpdate:.z.p from `.risk.circuitBreakerState where strategy=strategy;

  / Log event
  `.risk.circuitBreakerEvents insert (.z.p;strategy;result;newLosses;breached;pnl);
 };

/ Trigger circuit breaker for a strategy
triggerCircuitBreaker:{[strategy]
  / Use keyed table indexing for O(1) lookup
  state:.risk.circuitBreakerState[strategy];
  config:.risk.circuitBreakerConfig[strategy];

  / Calculate pause duration with exponential backoff
  / Duration = min(basePauseDuration * 2^breachCount, maxPauseDuration)
  breachCount:state`breachCount;
  pauseDuration:min[config[`basePauseDuration] * `long$2 xexp breachCount; config`maxPauseDuration];
  pausedUntil:.z.p + `long$pauseDuration * 1000000000; / convert seconds to nanoseconds

  / Update state
  update active:1b, breachCount:breachCount+1, pausedUntil:pausedUntil, lastUpdate:.z.p from `.risk.circuitBreakerState where strategy=strategy;

  / Log event
  .risk.logRiskEvent[.z.p;`circuitBreakerTriggered;strategy;`;`;
    `consecutiveLosses`breachCount`pauseDuration`pausedUntil!(state`consecutiveLosses;breachCount+1;pauseDuration;pausedUntil);
    `halt;`critical];

  -1 "CIRCUIT BREAKER TRIGGERED: ",string[strategy]," paused for ",string[pauseDuration]," seconds (breach #",string[breachCount+1],")";

  / Check if global circuit breaker should be triggered
  activeBreaches:exec count i from .risk.circuitBreakerState where active=1b;
  globalThreshold:first .risk.globalCircuitBreaker`strategyBreachThreshold;

  if[activeBreaches >= globalThreshold;
    triggerGlobalCircuitBreaker[];
  ];
 };

/ Trigger global circuit breaker (all strategies halted)
triggerGlobalCircuitBreaker:{[]
  / Idempotency: if already active, do not re-trigger
  if[first .risk.globalCircuitBreaker`active; :(::)];

  / Pause all trading for 1 hour
  pausedUntil:.z.p + 3600000000000; / 1 hour in nanoseconds

  / Update state
  .risk.globalCircuitBreaker[`active]:1b;
  .risk.globalCircuitBreaker[`pausedUntil]:pausedUntil;
  .risk.globalCircuitBreaker[`lastUpdate]:.z.p;

  / Log event
  .risk.logRiskEvent[.z.p;`globalCircuitBreakerTriggered;`;`;`;
    `activeBreaches`pausedUntil!(exec count i from .risk.circuitBreakerState where active=1b;pausedUntil);
    `halt;`critical];

  -1 "GLOBAL CIRCUIT BREAKER ACTIVATED: All trading halted for 1 hour";

  / Activate emergency stop as well
  .risk.activateEmergencyStop[`globalCircuitBreaker;`system];
 };

/ Check circuit breaker status (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <5μs per check
checkCircuitBreaker:{[strategy]
  / ROBUSTNESS: Validate single-row table integrity for global breaker
  if[1<>count .risk.globalCircuitBreaker;
    -1 "CRITICAL: globalCircuitBreaker table corrupted (row count: ",string[count .risk.globalCircuitBreaker],")";
    :(0b;`globalCircuitBreakerCorrupted;`strategy!strategy)
  ];

  / Check global circuit breaker first
  globalActive:first .risk.globalCircuitBreaker`active;
  globalPausedUntil:first .risk.globalCircuitBreaker`pausedUntil;

  if[globalActive;
    / Check if pause has expired
    if[.z.p < globalPausedUntil;
      :(0b;`globalCircuitBreakerActive;`strategy`pausedUntil!(strategy;globalPausedUntil))
    ];
    / Pause expired — deactivate
    .risk.globalCircuitBreaker[`active]:0b;
    .risk.logRiskEvent[.z.p;`globalCircuitBreakerExpired;`;`;`;`pausedUntil!globalPausedUntil;`resume;`info];
  ];

  / FAIL-SAFE: if strategy not configured, allow trading
  if[not strategy in key .risk.circuitBreakerState; :(1b;`;()!())];

  / Use keyed table indexing for O(1) lookup
  state:.risk.circuitBreakerState[strategy];

  / Check if circuit breaker is active
  if[not state`active; :(1b;`;()!())];

  / Check if pause has expired
  if[.z.p < state`pausedUntil;
    :(0b;`circuitBreakerActive;`strategy`pausedUntil!(strategy;state`pausedUntil))
  ];

  / Pause expired — resume trading
  resumeCircuitBreaker[strategy];
  (1b;`;()!())
 };

/ Resume circuit breaker for a strategy (auto-called when pause expires)
resumeCircuitBreaker:{[strategy]
  / Update state
  update active:0b, consecutiveLosses:0i, lastUpdate:.z.p from `.risk.circuitBreakerState where strategy=strategy;

  / Log event
  .risk.logRiskEvent[.z.p;`circuitBreakerResumed;strategy;`;`;()!();`resume;`info];

  -1 "Circuit breaker resumed: ",string[strategy];
 };

/ Get circuit breaker status for monitoring
getCircuitBreakerStatus:{[]
  `config`state`global`recentEvents!(
    select from .risk.circuitBreakerConfig;
    select from .risk.circuitBreakerState;
    first select from .risk.globalCircuitBreaker;
    select from .risk.circuitBreakerEvents where time>.z.p-01:00:00
  )
 };

\d .
