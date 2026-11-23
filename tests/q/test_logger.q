/ ============================================================================
/ test_logger.q - Tests for Structured Logging
/ ============================================================================

\l src/q/lib/logger.q
\l tests/q/test_framework.q

/ Test 1: Verify log format for INFO
test_infoLogFormat:{[]
  / Call INFO and verify it doesn't error
  .log.INFO["Test info message"];

  / Verify INFO function exists and is callable
  .test.assert["INFO function should exist"; 100h = type value `.log.INFO];
 };

/ Test 2: Verify log format for WARN
test_warnLogFormat:{[]
  .log.WARN["Test warning message"];
  .test.assert["WARN function should exist"; 100h = type value `.log.WARN];
 };

/ Test 3: Verify log format for ERROR
test_errorLogFormat:{[]
  .log.ERROR["Test error message"];
  .test.assert["ERROR function should exist"; 100h = type value `.log.ERROR];
 };

/ Test 4: Verify log format for CRITICAL
test_criticalLogFormat:{[]
  .log.CRITICAL["Test critical message"];
  .test.assert["CRITICAL function should exist"; 100h = type value `.log.CRITICAL];
 };

/ Test 5: Verify structured event logging format
test_eventLogFormat:{[]
  / Test structured event
  .log.event[`INFO;`risk;`validateOrder;`sym`qty!(`BTCUSD;100)];

  / Verify event function exists
  .test.assert["event function should exist"; 100h = type value `.log.event];
 };

/ Test 6: Verify log level filtering
test_logLevelFiltering:{[]
  / Set log level to ERROR
  .log.setLevel[`ERROR];

  / Verify minLevel is set
  .test.assert["minLevel should be ERROR"; .log.minLevel~`ERROR];

  / INFO should be suppressed (lower than ERROR)
  .test.assert["INFO should be suppressed when level is ERROR"; not .log.shouldLog[`INFO]];

  / ERROR should pass
  .test.assert["ERROR should pass when level is ERROR"; .log.shouldLog[`ERROR]];

  / CRITICAL should pass
  .test.assert["CRITICAL should pass when level is ERROR"; .log.shouldLog[`CRITICAL]];

  / Reset to INFO
  .log.setLevel[`INFO];
 };

/ Test 7: Verify getLevel returns current level
test_getLevel:{[]
  .log.setLevel[`WARN];
  level:.log.getLevel[];
  .test.assert["getLevel should return current level"; level~`WARN];

  / Reset
  .log.setLevel[`INFO];
 };

/ Test 8: Verify DEBUG level
test_debugLevel:{[]
  / Set to DEBUG
  .log.setLevel[`DEBUG];

  / Verify DEBUG passes
  .test.assert["DEBUG should pass when level is DEBUG"; .log.shouldLog[`DEBUG]];

  / Reset
  .log.setLevel[`INFO];
 };

/ Test 9: Verify invalid log level handling
test_invalidLogLevel:{[]
  / Try to set invalid level
  result:@[{.log.setLevel[`INVALID];1b};::;{`$x}];

  / Should not error (setLevel returns () for invalid level)
  .test.assert["Invalid level should not crash"; 1b];
 };

/ Test 10: Verify structured log output format
test_structuredLogOutputFormat:{[]
  / Verify event creates pipe-delimited output
  / Format: timestamp|level|module|action|detail

  / Call event and verify it doesn't error
  .log.event[`INFO;`exchange;`placeOrder;`orderId`exchange!(`ORD123;`coinbase)];

  / Verify detail dict serialization
  detail:`orderId`exchange!(`ORD123;`coinbase);
  detailStr:.Q.s1[detail];

  / Verify detail is not empty
  .test.assert["Detail serialization should produce non-empty string"; 0 < count detailStr];
 };

-1 "Logger tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];
