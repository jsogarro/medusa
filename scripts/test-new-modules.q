/ Minimal test for M2, M3, M4 modules

-1 "Loading logger.q..."
\l src/q/lib/logger.q

-1 "Loading cleanup.q..."
\l src/q/lib/cleanup.q

-1 "Loading riskLimits.q..."
\l src/q/config/riskLimits.q

-1 "";
-1 "All modules loaded successfully";
-1 "";

/ Simple functionality tests
-1 "Testing logger...";
.log.setLevel[`INFO];
.log.INFO["This is a test message"];
-1 "Logger works";

-1 "";
-1 "Testing risk config load...";
result:.config.risk.loadLimits[`$":configs/risk-limits.json"];
if[not result; -2 "Risk config load failed"; exit 1];
drawdownMax:.config.risk.getLimit[`drawdown;`maxPct];
-1 ("Risk limits loaded: drawdown maxPct = ", string[drawdownMax]);
-1 "Risk config works";

-1 "";
-1 "=== ALL MODULES VERIFIED ===";
exit 0
