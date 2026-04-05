/ ============================================================================
/ gds_init.q - GDS (Guaranteed Data Service) Initialization
/ ============================================================================
/
/ Initializes all GDS components:
/   - Alert manager (centralized alert routing)
/   - Heartbeat auditor (staleness detection)
/   - Orderbook auditor (quality checks)
/   - Trade auditor (anomaly detection)
/   - Performance auditor (latency monitoring)
/   - Audit dashboard (real-time view)
/
/ Sets up timer-based execution for continuous monitoring.
/
/ Usage:
/   \l gds/gds_init.q
/   .gds.init[]        / Initialize all components
/   .gds.start[]       / Start timer-based monitoring
/   .gds.stop[]        / Stop monitoring
/   .gds.status[]      / Show current status
/ ============================================================================

\d .gds

/ ============================================================================
/ LOAD ALL GDS MODULES
/ ============================================================================

-1 "";
-1 "════════════════════════════════════════════════════════════════════";
-1 "  Loading GDS (Guaranteed Data Service) Components";
-1 "════════════════════════════════════════════════════════════════════";
-1 "";

/ Load modules in dependency order
-1 "Loading alert_manager.q...";
\l gds/alert_manager.q

-1 "Loading heartbeat_auditor.q...";
\l gds/heartbeat_auditor.q

-1 "Loading orderbook_auditor.q...";
\l gds/orderbook_auditor.q

-1 "Loading trade_auditor.q...";
\l gds/trade_auditor.q

-1 "Loading perf_auditor.q...";
\l gds/perf_auditor.q

-1 "Loading audit_dashboard.q...";
\l gds/audit_dashboard.q

-1 "";
-1 "All GDS modules loaded successfully";
-1 "";

/ ============================================================================
/ AUDITOR REGISTRY
/ ============================================================================

/ Auditor metadata: name, enabled, interval (ms), lastRun, lastResult
auditors:([]
  name:`symbol$();
  enabled:`boolean$();
  intervalMs:`long$();
  lastRun:`timestamp$();
  lastResult:`symbol$()
 );

/ Timer state
timer:`enabled`lastTick`tickCount!(0b;0Np;0);

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize all GDS components
/ @return null
init:{[]
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "  Initializing GDS Components";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "";

  / Initialize alert manager
  -1 "Initializing alert manager...";
  alert.init[];

  / Initialize all auditors
  -1 "Initializing heartbeat auditor...";
  heartbeat.init[];

  -1 "Initializing orderbook auditor...";
  orderbook.init[];

  -1 "Initializing trade auditor...";
  trade.init[];

  -1 "Initializing performance auditor...";
  perf.init[];

  / Register auditors
  `.gds.auditors upsert (
    (`heartbeat;1b;5000;0Np;`);     / Run every 5 seconds
    (`orderbook;1b;5000;0Np;`);     / Run every 5 seconds
    (`trade;1b;10000;0Np;`);        / Run every 10 seconds
    (`perf;1b;30000;0Np;`)          / Run every 30 seconds
  );

  -1 "";
  -1 "GDS initialization complete";
  -1 "Registered auditors:";
  -1 .Q.s auditors;
  -1 "";
 };

/ ============================================================================
/ TIMER-BASED EXECUTION
/ ============================================================================

/ Timer tick handler
/ Called by .z.ts when timer is active
/ @return null
onTimer:{[]
  currentTime:.z.P;

  / Check each auditor
  {[aud]
    / Check if enabled
    if[not aud`enabled;
      :();
    ];

    / Check if interval elapsed since last run
    elapsed:$[null aud`lastRun;
      aud`intervalMs + 1;  / Force first run
      `long$((`timestamp$currentTime) - `timestamp$aud`lastRun) % 1000000000];  / nanoseconds to milliseconds (1e9 not 1e6)

    / Run if interval elapsed
    if[elapsed >= aud`intervalMs;
      / Execute auditor check
      result:runAuditor[aud`name];

      / Update auditor metadata
      update lastRun:currentTime, lastResult:result from `.gds.auditors where name=aud`name;
    ];
  } each auditors;

  / Update timer state
  timer[`lastTick]:.z.P;
  timer[`tickCount]+:1;
 };

/ Run a specific auditor
/ @param name symbol - Auditor name
/ @return symbol - Result (`PASS or `FAIL)
runAuditor:{[name]
  -1 "[GDS] Running auditor: ",string name;

  / Call auditor's check function
  result:$[name=`heartbeat; heartbeat.check[];
           name=`orderbook; orderbook.check[];
           name=`trade; trade.check[];
           name=`perf; perf.check[];
           / Unknown auditor
           (alert.raise[`WARN;`gds;"Unknown auditor: ",string name;()!()]; `FAIL)];

  -1 "[GDS] Auditor ",string[name]," result: ",string result;

  result
 };

/ ============================================================================
/ START/STOP CONTROLS
/ ============================================================================

/ Start timer-based monitoring
/ @param intervalMs long - Timer interval in milliseconds (default: 1000ms = 1 second)
/ @return null
start:{[intervalMs]
  if[timer`enabled;
    -1 "GDS monitoring already running";
    :();
  ];

  / Save existing .z.ts handler if one exists
  if[not (::)~.z.ts;
    -1 "Saving existing .z.ts handler";
    `.gds.previousTimerHandler set .z.ts;
  ];

  / Set timer interval
  \t intervalMs;

  / Enable timer
  timer[`enabled]:1b;
  timer[`lastTick]:.z.P;
  timer[`tickCount]:0;

  / Set timer handler (chain with previous if exists)
  .z.ts:{
    / Call GDS timer
    .gds.onTimer[];
    / Call previous handler if it exists
    if[`previousTimerHandler in key .gds;
      .gds.previousTimerHandler[];
    ];
  };

  -1 "GDS monitoring started with interval: ",string[intervalMs],"ms";
 };

/ Overload: start with default interval (1 second)
start:{[] start[1000]};

/ Stop timer-based monitoring
/ @return null
stop:{[]
  if[not timer`enabled;
    -1 "GDS monitoring not running";
    :();
  ];

  / Disable timer
  \t 0;
  timer[`enabled]:0b;

  -1 "GDS monitoring stopped";
 };

/ ============================================================================
/ STATUS & UTILITIES
/ ============================================================================

/ Display GDS status
/ @return null
status:{[]
  -1 "";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "  GDS Status";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "Monitoring: ",$[timer`enabled;"ACTIVE";"STOPPED"];
  -1 "Last tick: ",string timer`lastTick;
  -1 "Tick count: ",string timer`tickCount;
  -1 "";
  -1 "Auditors:";
  -1 .Q.s auditors;
  -1 "";
 };

/ Enable/disable specific auditor
/ @param name symbol - Auditor name
/ @param enabled boolean - Enable (1b) or disable (0b)
/ @return null
setAuditorEnabled:{[name;enabled]
  update enabled:enabled from `.gds.auditors where name=name;
  -1 "Set auditor ",string[name]," to: ",$[enabled;"enabled";"disabled"];
 };

/ Run all auditors once (manual execution)
/ @return dict - Results per auditor
runAll:{[]
  -1 "Running all auditors...";

  results:()!();

  {[aud]
    if[aud`enabled;
      result:runAuditor[aud`name];
      results[aud`name]:result;
    ];
  } each auditors;

  -1 "All auditors complete";
  -1 "Results: ",.Q.s results;

  results
 };

/ ============================================================================
/ HELP
/ ============================================================================

help:{[]
  -1 "";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "  GDS (Guaranteed Data Service) - Help";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "";
  -1 "Initialization:";
  -1 "  .gds.init[]          - Initialize all GDS components";
  -1 "";
  -1 "Monitoring:";
  -1 "  .gds.start[]         - Start timer-based monitoring (default 1s interval)";
  -1 "  .gds.start[2000]     - Start with 2-second interval";
  -1 "  .gds.stop[]          - Stop monitoring";
  -1 "  .gds.status[]        - Show current status";
  -1 "";
  -1 "Manual Execution:";
  -1 "  .gds.runAll[]        - Run all auditors once";
  -1 "  .gds.runAuditor[`heartbeat]  - Run specific auditor";
  -1 "";
  -1 "Dashboard:";
  -1 "  .gds.dashboard.show[]         - Show monitoring dashboard";
  -1 "  .gds.dashboard.showAuditor[`orderbook]  - Show auditor details";
  -1 "";
  -1 "Alert Management:";
  -1 "  .gds.alert.recent[30]         - Show alerts from last 30 minutes";
  -1 "  .gds.alert.bySeverity[`CRITICAL]  - Show critical alerts";
  -1 "";
  -1 "Configuration:";
  -1 "  .gds.heartbeat.setThreshold[`kraken;`BTCUSD;60]  - Set staleness threshold";
  -1 "  .gds.orderbook.setThresholds[`kraken;`BTCUSD;100;10]  - Set spread/depth limits";
  -1 "  .gds.trade.setThresholds[`kraken;`BTCUSD;5.0;30]  - Set price change/gap limits";
  -1 "  .gds.perf.setThreshold[`orderbook_ingest;50;100;200]  - Set latency thresholds";
  -1 "";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "";
 };

-1 "";
-1 "════════════════════════════════════════════════════════════════════";
-1 "  GDS Ready";
-1 "════════════════════════════════════════════════════════════════════";
-1 "  Type .gds.help[] for usage instructions";
-1 "  Type .gds.init[] to initialize all components";
-1 "════════════════════════════════════════════════════════════════════";
-1 "";

\d .
