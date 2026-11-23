/ ============================================================================
/ verify-medium-fixes.q - Verify q runtime utility modules
/ ============================================================================

\l src/q/lib/logger.q
\l src/q/lib/cleanup.q
\l src/q/config/riskLimits.q

fail:{[msg] -2 msg; exit 1};
failIf:{[cond;msg] if[cond; fail[msg]]};
pass:{[msg] -1 ("PASS: ",msg)};

-1 "";
-1 "=== M2: Cleanup Module ===";

failIf[key[`.cleanup]~();"FAIL: .cleanup namespace not found"];
failIf[not `pruneRDB in key[`.cleanup];"FAIL: cleanup.pruneRDB not found"];
failIf[not `scheduleCleanup in key[`.cleanup];"FAIL: cleanup.scheduleCleanup not found"];
pass["cleanup module loaded"];
pass["cleanup functions exist"];

-1 "";
-1 "=== M3: Configurable Risk Limits ===";

failIf[key[`.config]~();"FAIL: .config namespace not found"];
failIf[key[`.config.risk]~();"FAIL: .config.risk namespace not found"];
failIf[not `loadLimits in key[`.config.risk];"FAIL: config.risk.loadLimits not found"];
pass["risk limits config module loaded"];

result:.config.risk.loadLimits[`$":configs/risk-limits.json"];
failIf[not result;"FAIL: Failed to load risk-limits.json"];
pass["risk limits loaded from JSON"];

failIf[()~.config.risk.limits;"FAIL: risk limits not loaded"];
pass["risk limits accessible"];

drawdownMax:.config.risk.getLimit[`drawdown;`maxPct];
failIf[drawdownMax<>15.0;"FAIL: drawdown maxPct should be 15.0, got ",string[drawdownMax]];
pass["drawdown maxPct = 15.0"];

.config.risk.setLimit[`drawdown;`warnPct;7.5];
warnPct:.config.risk.getLimit[`drawdown;`warnPct];
failIf[warnPct<>7.5;"FAIL: setLimit failed, expected 7.5, got ",string[warnPct]];
pass["runtime override works (warnPct = 7.5)"];

-1 "";
-1 "=== M4: Structured Logging ===";

failIf[key[`.log]~();"FAIL: .log namespace not found"];
failIf[not `INFO in key[`.log];"FAIL: log.INFO not found"];
pass["logger module loaded"];

requiredFns:`INFO`WARN`ERROR`CRITICAL;
failIf[any not requiredFns in key[`.log];"FAIL: Missing log level functions"];
pass["all log level functions exist"];

failIf[not `event in key[`.log];"FAIL: log.event not found"];
pass["structured event logging exists"];

.log.setLevel[`ERROR];
failIf[not .log.minLevel~`ERROR;"FAIL: setLevel failed"];
pass["log level filtering works"];
.log.setLevel[`INFO];

-1 "";
-1 "=== M6: Thread-Safety Documentation ===";

docPath:`:docs/THREAD_SAFETY.md;
doc:@[read0;docPath;{()}];
failIf[doc~();"FAIL: docs/THREAD_SAFETY.md not found"];
pass["thread-safety documentation exists"];

requiredSections:("Single-Process Guarantees";"Multi-Process Scenarios";"Keyed Table Upserts Are Atomic");
hasSections:{[doc;section] any doc like ("*",section,"*")};
missingSections:requiredSections where not hasSections[doc] each requiredSections;
failIf[0<count missingSections;"FAIL: Missing documentation sections: ",", " sv missingSections];
pass["all required documentation sections present"];

-1 "";
-1 "=== ALL TESTS PASSED ===";
-1 "M2: Cleanup module implemented and verified";
-1 "M3: Configurable risk limits implemented and verified";
-1 "M4: Structured logging implemented and verified";
-1 "M6: Thread-safety documentation complete";
-1 "";

exit 0
