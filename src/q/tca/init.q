/ ============================================================================
/ init.q - TCA Module Initialization
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Loads all TCA modules in correct dependency order
/ ----------------------------------------------------------------------------
/ Modules loaded:
/   1. schema.q - Table schemas and initialization
/   2. benchmark.q - Real-time benchmark calculation
/   3. pretrade.q - Pre-trade cost estimation
/   4. posttrade.q - Post-trade analysis
/   5. aggregate.q - Aggregate analytics
/ ----------------------------------------------------------------------------
/ Usage:
/   \l src/q/tca/init.q
/ ============================================================================

-1 "Loading TCA module...";

/ Load modules in dependency order using repo-root-safe paths.
\l src/q/tca/schema.q
\l src/q/tca/benchmark.q
\l src/q/tca/pretrade.q
\l src/q/tca/posttrade.q
\l src/q/tca/aggregate.q

/ Initialize TCA schema
.tca.initTCASchema[];

/ Initialize benchmark tracking (optional - can be called separately)
/ Note: Benchmark updates via .z.ts timer need to be configured externally
/ Example: .z.ts:{.tca.benchmark.update[]}

-1 "TCA module loaded successfully";
-1 "  Tables: tcaBenchmark, preTradeTCA, tcaReport";
-1 "  Namespaces: .tca.benchmark, .tca.pretrade, .tca.posttrade, .tca.aggregate";
-1 "  ";
-1 "  Usage examples:";
-1 "    .tca.pretrade.estimateCost[`binance;`BTCUSD;`buy;1000000j]";
-1 "    .tca.posttrade.generateReport[orderId]";
-1 "    .tca.aggregate.summary[.z.d-7;.z.d]";
-1 "  ";
-1 "  To enable automatic benchmark updates, set:";
-1 "    .z.ts:{.tca.benchmark.update[]}";
