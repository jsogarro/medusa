/ Alert & Notification Engine
/ Configurable alerts with escalation (in-app, log, emergency stop)

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Alert Tables
/ ═══════════════════════════════════════════════════════════════════

/ Alert rules (user-configurable)
alertRules:([ruleId:`long$()]
  ruleName:`symbol$();
  metric:`symbol$();           / e.g., `pnl, `exposure, `orderFlow
  condition:`symbol$();        / e.g., `greaterThan, `lessThan
  threshold:`float$();
  severity:`symbol$();         / `warn, `halt, `critical
  enabled:`boolean$();
  lastTriggered:`timestamp$()
 );

/ Alert history (append-only)
alertHistory:([]
  time:`timestamp$();
  ruleId:`long$();
  ruleName:`symbol$();
  metric:`symbol$();
  actualValue:`float$();
  threshold:`float$();
  severity:`symbol$();
  acknowledged:`boolean$();
  acknowledgedBy:`symbol$();
  acknowledgedAt:`timestamp$()
 );

/ Alert ID generator state
alertIdGen:([] nextId:enlist 1000j);

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

initAlertEngine:{[]
  / Clear tables
  delete from `.risk.alertRules;
  delete from `.risk.alertHistory;
  `.risk.alertIdGen set ([] nextId:enlist 1000j);

  / Register default alert rules
  registerAlertRule[`pnlWarn; `pnl; `lessThan; -5000.0; `warn];
  registerAlertRule[`pnlHalt; `pnl; `lessThan; -15000.0; `halt];
  registerAlertRule[`exposureWarn; `exposure; `greaterThan; 500000.0; `warn];
  registerAlertRule[`exposureCritical; `exposure; `greaterThan; 1000000.0; `critical];
  registerAlertRule[`orderFlowWarn; `orderFlow; `greaterThan; 100.0; `warn];

  -1 "  Alert engine initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Alert Rule Management
/ ═══════════════════════════════════════════════════════════════════

/ Generate next alert rule ID
nextAlertId:{[]
  current:first .risk.alertIdGen`nextId;
  update nextId:current + 1j from `.risk.alertIdGen;
  current
 };

/ Register alert rule
registerAlertRule:{[ruleName;metric;condition;threshold;severity]
  ruleId:nextAlertId[];
  rows:0!.risk.alertRules;
  rows,:enlist `ruleId`ruleName`metric`condition`threshold`severity`enabled`lastTriggered!(ruleId;ruleName;metric;condition;threshold;severity;1b;0Np);
  `.risk.alertRules set `ruleId xkey rows;
  ruleId
 };

/ Enable/disable alert rule
setAlertRuleEnabled:{[ruleId;isEnabled]
  rows:0!.risk.alertRules;
  rows:update enabled:isEnabled from rows where ruleId=ruleId;
  `.risk.alertRules set `ruleId xkey rows;
 };

/ Update alert rule threshold
updateAlertThreshold:{[ruleId;newThreshold]
  rows:0!.risk.alertRules;
  rows:update threshold:newThreshold from rows where ruleId=ruleId;
  `.risk.alertRules set `ruleId xkey rows;
 };

/ ═══════════════════════════════════════════════════════════════════
/ Alert Evaluation
/ ═══════════════════════════════════════════════════════════════════

/ Get current metric values
getCurrentMetrics:{[]
  / Get P&L
  pnlMetric:first .risk.intradayPnL`totalPnL;

  / Get exposure
  exposureMetric:first .risk.exposureSummary`totalGross;

  / Get order flow rate
  orderFlowMetric:0.0;
  latestOrderFlow:first -1#select from .risk.orderFlowMetrics;
  if[not ()~latestOrderFlow; orderFlowMetric:latestOrderFlow`ordersPerSecond];

  / Return metrics dictionary
  `pnl`exposure`orderFlow!(pnlMetric;exposureMetric;orderFlowMetric)
 };

/ Evaluate condition
evaluateCondition:{[condition;actualValue;threshold]
  $[condition=`greaterThan; actualValue > threshold;
    condition=`lessThan; actualValue < threshold;
    condition=`equals; actualValue = threshold;
    0b]
 };

/ Check alert rules (run every 1s via .z.ts)
checkAlertRules:{[]
  / Get current metrics
  metrics:getCurrentMetrics[];

  / Check each enabled rule
  {[rule;metrics]
    metric:rule`metric;

    / Skip if metric not available
    if[not metric in key metrics; :()];

    currentValue:metrics metric;
    threshold:rule`threshold;
    condition:rule`condition;

    / Evaluate condition
    triggered:evaluateCondition[condition;currentValue;threshold];

    if[triggered;
      / Log alert
      `.risk.alertHistory insert (.z.p;rule`ruleId;rule`ruleName;metric;currentValue;threshold;rule`severity;0b;`;0Np);

      / Send to alert handlers based on severity
      sendAlert[rule;currentValue];

      / Update last triggered
      rows:0!.risk.alertRules;
      rows:update lastTriggered:.z.p from rows where ruleId=rule`ruleId;
      `.risk.alertRules set `ruleId xkey rows;
    ];
   }[;metrics] each 0!select from .risk.alertRules where enabled=1b;
 };

/ ═══════════════════════════════════════════════════════════════════
/ Alert Handlers
/ ═══════════════════════════════════════════════════════════════════

/ Send alert (routing based on severity)
sendAlert:{[rule;actualValue]
  severity:rule`severity;
  ruleName:rule`ruleName;
  metric:rule`metric;
  threshold:rule`threshold;

  / Log to console
  -1 "ALERT [",string[severity],"] ",string[ruleName]," triggered: ",string[metric],"=",string[actualValue]," (threshold=",string[threshold],")";

  / Escalate based on severity
  $[severity=`warn;
    / Warn: log only
    ();
    severity=`halt;
    / Halt: activate emergency stop
    .risk.activateEmergencyStop[ruleName;`alertEngine];
    severity=`critical;
    / Critical: emergency stop + log critical event
    [.risk.activateEmergencyStop[ruleName;`alertEngine];
     .risk.logRiskEvent[.z.p;`criticalAlert;`;`;`;`rule`metric`value!(ruleName;metric;actualValue);`halt;`critical]];
    ()
  ];

  / Publish alert to UI (if .u.pub exists)
  if[not ()~key `.u.pub;
    .u.pub[`alert; (.z.p;ruleName;metric;actualValue;threshold;severity)];
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Alert Acknowledgment
/ ═══════════════════════════════════════════════════════════════════

/ Acknowledge alert
acknowledgeAlert:{[alertIndex;user]
  update acknowledged:1b, acknowledgedBy:user, acknowledgedAt:.z.p from `.risk.alertHistory where i=alertIndex;
 };

/ Get unacknowledged alerts
getUnacknowledgedAlerts:{[]
  select from .risk.alertHistory where not acknowledged
 };

/ ═══════════════════════════════════════════════════════════════════
/ Query Functions (for UI)
/ ═══════════════════════════════════════════════════════════════════

/ Get all alert rules
alert.rules:{[]
  select from .risk.alertRules
 };

/ Get alert history (last N)
alert.history:{[n]
  -1 * n sublist reverse select from .risk.alertHistory
 };

/ Configure alert rule
alert.configure:{[metric;threshold;severity]
  / Create or update rule
  ruleName:`$"alert_",string[metric],"_",string[severity];
  condition:$[severity in `warn`halt`critical; `lessThan; `greaterThan];
  registerAlertRule[ruleName;metric;condition;threshold;severity]
 };

/ Fire alert manually (for testing)
alert.fire:{[alertId;severity;message]
  ruleName:`manualAlert;
  metric:`manual;
  actualValue:0.0;
  threshold:0.0;

  `.risk.alertHistory insert (.z.p;alertId;ruleName;metric;actualValue;threshold;severity;0b;`;0Np);

  -1 "MANUAL ALERT [",string[severity],"]: ",message;
 };

/ Acknowledge alert by index
alert.acknowledge:{[alertIndex;user]
  acknowledgeAlert[alertIndex;user]
 };

\d .
