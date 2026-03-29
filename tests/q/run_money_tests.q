/ Medusa — Money Library Test Runner
/ Runs all money-related tests in sequence

-1 "";
-1 "========================================";
-1 "  Money Library Test Suite";
-1 "========================================";
-1 "";

/ Test counter
.test.total: 0;
.test.passed: 0;
.test.failed: 0;

/ Run a test file
.test.run:{[file]
  -1 "Running: ",file;
  -1 "----------------------------------------";
  result: @[system;"l ",file;{-1 "ERROR: ",x; 0b}];
  if[result~0b;
    .test.failed+:1;
    -1 "FAILED: ",file;
    :0b
  ];
  .test.passed+:1;
  -1 "PASSED: ",file;
  -1 "";
  1b
 };

/ Run verification first
-1 "1. Running verification tests...";
-1 "";
.test.run["tests/q/verify_money.q"];

/ Run unit tests
-1 "2. Running unit tests...";
-1 "";
.test.run["tests/q/test_money.q"];

/ Run integration tests
-1 "3. Running integration tests...";
-1 "";
.test.run["tests/q/test_money_integration.q"];

/ Summary
-1 "";
-1 "========================================";
-1 "  Test Summary";
-1 "========================================";
-1 "  Total: ",string[.test.passed+.test.failed];
-1 "  Passed: ",string[.test.passed];
-1 "  Failed: ",string[.test.failed];
-1 "";

if[.test.failed > 0;
  -1 "Some tests failed!";
  exit 1
 ];

-1 "All tests passed!";
exit 0;
