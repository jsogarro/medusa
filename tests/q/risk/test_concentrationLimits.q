/ Tests for Concentration Limits Module

\l src/q/risk/init.q
\l tests/q/test_framework.q

/ ═══════════════════════════════════════════════════════════════════
/ Concentration Limits Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== CONCENTRATION LIMITS TESTS ===";

/ Test 1: Initialization
test_concentrationLimits_init:{[]
  .risk.initConcentrationLimits[];

  / Check default exchange limits exist
  .test.assert["exchangeConcentration initialized"; 3 = count .risk.exchangeConcentration];
  .test.assert["binance in limits"; `binance in exec exchange from .risk.exchangeConcentration];
  .test.assert["Tier 1 exchanges at 40%"; 40.0 = first exec maxPct from .risk.exchangeConcentration where exchange=`binance];

  / Check default asset limits exist
  .test.assert["assetConcentration initialized"; 2 = count .risk.assetConcentration];
  .test.assert["BTCUSD in limits"; `BTCUSD in exec sym from .risk.assetConcentration];
  .test.assertEqual["BTC limit 25%"; 25.0; first exec maxPct from .risk.assetConcentration where sym=`BTCUSD];

  / Check portfolio value initialized
  .test.assert["portfolioValue exists"; 1 = count .risk.portfolioValue];
 };

/ Test 2: Update portfolio value
test_concentrationLimits_portfolioValue:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Verify it was set
  .test.assertEqual["Portfolio value updated"; 1000000.0; first .risk.portfolioValue`totalValue];
 };

/ Test 3: Check exchange concentration - pass
test_concentrationLimits_exchange_pass:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Small order (10K = 1% of portfolio, well below 40% limit)
  result:.risk.checkExchangeConcentration[`binance;1.0;10000.0];
  .test.assert["Check passes"; result 0];
 };

/ Test 4: Check exchange concentration - fail
test_concentrationLimits_exchange_breach:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Large order (500K = 50% of portfolio, exceeds 40% limit)
  result:.risk.checkExchangeConcentration[`binance;1.0;500000.0];
  .test.assert["Check fails"; not result 0];
  .test.assertEqual["Reason is exchangeConcentrationExceeded"; `exchangeConcentrationExceeded; result 1];
 };

/ Test 5: Check asset concentration - pass
test_concentrationLimits_asset_pass:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Small order (10K = 1% of portfolio, well below 25% limit)
  result:.risk.checkAssetConcentration[`BTCUSD;1.0;10000.0];
  .test.assert["Check passes"; result 0];
 };

/ Test 6: Check asset concentration - fail
test_concentrationLimits_asset_breach:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Large order (300K = 30% of portfolio, exceeds 25% limit)
  result:.risk.checkAssetConcentration[`BTCUSD;1.0;300000.0];
  .test.assert["Check fails"; not result 0];
  .test.assertEqual["Reason is assetConcentrationExceeded"; `assetConcentrationExceeded; result 1];
 };

/ Test 7: Update concentration
test_concentrationLimits_update:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Add exposure
  .risk.updateConcentration[`binance;`BTCUSD;1.0;100000.0];

  / Verify exchange concentration updated
  exchPct:first exec currentPct from .risk.exchangeConcentration where exchange=`binance;
  .test.assert["Exchange pct updated"; exchPct > 0.0];
  .test.assertEqual["Exchange pct is 10%"; 10.0; exchPct];

  / Verify asset concentration updated
  assetPct:first exec currentPct from .risk.assetConcentration where sym=`BTCUSD;
  .test.assert["Asset pct updated"; assetPct > 0.0];
  .test.assertEqual["Asset pct is 10%"; 10.0; assetPct];
 };

/ Test 8: Zero portfolio value handling
test_concentrationLimits_zeroPortfolio:{[]
  .risk.initConcentrationLimits[];

  / Portfolio value is zero (startup case)
  .test.assertEqual["Portfolio value zero"; 0.0; first .risk.portfolioValue`totalValue];

  / Check should pass (no concentration enforcement at startup)
  result:.risk.checkExchangeConcentration[`binance;1.0;10000.0];
  .test.assert["Check passes with zero portfolio"; result 0];
 };

/ Test 9: Recalculate concentration
test_concentrationLimits_recalc:{[]
  .risk.initConcentrationLimits[];

  / Set initial portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Add exposure
  .risk.updateConcentration[`binance;`BTCUSD;1.0;100000.0];

  / Change portfolio value
  .risk.updatePortfolioValue[2000000.0];

  / Verify percentages recalculated
  exchPct:first exec currentPct from .risk.exchangeConcentration where exchange=`binance;
  .test.assertEqual["Pct recalculated"; 5.0; exchPct]; / 100K/2M = 5%
 };

/ Test 10: Default alt limit
test_concentrationLimits_defaultAlt:{[]
  .risk.initConcentrationLimits[];

  / Set portfolio value
  .risk.updatePortfolioValue[1000000.0];

  / Check altcoin not in explicit limits (should use 10% default)
  result:.risk.checkAssetConcentration[`SOLUSD;1.0;150000.0];
  .test.assert["Alt check fails at 15% (above 10% default)"; not result 0];
 };

if[not `medusaRunAll in key `.; exit .test.run[`.]];
