/ Comprehensive test runner for configuration system
/ Runs all config tests in sequence

-1 "";
-1 "========================================";
-1 "  Configuration System Test Suite";
-1 "========================================";
-1 "";

/ Test 1: Parser tests
-1 "Running parser tests...";
\l test_parser.q

/ Test 2: Validator tests
-1 "Running validator tests...";
\l test_validator.q

/ Test 3: Loader tests
-1 "Running loader tests...";
\l test_loader.q

/ Test 4: Integration tests
-1 "Running integration tests...";
\l test_config.q

-1 "";
-1 "========================================";
-1 "  All Configuration Tests Passed!";
-1 "========================================";
-1 "";

exit 0
