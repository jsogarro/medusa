/ ============================================================================
/ audit_dashboard.q - GDS Real-time Monitoring Dashboard
/ ============================================================================
/
/ Provides real-time view of auditor status, recent alerts, and summary stats.
/
/ Dependencies:
/   - alert_manager.q (.gds.auditLog)
/   - All auditor modules
/
/ Usage:
/   .gds.dashboard.show[]
/ ============================================================================

\d .gds.dashboard

/ ============================================================================
/ DASHBOARD DISPLAY
/ ============================================================================

/ Display real-time GDS monitoring dashboard
/ @return null
show:{[]
  -1 "";
  -1 "╔════════════════════════════════════════════════════════════════════════╗";
  -1 "║                    GDS MONITORING DASHBOARD                            ║";
  -1 "╠════════════════════════════════════════════════════════════════════════╣";
  -1 "║  Timestamp: ",string[.z.P],"                                     ║";
  -1 "╚════════════════════════════════════════════════════════════════════════╝";
  -1 "";

  / Auditor status section
  showAuditorStatus[];

  -1 "";

  / Recent alerts section
  showRecentAlerts[30];  / Last 30 minutes

  -1 "";

  / Summary stats
  showSummaryStats[];

  -1 "";
  -1 "═══════════════════════════════════════════════════════════════════════";
  -1 "";
 };

/ ============================================================================
/ AUDITOR STATUS
/ ============================================================================

/ Display status of all auditors
/ @return null
showAuditorStatus:{[]
  -1 "┌─────────────────────────────────────────────────────────────────────┐";
  -1 "│ AUDITOR STATUS                                                      │";
  -1 "├─────────────────────────────────────────────────────────────────────┤";

  / Check if auditors are initialized
  auditors:`heartbeat`orderbook`trade`perf;

  {[aud]
    / Get last result for this auditor
    lastResult:$[count .gds.auditLog;
      exec last timestamp, last severity from .gds.auditLog where auditor=aud;
      (`timestamp`severity)!(0Np;`)];

    / Format status
    status:$[null lastResult`severity;"UNKNOWN";string lastResult`severity];
    statusIcon:$[status~"PASS";"✓";status~"FAIL";"✗";status~"WARN";"⚠";"?"];

    / Format last run time
    lastRun:$[null lastResult`timestamp;"Never";string lastResult`timestamp];

    / Display
    -1 "│  ",statusIcon," ",string[aud],": ",status," (Last: ",lastRun,")";
  } each auditors;

  -1 "└─────────────────────────────────────────────────────────────────────┘";
 };

/ ============================================================================
/ RECENT ALERTS
/ ============================================================================

/ Display recent alerts
/ @param minutes long - Number of minutes to look back
/ @return null
showRecentAlerts:{[minutes]
  -1 "┌─────────────────────────────────────────────────────────────────────┐";
  -1 "│ RECENT ALERTS (Last ",string[minutes]," minutes)                                    │";
  -1 "├─────────────────────────────────────────────────────────────────────┤";

  / Get recent alerts
  cutoff:.z.P - minutes * 0D00:01:00;
  recent:select from .gds.auditLog where timestamp >= cutoff;
  recent:`timestamp xdesc recent;

  / Limit to 10 most recent
  recent:10#recent;

  / Display alerts
  if[0 = count recent;
    -1 "│  No alerts in the last ",string[minutes]," minutes                                    │";
    -1 "└─────────────────────────────────────────────────────────────────────┘";
    :();
  ];

  {[alert]
    / Format severity icon
    icon:$[alert[`severity]=`CRITICAL;"[CRIT]";
           alert[`severity]=`WARN;"[WARN]";
           "[INFO]"];

    / Format timestamp (HH:MM:SS)
    ts:string[`time$alert`timestamp];

    / Truncate message to fit width
    msg:alert`message;
    maxLen:50;
    msg:$[maxLen<count msg;(maxLen#msg),"...";msg];

    / Display
    -1 "│  ",ts," ",icon," [",string[alert`auditor],"] ",msg;
  } each recent;

  -1 "└─────────────────────────────────────────────────────────────────────┘";
 };

/ ============================================================================
/ SUMMARY STATISTICS
/ ============================================================================

/ Display summary statistics
/ @return null
showSummaryStats:{[]
  -1 "┌─────────────────────────────────────────────────────────────────────┐";
  -1 "│ SUMMARY STATISTICS                                                  │";
  -1 "├─────────────────────────────────────────────────────────────────────┤";

  / Alert counts by severity (last 24 hours)
  cutoff24h:.z.P - 0D24:00:00;
  recent24h:select from .gds.auditLog where timestamp >= cutoff24h;

  criticalCount:count select from recent24h where severity=`CRITICAL;
  warnCount:count select from recent24h where severity=`WARN;
  infoCount:count select from recent24h where severity=`INFO;

  -1 "│  Alerts (24h): CRITICAL=",string[criticalCount]," WARN=",string[warnCount]," INFO=",string[infoCount],"       │";

  / Table row counts (if tables exist)
  if[`orderbook in tables[];
    obCount:count orderbook;
    -1 "│  Orderbook rows: ",string obCount,"                                           │";
  ];

  if[`trade in tables[];
    tradeCount:count trade;
    -1 "│  Trade rows: ",string tradeCount,"                                               │";
  ];

  / Performance metrics summary
  if[count .gds.perf.metrics;
    -1 "│  Performance samples: ",string[count .gds.perf.metrics],"                                    │";
  ];

  -1 "└─────────────────────────────────────────────────────────────────────┘";
 };

/ ============================================================================
/ DETAILED VIEWS
/ ============================================================================

/ Show detailed view of a specific auditor
/ @param auditor symbol - Auditor name
/ @return null
showAuditor:{[auditor]
  -1 "";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 " AUDITOR: ",string auditor;
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "";

  / Get alerts for this auditor
  alerts:select from .gds.auditLog where auditor=auditor;
  alerts:`timestamp xdesc alerts;

  -1 "Total alerts: ",string count alerts;
  -1 "";

  / Show last 20 alerts
  recent:20#alerts;

  -1 "Last 20 alerts:";
  -1 "─────────────────────────────────────────────────────────────────────";

  {[alert]
    -1 string[alert`timestamp]," [",$[alert[`severity]=`CRITICAL;"CRIT";
                                      alert[`severity]=`WARN;"WARN";
                                      "INFO"],"] ",alert`message;
  } each recent;

  -1 "";
 };

/ Show performance metrics for a specific metric
/ @param metric symbol - Metric name (e.g., `orderbook_ingest)
/ @return null
showMetric:{[metric]
  -1 "";
  -1 "════════════════════════════════════════════════════════════════════";
  -1 " METRIC: ",string metric;
  -1 "════════════════════════════════════════════════════════════════════";
  -1 "";

  / Get percentiles
  percentiles:.gds.perf.getPercentiles[metric];

  -1 "Sample count: ",string percentiles`count;
  -1 "P50: ",string[percentiles`p50]," ms";
  -1 "P90: ",string[percentiles`p90]," ms";
  -1 "P99: ",string[percentiles`p99]," ms";
  -1 "";

  / Get measurements
  measurements:select from .gds.perf.metrics where metric=metric;
  measurements:`timestamp xdesc measurements;

  -1 "Last 10 measurements:";
  -1 "─────────────────────────────────────────────────────────────────────";

  recent:10#measurements;
  {[m]
    -1 string[m`timestamp]," ",string[m`latencyMs]," ms";
  } each recent;

  -1 "";
 };

-1 ".gds.dashboard namespace loaded: show, showAuditor, showMetric";

\d .
