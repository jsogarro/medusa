/ Tests for .audit namespace (audit/audit.q)

\l tests/q/test_framework.q
\l src/q/audit/audit.q

/ ========================================
/ Registry tests
/ ========================================

test_audit_registerType:{
  / Register a test audit type
  .audit.registerType[`TEST_AUDIT; "Test Audit"; "Testing audit registration"; `.audit.testValidate];

  .test.assert["Type registered"; `TEST_AUDIT in exec auditType from .audit.types];

  entry:.audit.types[`TEST_AUDIT];
  .test.assertEqual["Name set"; "Test Audit"; entry`name];
  .test.assertEqual["Description set"; "Testing audit registration"; entry`description];
  .test.assert["Enabled by default"; entry`enabled];
  .test.assertEqual["Validation func set"; `.audit.testValidate; entry`validationFunc];
 }

/ ========================================
/ Result tests
/ ========================================

test_audit_newResult:{
  result:.audit.newResult[`TEST; `PASS; (); (); `count`total!(42; 100)];

  .test.assert["Result is dict"; 99h = type result];
  .test.assertEqual["Audit type set"; `TEST; result`auditType];
  .test.assertEqual["Status set"; `PASS; result`status];
  .test.assert["Timestamp set"; not null result`timestamp];
  .test.assertEqual["Metrics set"; `count`total!(42; 100); result`metrics];
 }

test_audit_saveResult:{
  / Clear results
  .audit.results:0#.audit.results;

  result:.audit.newResult[`TEST_SAVE; `PASS; (); (); ()!()];
  .audit.saveResult[result];

  .test.assertEqual["Result saved"; 1; count .audit.results];

  saved:first .audit.results;
  .test.assertEqual["Audit type preserved"; `TEST_SAVE; saved`auditType];
  .test.assertEqual["Status preserved"; `PASS; saved`status];
 }

/ ========================================
/ Execution tests
/ ========================================

test_audit_run_pass:{
  / Register test audit
  .audit.testValidatePass:{[] .audit.newResult[`TEST_PASS; `PASS; (); (); ()!()]};
  .audit.registerType[`TEST_PASS; "Test Pass"; "Always passes"; `.audit.testValidatePass];

  / Run audit
  result:.audit.run[`TEST_PASS];

  .test.assertEqual["Status is PASS"; `PASS; result`status];
  .test.assert["Duration set"; not null result`duration];
 }

test_audit_run_fail:{
  / Register test audit
  .audit.testValidateFail:{[] .audit.newResult[`TEST_FAIL; `FAIL; enlist "Test error"; (); ()!()]};
  .audit.registerType[`TEST_FAIL; "Test Fail"; "Always fails"; `.audit.testValidateFail];

  / Run audit
  result:.audit.run[`TEST_FAIL];

  .test.assertEqual["Status is FAIL"; `FAIL; result`status];
  .test.assertEqual["Error message set"; enlist "Test error"; result`errors];
 }

test_audit_run_unknown:{
  result:.audit.run[`UNKNOWN_AUDIT];

  .test.assertEqual["Status is FAIL"; `FAIL; result`status];
  .test.assert["Error message about unknown type"; (count result`errors) > 0];
 }

test_audit_run_disabled:{
  / Register and disable
  .audit.registerType[`TEST_DISABLED; "Test Disabled"; "Disabled audit"; `.audit.testValidatePass];
  update enabled:0b from `.audit.types where auditType=`TEST_DISABLED;

  / Run disabled audit
  result:.audit.run[`TEST_DISABLED];

  .test.assertEqual["Status is WARNING"; `WARNING; result`status];
  .test.assert["Warning about disabled"; (count result`warnings) > 0];
 }

/ ========================================
/ Statistics tests
/ ========================================

test_audit_latestResults:{
  / Clear and populate results
  .audit.results:0#.audit.results;

  / Add multiple results for same type
  .audit.saveResult[.audit.newResult[`TEST_STATS; `PASS; (); (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_STATS; `FAIL; enlist "error"; (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_STATS; `PASS; (); (); ()!()]];

  / Get latest
  latest:.audit.latestResults[];

  .test.assert["Latest is table"; 99h = type latest];
  .test.assert["TEST_STATS in results"; `TEST_STATS in exec auditType from latest];

  / Latest status should be PASS (last result)
  latestStatus:first exec status from latest where auditType=`TEST_STATS;
  .test.assertEqual["Latest status is PASS"; `PASS; latestStatus];
 }

test_audit_failureRate:{
  / Clear and populate results
  .audit.results:0#.audit.results;

  / Add mix of PASS and FAIL
  .audit.saveResult[.audit.newResult[`TEST_RATE; `PASS; (); (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_RATE; `FAIL; enlist "error"; (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_RATE; `FAIL; enlist "error"; (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_RATE; `PASS; (); (); ()!()]];

  / Get failure rate (1 hour window)
  rates:.audit.failureRate[0D01:00:00];

  .test.assert["Rates is table"; 98h = type rates];

  / Check TEST_RATE stats
  testRates:select from rates where auditType=`TEST_RATE;
  if[count testRates;
    .test.assertEqual["Total runs is 4"; 4; first testRates`totalRuns];
    .test.assertEqual["Failures is 2"; 2; first testRates`failures];
    .test.assertEqual["Failure rate is 0.5"; 0.5; first testRates`failureRate];
  ];
 }

test_audit_failures:{
  / Clear and populate
  .audit.results:0#.audit.results;

  / Add failures
  .audit.saveResult[.audit.newResult[`TEST_FAILURES; `FAIL; enlist "error1"; (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_FAILURES; `PASS; (); (); ()!()]];
  .audit.saveResult[.audit.newResult[`TEST_FAILURES; `FAIL; enlist "error2"; (); ()!()]];

  / Get failures
  failures:.audit.failures[0D01:00:00];

  .test.assert["Failures is table"; 98h = type failures];
  .test.assertEqual["Only FAIL status"; 2; count failures];
  .test.assert["All statuses are FAIL"; all `FAIL = exec status from failures];
 }

test_audit_prune:{
  / Clear and populate
  .audit.results:0#.audit.results;

  / Add 15 results
  {.audit.saveResult[.audit.newResult[`TEST_PRUNE; `PASS; (); (); ()!()]]} each til 15;

  .test.assertEqual["15 results before prune"; 15; count .audit.results];

  / Prune to 10
  .audit.prune[10];

  .test.assertEqual["10 results after prune"; 10; count .audit.results];
 }

-1 "Audit tests loaded";
