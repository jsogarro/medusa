/ ============================================================================
/ perf_auditor.q - GDS Performance Monitoring
/ ============================================================================
/
/ Tracks ingestion pipeline latency and alerts on performance degradation.
/ Monitors percentile latencies against configured thresholds.
/
/ Dependencies:
/   - alert_manager.q (.gds.alert.raise)
/
/ Usage:
/   .gds.perf.init[]
/   .gds.perf.record[`orderbook_ingest;12.5]  / Record 12.5ms latency
/   .gds.perf.check[]  / Returns `PASS or `FAIL
/ ============================================================================

\d .gds.perf

/ ============================================================================
/ CONFIGURATION & DATA
/ ============================================================================

/ Performance metric thresholds
/ metric -> (p50threshold;p90threshold;p99threshold) in milliseconds
config:([metric:`symbol$()]
  p50Threshold:`float$();
  p90Threshold:`float$();
  p99Threshold:`float$()
 );

/ Latency measurements (rolling window)
/ Stores recent measurements for percentile calculations
metrics:([]
  timestamp:`timestamp$();
  metric:`symbol$();
  latencyMs:`float$()
 );

/ Window size for metrics (keep last N measurements per metric)
metricsWindowSize:1000;

/ Default thresholds (milliseconds)
defaultP50:50.0;   / 50ms p50
defaultP90:100.0;  / 100ms p90
defaultP99:200.0;  / 200ms p99

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize performance monitor with default thresholds
/ @return null
init:{[]
  / Define standard metrics
  metricList:`orderbook_ingest`trade_ingest`orderbook_process`trade_process`alert_publish;

  / Set default thresholds
  `.gds.perf.config upsert flip `metric`p50Threshold`p90Threshold`p99Threshold!(
    metricList;
    count[metricList]#defaultP50;
    count[metricList]#defaultP90;
    count[metricList]#defaultP99
  );

  / Initialize metrics table
  `.gds.perf.metrics set 0#metrics;

  -1 ".gds.perf initialized with ",string[count config]," metrics";
  -1 "  Default thresholds: p50=",string[defaultP50],"ms, p90=",string[defaultP90],"ms, p99=",string[defaultP99],"ms";
 };

/ ============================================================================
/ METRIC RECORDING
/ ============================================================================

/ Record a performance measurement
/ @param metric symbol - Metric name (e.g., `orderbook_ingest)
/ @param latencyMs float - Latency in milliseconds
/ @return null
record:{[metric;latencyMs]
  / Insert measurement
  `.gds.perf.metrics upsert ((.z.P;metric;latencyMs));

  / Batch pruning: only prune when count exceeds 2x window size
  / This reduces overhead of pruning on every insert
  metricCounts:exec count i by metric from metrics;

  / Prune metrics that exceed 2x window size
  {[m;cnt]
    if[cnt > 2 * metricsWindowSize;
      / Keep only last N measurements for this metric
      metricRows:select from metrics where metric=m;
      metricRows:`timestamp xdesc metricRows;
      toDelete:metricsWindowSize _ metricRows;
      delete from `.gds.perf.metrics where timestamp in exec timestamp from toDelete, metric=m;
    ];
  } ./: flip (key metricCounts; value metricCounts);
 };

/ ============================================================================
/ PERCENTILE CALCULATION
/ ============================================================================

/ Calculate percentiles from a list of values using linear interpolation
/ @param values float list - Latency values
/ @return dict - `p50`p90`p99 percentiles
calculatePercentiles:{[values]
  / Sort values
  sorted:asc values;

  / Handle empty list
  n:count sorted;
  if[n=0; :`p50`p90`p99!(0f;0f;0f)];

  / Linear interpolation for percentiles
  / For percentile p, index position = (n-1) * p/100
  / Interpolate between floor and ceiling indices
  interpolate:{[s;p]
    pos:(count[s]-1) * p;
    lower:floor pos;
    upper:ceiling pos;
    / If lower == upper (exact index), return that value
    / Otherwise interpolate between lower and upper
    weight:pos - lower;
    $[lower=upper; s[lower]; (1-weight) * s[lower] + weight * s[upper]]
  };

  / Calculate percentiles
  p50:interpolate[sorted;0.50];
  p90:interpolate[sorted;0.90];
  p99:interpolate[sorted;0.99];

  `p50`p90`p99!(p50;p90;p99)
 };

/ Get current percentiles for a metric
/ @param metric symbol - Metric name
/ @return dict - `p50`p90`p99`count
getPercentiles:{[metric]
  / Get measurements for this metric
  measurements:exec latencyMs from metrics where metric=metric;

  / Calculate percentiles
  percentiles:calculatePercentiles[measurements];

  / Add count
  percentiles[`count]:count measurements;

  percentiles
 };

/ ============================================================================
/ MAIN CHECK FUNCTION
/ ============================================================================

/ Run performance check on all configured metrics
/ @return symbol - `PASS or `FAIL
check:{[]
  / Get all configured metrics
  metricList:exec metric from config;

  / Check each metric
  issueCount:0;

  {[m]
    / Get current percentiles
    percentiles:getPercentiles[m];

    / If no measurements, skip
    if[0 = percentiles`count;
      :();
    ];

    / Get thresholds for this metric
    thresholds:exec first p50Threshold, first p90Threshold, first p99Threshold from config where metric=m;
    p50Threshold:thresholds 0;
    p90Threshold:thresholds 1;
    p99Threshold:thresholds 2;

    / Check p50
    if[percentiles[`p50] > p50Threshold;
      msg:"P50 latency exceeded for ",string[m],": ",string[percentiles`p50],"ms (threshold: ",string[p50Threshold],"ms)";
      details:`metric`p50`threshold`count!(m;percentiles`p50;p50Threshold;percentiles`count);
      .gds.alert.raise[`WARN;`perf;msg;details];
      issueCount+:1;
    ];

    / Check p90
    if[percentiles[`p90] > p90Threshold;
      msg:"P90 latency exceeded for ",string[m],": ",string[percentiles`p90],"ms (threshold: ",string[p90Threshold],"ms)";
      details:`metric`p90`threshold`count!(m;percentiles`p90;p90Threshold;percentiles`count);
      .gds.alert.raise[`WARN;`perf;msg;details];
      issueCount+:1;
    ];

    / Check p99
    if[percentiles[`p99] > p99Threshold;
      msg:"P99 latency exceeded for ",string[m],": ",string[percentiles`p99],"ms (threshold: ",string[p99Threshold],"ms)";
      details:`metric`p99`threshold`count!(m;percentiles`p99;p99Threshold;percentiles`count);
      .gds.alert.raise[`CRITICAL;`perf;msg;details];
      issueCount+:1;
    ];
  } each metricList;

  / Return status
  $[issueCount > 0; `FAIL; `PASS]
 };

/ ============================================================================
/ REPORTING
/ ============================================================================

/ Get summary report of all metrics
/ @return table - Metric summary with percentiles
summary:{[]
  / Get all configured metrics
  metricList:exec metric from config;

  / Calculate percentiles for each metric
  results:{[m]
    percentiles:getPercentiles[m];
    thresholds:exec first p50Threshold, first p90Threshold, first p99Threshold from config where metric=m;

    `metric`count`p50`p90`p99`p50Threshold`p90Threshold`p99Threshold!(
      m;
      percentiles`count;
      percentiles`p50;
      percentiles`p90;
      percentiles`p99;
      thresholds 0;
      thresholds 1;
      thresholds 2
    )
  } each metricList;

  / Convert to table
  flip `metric`count`p50`p90`p99`p50Threshold`p90Threshold`p99Threshold!(
    results[;`metric];
    results[;`count];
    results[;`p50];
    results[;`p90];
    results[;`p99];
    results[;`p50Threshold];
    results[;`p90Threshold];
    results[;`p99Threshold]
  )
 };

/ ============================================================================
/ CONFIGURATION HELPERS
/ ============================================================================

/ Set thresholds for a specific metric
/ @param metric symbol - Metric name
/ @param p50 float - P50 threshold in ms
/ @param p90 float - P90 threshold in ms
/ @param p99 float - P99 threshold in ms
/ @return null
setThreshold:{[metric;p50;p90;p99]
  `.gds.perf.config upsert (metric;p50;p90;p99);
  -1 "Set performance thresholds for ",string[metric],": p50=",string[p50],"ms, p90=",string[p90],"ms, p99=",string[p99],"ms";
 };

/ Get current config
/ @return table - Current configuration
getConfig:{[] config};

/ Clear all metrics (for testing or reset)
/ @return null
clearMetrics:{[]
  `.gds.perf.metrics set 0#metrics;
  -1 "Cleared all performance metrics";
 };

-1 ".gds.perf namespace loaded: init, record, check, summary, setThreshold";

\d .
