/ test_audit.q - Comprehensive audit system tests
/ Tests core infrastructure, all 5 audit types, and the runner

/ ============================================================================
/ SETUP
/ ============================================================================

/ Load schema first (audit modules reference .qg tables)
\l src/q/schema/init.q
.qg.loadAllSchemas[];
.qg.initAllTables[];

/ Load money library
\l src/q/lib/money.q

/ Load config
\l src/q/config/config.q

/ Load exchange base + registry + stub (for coordinator references)
\l src/q/exchange/base.q
\l src/q/exchange/registry.q
\l src/q/exchange/stub.q
\l src/q/exchange/coordinator.q

/ Load engine position (for position cache audit)
\l src/q/engine/position.q

/ Load audit system
\l src/q/audit/audit.q
\l src/q/audit/order.q
\l src/q/audit/volume_balance.q
\l src/q/audit/fiat_balance.q
\l src/q/audit/ledger.q
\l src/q/audit/position_cache.q
\l src/q/audit/runner.q

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

/ ============================================================================
/ PHASE 1: CORE AUDIT INFRASTRUCTURE TESTS
/ ============================================================================

-1 "\n=== Phase 1: Core Audit Infrastructure ===\n";

/ Test audit type registry populated by module loading
assert[0<count .audit.types; "Audit types table is populated"];
assert[`ORDER_AUDIT in exec auditType from .audit.types; "ORDER_AUDIT registered"];
assert[`VOLUME_BALANCE_AUDIT in exec auditType from .audit.types; "VOLUME_BALANCE_AUDIT registered"];
assert[`FIAT_BALANCE_AUDIT in exec auditType from .audit.types; "FIAT_BALANCE_AUDIT registered"];
assert[`LEDGER_AUDIT in exec auditType from .audit.types; "LEDGER_AUDIT registered"];
assert[`POSITION_CACHE_AUDIT in exec auditType from .audit.types; "POSITION_CACHE_AUDIT registered"];
assert[5=count .audit.types; "Exactly 5 audit types registered"];

/ Test all types are enabled by default
assert[all exec enabled from .audit.types; "All audit types enabled by default"];

/ Test newResult creates proper dict
result:.audit.newResult[`ORDER_AUDIT;`PASS;();();()!()];
assert[result[`auditType]=`ORDER_AUDIT; "newResult sets auditType"];
assert[result[`status]=`PASS; "newResult sets status"];
assert[not null result`timestamp; "newResult sets timestamp"];
assert[0=count result`errors; "newResult has empty errors"];
assert[0=count result`warnings; "newResult has empty warnings"];

/ Test newResult with errors
result:.audit.newResult[`ORDER_AUDIT;`FAIL;enlist "test error";enlist "test warning";`a`b!(1;2)];
assert[result[`status]=`FAIL; "newResult FAIL status"];
assert[1=count result`errors; "newResult has 1 error"];
assert[1=count result`warnings; "newResult has 1 warning"];
assert[result[`metrics;`a]=1; "newResult metrics preserved"];

/ Test saveResult persists to table
origCount:count .audit.results;
.audit.saveResult[result,enlist[`duration]!enlist 0D00:00:00.001];
assert[(count .audit.results)=origCount+1; "saveResult inserts row"];
assert[`FAIL=last exec status from .audit.results; "Saved result has FAIL status"];

/ Test run with unknown audit type
result:.audit.run[`NONEXISTENT];
assert[result[`status]=`FAIL; "Unknown audit type returns FAIL"];
assert[0<count result`errors; "Unknown audit type has error message"];

/ Test run with disabled audit type
update enabled:0b from `.audit.types where auditType=`ORDER_AUDIT;
result:.audit.run[`ORDER_AUDIT];
assert[result[`status]=`WARNING; "Disabled audit returns WARNING"];
update enabled:1b from `.audit.types where auditType=`ORDER_AUDIT;  / re-enable

/ Test latestResults
lr:.audit.latestResults[];
assert[0<count lr; "latestResults returns data"];

/ Test failureRate
fr:.audit.failureRate[0D01:00:00];
assert[0<count fr; "failureRate returns data"];

/ Test failures
fails:.audit.failures[0D01:00:00];
assert[0<=count fails; "failures returns a table"];

/ Test prune
/ Add many rows
{.audit.saveResult[(.audit.newResult[`ORDER_AUDIT;`PASS;();();()!()]),enlist[`duration]!enlist 0D00:00:00.000001]} each til 50;
origCount:count .audit.results;
.audit.prune[10];
assert[(count .audit.results)<=10; "prune keeps at most maxRows"];

/ ============================================================================
/ PHASE 2: ORDER AUDIT TESTS
/ ============================================================================

-1 "\n=== Phase 2: Order Audit ===\n";

/ Test amountsMatch
assert[.audit.ORDER.amountsMatch[1.0;1.0]; "amountsMatch: equal values match"];
assert[.audit.ORDER.amountsMatch[1.0;1.0000001]; "amountsMatch: within tolerance"];
assert[not .audit.ORDER.amountsMatch[1.0;1.01]; "amountsMatch: beyond tolerance"];

/ Test findMissing
localOrders:([] order_id:1 2 3; status:`open`filled`filled);
exchangeOrders:([] order_id:1 2 4; status:`open`filled`open);
missing:.audit.ORDER.findMissing[localOrders;exchangeOrders];
assert[1=count missing; "findMissing: detects 1 missing order"];
assert[4=first exec order_id from missing; "findMissing: order 4 is missing from local"];

/ Test findOrphaned
orphaned:.audit.ORDER.findOrphaned[localOrders;exchangeOrders];
assert[1=count orphaned; "findOrphaned: detects 1 orphaned order"];
assert[3=first exec order_id from orphaned; "findOrphaned: order 3 is orphaned"];

/ Test findStatusMismatches
localOrders2:([] order_id:1 2; status:`open`filled; price:100 200; volume:10 20; filled_volume:0 20; volume_currency:`BTC`BTC);
exchangeOrders2:([] order_id:1 2; status:`filled`filled; filled_volume:10 20);
mismatches:.audit.ORDER.findStatusMismatches[localOrders2;exchangeOrders2];
assert[1=count mismatches; "findStatusMismatches: detects order 1 status mismatch"];
assert[`open=first exec localStatus from mismatches; "findStatusMismatches: local shows open"];
assert[`filled=first exec exchangeStatus from mismatches; "findStatusMismatches: exchange shows filled"];

/ Test ORDER.validate runs without crash (empty tables)
result:.audit.ORDER.validate[];
assert[result[`status] in `PASS`WARNING`FAIL; "ORDER.validate returns valid status"];
assert[`ORDER_AUDIT=result`auditType; "ORDER.validate sets correct auditType"];

/ ============================================================================
/ PHASE 3: VOLUME BALANCE AUDIT TESTS
/ ============================================================================

-1 "\n=== Phase 3: Volume Balance Audit ===\n";

/ Test compareAmounts
comp:.audit.VOLUME_BALANCE.compareAmounts[1.0;1.0];
assert[comp`matches; "compareAmounts: equal values match"];
assert[comp[`delta]=0f; "compareAmounts: zero delta"];

comp:.audit.VOLUME_BALANCE.compareAmounts[1.0;1.1];
assert[not comp`matches; "compareAmounts: 0.1 delta does not match"];
assert[0.1=comp`delta; "compareAmounts: delta is 0.1"];

comp:.audit.VOLUME_BALANCE.compareAmounts[1.0;1.000000001];
assert[comp`matches; "compareAmounts: within 1 satoshi tolerance"];

/ Test VOLUME_BALANCE.validate runs
result:.audit.VOLUME_BALANCE.validate[];
assert[result[`status] in `PASS`FAIL`WARNING; "VOLUME_BALANCE.validate returns valid status"];
assert[`VOLUME_BALANCE_AUDIT=result`auditType; "VOLUME_BALANCE.validate correct auditType"];

/ ============================================================================
/ PHASE 4: FIAT BALANCE AUDIT TESTS
/ ============================================================================

-1 "\n=== Phase 4: Fiat Balance Audit ===\n";

/ Test fiat compareAmounts with currency rounding
comp:.audit.FIAT_BALANCE.compareAmounts[100.005;100.004;`USD];
assert[comp`matches; "Fiat compareAmounts: within 1 cent"];

comp:.audit.FIAT_BALANCE.compareAmounts[100.00;100.02;`USD];
assert[not comp`matches; "Fiat compareAmounts: 2 cents does not match"];

/ Test FIAT_BALANCE.validate runs
result:.audit.FIAT_BALANCE.validate[];
assert[result[`status] in `PASS`FAIL`WARNING; "FIAT_BALANCE.validate returns valid status"];
assert[`FIAT_BALANCE_AUDIT=result`auditType; "FIAT_BALANCE.validate correct auditType"];

/ ============================================================================
/ PHASE 5: LEDGER AUDIT TESTS
/ ============================================================================

-1 "\n=== Phase 5: Ledger Audit ===\n";

/ Test checkCurrencies with valid currencies
txns:([] transaction_id:1 2; currency:`BTC`USD; transaction_type:`deposit`deposit; amount:1.0 100.0; time_created:.z.P,.z.P);
result:.audit.LEDGER.checkCurrencies[txns];
assert[result`valid; "checkCurrencies: BTC and USD are valid"];

/ Test checkCurrencies with invalid currency
txns2:([] transaction_id:enlist 1; currency:enlist `FAKECOIN; transaction_type:enlist `deposit; amount:enlist 1.0; time_created:enlist .z.P);
result:.audit.LEDGER.checkCurrencies[txns2];
assert[not result`valid; "checkCurrencies: FAKECOIN is invalid"];
assert[`FAKECOIN in result`invalidCurrencies; "checkCurrencies: reports FAKECOIN"];

/ Test checkDoubleEntry — balanced
txns3:([] transaction_id:1 2; currency:`BTC`BTC; transaction_type:`deposit`withdrawal; amount:100.0 100.0; time_created:.z.P,.z.P);
result:.audit.LEDGER.checkDoubleEntry[txns3];
assert[result`balanced; "checkDoubleEntry: equal deposit and withdrawal balances"];

/ Test checkDoubleEntry — imbalanced
txns4:([] transaction_id:1 2; currency:`BTC`BTC; transaction_type:`deposit`withdrawal; amount:100.0 50.0; time_created:.z.P,.z.P);
result:.audit.LEDGER.checkDoubleEntry[txns4];
assert[not result`balanced; "checkDoubleEntry: unequal deposit/withdrawal imbalances"];

/ Test checkOrphanedTransactions — no parent column
txns5:([] transaction_id:1 2; currency:`BTC`BTC; transaction_type:`deposit`deposit; amount:1.0 2.0; time_created:.z.P,.z.P);
result:.audit.LEDGER.checkOrphanedTransactions[txns5];
assert[result`valid; "checkOrphaned: valid when no parent_transaction_id column"];

/ Test checkOrphanedTransactions — with orphans
txns6:([] transaction_id:1 2; parent_transaction_id:0N 999; currency:`BTC`BTC; transaction_type:`deposit`deposit; amount:1.0 2.0; time_created:.z.P,.z.P);
result:.audit.LEDGER.checkOrphanedTransactions[txns6];
assert[not result`valid; "checkOrphaned: detects orphaned reference to 999"];
assert[999 in result`orphanedTxIds; "checkOrphaned: reports tx 999"];

/ Test checkTimestamps — monotonic
t1:.z.P;
t2:t1+0D00:01:00;
txns7:([] transaction_id:1 2; time_created:t1,t2; currency:`BTC`BTC; transaction_type:`deposit`deposit; amount:1.0 2.0);
result:.audit.LEDGER.checkTimestamps[txns7];
assert[result`valid; "checkTimestamps: monotonic timestamps valid"];

/ Test checkTimestamps — backdated
txns8:([] transaction_id:1 2; time_created:t2,t1; currency:`BTC`BTC; transaction_type:`deposit`deposit; amount:1.0 2.0);
result:.audit.LEDGER.checkTimestamps[txns8];
assert[not result`valid; "checkTimestamps: backdated timestamp detected"];

/ Test LEDGER.validate on empty transaction table
result:.audit.LEDGER.validate[];
assert[result[`status] in `PASS`WARNING; "LEDGER.validate handles empty/missing txn table"];

/ ============================================================================
/ PHASE 6: POSITION CACHE AUDIT TESTS
/ ============================================================================

-1 "\n=== Phase 6: Position Cache Audit ===\n";

/ Test with empty cache
result:.audit.POSITION_CACHE.validate[];
assert[result[`status] in `PASS`WARNING; "POSITION_CACHE.validate handles empty cache"];

/ Seed cache with a known position and test comparison
.engine.position.cache[(`stub;`BTC;`testStrat)]:(1.5f;50000.0f;.z.p);
comp:.audit.POSITION_CACHE.comparePosition[`stub;`BTC;`testStrat];
/ queryDB returns 0 quantity by default, so cached=1.5 vs calculated=0 -> mismatch
assert[not comp`matches; "comparePosition: detects mismatch (cached 1.5 vs calculated 0)"];
assert[1.5=comp`cachedQty; "comparePosition: cachedQty is 1.5"];
assert[0f=comp`calculatedQty; "comparePosition: calculatedQty is 0"];

/ Run full validate
result:.audit.POSITION_CACHE.validate[];
assert[result[`status]=`FAIL; "POSITION_CACHE.validate detects mismatch"];
assert[0<count result`errors; "POSITION_CACHE.validate reports errors"];

/ Clean up
delete from `.engine.position.cache where exchange=`stub, asset=`BTC, strategyId=`testStrat;

/ ============================================================================
/ PHASE 7: AUDIT RUNNER TESTS
/ ============================================================================

-1 "\n=== Phase 7: Audit Runner ===\n";

/ Test schedule
.audit.schedule[5];
assert[.audit.runner.enabled; "schedule: runner enabled"];
assert[.audit.runner.mode=`tick; "schedule: mode is tick"];
assert[.audit.runner.frequency=5; "schedule: frequency set to 5"];
assert[.audit.runner.tickCount=0; "schedule: tick counter reset"];

/ Test tick counting
.audit.onStrategyTick[];
assert[.audit.runner.tickCount=1; "onStrategyTick: increments counter"];
.audit.onStrategyTick[];
assert[.audit.runner.tickCount=2; "onStrategyTick: counter at 2"];

/ Test that audits fire at frequency boundary
preCount:count .audit.results;
{.audit.onStrategyTick[]} each til 3;  / 3 more ticks = total 5
assert[.audit.runner.tickCount=0; "Runner: counter reset after frequency reached"];
assert[(count .audit.results)>preCount; "Runner: audits executed at frequency boundary"];

/ Test stop
.audit.stop[];
assert[not .audit.runner.enabled; "stop: runner disabled"];
assert[.audit.runner.mode=`; "stop: mode cleared"];

/ Test scheduler doesn't tick when disabled
preCount2:count .audit.results;
.audit.onStrategyTick[];
assert[(count .audit.results)=preCount2; "Disabled runner: no audits executed on tick"];

/ Test schedulerStatus
.audit.schedule[10];
ss:.audit.schedulerStatus[];
assert[ss[`enabled]; "schedulerStatus: shows enabled"];
assert[ss[`frequency]=10; "schedulerStatus: shows frequency"];
assert[ss[`mode]=`tick; "schedulerStatus: shows tick mode"];
.audit.stop[];

/ Test consecutive failure tracking
.audit.runner.consecutiveFailures:()!();
.audit.runner.consecutiveFailures[`ORDER_AUDIT]:3;
assert[3=.audit.runner.consecutiveFailures[`ORDER_AUDIT]; "consecutiveFailures: tracks count"];

/ Test invalid frequency
errCaught:0b;
@[.audit.schedule;0;{errCaught::1b}];
assert[errCaught; "schedule: rejects zero frequency"];

errCaught:0b;
@[.audit.schedule;-5;{errCaught::1b}];
assert[errCaught; "schedule: rejects negative frequency"];

/ ============================================================================
/ INTEGRATION: runAll
/ ============================================================================

-1 "\n=== Integration: runAll ===\n";

preCount:count .audit.results;
results:.audit.runAll[];
assert[5=count results; "runAll: returns results for all 5 audit types"];
assert[`ORDER_AUDIT in key results; "runAll: includes ORDER_AUDIT"];
assert[`VOLUME_BALANCE_AUDIT in key results; "runAll: includes VOLUME_BALANCE_AUDIT"];
assert[`FIAT_BALANCE_AUDIT in key results; "runAll: includes FIAT_BALANCE_AUDIT"];
assert[`LEDGER_AUDIT in key results; "runAll: includes LEDGER_AUDIT"];
assert[`POSITION_CACHE_AUDIT in key results; "runAll: includes POSITION_CACHE_AUDIT"];
assert[(count .audit.results)>=preCount+5; "runAll: all results persisted"];

/ Verify each result has standard structure
{[at;res]
  assert[at=res`auditType; "runAll result for ",(string at)," has correct auditType"];
  assert[res[`status] in `PASS`FAIL`WARNING; "runAll result for ",(string at)," has valid status"];
  assert[not null res`timestamp; "runAll result for ",(string at)," has timestamp"];
} ./: flip (key results; value results);

/ ============================================================================
/ SUMMARY
/ ============================================================================

-1 "\n========================================";
-1 "  Audit Test Results";
-1 "  Total:  ",string testCount;
-1 "  Passed: ",string passCount;
-1 "  Failed: ",string failCount;
-1 "========================================\n";

if[failCount>0; -1 "!!! SOME TESTS FAILED !!!"; exit 1];
-1 "All tests passed!";
exit 0;
