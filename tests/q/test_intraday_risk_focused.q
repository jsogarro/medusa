/ Focused verification for intraday risk modules (#34a)

\l tests/q/test_framework.q
\l src/q/schema/equity.q
\l src/q/risk/init.q

reset_intraday_risk_fixtures:{[]
  set[`.schema.position;([] strategy:`symbol$(); sym:`symbol$(); exchange:`symbol$(); quantity:`float$(); avgEntryPrice:`float$(); lastUpdate:`timestamp$())];
  set[`.schema.order;([] time_created:`timestamp$(); exchange:`symbol$(); status:`symbol$(); quantity:`float$(); price:`float$())];

  .risk.initRealtimePnL[];
  .risk.initExposureHeatmap[];
  .risk.initOrderFlowRisk[];
  .risk.initAlertEngine[];
  .risk.initRiskSnapshot[];
  .risk.deactivateEmergencyStop[`testSetup];
 };

test_intraday_risk_initializes_state:{[]
  reset_intraday_risk_fixtures[];

  pnl:first .risk.intradayPnL;
  .test.assertEqual["Intraday total PnL starts at zero"; 0.0; pnl`totalPnL];
  .test.assertEqual["Default PnL alert thresholds loaded"; 2; count .risk.pnlAlertThresholds];
  .test.assertEqual["Default alert rules loaded"; 5; count .risk.alertRules];
  .test.assertEqual["Risk snapshots start empty"; 0; count .risk.riskSnapshots];
 };

test_intraday_risk_updates_strategy_pnl:{[]
  reset_intraday_risk_fixtures[];

  .risk.updateStrategyPnLRT[`alpha;100.0;0.0];
  .risk.updateStrategyPnLRT[`alpha;-25.0;0.0];

  strategyPnL:first select from .risk.pnlByStrategyRT where strategy=`alpha;
  .test.assertEqual["Strategy realized PnL accumulates"; 75.0; strategyPnL`realizedPnL];
  .test.assertEqual["Strategy trade count accumulates"; 2i; strategyPnL`tradeCount];
  .test.assertEqual["Strategy win count tracks positive realized PnL"; 1i; strategyPnL`winCount];
  .test.assertEqual["Strategy loss count tracks negative realized PnL"; 1i; strategyPnL`lossCount];
 };

test_intraday_risk_recalculates_exposure_grid:{[]
  reset_intraday_risk_fixtures[];
  set[`.schema.position;([] strategy:`alpha`beta; sym:`BTCUSD`ETHUSD; exchange:`coinbase`kraken; quantity:1.0 -2.0; avgEntryPrice:50000.0 3000.0; lastUpdate:.z.p,.z.p)];

  .risk.recalcExposureGrid[];

  .test.assertEqual["Exposure grid has one row per exchange-symbol position"; 2; count .risk.exposureSnapshot];
  .test.assertNear["Gross exposure aggregates absolute notionals"; 56000.0; .risk.exposure.gross[]; 0.01];
  .test.assertNear["Net exposure preserves signed notionals"; 44000.0; .risk.exposure.net[]; 0.01];
 };

test_intraday_risk_updates_order_flow:{[]
  reset_intraday_risk_fixtures[];
  now:.z.p;
  set[`.schema.order;([] time_created:now,now,now; exchange:`coinbase`coinbase`kraken; status:`open`rejected`filled; quantity:1.0 2.0 3.0; price:100.0 200.0 300.0)];

  .risk.updateOrderFlowMetrics[];

  latest:.risk.orderFlow.current[];
  .test.assertEqual["Order flow submitted count includes window orders"; 3i; latest`ordersSubmitted];
  .test.assertNear["Order flow rejection rate is calculated"; 33.33333333333333; latest`rejectionRate; 0.01];
  .test.assertEqual["Order flow by exchange is populated"; 2; count .risk.orderFlow.byExchange[]];
 };

test_intraday_risk_alerts_and_snapshots:{[]
  reset_intraday_risk_fixtures[];

  update totalPnL:-6000.0 from `.risk.intradayPnL;
  .risk.checkAlertRules[];
  .test.assert["Pnl alert rule records alert history"; 0 < count .risk.alertHistory];

  .risk.snapshot.capture[];
  .test.assertEqual["Snapshot capture appends one row"; 1; count .risk.riskSnapshots];
 };

-1 "Focused intraday risk tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];
