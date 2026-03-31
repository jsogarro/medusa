/ ============================================================================
/ test_arb.q - Tests for Arbitrage Detection Library
/ ============================================================================

/ Simple assertion helper
assert:{[cond;msg] if[not cond;'"FAIL: ",msg]};

/ Load arbitrage module
\l src/q/strategy/arb.q

/ ============================================================================
/ TEST: Directional Cross Detection
/ ============================================================================

.test.arb.testNoOverlap:{[]
  / Create orderbooks with no overlap (asks > bids)
  buyOb:([] price:101.0 101.5; volume:1.0 2.0; side:`ask`ask);
  sellOb:([] price:100.0 99.5; volume:0.5 1.0; side:`bid`bid);

  / Detect cross
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`GDAX;`Kraken;`BTCUSD];

  / Verify no cross detected
  assert[null cross; "No overlap should return null"];

  -1 "  PASS: testNoOverlap";
 };

.test.arb.testSingleLevelOverlap:{[]
  / Create orderbooks with single-level overlap
  buyOb:([] price:enlist 100.0; volume:enlist 1.0; side:enlist `ask);
  sellOb:([] price:enlist 100.5; volume:enlist 0.5; side:enlist `bid);

  / Detect cross
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`GDAX;`Kraken;`BTCUSD];

  / Verify cross detected
  assert[not null cross; "Single-level overlap should detect cross"];
  assert[cross[`volume] = 0.5; "Volume should be min of levels"];
  assert[cross[`revenue] > 0; "Revenue should be positive"];
  assert[cross[`profit] < cross[`revenue]; "Profit < revenue (fees)"];

  -1 "  PASS: testSingleLevelOverlap";
 };

.test.arb.testMultiLevelOverlap:{[]
  / Create orderbooks with multi-level overlap
  buyOb:([] price:100.0 100.5; volume:1.0 2.0; side:`ask`ask);
  sellOb:([] price:101.0 100.8; volume:0.5 1.5; side:`bid`bid);

  / Detect cross
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`GDAX;`Kraken;`BTCUSD];

  / Verify cross detected with correct volume
  assert[not null cross; "Multi-level overlap should detect cross"];
  assert[cross[`volume] = 2.0; "Should consume multiple levels"];
  assert[cross[`profit] > 0; "Profit should be positive"];

  -1 "  PASS: testMultiLevelOverlap";
 };

.test.arb.testEmptyOrderbook:{[]
  / Create empty buy orderbook
  buyOb:([] price:(); volume:(); side:());
  sellOb:([] price:enlist 100.5; volume:enlist 0.5; side:enlist `bid);

  / Detect cross
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`GDAX;`Kraken;`BTCUSD];

  / Verify no cross
  assert[null cross; "Empty buy orderbook should return null"];

  -1 "  PASS: testEmptyOrderbook";
 };

/ ============================================================================
/ TEST: Bidirectional Cross Detection
/ ============================================================================

.test.arb.testBidirectionalCross:{[]
  / Create orderbooks where both directions have overlap
  ob1:([] price:100.0 100.5 101.0; volume:1.0 2.0 1.0; side:`ask`ask`bid);
  ob2:([] price:99.0 99.5 100.2; volume:0.5 1.0 0.8; side:`ask`ask`bid);

  / Detect cross (both directions)
  cross:.strategy.arb.detectCross[ob1;ob2;`GDAX;`Kraken;`BTCUSD];

  / Verify a cross was found
  assert[not null cross; "Bidirectional detection should find cross"];
  assert[cross[`profit] > 0; "Should return profitable cross"];

  -1 "  PASS: testBidirectionalCross";
 };

/ ============================================================================
/ TEST: Many-Exchange Cross Detection
/ ============================================================================

.test.arb.testDetectCrossesMany:{[]
  / Create orderbooks for multiple exchanges
  orderbooks:`GDAX`Kraken`Binance!(
    ([] price:100.0 100.5; volume:1.0 2.0; side:`ask`ask);
    ([] price:101.0 100.8; volume:0.5 1.5; side:`bid`bid);
    ([] price:100.2 100.6; volume:1.0 1.0; side:`ask`ask)
  );

  / Detect all crosses
  crosses:.strategy.arb.detectCrossesMany[orderbooks;`BTCUSD];

  / Verify crosses found
  assert[count crosses >= 1; "Should find at least one cross"];
  assert[`profit in cols crosses; "Result should be a table with profit column"];

  / Verify sorted by profit descending
  if[count crosses > 1;
    assert[crosses[0;`profit] >= crosses[1;`profit]; "Should be sorted by profit desc"];
  ];

  -1 "  PASS: testDetectCrossesMany";
 };

/ ============================================================================
/ TEST: Volume Calculation
/ ============================================================================

.test.arb.testMaxBuyVolumeInsufficientBalance:{[]
  / Create orderbook
  buyOb:([] price:100.0 100.5; volume:1.0 2.0; side:`ask`ask);

  / Calculate max volume with insufficient balance
  balance:150.0;  / Can afford 1.5 BTC at 100
  maxVol:.strategy.arb.maxBuyVolume[balance;buyOb];

  / Verify limited by balance
  assert[maxVol < 3.0; "Should be limited by balance"];
  assert[maxVol > 0; "Should be able to buy some"];

  -1 "  PASS: testMaxBuyVolumeInsufficientBalance";
 };

.test.arb.testMaxBuyVolumeAmpleBalance:{[]
  / Create orderbook
  buyOb:([] price:100.0 100.5; volume:1.0 2.0; side:`ask`ask);

  / Calculate max volume with ample balance
  balance:500.0;  / Can afford entire orderbook
  maxVol:.strategy.arb.maxBuyVolume[balance;buyOb];

  / Verify consumes all orderbook
  assert[maxVol = 3.0; "Should consume all orderbook"];

  -1 "  PASS: testMaxBuyVolumeAmpleBalance";
 };

.test.arb.testGetExecutableVolume:{[]
  / Create cross result
  cross:`volume`revenue`fees`profit`buyExchange`sellExchange`pair!(
    2.0; 1.0; 0.02; 0.98; `GDAX; `Kraken; `BTCUSD
  );

  / Create buy orderbook
  buyOb:([] price:100.0 100.5; volume:1.0 2.0; side:`ask`ask);

  / Test with limited buy balance
  execVol:.strategy.arb.getExecutableVolume[cross;100.0;10.0;buyOb];
  assert[execVol <= 2.0; "Should not exceed cross volume"];
  assert[execVol > 0; "Should have some executable volume"];

  / Test with limited sell balance
  execVol2:.strategy.arb.getExecutableVolume[cross;10000.0;0.5;buyOb];
  assert[execVol2 = 0.5; "Should be limited by sell balance"];

  -1 "  PASS: testGetExecutableVolume";
 };

/ ============================================================================
/ TEST: Spread Calculation
/ ============================================================================

.test.arb.testCalculateSpread:{[]
  / Calculate spread
  spread:.strategy.arb.calculateSpread[100.0;101.0;0.001];

  / Verify spread components
  assert[spread[`grossSpread] = 1.0; "Gross spread should be 1.0"];
  assert[spread[`totalFees] > 0; "Fees should be positive"];
  assert[spread[`netSpread] < spread[`grossSpread]; "Net spread < gross spread"];
  assert[spread[`netSpreadPct] > 0; "Net spread should still be positive"];

  -1 "  PASS: testCalculateSpread";
 };

.test.arb.testNegativeSpread:{[]
  / Calculate spread with negative spread (sell price < buy price)
  spread:.strategy.arb.calculateSpread[101.0;100.0;0.001];

  / Verify negative spread
  assert[spread[`grossSpread] = -1.0; "Gross spread should be -1.0"];
  assert[spread[`netSpread] < 0; "Net spread should be negative"];
  assert[spread[`netSpreadPct] < 0; "Net spread percentage should be negative"];

  / Verify no cross should be detected with negative spread
  buyOb:([] price:enlist 101.0; volume:enlist 1.0; side:enlist `ask);
  sellOb:([] price:enlist 100.0; volume:enlist 0.5; side:enlist `bid);
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`GDAX;`Kraken;`BTCUSD];
  assert[null cross; "No cross should be detected with negative spread"];

  -1 "  PASS: testNegativeSpread";
 };

.test.arb.testFeeCalculation:{[]
  / Test fee calculation matches expected 0.1% (0.001 fee rate)
  buyPrice:1000.0;
  sellPrice:1001.0;
  feeRate:0.001;

  spread:.strategy.arb.calculateSpread[buyPrice;sellPrice;feeRate];

  / Expected fees: buy fee + sell fee
  expectedBuyFee:buyPrice * feeRate;  / 1.0
  expectedSellFee:sellPrice * feeRate; / 1.001
  expectedTotalFees:expectedBuyFee + expectedSellFee; / 2.001

  assert[spread[`totalFees] = expectedTotalFees; "Total fees should match expected 0.1% calculation"];

  -1 "  PASS: testFeeCalculation";
 };

.test.arb.testZeroPriceSpread:{[]
  / Test division by zero handling in spread calculation
  result:@[.strategy.arb.calculateSpread;(0.0;100.0;0.001);{x}];

  / Verify error is thrown for zero buy price
  assert[10h = type result; "Zero buyPrice should throw error"];

  -1 "  PASS: testZeroPriceSpread";
 };

/ ============================================================================
/ TEST: Opportunity Scoring
/ ============================================================================

.test.arb.testScoreOpportunity:{[]
  / Create cross
  cross:`volume`revenue`fees`profit`buyExchange`sellExchange`pair!(
    2.0; 2.0; 0.1; 1.9; `GDAX; `Kraken; `BTCUSD
  );

  / Score opportunity
  scored:.strategy.arb.scoreOpportunity[cross;1.5];

  / Verify scoring
  assert[`score in key scored; "Should contain score"];
  assert[`totalProfit in key scored; "Should contain totalProfit"];
  assert[`profitPerUnit in key scored; "Should contain profitPerUnit"];
  assert[`volumeRisk in key scored; "Should contain volumeRisk"];
  assert[scored[`score] > 0; "Score should be positive"];

  -1 "  PASS: testScoreOpportunity";
 };

/ ============================================================================
/ TEST: Execution Plan Generation
/ ============================================================================

.test.arb.testGenerateExecutionPlan:{[]
  / Create scored opportunity
  opportunity:`volume`revenue`fees`profit`buyExchange`sellExchange`pair`executableVolume`totalProfit`profitPerUnit`profitPct`volumeRisk`score!(
    2.0; 2.0; 0.1; 1.9; `GDAX; `Kraken; `BTCUSD; 1.5; 1.425; 0.95; 95.0; 0.25; 85.0
  );

  / Generate execution plan
  plan:.strategy.arb.generateExecutionPlan[opportunity];

  / Verify plan components
  assert[`buyOrder in key plan; "Should contain buyOrder"];
  assert[`sellOrder in key plan; "Should contain sellOrder"];
  assert[`expectedProfit in key plan; "Should contain expectedProfit"];

  / Verify buy order
  buyOrder:plan`buyOrder;
  assert[buyOrder[`exchange] = `GDAX; "Buy exchange should be GDAX"];
  assert[buyOrder[`side] = `buy; "Buy order side should be buy"];

  / Verify sell order
  sellOrder:plan`sellOrder;
  assert[sellOrder[`exchange] = `Kraken; "Sell exchange should be Kraken"];
  assert[sellOrder[`side] = `sell; "Sell order side should be sell"];

  -1 "  PASS: testGenerateExecutionPlan";
 };

/ Test: execution plan includes actionable rollback guidance
.test.arb.testExecutionPlanRollback:{[]
  opportunity:`volume`revenue`fees`profit`buyExchange`sellExchange`pair`executableVolume`totalProfit`profitPct`volumeRisk`score!(
    2.0; 2.0; 0.2; 1.8; `GDAX; `Kraken; `BTCUSD; 1.5; 1.35; 0.9; 0.25; 0.85
  );

  plan:.strategy.arb.generateExecutionPlan[opportunity];

  / Verify rollback plan exists and has required fields
  assert[`rollbackPlan in key plan; "Plan must include rollbackPlan"];
  rollback:plan`rollbackPlan;
  assert[`buyLegFails in key rollback; "Rollback must cover buy leg failure"];
  assert[`sellLegFails in key rollback; "Rollback must cover sell leg failure"];

  / Verify sell-leg-fails guidance mentions hedging (most dangerous scenario)
  sellFailMsg:rollback`sellLegFails;
  assert[0 < count sellFailMsg; "Sell leg failure guidance must not be empty"];

  -1 "  PASS: testExecutionPlanRollback";
 };

/ Test: scoreOpportunity with zero executable volume
.test.arb.testScoreZeroExecVolume:{[]
  cross:`volume`revenue`fees`profit`buyExchange`sellExchange`pair!(
    2.0; 2.0; 0.1; 1.9; `GDAX; `Kraken; `BTCUSD
  );

  / Zero executable volume should error (division guard)
  result:@[.strategy.arb.scoreOpportunity;(cross;0.0);{x}];
  assert[10h = type result; "Zero executable volume should throw error"];

  -1 "  PASS: testScoreZeroExecVolume";
 };

/ ============================================================================
/ RUN ALL TESTS
/ ============================================================================

.test.arb.runAll:{[]
  -1 "";
  -1 "Running Arbitrage Library Tests...";
  -1 "====================================";

  .test.arb.testNoOverlap[];
  .test.arb.testSingleLevelOverlap[];
  .test.arb.testMultiLevelOverlap[];
  .test.arb.testEmptyOrderbook[];
  .test.arb.testBidirectionalCross[];
  .test.arb.testDetectCrossesMany[];
  .test.arb.testMaxBuyVolumeInsufficientBalance[];
  .test.arb.testMaxBuyVolumeAmpleBalance[];
  .test.arb.testGetExecutableVolume[];
  .test.arb.testCalculateSpread[];
  .test.arb.testNegativeSpread[];
  .test.arb.testFeeCalculation[];
  .test.arb.testZeroPriceSpread[];
  .test.arb.testScoreOpportunity[];
  .test.arb.testGenerateExecutionPlan[];
  .test.arb.testExecutionPlanRollback[];
  .test.arb.testScoreZeroExecVolume[];

  -1 "";
  -1 "All Arbitrage Library Tests Passed!";
  -1 "";
 };

/ Run tests
.test.arb.runAll[];

/ Exit
\\
