/ Real-time TCA focused tests

\l tests/q/test_framework.q
\l src/q/tca/init.q

setupTCA:{[]
  .tca.initTCASchema[];
  .tca.benchmark.lastUpdate:.z.p - 61000000000j;
  .tca.posttrade.reportIdCounter:0j;

  set[`.qg.trade; ([] time_created:`timestamp$(); exchange_name:`symbol$(); volume_currency:`symbol$(); price_currency:`symbol$(); price:`long$(); volume:`long$())];
  set[`.qg.order; ([] order_id:`long$(); exchange_name:`symbol$(); volume_currency:`symbol$(); price_currency:`symbol$(); order_type:`symbol$(); price:`long$(); volume:`long$(); filled_volume:`long$(); status:`symbol$(); time_created:`timestamp$(); actor:`symbol$())];
  set[`.qg.getOrder; {[oid] first select from .qg.order where order_id=oid}];
  set[`.qg.getTradesForOrder; {[oid] select time_created,price,volume from .qg.trade}];

  set[`.risk.orderbook; ([] exchange:`symbol$(); sym:`symbol$(); side:`symbol$(); price:`long$(); size:`long$())];
  set[`.risk.calcBookDepth; {[ex;pair;side;qty] 90f}];

  now:.z.p;
  `.qg.trade insert (now - 30000000000j; `binance; `BTC; `USD; 50000000000j; 1000000j);
  `.qg.trade insert (now - 20000000000j; `binance; `BTC; `USD; 50100000000j; 2000000j);
  `.qg.trade insert (now - 10000000000j; `binance; `BTC; `USD; 49900000000j; 1500000j);
  `.qg.order insert (1j; `binance; `BTC; `USD; `buy; 50000000000j; 3000000j; 3000000j; `filled; now - 25000000000j; `testStrategy);
  `.risk.orderbook insert (`binance; `BTCUSD; `bid; 49990000000j; 5000000j);
  `.risk.orderbook insert (`binance; `BTCUSD; `ask; 50010000000j; 5000000j);
 };

test_tca_loads_namespaces:{[]
  .test.assert["Benchmark namespace loaded"; not ()~key `.tca.benchmark.update];
  .test.assert["Pretrade namespace loaded"; not ()~key `.tca.pretrade.estimateCost];
  .test.assert["Posttrade namespace loaded"; not ()~key `.tca.posttrade.generateReport];
  .test.assert["Aggregate namespace loaded"; not ()~key `.tca.aggregate.summary];
 };

test_tca_benchmark_update:{[]
  setupTCA[];
  .tca.benchmark.update[];
  benchRows:select from .tca.tcaBenchmark where exchange=`binance, pair=`BTCUSD, interval=`1min;
  .test.assert["1-minute benchmark generated"; 1=count benchRows];
  bench:first benchRows;
  .test.assert["VWAP is populated"; not null bench`vwap];
  .test.assert["Volume is aggregated"; bench[`volume]=4500000j];
 };

test_tca_pretrade_cost:{[]
  setupTCA[];
  cost:.tca.pretrade.estimateCost[`binance;`BTCUSD;`buy;2000000j];
  .test.assert["Spread cost present"; `spreadCostBps in key cost];
  .test.assert["Impact present"; `impactBps in key cost];
  .test.assert["Total equals components"; cost[`totalCostBps]=cost[`spreadCostBps]+cost[`impactBps]+cost[`timingRiskBps]];
  .test.assert["Pre-trade table populated"; 1=count .tca.preTradeTCA];
 };

test_tca_slippage_guards:{[]
  .test.assertNear["Buy slippage bps"; 20f; .tca.posttrade.calculateSlippage[50100000000j;50000000000j;`buy]; 0.01f];
  .test.assertNear["Sell slippage bps"; 20f; .tca.posttrade.calculateSlippage[49900000000j;50000000000j;`sell]; 0.01f];
  .test.assert["Null benchmark returns null"; null .tca.posttrade.calculateSlippage[50100000000j;0Nj;`buy]];
  .test.assert["Zero benchmark returns null"; null .tca.posttrade.calculateSlippage[50100000000j;0j;`buy]];
 };

test_tca_posttrade_report_and_summary:{[]
  setupTCA[];
  .tca.benchmark.update[];
  reportId:.tca.posttrade.generateReport[1j];
  .test.assert["Report id generated"; reportId=1j];
  .test.assert["Report stored"; reportId in exec reportId from .tca.tcaReport];
  report:.tca.posttrade.getReport[reportId];
  .test.assert["Report pair is BTCUSD"; report[`pair]=`BTCUSD];
  summary:.tca.aggregate.summary[.z.d;.z.d];
  .test.assert["Summary counts report"; summary[`totalOrders]=1];
  .test.assert["Summary has total cost"; not null summary`avgTotalCostBps];
 };

-1 "TCA focused tests loaded";
failed:.test.run[`.];
exit failed;
