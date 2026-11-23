/ Tests for P&L Attribution Module

\l src/q/risk/init.q
\l tests/q/test_framework.q

/ ═══════════════════════════════════════════════════════════════════
/ P&L Attribution Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== P&L ATTRIBUTION TESTS ===";

/ Test 1: Initialization
test_pnlAttribution_init:{[]
  .risk.initPnLAttribution[];

  / Check tables exist
  .test.assert["fillsAttributed exists"; .Q.qt .risk.fillsAttributed];
  .test.assert["pnlByStrategy exists"; .Q.qt .risk.pnlByStrategy];
  .test.assert["pnlByExchange exists"; .Q.qt .risk.pnlByExchange];
  .test.assert["pnlBySignalType exists"; .Q.qt .risk.pnlBySignalType];
  .test.assert["pnlBySession exists"; .Q.qt .risk.pnlBySession];
  .test.assert["pnlCube exists"; .Q.qt .risk.pnlCube];
 };

/ Test 2: Get session
test_pnlAttribution_getSession:{[]
  .risk.initPnLAttribution[];

  / Test different hours
  asiaTs:2025.01.01D04:00:00.000000000;
  europeTs:2025.01.01D12:00:00.000000000;
  usTs:2025.01.01D20:00:00.000000000;

  .test.assertEqual["Asia session"; `asia; .risk.getSession[asiaTs]];
  .test.assertEqual["Europe session"; `europe; .risk.getSession[europeTs]];
  .test.assertEqual["US session"; `us; .risk.getSession[usTs]];
 };

/ Test 3: Record fill
test_pnlAttribution_recordFill:{[]
  .risk.initPnLAttribution[];

  / Clear fills
  delete from `.risk.fillsAttributed;

  / Record a fill
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];

  / Verify fill recorded
  .test.assertEqual["Fill recorded"; 1; count .risk.fillsAttributed];
  .test.assertEqual["Strategy correct"; `strat1; first exec strategy from .risk.fillsAttributed];
  .test.assertEqual["Signal type correct"; `arb; first exec signalType from .risk.fillsAttributed];
 };

/ Test 4: Update fill P&L
test_pnlAttribution_updateFillPnL:{[]
  .risk.initPnLAttribution[];

  / Clear fills
  delete from `.risk.fillsAttributed;

  / Record a fill
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];

  / Update P&L
  .risk.updateFillPnL[0j;100.0];

  / Verify P&L updated
  .test.assertEqual["P&L updated"; 100.0; first exec realizedPnL from .risk.fillsAttributed];
 };

/ Test 5: Update strategy P&L
test_pnlAttribution_updateStrategyPnL:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlByStrategy;

  / Record fills with P&L
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;100.0];

  .risk.recordFill[`strat1;`coinbase;`ETHUSD;`sell;10.0;3000.0;`momentum];
  .risk.updateFillPnL[1j;-50.0];

  / Verify aggregation
  .test.assertEqual["Strategy count"; 1; count .risk.pnlByStrategy];
  .test.assertEqual["Total P&L"; 50.0; first exec totalPnL from .risk.pnlByStrategy where strategy=`strat1];
  .test.assertEqual["Trade count"; 2i; first exec tradeCount from .risk.pnlByStrategy where strategy=`strat1];
  .test.assertEqual["Win rate"; 50.0; first exec winRate from .risk.pnlByStrategy where strategy=`strat1];
 };

/ Test 6: Update exchange P&L
test_pnlAttribution_updateExchangePnL:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlByExchange;

  / Record fills on different exchanges
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;100.0];

  .risk.recordFill[`strat2;`binance;`ETHUSD;`sell;10.0;3000.0;`momentum];
  .risk.updateFillPnL[1j;50.0];

  / Verify aggregation by exchange
  .test.assertEqual["Exchange count"; 1; count .risk.pnlByExchange];
  .test.assertEqual["Binance total P&L"; 150.0; first exec totalPnL from .risk.pnlByExchange where exchange=`binance];
 };

/ Test 7: Update signal type P&L
test_pnlAttribution_updateSignalTypePnL:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlBySignalType;

  / Record fills with different signal types
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;100.0];

  .risk.recordFill[`strat2;`coinbase;`ETHUSD;`sell;10.0;3000.0;`arb];
  .risk.updateFillPnL[1j;50.0];

  / Verify aggregation by signal type
  .test.assertEqual["Signal type count"; 1; count .risk.pnlBySignalType];
  .test.assertEqual["Arb total P&L"; 150.0; first exec totalPnL from .risk.pnlBySignalType where signalType=`arb];
 };

/ Test 8: OLAP cube
test_pnlAttribution_pnlCube:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlCube;

  / Record fills
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;100.0];

  / Verify cube populated
  .test.assertEqual["Cube count"; 1; count .risk.pnlCube];
  .test.assert["Cube has strategy"; `strat1 in exec strategy from .risk.pnlCube];
  .test.assert["Cube has exchange"; `binance in exec exchange from .risk.pnlCube];
  .test.assert["Cube has signalType"; `arb in exec signalType from .risk.pnlCube];
 };

/ Test 9: Query P&L cube
test_pnlAttribution_queryCube:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlCube;

  / Record fills
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;100.0];

  .risk.recordFill[`strat2;`coinbase;`ETHUSD;`sell;10.0;3000.0;`momentum];
  .risk.updateFillPnL[1j;50.0];

  / Query with filter
  result:.risk.queryPnLCube[`strategy`strat1!()];

  / Verify filtered result
  .test.assertEqual["Filtered count"; 1; count result];
  .test.assert["Only strat1"; all `strat1 = exec strategy from result];
 };

/ Test 10: Top and bottom performers
test_pnlAttribution_topBottom:{[]
  .risk.initPnLAttribution[];

  / Clear tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlByStrategy;

  / Record fills with varying P&L
  .risk.recordFill[`strat1;`binance;`BTCUSD;`buy;1.0;50000.0;`arb];
  .risk.updateFillPnL[0j;500.0];

  .risk.recordFill[`strat2;`coinbase;`ETHUSD;`sell;10.0;3000.0;`momentum];
  .risk.updateFillPnL[1j;100.0];

  .risk.recordFill[`strat3;`kraken;`ADAUSD;`buy;1000.0;1.0;`meanReversion];
  .risk.updateFillPnL[2j;-200.0];

  / Get top performers
  top:.risk.getTopPerformers[`strategy;2];
  .test.assertEqual["Top 2 strategies"; 2; count top];
  .test.assertEqual["Top performer"; `strat1; first exec strategy from top];

  / Get bottom performers
  bottom:.risk.getBottomPerformers[`strategy;2];
  .test.assertEqual["Bottom 2 strategies"; 2; count bottom];
  .test.assertEqual["Bottom performer"; `strat3; first exec strategy from bottom];
 };

if[not `medusaRunAll in key `.; exit .test.run[`.]];
