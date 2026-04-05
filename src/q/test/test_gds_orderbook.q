/ ============================================================================
/ test_gds_orderbook.q - Orderbook Auditor Tests
/ ============================================================================

/ Load GDS modules
\l src/q/tick/sym.q
\l src/q/gds/alert_manager.q
\l src/q/gds/orderbook_auditor.q

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
  delete from `orderbook;
  delete from `.gds.auditLog;
  / Reset config to defaults
  .gds.alert.init[];
  .gds.orderbook.init[];
 };

-1 "\n=== GDS Orderbook Auditor Tests ===\n";

/ ============================================================================
/ INITIALIZATION TESTS
/ ============================================================================

-1 "Phase 1: Initialization";

.gds.alert.init[];
.gds.orderbook.init[];

assert[0 < count .gds.orderbook.config; "Config table populated after init"];
assert[.gds.orderbook.defaultMaxSpreadBps = 200; "Default max spread is 200 bps"];
assert[.gds.orderbook.defaultMinLevels = 5; "Default min levels is 5"];

/ ============================================================================
/ CROSSED BOOK DETECTION
/ ============================================================================

-1 "\nPhase 2: Crossed Book Detection";
cleanup[];

/ Test case: Normal book (bid < ask)
bids:enlist (49900.0;1.5);
asks:enlist (50000.0;2.0);
check:.gds.orderbook.checkCrossed[bids;asks];
assert[not check`crossed; "Normal book is not crossed"];
assert[check[`bestBid] = 49900.0; "Best bid extracted correctly"];
assert[check[`bestAsk] = 50000.0; "Best ask extracted correctly"];

/ Test case: Crossed book (bid >= ask)
bids:enlist (50100.0;1.5);
asks:enlist (50000.0;2.0);
check:.gds.orderbook.checkCrossed[bids;asks];
assert[check`crossed; "Crossed book detected (bid > ask)"];

/ Test case: Equal bid and ask (crossed)
bids:enlist (50000.0;1.5);
asks:enlist (50000.0;2.0);
check:.gds.orderbook.checkCrossed[bids;asks];
assert[check`crossed; "Crossed book detected (bid = ask)"];

/ Test case: Empty bids (not crossed due to zero check)
bids:();
asks:enlist (50000.0;2.0);
check:.gds.orderbook.checkCrossed[bids;asks];
assert[not check`crossed; "Empty bids not considered crossed"];

/ ============================================================================
/ SPREAD CALCULATION & DETECTION
/ ============================================================================

-1 "\nPhase 3: Spread Detection";
cleanup[];

/ Test case: Normal spread (100 bps = 1%)
bids:enlist (49750.0;1.0);
asks:enlist (50250.0;1.0);
check:.gds.orderbook.checkSpread[bids;asks;200];
assert[not check`excessive; "1% spread (100 bps) is within 200 bps threshold"];
assert[check[`spreadBps] < 200; "Spread calculation correct"];

/ Test case: Excessive spread
bids:enlist (49000.0;1.0);
asks:enlist (51000.0;1.0);
check:.gds.orderbook.checkSpread[bids;asks;200];
assert[check`excessive; "4% spread (~400 bps) exceeds 200 bps threshold"];
assert[check[`spreadBps] > 200; "Excessive spread detected"];

/ Test case: Zero bid or ask (no spread calculation)
bids:();
asks:enlist (50000.0;1.0);
check:.gds.orderbook.checkSpread[bids;asks;200];
assert[not check`excessive; "Empty bids: no excessive spread flagged"];

/ ============================================================================
/ LEVEL DEPTH DETECTION
/ ============================================================================

-1 "\nPhase 4: Level Depth Detection";
cleanup[];

/ Test case: Sufficient levels
bids:(49900.0 49850.0 49800.0 49750.0 49700.0;1.0 1.0 1.0 1.0 1.0);
asks:(50000.0 50050.0 50100.0 50150.0 50200.0;1.0 1.0 1.0 1.0 1.0);
check:.gds.orderbook.checkLevels[bids;asks;5];
assert[not check`insufficient; "5 levels on each side is sufficient for 5-level threshold"];
assert[check[`bidLevels] = 5; "Bid levels counted correctly"];
assert[check[`askLevels] = 5; "Ask levels counted correctly"];

/ Test case: Insufficient levels
bids:(49900.0 49850.0;1.0 1.0);
asks:(50000.0 50050.0 50100.0;1.0 1.0 1.0);
check:.gds.orderbook.checkLevels[bids;asks;5];
assert[check`insufficient; "2 bid levels insufficient for 5-level threshold"];

/ Test case: Empty book
bids:();
asks:enlist (50000.0;1.0);
check:.gds.orderbook.checkLevels[bids;asks;5];
assert[check`insufficient; "Empty bids insufficient"];

/ ============================================================================
/ EMPTY BOOK DETECTION
/ ============================================================================

-1 "\nPhase 5: Empty Book Detection";
cleanup[];

/ Test case: Normal book
bids:enlist (49900.0;1.0);
asks:enlist (50000.0;1.0);
check:.gds.orderbook.checkEmpty[bids;asks];
assert[not check`empty; "Normal book not empty"];

/ Test case: Empty bids
bids:();
asks:enlist (50000.0;1.0);
check:.gds.orderbook.checkEmpty[bids;asks];
assert[check`empty; "Empty bids flagged as empty"];

/ Test case: Empty asks
bids:enlist (49900.0;1.0);
asks:();
check:.gds.orderbook.checkEmpty[bids;asks];
assert[check`empty; "Empty asks flagged as empty"];

/ Test case: Both empty
bids:();
asks:();
check:.gds.orderbook.checkEmpty[bids;asks];
assert[check`empty; "Both sides empty flagged as empty"];

/ ============================================================================
/ MAIN CHECK FUNCTION TESTS
/ ============================================================================

-1 "\nPhase 6: Main Check Function";
cleanup[];

/ Test case: Healthy book (PASS)
delete from `orderbook;
delete from `.gds.auditLog;

bids:enlist (49900.0 49850.0 49800.0 49750.0 49700.0;1.0 1.0 1.0 1.0 1.0);
asks:enlist (50000.0 50050.0 50100.0 50150.0 50200.0;1.0 1.0 1.0 1.0 1.0);
`orderbook insert ((.z.P; `kraken; `BTCUSD; bids; asks; 123; 49950.0));

result:.gds.orderbook.check[];
assert[result=`PASS; "Healthy book returns PASS"];

/ Test case: Crossed book (FAIL with alert)
delete from `orderbook;
delete from `.gds.auditLog;

bids:enlist (50100.0;1.0);
asks:enlist (50000.0;1.0);
`orderbook insert ((.z.P; `kraken; `BTCUSD; bids; asks; 123; 50050.0));

result:.gds.orderbook.check[];
assert[result=`FAIL; "Crossed book returns FAIL"];
assert[0 < count .gds.auditLog; "Alert raised for crossed book"];

/ Verify alert
alert:first .gds.auditLog;
assert[alert[`auditor]=`orderbook; "Alert from orderbook auditor"];
assert[alert[`severity]=`CRITICAL; "Crossed book is CRITICAL severity"];

/ Test case: Excessive spread (FAIL with WARN alert)
delete from `orderbook;
delete from `.gds.auditLog;

bids:enlist (48000.0;1.0);
asks:enlist (52000.0;1.0);
`orderbook insert ((.z.P; `kraken; `BTCUSD; bids; asks; 123; 50000.0));

result:.gds.orderbook.check[];
assert[result=`FAIL; "Excessive spread returns FAIL"];
alert:first .gds.auditLog;
assert[alert[`severity]=`WARN; "Excessive spread is WARN severity"];

/ Test case: Empty book (FAIL with CRITICAL alert)
delete from `orderbook;
delete from `.gds.auditLog;

bids:();
asks:enlist (50000.0;1.0);
`orderbook insert ((.z.P; `kraken; `BTCUSD; bids; asks; 123; 50000.0));

result:.gds.orderbook.check[];
assert[result=`FAIL; "Empty book returns FAIL"];
alert:first .gds.auditLog;
assert[alert[`severity]=`CRITICAL; "Empty book is CRITICAL severity"];

/ ============================================================================
/ CONFIGURATION TESTS
/ ============================================================================

-1 "\nPhase 7: Configuration";
cleanup[];

/ Set custom thresholds
.gds.orderbook.setThresholds[`kraken;`BTCUSD;500;10];

cfg:select from .gds.orderbook.config where exchange=`kraken, sym=`BTCUSD;
assert[1 = count cfg; "Config entry exists"];
assert[500 = first exec maxSpreadBps from cfg; "Custom max spread set to 500 bps"];
assert[10 = first exec minLevels from cfg; "Custom min levels set to 10"];

/ ============================================================================
/ CLEANUP & SUMMARY
/ ============================================================================

-1 "\n========================================";
-1 "  Orderbook Auditor Test Results";
-1 "  Total:  ",string testCount;
-1 "  Passed: ",string passCount;
-1 "  Failed: ",string failCount;
-1 "========================================\n";

if[failCount>0; -1 "!!! SOME TESTS FAILED !!!"; exit 1];
-1 "All tests passed!";
exit 0;
