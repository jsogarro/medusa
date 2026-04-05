/ ============================================================================
/ test_gds_trade.q - Trade Auditor Tests
/ ============================================================================

/ Load GDS modules
\l src/q/tick/sym.q
\l src/q/gds/alert_manager.q
\l src/q/gds/trade_auditor.q

/ Test framework
testCount:0;
passCount:0;
failCount:0;

assert:{[condition;testName]
  testCount+:1;
  if[condition;
    passCount+:1;
    -1 "  PASS ",testName;
    :1b
  ];
  failCount+:1;
  -1 "  FAIL ",testName;
  0b
 };

/ Cleanup function to reset state between test phases
cleanup:{[]
  / Clear all tables
  delete from `trade;
  delete from `.gds.auditLog;
  / Reset config to defaults
  .gds.alert.init[];
  .gds.trade.init[];
 };

-1 "\n=== GDS Trade Auditor Tests ===\n";

/ ============================================================================
/ INITIALIZATION TESTS
/ ============================================================================

-1 "Phase 1: Initialization";

.gds.alert.init[];
.gds.trade.init[];

assert[0 < count .gds.trade.config; "Config table populated after init"];
assert[.gds.trade.defaultMaxPriceChangePercent = 10.0; "Default max price change is 10%"];
assert[.gds.trade.defaultMaxGapSec = 60; "Default max gap is 60 seconds"];

/ ============================================================================
/ DUPLICATE DETECTION
/ ============================================================================

-1 "\nPhase 2: Duplicate Detection";
cleanup[];

/ Test case: No duplicates
delete from `trade;
`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((.z.P; `kraken; `BTCUSD; `trade2; 50010.0; 0.2; `sell; 10002.0));

duplicates:.gds.trade.checkDuplicates[`kraken;`BTCUSD];
assert[0 = count duplicates; "No duplicates in clean data"];

/ Test case: Duplicate trade IDs
delete from `trade;
`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50010.0; 0.2; `buy; 10002.0));  / Same ID
`trade insert ((.z.P; `kraken; `BTCUSD; `trade2; 50020.0; 0.3; `sell; 15006.0));

duplicates:.gds.trade.checkDuplicates[`kraken;`BTCUSD];
assert[2 = count duplicates; "2 rows with duplicate trade1 detected"];
assert[all `trade1 = exec tradeId from duplicates; "Duplicate trade ID is trade1"];

/ ============================================================================
/ PRICE OUTLIER DETECTION
/ ============================================================================

-1 "\nPhase 3: Price Outlier Detection";
cleanup[];

/ Test case: Normal price changes (no outliers)
delete from `trade;
t1:.z.P - 0D00:00:03;
t2:.z.P - 0D00:00:02;
t3:.z.P - 0D00:00:01;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 50050.0; 0.1; `buy; 5005.0));  / 0.1% change
`trade insert ((t3; `kraken; `BTCUSD; `trade3; 50100.0; 0.1; `buy; 5010.0));  / 0.1% change

outliers:.gds.trade.checkPriceOutliers[`kraken;`BTCUSD;10.0];
assert[0 = count outliers; "No outliers with small price changes"];

/ Test case: Large price change (outlier)
delete from `trade;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 60000.0; 0.1; `buy; 6000.0));  / 20% change

outliers:.gds.trade.checkPriceOutliers[`kraken;`BTCUSD;10.0];
assert[1 = count outliers; "1 outlier detected with 20% price change"];
assert[first[exec changePercent from outliers] > 10.0; "Change percent exceeds threshold"];

/ Test case: Single trade (no outliers possible)
delete from `trade;
`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));

outliers:.gds.trade.checkPriceOutliers[`kraken;`BTCUSD;10.0];
assert[0 = count outliers; "No outliers with single trade"];

/ ============================================================================
/ TIME GAP DETECTION
/ ============================================================================

-1 "\nPhase 4: Time Gap Detection";
cleanup[];

/ Test case: No gaps (frequent trades)
delete from `trade;
t1:.z.P - 0D00:00:10;
t2:.z.P - 0D00:00:05;
t3:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 50010.0; 0.1; `buy; 5001.0));  / 5s gap
`trade insert ((t3; `kraken; `BTCUSD; `trade3; 50020.0; 0.1; `buy; 5002.0));  / 5s gap

gaps:.gds.trade.checkTimeGaps[`kraken;`BTCUSD;60];
assert[0 = count gaps; "No gaps with 5-second intervals and 60s threshold"];

/ Test case: Large time gap
delete from `trade;
t1:.z.P - 0D00:02:00;  / 2 minutes ago
t2:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 50010.0; 0.1; `buy; 5001.0));  / 120s gap

gaps:.gds.trade.checkTimeGaps[`kraken;`BTCUSD;60];
assert[1 = count gaps; "1 gap detected with 120-second interval"];
assert[first[exec gapSec from gaps] > 60; "Gap exceeds 60-second threshold"];

/ ============================================================================
/ MAIN CHECK FUNCTION TESTS
/ ============================================================================

-1 "\nPhase 5: Main Check Function";
cleanup[];

/ Test case: Clean data (PASS)
delete from `trade;
delete from `.gds.auditLog;

t1:.z.P - 0D00:00:02;
t2:.z.P - 0D00:00:01;
t3:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 50050.0; 0.1; `buy; 5005.0));
`trade insert ((t3; `kraken; `BTCUSD; `trade3; 50100.0; 0.1; `buy; 5010.0));

result:.gds.trade.check[];
assert[result=`PASS; "Clean data returns PASS"];

/ Test case: Duplicates (FAIL with alert)
delete from `trade;
delete from `.gds.auditLog;

`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((.z.P; `kraken; `BTCUSD; `trade1; 50010.0; 0.2; `buy; 10002.0));  / Duplicate

result:.gds.trade.check[];
assert[result=`FAIL; "Duplicates return FAIL"];
assert[0 < count .gds.auditLog; "Alert raised for duplicates"];

/ Test case: Price outliers (FAIL with alert)
delete from `trade;
delete from `.gds.auditLog;

t1:.z.P - 0D00:00:01;
t2:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 60000.0; 0.1; `buy; 6000.0));  / 20% jump

result:.gds.trade.check[];
assert[result=`FAIL; "Price outliers return FAIL"];
assert[0 < count .gds.auditLog; "Alert raised for outliers"];

/ Test case: Time gaps (FAIL with alert)
delete from `trade;
delete from `.gds.auditLog;

t1:.z.P - 0D00:02:00;
t2:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 50010.0; 0.1; `buy; 5001.0));

result:.gds.trade.check[];
assert[result=`FAIL; "Time gaps return FAIL"];
assert[0 < count .gds.auditLog; "Alert raised for gaps"];

/ ============================================================================
/ CONFIGURATION TESTS
/ ============================================================================

-1 "\nPhase 6: Configuration";
cleanup[];

/ Set custom thresholds
.gds.trade.setThresholds[`kraken;`BTCUSD;20.0;120];

cfg:select from .gds.trade.config where exchange=`kraken, sym=`BTCUSD;
assert[1 = count cfg; "Config entry exists"];
assert[20.0 = first exec maxPriceChangePercent from cfg; "Custom max price change set to 20%"];
assert[120 = first exec maxGapSec from cfg; "Custom max gap set to 120s"];

/ Verify custom threshold is used (20% change should now pass)
delete from `trade;
delete from `.gds.auditLog;

t1:.z.P - 0D00:00:01;
t2:.z.P;
`trade insert ((t1; `kraken; `BTCUSD; `trade1; 50000.0; 0.1; `buy; 5000.0));
`trade insert ((t2; `kraken; `BTCUSD; `trade2; 58000.0; 0.1; `buy; 5800.0));  / 16% change

result:.gds.trade.check[];
assert[result=`PASS; "16% change passes with 20% threshold"];

/ ============================================================================
/ CLEANUP & SUMMARY
/ ============================================================================

-1 "\n========================================";
-1 "  Trade Auditor Test Results";
-1 "  Total:  ",string testCount;
-1 "  Passed: ",string passCount;
-1 "  Failed: ",string failCount;
-1 "========================================\n";

if[failCount>0; -1 "!!! SOME TESTS FAILED !!!"; exit 1];
-1 "All tests passed!";
exit 0;
