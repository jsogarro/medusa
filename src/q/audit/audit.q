/ ============================================================================
/ audit.q - Core Audit Infrastructure
/ ============================================================================
/
/ Provides:
/   - Audit type registry (table-driven audit definitions)
/   - Standardized audit result schema
/   - Core execution functions (run single, run all)
/   - Audit history persistence and querying
/   - Statistics and reporting (latest results, failure rates)
/
/ Dependencies:
/   - None (foundation module — audit implementations loaded separately)
/
/ Namespaces:
/   .audit        — Core orchestration and result storage
/   .audit.ORDER  — (loaded from order.q)
/   .audit.VOLUME_BALANCE — (loaded from volume_balance.q)
/   .audit.FIAT_BALANCE   — (loaded from fiat_balance.q)
/   .audit.LEDGER         — (loaded from ledger.q)
/   .audit.POSITION_CACHE — (loaded from position_cache.q)
/   .audit.runner         — (loaded from runner.q)
/
/ Usage:
/   .audit.run[`ORDER_AUDIT]       / Execute single audit
/   .audit.runAll[]                / Execute all enabled audits
/   .audit.status[]                / Print human-readable status report
/   .audit.latestResults[]         / Table of latest result per type
/   .audit.failureRate[0D01:00:00] / Failure rates over last hour
/ ============================================================================

\d .audit

/ ============================================================================
/ AUDIT TYPE REGISTRY
/ ============================================================================

/ Keyed table defining all audit types
/ validationFunc column holds symbol referencing each audit's validate function
types:([auditType:`symbol$()] name:(); description:(); enabled:`boolean$(); validationFunc:`symbol$(); lastRun:`timestamp$(); lastStatus:`symbol$());

/ Register a new audit type (called by each audit module on load)
/ @param auditType symbol - Unique audit type key
/ @param name string - Human-readable name
/ @param description string - What the audit checks
/ @param validationFunc symbol - Symbol referencing the validate function
registerType:{[auditType;name;description;validationFunc]
  `.audit.types upsert (auditType; name; description; 1b; validationFunc; 0Np; `);
 };

/ ============================================================================
/ AUDIT RESULTS TABLE
/ ============================================================================

/ Stores all audit execution results for trend analysis and forensics
results:([] timestamp:`timestamp$(); auditType:`symbol$(); status:`symbol$(); duration:`timespan$(); errors:(); warnings:(); metrics:());

/ Create a standardized audit result dictionary
/ @param auditType symbol - Type of audit
/ @param status symbol - `PASS, `FAIL, or `WARNING
/ @param errors list - List of error message strings
/ @param warnings list - List of warning message strings
/ @param metrics dict - Audit-specific metrics
/ @return dict - Standardized result dictionary
newResult:{[auditType;status;errors;warnings;metrics]
  `auditType`status`timestamp`errors`warnings`metrics!(auditType; status; .z.P; errors; warnings; metrics)
 };

/ Persist a result to the results table and update type registry
/ @param result dict - Result from newResult
saveResult:{[result]
  `.audit.results insert `timestamp`auditType`status`duration`errors`warnings`metrics#result;
  / Update type registry with last run info
  if[result[`auditType] in exec auditType from .audit.types;
    update lastRun:result`timestamp, lastStatus:result`status from `.audit.types where auditType=result`auditType;
  ];
 };

/ ============================================================================
/ CORE EXECUTION
/ ============================================================================

/ Execute a specific audit type
/ @param auditType symbol - Type of audit to run
/ @return dict - Audit result
run:{[auditType]
  / Validate audit type exists
  if[not auditType in exec auditType from .audit.types;
    :newResult[auditType; `FAIL; enlist "Unknown audit type: ",string auditType; (); ()!()]
  ];

  / Check if audit is enabled
  if[not .audit.types[auditType;`enabled];
    :newResult[auditType; `WARNING; (); enlist "Audit type is disabled"; ()!()]
  ];

  / Get validation function
  validationFunc:.audit.types[auditType;`validationFunc];

  / Execute with timing and error handling
  t0:.z.P;
  result:@[value; validationFunc; {[at;err]
    .audit.newResult[at; `FAIL; enlist "Audit execution failed: ",err; (); ()!()]
  }[auditType]];

  / Add duration to result
  result[`duration]:.z.P - t0;

  / Save and return
  saveResult[result];
  result
 };

/ Execute all enabled audits
/ @return dict - Map of auditType -> result
runAll:{[]
  enabledTypes:exec auditType from .audit.types where enabled;
  enabledTypes!run each enabledTypes
 };

/ ============================================================================
/ STATISTICS AND REPORTING
/ ============================================================================

/ Latest result for each audit type
/ @return table - Most recent result per audit type
latestResults:{[]
  select last timestamp, last status, last duration, last errors, last warnings by auditType from .audit.results
 };

/ Failure rate for each audit type over a time window
/ @param window timespan - Time window to analyze
/ @return table - Failure rates by audit type
failureRate:{[window]
  cutoff:.z.P - window;
  select totalRuns:count i, failures:sum status=`FAIL, warnings:sum status=`WARNING,
    failureRate:(sum status=`FAIL) % count i
    by auditType from .audit.results where timestamp>=cutoff
 };

/ All failed audits in a time window
/ @param window timespan - Time window
/ @return table - Failed audit results
failures:{[window]
  cutoff:.z.P - window;
  select from .audit.results where timestamp>=cutoff, status=`FAIL
 };

/ Human-readable audit status report
status:{[]
  -1 "=== Audit Status Report ===";
  -1 "Generated: ",string .z.P;
  -1 "";
  lr:latestResults[];
  if[0=count lr; -1 "No audit results yet."; :()];
  {[at]
    row:lr[at];
    -1 "  ",string[at];
    -1 "    Status:   ",string row`status;
    -1 "    Last Run: ",string row`timestamp;
    -1 "    Duration: ",string row`duration;
    if[count row`errors;   -1 "    Errors:   ",", " sv row`errors];
    if[count row`warnings; -1 "    Warnings: ",", " sv row`warnings];
    -1 "";
  } each key lr;
  -1 "=== End Report ===";
 };

/ Prune old results to keep in-memory table small
/ @param maxRows int - Maximum rows to keep (default 1000)
prune:{[maxRows]
  if[maxRows<=0; maxRows:1000];
  n:count .audit.results;
  if[n>maxRows;
    .audit.results:neg[maxRows] sublist .audit.results;
    -1 "Pruned ",(string n-maxRows)," old audit results";
  ];
 };

\d .
