/ ============================================================================
/ cleanup.q - Event Log Cleanup and Retention
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides automatic pruning of unbounded event tables to prevent memory growth.
/ Scheduled via .z.ts timer to run hourly.
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - risk/schema.q (risk event tables)
/   - tca/schema.q (TCA tables)
/   - audit/*.q (audit tables)
/ ----------------------------------------------------------------------------
/ Usage:
/   .cleanup.pruneRDB[]          / Manual pruning
/   .cleanup.scheduleCleanup[]   / Enable hourly auto-cleanup
/ ============================================================================

-1 "  Loading cleanup.q...";

\d .cleanup

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Retention periods (in timespan)
retentionPeriod:1D;           / Keep last 24 hours for most events
snapshotRetention:01:00:00;   / Keep last 1 hour for risk snapshots (high-frequency)
auditRetention:7D;            / Keep last 7 days for audit results

/ ============================================================================
/ PRUNING FUNCTIONS
/ ============================================================================

/ Prune old events from RDB tables (keep last 24h by default)
/ @return long - Total rows deleted across all tables
pruneRDB:{[]
  cutoff:.z.p - retentionPeriod;
  snapshotCutoff:.z.p - snapshotRetention;
  auditCutoff:.z.p - auditRetention;

  totalDeleted:0j;

  / ═══════════════════════════════════════════════════════════════════
  / Risk Event Tables
  / ═══════════════════════════════════════════════════════════════════

  / Risk events
  if[`riskEvents in tables`.risk;
    n:count .risk.riskEvents;
    delete from `.risk.riskEvents where time < cutoff;
    totalDeleted+:n - count .risk.riskEvents;
  ];

  / Rate limit events
  if[`rateLimitEvents in tables`.risk;
    n:count .risk.rateLimitEvents;
    delete from `.risk.rateLimitEvents where time < cutoff;
    totalDeleted+:n - count .risk.rateLimitEvents;
  ];

  / Correlation events
  if[`correlationEvents in tables`.risk;
    n:count .risk.correlationEvents;
    delete from `.risk.correlationEvents where time < cutoff;
    totalDeleted+:n - count .risk.correlationEvents;
  ];

  / Concentration events
  if[`concentrationEvents in tables`.risk;
    n:count .risk.concentrationEvents;
    delete from `.risk.concentrationEvents where time < cutoff;
    totalDeleted+:n - count .risk.concentrationEvents;
  ];

  / Market impact events
  if[`impactEvents in tables`.risk;
    n:count .risk.impactEvents;
    delete from `.risk.impactEvents where time < cutoff;
    totalDeleted+:n - count .risk.impactEvents;
  ];

  / Circuit breaker events
  if[`circuitBreakerEvents in tables`.risk;
    n:count .risk.circuitBreakerEvents;
    delete from `.risk.circuitBreakerEvents where time < cutoff;
    totalDeleted+:n - count .risk.circuitBreakerEvents;
  ];

  / Alert history
  if[`alertHistory in tables`.risk;
    n:count .risk.alertHistory;
    delete from `.risk.alertHistory where time < cutoff;
    totalDeleted+:n - count .risk.alertHistory;
  ];

  / Risk snapshots (keep last 1h for replay, not 24h)
  if[`riskSnapshots in tables`.risk;
    n:count .risk.riskSnapshots;
    delete from `.risk.riskSnapshots where time < snapshotCutoff;
    totalDeleted+:n - count .risk.riskSnapshots;
  ];

  / ═══════════════════════════════════════════════════════════════════
  / TCA Event Tables
  / ═══════════════════════════════════════════════════════════════════

  / Pre-trade TCA estimates
  if[`preTradeTCA in tables`.tca;
    n:count .tca.preTradeTCA;
    delete from `.tca.preTradeTCA where time < cutoff;
    totalDeleted+:n - count .tca.preTradeTCA;
  ];

  / ═══════════════════════════════════════════════════════════════════
  / Audit Event Tables
  / ═══════════════════════════════════════════════════════════════════

  / Audit results (keep 7 days for compliance)
  if[`results in key `.audit;
    n:count .audit.results;
    delete from `.audit.results where timestamp < auditCutoff;
    totalDeleted+:n - count .audit.results;
  ];

  -1 ("RDB pruned: removed ",string[totalDeleted]," events older than ",string cutoff);
  totalDeleted
 };

/ ============================================================================
/ TIMER INTEGRATION
/ ============================================================================

/ Original .z.ts handler (if one exists)
existingTsHandler:@[value;`.z.ts;{{}}];

/ Scheduled cleanup wrapper — runs hourly
timerHandler:{[]
  / Run existing handler first
  existingTsHandler[];

  / Run cleanup on the hour
  if[0=.z.t.minute;
    .cleanup.pruneRDB[];
  ];
 };

/ Schedule cleanup to run every hour via .z.ts
scheduleCleanup:{[]
  / Install timer handler
  .z.ts:.cleanup.timerHandler;

  / Set timer interval to 1 minute (cleanup runs hourly but timer checks every minute)
  system "t 60000";

  -1 ("Cleanup scheduled: hourly RDB pruning enabled (next run at ",(string .z.d + 01:00:00 xbar .z.t),")");
 };

\d .
