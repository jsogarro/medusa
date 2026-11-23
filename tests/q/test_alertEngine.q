/ Tests for Alert & Notification Engine

/ Load test framework
\l tests/q/testFramework.q

\d .test

/ ═══════════════════════════════════════════════════════════════════
/ Setup
/ ═══════════════════════════════════════════════════════════════════

setup:{[]
  / Initialize risk system
  .risk.init[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Test Cases
/ ═══════════════════════════════════════════════════════════════════

/ Test: Alert rule registration
testAlertRuleRegistration:{[]
  setup[];

  / Register a new alert rule
  ruleId:.risk.registerAlertRule[`testAlert; `pnl; `lessThan; -1000.0; `warn];

  / Check rule was created
  rule:first select from .risk.alertRules where ruleId=ruleId;
  assert[rule[`ruleName] = `testAlert; "Rule name should be testAlert"];
  assert[rule[`metric] = `pnl; "Metric should be pnl"];
  assert[rule[`threshold] = -1000.0; "Threshold should be -1000"];
  assert[rule[`severity] = `warn; "Severity should be warn"];
  assert[rule[`enabled] = 1b; "Rule should be enabled"];

  pass[];
 };

/ Test: Alert rule triggering
testAlertRuleTrigger:{[]
  setup[];

  / Set P&L to trigger alert
  .risk.intradayPnL[`totalPnL]:-6000.0;

  / Register alert rule
  ruleId:.risk.registerAlertRule[`pnlLoss; `pnl; `lessThan; -5000.0; `warn];

  / Check alerts
  .risk.checkAlertRules[];

  / Alert should be triggered
  alerts:select from .risk.alertHistory where ruleId=ruleId;
  assert[count[alerts] > 0; "Alert should be triggered"];

  / Check alert details
  alert:first alerts;
  assert[alert[`actualValue] = -6000.0; "Actual value should be -6000"];
  assert[alert[`threshold] = -5000.0; "Threshold should be -5000"];
  assert[alert[`severity] = `warn; "Severity should be warn"];

  pass[];
 };

/ Test: Alert condition evaluation
testConditionEvaluation:{[]
  setup[];

  / Test greaterThan condition
  assert[.risk.evaluateCondition[`greaterThan; 10.0; 5.0] = 1b; "10 > 5 should be true"];
  assert[.risk.evaluateCondition[`greaterThan; 3.0; 5.0] = 0b; "3 > 5 should be false"];

  / Test lessThan condition
  assert[.risk.evaluateCondition[`lessThan; 3.0; 5.0] = 1b; "3 < 5 should be true"];
  assert[.risk.evaluateCondition[`lessThan; 10.0; 5.0] = 0b; "10 < 5 should be false"];

  / Test equals condition
  assert[.risk.evaluateCondition[`equals; 5.0; 5.0] = 1b; "5 = 5 should be true"];
  assert[.risk.evaluateCondition[`equals; 5.0; 6.0] = 0b; "5 = 6 should be false"];

  pass[];
 };

/ Test: Alert acknowledgment
testAlertAcknowledgment:{[]
  setup[];

  / Create an alert
  `.risk.alertHistory insert (.z.p;1000j;`testAlert;`pnl;-5000.0;-1000.0;`warn;0b;`;0Np);

  / Acknowledge the alert
  .risk.acknowledgeAlert[0j;`testUser];

  / Check acknowledgment
  alert:first select from .risk.alertHistory;
  assert[alert[`acknowledged] = 1b; "Alert should be acknowledged"];
  assert[alert[`acknowledgedBy] = `testUser; "Alert should be acknowledged by testUser"];

  pass[];
 };

/ Test: Get current metrics
testGetCurrentMetrics:{[]
  setup[];

  / Set metrics
  .risk.intradayPnL[`totalPnL]:12345.0;
  .risk.exposureSummary[`totalGross]:500000.0;

  / Get metrics
  metrics:.risk.getCurrentMetrics[];

  / Check metrics
  assert[metrics[`pnl] = 12345.0; "P&L metric should be 12345"];
  assert[metrics[`exposure] = 500000.0; "Exposure metric should be 500000"];

  pass[];
 };

/ Test: Enable/disable alert rule
testEnableDisableRule:{[]
  setup[];

  / Register a rule
  ruleId:.risk.registerAlertRule[`testAlert; `pnl; `lessThan; -1000.0; `warn];

  / Disable the rule
  .risk.setAlertRuleEnabled[ruleId;0b];

  / Check rule is disabled
  rule:first select from .risk.alertRules where ruleId=ruleId;
  assert[rule[`enabled] = 0b; "Rule should be disabled"];

  / Enable the rule
  .risk.setAlertRuleEnabled[ruleId;1b];

  / Check rule is enabled
  rule:first select from .risk.alertRules where ruleId=ruleId;
  assert[rule[`enabled] = 1b; "Rule should be enabled"];

  pass[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests
/ ═══════════════════════════════════════════════════════════════════

runTests:{[]
  .test.run[`testAlertRuleRegistration];
  .test.run[`testAlertRuleTrigger];
  .test.run[`testConditionEvaluation];
  .test.run[`testAlertAcknowledgment];
  .test.run[`testGetCurrentMetrics];
  .test.run[`testEnableDisableRule];
 };

/ Run tests
runTests[];

\d .
