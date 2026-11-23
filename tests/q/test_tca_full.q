/ ============================================================================
/ test_tca_full.q - Transaction Cost Analysis Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests for:
/   - Benchmark calculation (VWAP, TWAP, arrival price)
/   - Pre-trade cost estimation (spread, impact, timing risk)
/   - Post-trade slippage calculation
/   - Aggregate TCA queries (by strategy, exchange, hour)
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - VWAP benchmark: known trades → expected VWAP
/   - TWAP benchmark: avg of prices at intervals
/   - Pre-trade cost: spread + impact + timing risk
/   - Post-trade slippage: (avgFill - arrival) / arrival × 10000
/   - Aggregate queries: by strategy, by exchange, by hour
/ ----------------------------------------------------------------------------
/ Usage:
/   q test_tca_full.q
/ ============================================================================

/ Load test framework
\l ../src/q/test/test_framework.q

/ Load TCA modules
\l ../src/q/tca/schema.q
\l ../src/q/tca/benchmark.q
\l ../src/q/tca/pretrade.q
\l ../src/q/tca/posttrade.q

// ============================================================================
// TEST FIXTURES
// ============================================================================

\d .fixtures

/ Initialize global trade table for TCA
.qg.trade:([] time_created:`timestamp$(); exchange_name:`symbol$();
               volume_currency:`symbol$(); price_currency:`symbol$();
               price:`long$(); volume:`long$(); tradeId:`long$());

/ Sample trades for benchmark calculation
sampleTrades:([] time_created:.z.p + til 5 * 1000000000;
                 exchange_name:5#`kraken;
                 volume_currency:5#`BTC;
                 price_currency:5#`USD;
                 price:50000000000 50010000000 50020000000 50015000000 50030000000j;
                 volume:1000000 1500000 2000000 1800000 1200000j;  / 1.0, 1.5, 2.0, 1.8, 1.2 units
                 tradeId:til 5);

/ Sample orderbook for risk module
.risk.orderbook:([] exchange:`symbol$(); sym:`symbol$(); side:`symbol$();
                     price:`long$(); volume:`long$());

/ Standard orderbook levels
standardOrderbook:([] exchange:12#`kraken;
                       sym:12#`BTCUSD;
                       side:`bid`bid`bid`bid`bid`bid`ask`ask`ask`ask`ask`ask;
                       price:50040000000 50030000000 50020000000 50010000000 50000000000 49990000000
                             50050000000 50060000000 50070000000 50080000000 50090000000 50100000000j;
                       volume:10000000 15000000 20000000 25000000 30000000 35000000
                              12000000 18000000 22000000 28000000 32000000 38000000j);

/ Initialize TCA tables
.tca.tcaBenchmark:([] time:`timestamp$(); exchange:`symbol$(); pair:`symbol$();
                      interval:`symbol$(); arrivalPx:`long$(); vwap:`long$();
                      twap:`long$(); closePx:`long$(); volume:`long$(); volatility:`float$());

.tca.preTradeTCA:([] time:`timestamp$(); exchange:`symbol$(); pair:`symbol$();
                     side:`symbol$(); qty:`long$(); estimatedSpreadBps:`float$();
                     estimatedImpactBps:`float$(); estimatedTotalBps:`float$());

.tca.tcaReport:([] reportId:`long$(); orderId:`long$(); exchange:`symbol$();
                   pair:`symbol$(); side:`symbol$(); targetQty:`long$();
                   filledQty:`long$(); avgFillPx:`long$(); arrivalPx:`long$();
                   vwapBenchmark:`long$(); twapBenchmark:`long$();
                   arrivalSlippageBps:`float$(); vwapSlippageBps:`float$();
                   marketImpactBps:`float$(); spreadCostBps:`float$();
                   totalCostBps:`float$(); executionTime:`long$();
                   submitTime:`timestamp$(); completeTime:`timestamp$());

\d .

// ============================================================================
// BENCHMARK CALCULATION TESTS
// ============================================================================

\d .test.benchmark

/ Test VWAP calculation from trades
test_update_vwapCalculation:{[]
  / Setup
  delete from `.qg.trade;
  delete from `.tca.tcaBenchmark;
  `.qg.trade upsert .fixtures.sampleTrades;

  / Execute
  .tca.benchmark.update[];

  / Assert
  .test.assert["Benchmark rows created"; 0 < count .tca.tcaBenchmark];

  / Get benchmark for BTCUSD
  bench:first select from .tca.tcaBenchmark where pair=`BTCUSD, interval=`1min;

  / Calculate expected VWAP manually with correct fixed-precision arithmetic
  / Prices are already in fixed precision (e.g., 50000000000j = 50000.0)
  / Volumes are in fixed precision (e.g., 1000000j = 1.0)
  trades:.fixtures.sampleTrades;
  totalNotional:sum trades[`price] * trades`volume;
  totalVolume:sum trades`volume;
  expectedVwap:totalNotional % totalVolume;

  / Assert VWAP calculated correctly
  .test.assertNear["VWAP calculated correctly"; expectedVwap; bench`vwap; 1000000j];
 };

/ Test TWAP calculation from trades
test_update_twapCalculation:{[]
  / Setup
  delete from `.qg.trade;
  delete from `.tca.tcaBenchmark;
  `.qg.trade upsert .fixtures.sampleTrades;

  / Execute
  .tca.benchmark.update[];

  / Assert
  bench:first select from .tca.tcaBenchmark where pair=`BTCUSD, interval=`1min;

  / Calculate expected TWAP (simple average of prices)
  trades:.fixtures.sampleTrades;
  expectedTwap:avg trades[`price] % 1000000;

  / Assert TWAP calculated correctly
  actualTwap:bench[`twap] % 1000000;
  .test.assertNear["TWAP calculated correctly"; expectedTwap; actualTwap; 0.01];
 };

/ Test getBenchmark retrieves correct benchmark
test_getBenchmark:{[]
  / Setup
  delete from `.tca.tcaBenchmark;
  now:.z.p;
  `.tca.tcaBenchmark insert (now;`kraken;`BTCUSD;`1min;50000000000j;50015000000j;50010000000j;50020000000j;7500000j;0.0001);

  / Execute
  bench:.tca.benchmark.getBenchmark[`kraken;`BTCUSD;`1min;now];

  / Assert
  .test.assertNear["VWAP retrieved"; 50015000000j; bench`vwap; 1000000j];
  .test.assertNear["TWAP retrieved"; 50010000000j; bench`twap; 1000000j];
  .test.assertNear["ArrivalPx retrieved"; 50000000000j; bench`arrivalPx; 1000000j];
 };

/ Test getBenchmarksForWindow aggregates across time
test_getBenchmarksForWindow:{[]
  / Setup
  delete from `.tca.tcaBenchmark;
  now:.z.p;
  / Insert 3 benchmarks over 3 minutes
  `.tca.tcaBenchmark insert (now;`kraken;`BTCUSD;`1min;50000000000j;50010000000j;50005000000j;50015000000j;2000000j;0.0001);
  `.tca.tcaBenchmark insert (now + 60000000000;`kraken;`BTCUSD;`1min;50015000000j;50020000000j;50018000000j;50025000000j;3000000j;0.0001);
  `.tca.tcaBenchmark insert (now + 120000000000;`kraken;`BTCUSD;`1min;50025000000j;50030000000j;50028000000j;50035000000j;2500000j;0.0001);

  / Execute
  benchmarks:.tca.benchmark.getBenchmarksForWindow[`kraken;`BTCUSD;`1min;now;now + 120000000000];

  / Assert
  / Window VWAP = volume-weighted across 3 intervals
  / Calculate expected with correct fixed-precision multiplication
  totalNotional:50010000000j * 2000000j + 50020000000j * 3000000j + 50030000000j * 2500000j;
  totalVolume:2000000j + 3000000j + 2500000j;
  expectedVwap:totalNotional % totalVolume;
  .test.assertNear["Window VWAP aggregated"; expectedVwap; benchmarks`vwap; 10000000j];
 };

// ============================================================================
// PRE-TRADE COST ESTIMATION TESTS
// ============================================================================

\d .test.pretrade

/ Test spread cost calculation
test_estimateSpreadCost:{[]
  / Setup
  delete from `.risk.orderbook;
  `.risk.orderbook upsert .fixtures.standardOrderbook;

  / Execute
  spreadCost:.tca.pretrade.estimateSpreadCost[`kraken;`BTCUSD];

  / Assert
  / Spread = (50050 - 50040) / mid × 10000
  / Mid = (50040 + 50050) / 2 = 50045
  / Spread = 10 / 50045 × 10000 ≈ 1.998 bps
  .test.assertNear["Spread cost ~2 bps"; 2.0; spreadCost; 0.1];
 };

/ Test total cost estimation
test_estimateCost:{[]
  / Setup
  delete from `.risk.orderbook;
  delete from `.tca.preTradeTCA;
  delete from `.tca.tcaBenchmark;
  `.risk.orderbook upsert .fixtures.standardOrderbook;

  / Insert benchmark with volatility
  `.tca.tcaBenchmark insert (.z.p;`kraken;`BTCUSD;`1min;50000000000j;50020000000j;50010000000j;50030000000j;5000000j;0.0002);

  / Execute
  cost:.tca.pretrade.estimateCost[`kraken;`BTCUSD;`buy;10000000j];

  / Assert
  .test.assert["SpreadCostBps > 0"; cost[`spreadCostBps] > 0.0];
  .test.assert["ImpactBps >= 0"; cost[`impactBps] >= 0.0];
  .test.assert["TimingRiskBps >= 0"; cost[`timingRiskBps] >= 0.0];
  .test.assert["TotalCostBps > 0"; cost[`totalCostBps] > 0.0];

  / Verify inserted into preTradeTCA table
  .test.assert["Pre-trade TCA record created"; 0 < count .tca.preTradeTCA];
 };

// ============================================================================
// POST-TRADE SLIPPAGE CALCULATION TESTS
// ============================================================================

\d .test.posttrade

/ Test slippage calculation - buy order (paid more)
test_calculateSlippage_buy:{[]
  / Setup
  fillPx:50020000000j;  / Filled at 50020
  benchmarkPx:50000000000j;  / Benchmark was 50000
  side:`buy;

  / Execute
  slippage:.tca.posttrade.calculateSlippage[fillPx;benchmarkPx;side];

  / Assert
  / Slippage = (50020 - 50000) / 50000 × 10000 = 4 bps (positive = bad)
  .test.assertNear["Buy slippage is 4 bps"; 4.0; slippage; 0.1];
 };

/ Test slippage calculation - sell order (received less)
test_calculateSlippage_sell:{[]
  / Setup
  fillPx:49980000000j;  / Filled at 49980
  benchmarkPx:50000000000j;  / Benchmark was 50000
  side:`sell;

  / Execute
  slippage:.tca.posttrade.calculateSlippage[fillPx;benchmarkPx;side];

  / Assert
  / Slippage = (50000 - 49980) / 50000 × 10000 = 4 bps (positive = bad)
  .test.assertNear["Sell slippage is 4 bps"; 4.0; slippage; 0.1];
 };

/ Test slippage with null benchmark
test_calculateSlippage_nullBenchmark:{[]
  / Setup
  fillPx:50000000000j;
  benchmarkPx:0Nj;  / Null benchmark
  side:`buy;

  / Execute
  slippage:.tca.posttrade.calculateSlippage[fillPx;benchmarkPx;side];

  / Assert
  .test.assert["Null benchmark returns null slippage"; null slippage];
 };

/ Test slippage with null fillPx
test_calculateSlippage_nullFillPx:{[]
  / Setup
  fillPx:0Nj;  / Null fill price
  benchmarkPx:50000000000j;
  side:`buy;

  / Execute
  slippage:.tca.posttrade.calculateSlippage[fillPx;benchmarkPx;side];

  / Assert
  .test.assert["Null fillPx returns null slippage"; null slippage];
 };

// ============================================================================
// AGGREGATE TCA QUERY TESTS
// ============================================================================

\d .test.aggregate

/ Test aggregate by exchange
test_aggregateByExchange:{[]
  / Setup
  delete from `.tca.tcaReport;
  / Insert sample reports
  `.tca.tcaReport insert (1j;1001j;`kraken;`BTCUSD;`buy;10000000j;10000000j;50020000000j;50000000000j;50010000000j;50005000000j;4.0;2.0;1.0;2.0;9.0;120000000000j;.z.p - 300000000000j;.z.p - 180000000000j);
  `.tca.tcaReport insert (2j;1002j;`kraken;`ETHUSD;`sell;5000000j;5000000j;3200000000j;3205000000j;3202000000j;3203000000j;1.5;0.6;0.5;1.0;3.6;90000000000j;.z.p - 200000000000j;.z.p - 110000000000j);
  `.tca.tcaReport insert (3j;1003j;`coinbase;`BTCUSD;`buy;8000000j;8000000j;50030000000j;50000000000j;50015000000j;50010000000j;6.0;3.0;1.5;2.5;13.0;150000000000j;.z.p - 400000000000j;.z.p - 250000000000j);

  / Execute
  agg:select avgTotalCost:avg totalCostBps, reportCount:count i by exchange from .tca.tcaReport;

  / Assert
  .test.assertEqual["3 reports total"; 3; sum agg`reportCount];
  krakenAvg:exec avgTotalCost from agg where exchange=`kraken;
  / Kraken avg = (9.0 + 3.6) / 2 = 6.3
  .test.assertNear["Kraken avg cost is 6.3 bps"; 6.3; first krakenAvg; 0.1];
 };

/ Test aggregate by pair
test_aggregateByPair:{[]
  / Setup
  delete from `.tca.tcaReport;
  / Insert sample reports
  `.tca.tcaReport insert (1j;1001j;`kraken;`BTCUSD;`buy;10000000j;10000000j;50020000000j;50000000000j;50010000000j;50005000000j;4.0;2.0;1.0;2.0;9.0;120000000000j;.z.p - 300000000000j;.z.p - 180000000000j);
  `.tca.tcaReport insert (2j;1002j;`kraken;`BTCUSD;`sell;5000000j;5000000j;50010000000j;50000000000j;50005000000j;50003000000j;2.0;1.0;0.5;1.5;5.0;90000000000j;.z.p - 200000000000j;.z.p - 110000000000j);
  `.tca.tcaReport insert (3j;1003j;`coinbase;`ETHUSD;`buy;8000000j;8000000j;3200000000j;3195000000j;3198000000j;3197000000j;1.5;0.6;0.3;1.0;3.4;150000000000j;.z.p - 400000000000j;.z.p - 250000000000j);

  / Execute
  agg:select avgTotalCost:avg totalCostBps, reportCount:count i by pair from .tca.tcaReport;

  / Assert
  / Verify BTCUSD has 2 reports
  btcCount:exec reportCount from agg where pair=`BTCUSD;
  .test.assertEqual["BTCUSD has 2 reports"; 2; first btcCount];
  / BTCUSD avg = (9.0 + 5.0) / 2 = 7.0
  btcAvg:exec avgTotalCost from agg where pair=`BTCUSD;
  .test.assertNear["BTCUSD avg cost is 7.0 bps"; 7.0; first btcAvg; 0.1];
 };

/ Test aggregate by hour
test_aggregateByHour:{[]
  / Setup
  delete from `.tca.tcaReport;
  now:.z.p;
  / Insert reports across 2 hours
  `.tca.tcaReport insert (1j;1001j;`kraken;`BTCUSD;`buy;10000000j;10000000j;50020000000j;50000000000j;50010000000j;50005000000j;4.0;2.0;1.0;2.0;9.0;120000000000j;now - 3600000000000j;now - 3480000000000j);  / Hour -1
  `.tca.tcaReport insert (2j;1002j;`kraken;`BTCUSD;`sell;5000000j;5000000j;50010000000j;50000000000j;50005000000j;50003000000j;2.0;1.0;0.5;1.5;5.0;90000000000j;now - 1800000000000j;now - 1710000000000j);  / Hour 0
  `.tca.tcaReport insert (3j;1003j;`coinbase;`BTCUSD;`buy;8000000j;8000000j;50030000000j;50000000000j;50015000000j;50010000000j;6.0;3.0;1.5;2.5;13.0;150000000000j;now - 600000000000j;now - 450000000000j);  / Hour 0

  / Execute
  agg:select avgTotalCost:avg totalCostBps, count i by hour:`hh$submitTime from .tca.tcaReport;

  / Assert
  .test.assert["Aggregated by hour"; 0 < count agg];
  / Should have 2 distinct hours
  .test.assertEqual["2 distinct hours"; 2; count agg];
 };

// ============================================================================
// MULTI-EXCHANGE TCA TESTS
// ============================================================================

\d .test.multiExchange

/ Test slippage calculation across different exchanges
test_slippageAcrossExchanges:{[]
  / Setup
  delete from `.tca.tcaReport;
  / Same pair, different exchanges
  `.tca.tcaReport insert (1j;1001j;`kraken;`BTCUSD;`buy;10000000j;10000000j;50020000000j;50000000000j;50010000000j;50005000000j;4.0;2.0;1.0;2.0;9.0;120000000000j;.z.p - 300000000000j;.z.p - 180000000000j);
  `.tca.tcaReport insert (2j;1002j;`coinbase;`BTCUSD;`buy;10000000j;10000000j;50030000000j;50000000000j;50015000000j;50010000000j;6.0;3.0;1.5;2.5;13.0;150000000000j;.z.p - 200000000000j;.z.p - 50000000000j);

  / Execute
  agg:select avgSlippage:avg arrivalSlippageBps by exchange from .tca.tcaReport;

  / Assert
  .test.assertEqual["Both exchanges present"; 2; count agg];
  / Kraken slippage should be 4.0 bps
  krakenSlip:exec avgSlippage from agg where exchange=`kraken;
  .test.assertNear["Kraken slippage is 4.0 bps"; 4.0; first krakenSlip; 0.1];
  / Coinbase slippage should be 6.0 bps
  coinbaseSlip:exec avgSlippage from agg where exchange=`coinbase;
  .test.assertNear["Coinbase slippage is 6.0 bps"; 6.0; first coinbaseSlip; 0.1];
 };

\d .

// ============================================================================
// RUN ALL TESTS
// ============================================================================

-1 "\n=== Running TCA Tests ===\n";
.test.run[`.test.benchmark];
.test.run[`.test.pretrade];
.test.run[`.test.posttrade];
.test.run[`.test.aggregate];
.test.run[`.test.multiExchange];

/ Exit with appropriate code
exit .test.failed
