/ Tests for Real-Time P&L Monitoring

/ Load test framework
\l test_framework.q

\d .test

/ ═══════════════════════════════════════════════════════════════════
/ Setup
/ ═══════════════════════════════════════════════════════════════════

setup:{[]
  / Initialize risk system
  .risk.init[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Test Cases
/ ═══════════════════════════════════════════════════════════════════

/ Test: P&L initialization
testPnLInitialization:{[]
  setup[];

  / Check intraday P&L is initialized to zero
  pnl:first .risk.intradayPnL;
  assert[pnl[`totalPnL] = 0.0; "Total P&L should be 0"];
  assert[pnl[`realizedPnL] = 0.0; "Realized P&L should be 0"];
  assert[pnl[`unrealizedPnL] = 0.0; "Unrealized P&L should be 0"];

  / Check alert thresholds are set
  assert[2 = count .risk.pnlAlertThresholds; "Should have 2 alert thresholds"];

  pass[];
 };

/ Test: Realized P&L calculation (FIFO)
testRealizedPnLCalc:{[]
  setup[];

  / Create a position (buy 1 BTC at 60000)
  `.schema.position upsert ([] strategy:`testStrategy; sym:`BTCUSD; exchange:`coinbase;
                               quantity:1.0; avgEntryPrice:60000.0; lastUpdate:.z.p);

  / Calculate realized P&L for closing trade (sell 1 BTC at 61000)
  realizedPnL:.risk.calculateRealizedPnL[`testStrategy;`BTCUSD;`sell;1.0;61000.0];

  / Expected: (61000 - 60000) * 1.0 = 1000.0
  assert[realizedPnL = 1000.0; "Realized P&L should be 1000"];

  pass[];
 };

/ Test: P&L aggregation by strategy
testPnLByStrategy:{[]
  setup[];

  / Update strategy P&L
  .risk.updateStrategyPnLRT[`arb_v2; 1000.0; 0.0];
  .risk.updateStrategyPnLRT[`arb_v2; 500.0; 0.0];

  / Check aggregation
  strategyPnL:first select from .risk.pnlByStrategyRT where strategy=`arb_v2;
  assert[strategyPnL[`realizedPnL] = 1500.0; "Realized P&L should be 1500"];
  assert[strategyPnL[`tradeCount] = 2i; "Trade count should be 2"];

  pass[];
 };

/ Test: P&L alert threshold breach
testPnLAlertThreshold:{[]
  setup[];

  / Set total P&L to -6000 (below halt threshold of -15000 absolute or -5% loss)
  .risk.intradayPnL[`totalPnL]:-6000.0;
  .risk.intradayPnL[`dayOpenPnL]:0.0;

  / Check alerts
  .risk.checkPnLAlerts[];

  / Warn threshold should be breached
  warnThreshold:first select from .risk.pnlAlertThresholds where severity=`warn;
  assert[warnThreshold[`breached] = 1b; "Warn threshold should be breached"];

  pass[];
 };

/ Test: Win rate calculation
testWinRate:{[]
  setup[];

  / Simulate 3 winning trades and 2 losing trades
  .risk.updateStrategyPnLRT[`mm_v1; 100.0; 0.0];  / win
  .risk.updateStrategyPnLRT[`mm_v1; -50.0; 0.0];  / loss
  .risk.updateStrategyPnLRT[`mm_v1; 200.0; 0.0];  / win
  .risk.updateStrategyPnLRT[`mm_v1; -30.0; 0.0];  / loss
  .risk.updateStrategyPnLRT[`mm_v1; 150.0; 0.0];  / win

  / Check win rate
  strategyPnL:first select from .risk.pnlByStrategyRT where strategy=`mm_v1;
  assert[strategyPnL[`winCount] = 3i; "Win count should be 3"];
  assert[strategyPnL[`lossCount] = 2i; "Loss count should be 2"];
  assert[strategyPnL[`winRate] = 60.0; "Win rate should be 60%"];

  pass[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests
/ ═══════════════════════════════════════════════════════════════════

runTests:{[]
  .test.run[`testPnLInitialization];
  .test.run[`testRealizedPnLCalc];
  .test.run[`testPnLByStrategy];
  .test.run[`testPnLAlertThreshold];
  .test.run[`testWinRate];
 };

/ Run tests
runTests[];

\d .
