/ Master test runner for Medusa q tests
/ Loads all test files and executes them

-1 "\n╔════════════════════════════════════════════════════════════════╗";
-1 "║            Medusa q/kdb+ Test Suite                           ║";
-1 "╚════════════════════════════════════════════════════════════════╝\n";

/ Load test framework
\l tests/q/test_framework.q

/ Load all test modules
-1 "Loading test modules...\n";

medusaRunAll:1b;

\l tests/q/test_money.q
\l tests/q/test_config.q
\l tests/q/test_schema.q
\l tests/q/test_engine.q
\l tests/q/test_exchange.q
\l tests/q/test_audit.q
\l tests/q/test_risk.q
\l tests/q/test_intraday_risk_focused.q
\l tests/q/test_alpaca_phase3_focused.q
\l tests/q/test_options_schema.q
\l tests/q/risk/test_concentrationLimits.q
\l tests/q/risk/test_rateLimiting.q
\l tests/q/test_cleanup.q
\l tests/q/test_logger.q

/ Re-pin the PDT clock to a known trading date AFTER all test-file loads.
/ Each \l of src/q/risk/init.q re-runs pdt.q which resets pdt.today:{.z.d},
/ so this needs to land after the last risk-touching test file.
.risk.pdt.today:{2026.04.06};

-1 "\n╔════════════════════════════════════════════════════════════════╗";
-1 "║            Running All Tests                                   ║";
-1 "╚════════════════════════════════════════════════════════════════╝\n";

/ Run all tests
totalFailed:.test.run[`.];

-1 "\n╔════════════════════════════════════════════════════════════════╗";
-1 "║            Test Run Complete                                   ║";
-1 "╚════════════════════════════════════════════════════════════════╝\n";

/ Exit with appropriate code
-1 "Exiting with code: ",string totalFailed;
exit totalFailed
