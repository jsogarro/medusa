/ ============================================================================
/ test_tca_integration.q - Tests for TCA Integration (15 tests)
/ ============================================================================
/ Tests VWAP benchmark, pre-trade estimates, post-trade slippage, aggregation
/ ============================================================================

\l tests/q/test_framework.q
\l src/q/schema/init.q
\l src/q/tca/schema.q
\l src/q/tca/benchmark.q
\l src/q/tca/pretrade.q
\l src/q/tca/posttrade.q
\l src/q/tca/aggregate.q

/ ============================================================================
/ SETUP & TEARDOWN
/ ============================================================================

setUp:{[]
  / Clear all TCA tables
  delete from `.tca.tcaBenchmark;
  delete from `.tca.preTradeTCA;
  delete from `.tca.tcaReport;

  / Reset report ID counter
  .tca.posttrade.reportIdCounter:0;

  / Mock .qg.trade table with known data
  `.qg.trade upsert (
    `time_created`exchange_name`volume_currency`price_currency`price`volume!(
      .z.p - 30000000000j; `binance; `BTC; `USD; 50000000000j; 1000000j
    )
  );

  `.qg.trade upsert (
    .z.p - 20000000000j; `binance; `BTC; `USD; 50100000000j; 2000000j
  );

  `.qg.trade upsert (
    .z.p - 10000000000j; `binance; `BTC; `USD; 49900000000j; 1500000j
  );

  / Mock .qg.order table
  `.qg.order upsert (
    `order_id`exchange_name`volume_currency`price_currency`order_type`price`volume`filled_volume`time_created`actor!(
      1j; `binance; `BTC; `USD; `buy; 50000000000j; 3000000j; 3000000j; .z.p - 15000000000j; `testStrategy
    )
  );

  / Mock .qg.getOrder
  .qg.getOrder:{[orderId]
    first select from .qg.order where order_id=orderId
  };

  / Mock .qg.getTradesForOrder
  .qg.getTradesForOrder:{[orderId]
    / Return all trades as fills for this order
    select time_created, price, volume from .qg.trade
  };

  / Mock .risk.orderbook table
  `.risk.orderbook upsert (
    `exchange`sym`side`price`size!(
      `binance; `BTCUSD; `bid; 49990000000j; 5000000j
    )
  );

  `.risk.orderbook upsert (
    `binance; `BTCUSD; `ask; 50010000000j; 5000000j
  );

  / Mock .risk.calcBookDepth
  .risk.calcBookDepth:{[ex;pair;side;qty] 100f}; / 100% depth available
 }

tearDown:{[]
  / Clear tables
  delete from `.tca.tcaBenchmark;
  delete from `.tca.preTradeTCA;
  delete from `.tca.tcaReport;
 }

/ ============================================================================
/ TEST CASES
/ ============================================================================

/ ============================================================================
/ TEST CASES
/ ============================================================================

test_vwap_benchmark_known_trades:{
  setUp[];

  / Calculate benchmark
  .tca.benchmark.update[];

  / Verify benchmark exists
  benchmarks:select from .tca.tcaBenchmark where pair=`BTCUSD;
  .test.assert["Benchmark created"; 0 < count benchmarks];

  / Verify VWAP calculation
  / Expected VWAP: (50000*1 + 50100*2 + 49900*1.5) / (1 + 2 + 1.5) = 50022.22...
  bench1min:first select from .tca.tcaBenchmark where pair=`BTCUSD, interval=`1min;
  expectedVwap:50022222222j; / ~50022.222222
  .test.assertNear["VWAP correct"; expectedVwap; bench1min`vwap; 100000000j]; / Tolerance: 100.0

  tearDown[];
 }

/ Test: Pre-trade estimate components (spread + impact + timing)
test_pretrade_estimate_components:{
  setUp[];

  / Estimate cost
  result:.tca.pretrade.estimateCost[`binance; `BTCUSD; `buy; 2000000j];

  / Verify components present
  .test.assert["Spread cost present"; `spreadCostBps in key result];
  .test.assert["Impact present"; `impactBps in key result];
  .test.assert["Timing risk present"; `timingRiskBps in key result];
  .test.assert["Total cost present"; `totalCostBps in key result];

  / Verify total = sum of components
  expectedTotal:result[`spreadCostBps] + result[`impactBps] + result[`timingRiskBps];
  .test.assertNear["Total equals sum"; expectedTotal; result`totalCostBps; 0.01f];

  tearDown[];
 }

/ Test: Post-trade slippage (buy) — positive slippage = overpaid
test_posttrade_slippage_buy:{
  setUp[];

  / Calculate slippage: buy at 50100, benchmark 50000 → +0.2% = +20 bps
  slippage:.tca.posttrade.calculateSlippage[50100000000j; 50000000000j; `buy];

  / Expected: (50100 - 50000) / 50000 * 10000 = 20 bps
  .test.assertNear["Buy slippage correct"; 20f; slippage; 0.1f];

  tearDown[];
 }

/ Test: Post-trade slippage (sell) — positive slippage = undersold
test_posttrade_slippage_sell:{
  setUp[];

  / Calculate slippage: sell at 49900, benchmark 50000 → +0.2% = +20 bps
  slippage:.tca.posttrade.calculateSlippage[49900000000j; 50000000000j; `sell];

  / Expected: (50000 - 49900) / 50000 * 10000 = 20 bps
  .test.assertNear["Sell slippage correct"; 20f; slippage; 0.1f];

  tearDown[];
 }

/ Test: Aggregate by strategy
test_aggregate_by_strategy:{
  setUp[];

  / Generate TCA report
  .tca.posttrade.generateReport[1j];

  / Aggregate by strategy
  agg:.tca.aggregate.byStrategy[.z.D; .z.D];

  / Verify aggregation
  .test.assert["Strategy aggregation has rows"; 0 < count agg];

  / Verify columns present
  .test.assert["orderCount present"; `orderCount in cols agg];
  .test.assert["avgTotalCostBps present"; `avgTotalCostBps in cols agg];

  tearDown[];
 }

/ Test: Aggregate by exchange
test_aggregate_by_exchange:{
  setUp[];

  / Generate TCA report
  .tca.posttrade.generateReport[1j];

  / Aggregate by exchange
  agg:.tca.aggregate.byExchange[.z.D; .z.D];

  / Verify aggregation
  .test.assert["Exchange aggregation has rows"; 0 < count agg];

  / Verify binance present
  .test.assert["Binance in results"; `binance in exec exchange from agg];

  tearDown[];
 }

/ Test: Pre-trade spread cost calculation
test_pretrade_spread_cost:{
  setUp[];

  / Calculate spread cost
  spreadCost:.tca.pretrade.estimateSpreadCost[`binance; `BTCUSD];

  / Expected: (50010 - 49990) / 50000 * 10000 = 4 bps
  .test.assertNear["Spread cost correct"; 4f; spreadCost; 0.5f];

  tearDown[];
 }

/ Test: Pre-trade market impact estimation
test_pretrade_market_impact:{
  setUp[];

  / Override calcBookDepth to return 50% depth
  .risk.calcBookDepth:{[ex;pair;side;qty] 50f};

  / Estimate impact
  impact:.tca.pretrade.estimateMarketImpact[`binance; `BTCUSD; `buy; 5000000j];

  / Expected: 100 - 50 = 50%, scaled to bps = 5000 bps
  .test.assertNear["Market impact correct"; 5000f; impact; 100f];

  tearDown[];
 }

/ Test: Pre-trade timing risk from volatility
test_pretrade_timing_risk:{
  setUp[];

  / Populate benchmark with volatility
  `.tca.tcaBenchmark upsert (
    .z.p; `binance; `BTCUSD; `1min; 50000000000j; 50000000000j; 50000000000j; 50000000000j; 0j; 0.02
  );

  / Estimate timing risk
  timingRisk:.tca.pretrade.estimateTimingRisk[`binance; `BTCUSD];

  / Expected: 0.02 * 10000 = 200 bps
  .test.assertNear["Timing risk correct"; 200f; timingRisk; 1f];

  tearDown[];
 }

/ Test: Post-trade report generation
test_posttrade_report_generation:{
  setUp[];

  / Generate report
  reportId:.tca.posttrade.generateReport[1j];

  / Verify report created
  .test.assert["Report created"; reportId in exec reportId from .tca.tcaReport];

  / Verify report structure
  report:first select from .tca.tcaReport where reportId=reportId;
  .test.assert["orderId present"; `orderId in key report];
  .test.assert["avgFillPx present"; `avgFillPx in key report];
  .test.assert["totalCostBps present"; `totalCostBps in key report];

  tearDown[];
 }

/ Test: Slippage null benchmark handling
test_slippage_null_benchmark:{
  setUp[];

  / Calculate slippage with null benchmark
  slippage:.tca.posttrade.calculateSlippage[50100000000j; 0Nj; `buy];

  / Verify null returned
  .test.assert["Null slippage on null benchmark"; null slippage];

  tearDown[];
 }

/ Test: Slippage zero benchmark handling
test_slippage_zero_benchmark:{
  setUp[];

  / Calculate slippage with zero benchmark (guard against division by zero)
  slippage:.tca.posttrade.calculateSlippage[50100000000j; 0j; `buy];

  / Verify null returned
  .test.assert["Null slippage on zero benchmark"; null slippage];

  tearDown[];
 }

/ Test: Benchmark volatility calculation
test_benchmark_volatility:{
  setUp[];

  / Update benchmark (includes volatility calculation)
  .tca.benchmark.update[];

  / Verify volatility calculated
  bench:first select from .tca.tcaBenchmark where pair=`BTCUSD, interval=`1min;
  .test.assert["Volatility present"; `volatility in key bench];

  / Verify volatility is non-negative
  .test.assert["Volatility non-negative"; bench[`volatility] >= 0f];

  tearDown[];
 }

/ Test: Aggregate summary statistics
test_aggregate_summary:{
  setUp[];

  / Generate report
  .tca.posttrade.generateReport[1j];

  / Get summary
  summary:.tca.aggregate.summary[.z.D; .z.D];

  / Verify summary structure
  .test.assert["totalOrders present"; `totalOrders in key summary];
  .test.assert["avgTotalCostBps present"; `avgTotalCostBps in key summary];
  .test.assert["medianTotalCostBps present"; `medianTotalCostBps in key summary];

  tearDown[];
 }

/ Test: Empty date range returns empty aggregation
test_empty_date_range:{
  setUp[];

  / Query future date range (no data)
  agg:.tca.aggregate.byStrategy[.z.D + 10; .z.D + 20];

  / Verify empty result
  .test.assertEqual["Empty aggregation"; 0; count agg];

  tearDown[];
 }

/ ============================================================================
/ RUN TESTS
/ ============================================================================

if[not "run_all_tests.q" ~ last get[`.z.f]; .test.run[`test_vwap_benchmark_known_trades; `test_pretrade_estimate_components; `test_posttrade_slippage_buy; `test_posttrade_slippage_sell; `test_aggregate_by_strategy; `test_aggregate_by_exchange; `test_pretrade_spread_cost; `test_pretrade_market_impact; `test_pretrade_timing_risk; `test_posttrade_report_generation; `test_slippage_null_benchmark; `test_slippage_zero_benchmark; `test_benchmark_volatility; `test_aggregate_summary; `test_empty_date_range]];
