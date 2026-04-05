/ ============================================================================
/ runner.q - Audit Runner and Scheduler
/ ============================================================================
/
/ Executes audits at configurable intervals (every N ticks or time-based)
/ without blocking the main strategy loop. Triggers alerts on failures.
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - All audit implementations (order, volume_balance, fiat_balance, ledger, position_cache)
/   - config/config.q (.conf.get) — optional, uses defaults if unavailable
/
/ Usage:
/   .audit.schedule[100]              / Run audits every 100 ticks
/   .audit.scheduleTime[0D01:00:00]  / Run audits every hour
/   .audit.stop[]                    / Stop scheduler
/   .audit.onStrategyTick[]          / Hook into strategy tick
/   .audit.schedulerStatus[]         / Get scheduler state
/ ============================================================================

\d .audit

/ ============================================================================
/ RUNNER STATE
/ ============================================================================

runner.enabled:0b;
runner.frequency:0N;          / Ticks between audit runs (null = disabled)
runner.tickCount:0;           / Current tick counter
runner.lastRun:0Np;           / Timestamp of last audit run
runner.mode:`;                / `tick or `time
runner.consecutiveFailures:()!();  / auditType -> count of consecutive failures

/ ============================================================================
/ TICK-BASED EXECUTION
/ ============================================================================

/ Reset tick counter
runner.resetCounter:{[]
  runner.tickCount::0;
 };

/ Called on each strategy tick
runner.tick:{[]
  if[not runner.enabled; :()];
  if[not runner.mode=`tick; :()];
  runner.tickCount+:1;

  if[runner.tickCount>=runner.frequency;
    runner.executeAudits[];
    runner.resetCounter[];
  ];
 };

/ ============================================================================
/ AUDIT EXECUTION
/ ============================================================================

/ Execute all enabled audits and handle results
runner.executeAudits:{[]
  -1 "=== Audit Run Started === ",string .z.P;

  / Run all audits
  results:.audit.runAll[];

  / Log results and track consecutive failures
  {[auditType;result]
    statusStr:string result`status;
    -1 "  ",string[auditType],": ",statusStr;

    / Track consecutive failures
    if[result[`status]=`FAIL;
      prev:$[auditType in key runner.consecutiveFailures; runner.consecutiveFailures[auditType]; 0];
      runner.consecutiveFailures[auditType]::prev+1;
    ];
    if[not result[`status]=`FAIL;
      runner.consecutiveFailures[auditType]::0;
    ];

    / Log errors/warnings
    if[0<count result`errors; {-1 "    ERROR: ",x} each result`errors];
    if[0<count result`warnings; {-1 "    WARN: ",x} each result`warnings];
  } ./: flip (key results; value results);

  / Update last run
  runner.lastRun::.z.P;

  / Check alerts
  runner.checkAlerts[results];

  -1 "=== Audit Run Complete === ",string .z.P;
 };

/ Check for critical failures and trigger alerts
/ @param results dict - auditType -> result
runner.checkAlerts:{[results]
  / Find all failed audits
  failedAudits:key[results] where {x[`status]=`FAIL} each value results;

  if[0<count failedAudits;
    -2 "!!! AUDIT FAILURES DETECTED !!!";
    {[at]
      consecutiveCount:$[at in key runner.consecutiveFailures; runner.consecutiveFailures[at]; 1];
      -2 "  Failed: ",(string at)," (consecutive failures: ",(string consecutiveCount),")";

      / Critical: ledger imbalance -> halt trading
      if[at=`LEDGER_AUDIT;
        result:results[at];
        if[0<count result`errors;
          @[.audit.LEDGER.handleCriticalFailure; result`errors; {-2 "Alert handler error: ",x}];
        ];
      ];

      / Escalation: 3+ consecutive failures
      if[consecutiveCount>=3;
        -2 "  !!! ESCALATION: ",(string at)," has failed ",(string consecutiveCount)," times consecutively !!!";
      ];
    } each failedAudits;
  ];
 };

/ ============================================================================
/ SCHEDULER CONTROL
/ ============================================================================

/ Start tick-based audit scheduling
/ @param freq int - Number of ticks between audit runs
schedule:{[freq]
  if[freq<=0; '"Frequency must be positive"];
  runner.frequency::freq;
  runner.enabled::1b;
  runner.mode::`tick;
  runner.resetCounter[];
  -1 "Audit scheduler started: running every ",(string freq)," ticks";
 };

/ Start time-based audit scheduling
/ @param interval timespan - Time between audit runs
scheduleTime:{[interval]
  if[interval<=0D00:00:00; '"Interval must be positive"];
  runner.enabled::1b;
  runner.mode::`time;
  / Set up kdb+ timer
  .z.ts:{[] .audit.runner.executeAudits[]};
  system "t ",string `int$interval%1000000;  / Convert timespan to milliseconds
  -1 "Audit scheduler started: running every ",string interval;
 };

/ Stop audit scheduler
stop:{[]
  runner.enabled::0b;
  / Clear timer if time-based
  if[runner.mode=`time; system "t 0"];
  runner.mode::`;
  -1 "Audit scheduler stopped";
 };

/ Get scheduler status
/ @return dict
schedulerStatus:{[]
  `enabled`mode`frequency`tickCount`lastRun`consecutiveFailures!(
    runner.enabled; runner.mode; runner.frequency; runner.tickCount;
    runner.lastRun; runner.consecutiveFailures)
 };

/ ============================================================================
/ STRATEGY HOOK
/ ============================================================================

/ Hook for strategy tick — call this from your strategy's onTick
onStrategyTick:{[]
  runner.tick[];
 };

/ ============================================================================
/ INITIALIZATION FROM CONFIG
/ ============================================================================

/ Initialize audit runner from configuration file
/ Reads audit.tick_frequency or audit.time_frequency from config
runner.initFromConfig:{[]
  / Try tick frequency first
  tickFreq:@[{`int$.conf.get[`audit;`tick_frequency;100]};::;{100}];
  if[tickFreq>0; schedule[tickFreq]; :()];

  / Fall back to time frequency
  timeFreq:@[{`timespan$.conf.get[`audit;`time_frequency;0D01:00:00]};::;{0D01:00:00}];
  if[timeFreq>0D00:00:00; scheduleTime[timeFreq]];
 };

\d .
