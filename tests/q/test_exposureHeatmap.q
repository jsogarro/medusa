/ Tests for Exposure Heatmap

/ Load test framework
\l tests/q/testFramework.q

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

/ Test: Exposure grid calculation
testExposureGridCalc:{[]
  setup[];

  / Create positions
  `.schema.position upsert ([] strategy:`arb_v2; sym:`BTCUSD`ETHUSD; exchange:`coinbase`coinbase;
                               quantity:1.0 5.0; avgEntryPrice:60000.0 3000.0; lastUpdate:.z.p .z.p);

  / Recalc exposure grid
  .risk.recalcExposureGrid[];

  / Check grid
  grid:select from .risk.exposureSnapshot;
  assert[2 = count grid; "Should have 2 exposure rows"];

  / Check BTC exposure
  btcExp:first select from grid where sym=`BTCUSD;
  assert[btcExp[`grossExposure] = 60000.0; "BTC gross exposure should be 60000"];
  assert[btcExp[`netExposure] = 60000.0; "BTC net exposure should be 60000"];

  / Check ETH exposure
  ethExp:first select from grid where sym=`ETHUSD;
  assert[ethExp[`grossExposure] = 15000.0; "ETH gross exposure should be 15000"];

  pass[];
 };

/ Test: Concentration level detection
testConcentrationLevel:{[]
  setup[];

  / Create a large position (>50% of portfolio)
  `.schema.position upsert ([] strategy:`arb_v2; sym:`BTCUSD`ETHUSD; exchange:`coinbase`coinbase;
                               quantity:10.0 1.0; avgEntryPrice:60000.0 3000.0; lastUpdate:.z.p .z.p);

  / Recalc exposure grid
  .risk.recalcExposureGrid[];

  / Check concentration levels
  grid:select from .risk.exposureSnapshot;

  / BTC should be critical (600000 / (600000 + 3000) = 99.5%)
  btcExp:first select from grid where sym=`BTCUSD;
  assert[btcExp[`concentration] = `critical; "BTC concentration should be critical"];

  / ETH should be ok (3000 / 603000 = 0.5%)
  ethExp:first select from grid where sym=`ETHUSD;
  assert[ethExp[`concentration] = `ok; "ETH concentration should be ok"];

  pass[];
 };

/ Test: Beta-adjusted exposure
testBetaAdjustedExposure:{[]
  setup[];

  / Create positions
  `.schema.position upsert ([] strategy:`arb_v2; sym:`BTCUSD`ETHUSD`SOLUSD; exchange:`coinbase`coinbase`coinbase;
                               quantity:1.0 5.0 10.0; avgEntryPrice:60000.0 3000.0 120.0; lastUpdate:.z.p .z.p .z.p);

  / Recalc beta-adjusted exposure
  .risk.recalcBetaAdjustedExposure[];

  / Check beta-adjusted exposure
  betaExp:select from .risk.betaAdjustedExposure;
  assert[3 = count betaExp; "Should have 3 beta-adjusted rows"];

  / BTC beta = 1.0
  btcBeta:first select from betaExp where sym=`BTCUSD;
  assert[btcBeta[`betaToBTC] = 1.0; "BTC beta should be 1.0"];
  assert[btcBeta[`btcEquivalent] = 60000.0; "BTC equivalent should be 60000"];

  / ETH beta = 0.8
  ethBeta:first select from betaExp where sym=`ETHUSD;
  assert[ethBeta[`betaToBTC] = 0.8; "ETH beta should be 0.8"];
  assert[ethBeta[`btcEquivalent] = 12000.0; "ETH BTC-equivalent should be 12000"];

  pass[];
 };

/ Test: Exposure summary aggregation
testExposureSummary:{[]
  setup[];

  / Create long and short positions
  `.schema.position upsert ([] strategy:`arb_v2; sym:`BTCUSD`ETHUSD; exchange:`coinbase`coinbase;
                               quantity:1.0 -5.0; avgEntryPrice:60000.0 3000.0; lastUpdate:.z.p .z.p);

  / Recalc exposure grid
  .risk.recalcExposureGrid[];

  / Check summary
  summary:first .risk.exposureSummary;
  assert[summary[`totalGross] = 75000.0; "Total gross should be 75000"];
  assert[summary[`totalNet] = 45000.0; "Total net should be 45000"];
  assert[summary[`totalLong] = 60000.0; "Total long should be 60000"];
  assert[summary[`totalShort] = 15000.0; "Total short should be 15000"];

  pass[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests
/ ═══════════════════════════════════════════════════════════════════

runTests:{[]
  .test.run[`testExposureGridCalc];
  .test.run[`testConcentrationLevel];
  .test.run[`testBetaAdjustedExposure];
  .test.run[`testExposureSummary];
 };

/ Run tests
runTests[];

\d .
