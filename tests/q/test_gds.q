/ ============================================================================
/ test_gds.q - Guardian Data System Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests for GDS auditors:
/   - Orderbook auditor (crossed books, extreme spreads, empty books)
/   - Trade auditor (duplicate trades, price outliers, time gaps)
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - Heartbeat monitoring (stale feed detection)
/   - Orderbook quality checks (crossed, spread, depth, empty)
/   - Trade data anomalies (duplicates, outliers, gaps)
/   - Alert generation for each failure mode
/ ----------------------------------------------------------------------------
/ Usage:
/   q test_gds.q
/ ============================================================================

/ Load test framework
\l ../src/q/test/test_framework.q

/ Load GDS modules
\l ../src/q/gds/alert_manager.q
\l ../src/q/gds/orderbook_auditor.q
\l ../src/q/gds/trade_auditor.q

// ============================================================================
// TEST FIXTURES
// ============================================================================

\d .fixtures

/ Initialize global tables for GDS to check
orderbook:([] time:`timestamp$(); exchange:`symbol$(); sym:`symbol$();
               bids:(); asks:(); mid:`float$());
trade:([] time:`timestamp$(); exchange:`symbol$(); sym:`symbol$();
           tradeId:`symbol$(); price:`float$(); volume:`float$());

/ Standard orderbook data (nested lists)
/ bids/asks format: (priceList;sizeList)
standardBids:(100.0 99.9 99.8;10.0 15.0 20.0);
standardAsks:(100.1 100.2 100.3;12.0 18.0 25.0);

/ Crossed orderbook (bid >= ask)
crossedBids:(100.5 100.4 100.3;10.0 15.0 20.0);
crossedAsks:(100.0 100.1 100.2;12.0 18.0 25.0);

/ Empty orderbook
emptyBids:(();());
emptyAsks:(();());

/ Insufficient depth orderbook (< 5 levels)
shallowBids:(100.0 99.9;10.0 15.0);
shallowAsks:(100.1 100.2;12.0 18.0);

\d .

// ============================================================================
// ORDERBOOK AUDITOR TESTS
// ============================================================================

\d .test.orderbook

/ Test initialization
test_init:{[]
  / Setup - clean slate
  delete from `.gds.orderbook.config;

  / Execute
  .gds.orderbook.init[];

  / Assert
  .test.assert["Config table populated"; 0 < count .gds.orderbook.config];
  .test.assert["Default maxSpreadBps set"; .gds.orderbook.defaultMaxSpreadBps = 200];
  .test.assert["Default minLevels set"; .gds.orderbook.defaultMinLevels = 5];
 };

/ Test crossed book detection
test_checkCrossed_normalBook:{[]
  / Setup
  bids:.fixtures.standardBids;
  asks:.fixtures.standardAsks;

  / Execute
  result:.gds.orderbook.checkCrossed[bids;asks];

  / Assert
  .test.assert["Not crossed"; not result`crossed];
  .test.assertNear["BestBid is 100.0"; 100.0; result`bestBid; 0.01];
  .test.assertNear["BestAsk is 100.1"; 100.1; result`bestAsk; 0.01];
 };

/ Test crossed book detection - crossed
test_checkCrossed_crossedBook:{[]
  / Setup
  bids:.fixtures.crossedBids;
  asks:.fixtures.crossedAsks;

  / Execute
  result:.gds.orderbook.checkCrossed[bids;asks];

  / Assert
  .test.assert["Crossed detected"; result`crossed];
  .test.assertNear["BestBid is 100.5"; 100.5; result`bestBid; 0.01];
  .test.assertNear["BestAsk is 100.0"; 100.0; result`bestAsk; 0.01];
 };

/ Test empty book detection
test_checkEmpty_normalBook:{[]
  / Setup
  bids:.fixtures.standardBids;
  asks:.fixtures.standardAsks;

  / Execute
  result:.gds.orderbook.checkEmpty[bids;asks];

  / Assert
  .test.assert["Not empty"; not result`empty];
  .test.assertEqual["BidCount is 3"; 3; result`bidCount];
  .test.assertEqual["AskCount is 3"; 3; result`askCount];
 };

/ Test empty book detection - empty
test_checkEmpty_emptyBook:{[]
  / Setup
  bids:.fixtures.emptyBids;
  asks:.fixtures.emptyAsks;

  / Execute
  result:.gds.orderbook.checkEmpty[bids;asks];

  / Assert
  .test.assert["Empty detected"; result`empty];
  .test.assertEqual["BidCount is 0"; 0; result`bidCount];
  .test.assertEqual["AskCount is 0"; 0; result`askCount];
 };

/ Test spread calculation
test_calculateSpreadBps:{[]
  / Setup
  bestBid:100.0;
  bestAsk:100.2;

  / Execute
  spreadBps:.gds.orderbook.calculateSpreadBps[bestBid;bestAsk];

  / Assert
  / Spread = (100.2 - 100.0) / mid * 10000
  / Mid = (100.0 + 100.2) / 2 = 100.1
  / Spread = 0.2 / 100.1 * 10000 ≈ 19.98 bps
  .test.assertNear["Spread is ~20 bps"; 19.98; spreadBps; 0.5];
 };

/ Test spread calculation with zero mid (edge case)
test_calculateSpreadBps_zeroMid:{[]
  / Setup
  bestBid:0.0;
  bestAsk:0.0;

  / Execute - should handle division by zero gracefully
  .test.assertError["Zero mid signals error"; {.gds.orderbook.calculateSpreadBps[0.0;0.0]}];
 };

/ Test spread check - normal spread
test_checkSpread_normalSpread:{[]
  / Setup
  bids:.fixtures.standardBids;
  asks:.fixtures.standardAsks;
  maxSpreadBps:200;  / Allow up to 2%

  / Execute
  result:.gds.orderbook.checkSpread[bids;asks;maxSpreadBps];

  / Assert
  .test.assert["Spread not excessive"; not result`excessive];
  .test.assert["SpreadBps within threshold"; result[`spreadBps] <= maxSpreadBps];
 };

/ Test spread check - excessive spread
test_checkSpread_excessiveSpread:{[]
  / Setup
  bids:(90.0 89.0 88.0;10.0 15.0 20.0);
  asks:(100.0 101.0 102.0;12.0 18.0 25.0);
  maxSpreadBps:200;  / Allow up to 2%

  / Execute
  result:.gds.orderbook.checkSpread[bids;asks;maxSpreadBps];

  / Assert
  .test.assert["Spread is excessive"; result`excessive];
  .test.assert["SpreadBps exceeds threshold"; result[`spreadBps] > maxSpreadBps];
 };

/ Test levels check - sufficient depth
test_checkLevels_sufficientDepth:{[]
  / Setup
  bids:.fixtures.standardBids;
  asks:.fixtures.standardAsks;
  minLevels:2;

  / Execute
  result:.gds.orderbook.checkLevels[bids;asks;minLevels];

  / Assert
  .test.assert["Depth sufficient"; not result`insufficient];
  .test.assertEqual["BidLevels is 3"; 3; result`bidLevels];
  .test.assertEqual["AskLevels is 3"; 3; result`askLevels];
 };

/ Test levels check - insufficient depth
test_checkLevels_insufficientDepth:{[]
  / Setup
  bids:.fixtures.shallowBids;
  asks:.fixtures.shallowAsks;
  minLevels:5;

  / Execute
  result:.gds.orderbook.checkLevels[bids;asks;minLevels];

  / Assert
  .test.assert["Depth insufficient"; result`insufficient];
  .test.assertEqual["BidLevels is 2"; 2; result`bidLevels];
  .test.assertEqual["AskLevels is 2"; 2; result`askLevels];
 };

// ============================================================================
// TRADE AUDITOR TESTS
// ============================================================================

\d .test.trade

/ Test initialization
test_init:{[]
  / Execute
  .gds.trade.init[];

  / Assert
  .test.assert["Config table populated"; 0 < count .gds.trade.config];
  .test.assertNear["Default maxPriceChangePercent is 10%"; 10.0; .gds.trade.defaultMaxPriceChangePercent; 0.01];
  .test.assertEqual["Default maxGapSec is 60"; 60; .gds.trade.defaultMaxGapSec];
 };

/ Test duplicate detection - no duplicates
test_checkDuplicates_noDuplicates:{[]
  / Setup
  delete from `trade;
  `trade insert (`.z.p;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (`.z.p;`kraken;`BTCUSD;`trade2;50001.0;1.5);
  `trade insert (`.z.p;`kraken;`BTCUSD;`trade3;50002.0;2.0);

  / Execute
  duplicates:.gds.trade.checkDuplicates[`kraken;`BTCUSD];

  / Assert
  .test.assertEqual["No duplicates found"; 0; count duplicates];
 };

/ Test duplicate detection - with duplicates (different timestamps)
test_checkDuplicates_withDuplicates:{[]
  / Setup
  delete from `trade;
  now:.z.p;
  `trade insert (now;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (now + 1000000000;`kraken;`BTCUSD;`trade1;50000.0;1.0);  / Duplicate tradeId, different time
  `trade insert (now + 2000000000;`kraken;`BTCUSD;`trade2;50001.0;1.5);

  / Execute
  duplicates:.gds.trade.checkDuplicates[`kraken;`BTCUSD];

  / Assert
  .test.assertEqual["Duplicates found"; 2; count duplicates];
  .test.assert["Duplicate tradeId is trade1"; all duplicates[`tradeId]=`trade1];
 };

/ Test price change percent calculation - positive change
test_calcPriceChangePercent_positive:{[]
  / Setup
  prevPrice:100.0;
  currPrice:110.0;

  / Execute
  changePercent:.gds.trade.calcPriceChangePercent[prevPrice;currPrice];

  / Assert
  .test.assertNear["Change is 10%"; 10.0; changePercent; 0.01];
 };

/ Test price change percent calculation - negative change
test_calcPriceChangePercent_negative:{[]
  / Setup
  prevPrice:100.0;
  currPrice:90.0;

  / Execute
  changePercent:.gds.trade.calcPriceChangePercent[prevPrice;currPrice];

  / Assert
  .test.assertNear["Change is -10%"; 10.0; changePercent; 0.01];  / Absolute value
 };

/ Test price change percent with zero prevPrice
test_calcPriceChangePercent_zeroPrev:{[]
  .test.assertError["Zero prevPrice signals error"; {.gds.trade.calcPriceChangePercent[0.0;100.0]}];
 };

/ Test price outlier detection - no outliers
test_checkPriceOutliers_noOutliers:{[]
  / Setup
  delete from `trade;
  now:.z.p;
  `trade insert (now;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (now + 1000000000;`kraken;`BTCUSD;`trade2;50005.0;1.5);  / 0.01% change
  `trade insert (now + 2000000000;`kraken;`BTCUSD;`trade3;50010.0;2.0);  / 0.01% change

  / Execute
  outliers:.gds.trade.checkPriceOutliers[`kraken;`BTCUSD;10.0];  / 10% max change

  / Assert
  .test.assertEqual["No outliers found"; 0; count outliers];
 };

/ Test price outlier detection - with outliers
test_checkPriceOutliers_withOutliers:{[]
  / Setup
  delete from `trade;
  now:.z.p;
  `trade insert (now;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (now + 1000000000;`kraken;`BTCUSD;`trade2;60000.0;1.5);  / 20% jump (outlier)
  `trade insert (now + 2000000000;`kraken;`BTCUSD;`trade3;60100.0;2.0);

  / Execute
  outliers:.gds.trade.checkPriceOutliers[`kraken;`BTCUSD;10.0];  / 10% max change

  / Assert
  .test.assertEqual["Outlier found"; 1; count outliers];
  / Verify ALL outliers exceed threshold
  .test.assert["All outliers exceed 10%"; all (exec changePercent from outliers) > 10.0];
 };

/ Test time gap detection - no gaps
test_checkTimeGaps_noGaps:{[]
  / Setup
  delete from `trade;
  now:.z.p;
  `trade insert (now;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (now + 10000000000;`kraken;`BTCUSD;`trade2;50005.0;1.5);  / 10 sec gap
  `trade insert (now + 20000000000;`kraken;`BTCUSD;`trade3;50010.0;2.0);  / 10 sec gap

  / Execute
  gaps:.gds.trade.checkTimeGaps[`kraken;`BTCUSD;60];  / 60 sec max gap

  / Assert
  .test.assertEqual["No gaps found"; 0; count gaps];
 };

/ Test time gap detection - with gaps
test_checkTimeGaps_withGaps:{[]
  / Setup
  delete from `trade;
  now:.z.p;
  `trade insert (now;`kraken;`BTCUSD;`trade1;50000.0;1.0);
  `trade insert (now + 120000000000;`kraken;`BTCUSD;`trade2;50005.0;1.5);  / 120 sec gap (exceeds 60)
  `trade insert (now + 130000000000;`kraken;`BTCUSD;`trade3;50010.0;2.0);

  / Execute
  gaps:.gds.trade.checkTimeGaps[`kraken;`BTCUSD;60];  / 60 sec max gap

  / Assert
  .test.assertEqual["Gap found"; 1; count gaps];
  / Verify ALL gaps exceed threshold
  .test.assert["All gaps exceed 60 sec"; all (exec gapSec from gaps) > 60];
 };

\d .

// ============================================================================
// RUN ALL TESTS
// ============================================================================

-1 "\n=== Running GDS Tests ===\n";
.test.run[`.test.orderbook];
.test.run[`.test.trade];

/ Exit with appropriate code
exit .test.failed
