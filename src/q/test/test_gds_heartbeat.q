/ ============================================================================
/ test_gds_heartbeat.q - Heartbeat Auditor Tests
/ ============================================================================

/ Load GDS modules
\l src/q/tick/sym.q
\l src/q/gds/alert_manager.q
\l src/q/gds/heartbeat_auditor.q

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
  delete from `trade;
  delete from `.gds.auditLog;
  / Reset config to defaults
  .gds.alert.init[];
  .gds.heartbeat.init[];
 };

-1 "\n=== GDS Heartbeat Auditor Tests ===\n";

/ ============================================================================
/ INITIALIZATION TESTS
/ ============================================================================

-1 "Phase 1: Initialization";

.gds.alert.init[];
.gds.heartbeat.init[];

assert[0 < count .gds.heartbeat.config; "Config table populated after init"];
assert[.gds.heartbeat.defaultThreshold = 30; "Default threshold is 30 seconds"];

/ ============================================================================
/ STALENESS DETECTION TESTS
/ ============================================================================

-1 "\nPhase 2: Staleness Detection";
cleanup[];

/ Test case: No data (should not be stale)
check:.gds.heartbeat.checkStaleness[`kraken;`BTCUSD];
assert[not check`stale; "No data is not stale"];
assert[0Np~check`lastUpdate; "No data has null lastUpdate"];

/ Test case: Recent data (not stale)
/ Insert recent orderbook data
`orderbook insert ((.z.P; `kraken; `BTCUSD; (); (); 0; 0f));
check:.gds.heartbeat.checkStaleness[`kraken;`BTCUSD];
assert[not check`stale; "Recent data is not stale"];
assert[check[`staleSec] < .gds.heartbeat.defaultThreshold; "Staleness below threshold"];

/ Test case: Stale data
/ Insert old orderbook data (61 seconds ago)
oldTime:.z.P - 0D00:01:01;
delete from `orderbook;
`orderbook insert ((oldTime; `kraken; `BTCUSD; (); (); 0; 0f));
check:.gds.heartbeat.checkStaleness[`kraken;`BTCUSD];
assert[check`stale; "Old data (61s) is stale with 30s threshold"];
assert[check[`staleSec] > .gds.heartbeat.defaultThreshold; "Staleness above threshold"];

/ Test case: Trade table updates also count
delete from `orderbook;
delete from `trade;
`trade insert ((.z.P; `kraken; `BTCUSD; `trade123; 50000.0; 0.1; `buy; 5000.0));
check:.gds.heartbeat.checkStaleness[`kraken;`BTCUSD];
assert[not check`stale; "Recent trade data prevents staleness"];

/ ============================================================================
/ MAIN CHECK FUNCTION TESTS
/ ============================================================================

-1 "\nPhase 3: Main Check Function";
cleanup[];

/ Test case: Fresh data (PASS)
delete from `orderbook;
delete from `trade;
delete from `.gds.auditLog;

`orderbook insert ((.z.P; `kraken; `BTCUSD; (); (); 0; 0f));
`orderbook insert ((.z.P; `coinbase; `ETHUSD; (); (); 0; 0f));

result:.gds.heartbeat.check[];
assert[result=`PASS; "Check returns PASS for fresh data"];

/ Test case: Stale data (FAIL with alerts)
delete from `orderbook;
delete from `trade;
delete from `.gds.auditLog;

/ Insert stale data (61 seconds old)
oldTime:.z.P - 0D00:01:01;
`orderbook insert ((oldTime; `kraken; `BTCUSD; (); (); 0; 0f));

result:.gds.heartbeat.check[];
assert[result=`FAIL; "Check returns FAIL for stale data"];
assert[0 < count .gds.auditLog; "Alert was raised"];

/ Verify alert details
alert:first .gds.auditLog;
assert[alert[`auditor]=`heartbeat; "Alert source is heartbeat auditor"];
assert[alert[`severity]=`WARN; "Staleness alert is WARN severity"];

/ ============================================================================
/ CONFIGURATION TESTS
/ ============================================================================

-1 "\nPhase 4: Configuration";
cleanup[];

/ Test setThreshold
.gds.heartbeat.setThreshold[`kraken;`BTCUSD;60];
cfg:select from .gds.heartbeat.config where exchange=`kraken, sym=`BTCUSD;
assert[1 = count cfg; "Config entry exists for kraken/BTCUSD"];
assert[60 = first exec maxStaleSec from cfg; "Custom threshold set to 60s"];

/ Test that custom threshold is used
delete from `orderbook;
delete from `trade;
delete from `.gds.auditLog;

/ Insert data that is 45 seconds old (stale with 30s threshold, fresh with 60s)
midTime:.z.P - 0D00:00:45;
`orderbook insert ((midTime; `kraken; `BTCUSD; (); (); 0; 0f));

result:.gds.heartbeat.check[];
assert[result=`PASS; "45s old data passes with 60s threshold"];

/ ============================================================================
/ CLEANUP & SUMMARY
/ ============================================================================

-1 "\n========================================";
-1 "  Heartbeat Auditor Test Results";
-1 "  Total:  ",string testCount;
-1 "  Passed: ",string passCount;
-1 "  Failed: ",string failCount;
-1 "========================================\n";

if[failCount>0; -1 "!!! SOME TESTS FAILED !!!"; exit 1];
-1 "All tests passed!";
exit 0;
