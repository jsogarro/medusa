/ Tests for Correlation Limits Module

\l src/q/risk/init.q
\l tests/q/test_framework.q

/ ═══════════════════════════════════════════════════════════════════
/ Correlation Limits Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== CORRELATION LIMITS TESTS ===";

/ Test 1: Initialization
test_correlationLimits_init:{[]
  .risk.initCorrelationGroups[];

  / Check default groups exist
  .test.assert["correlationGroups initialized"; 4 = count .risk.correlationGroups];
  .test.assert["btcGroup exists"; `btcGroup in exec groupId from .risk.correlationGroups];
  .test.assert["ethGroup exists"; `ethGroup in exec groupId from .risk.correlationGroups];
  .test.assert["altGroup exists"; `altGroup in exec groupId from .risk.correlationGroups];
  .test.assert["stableGroup exists"; `stableGroup in exec groupId from .risk.correlationGroups];

  / Check default limits
  .test.assertEqual["btcGroup limit"; 250000.0; first exec maxExposure from .risk.correlationGroups where groupId=`btcGroup];
  .test.assertEqual["ethGroup limit"; 200000.0; first exec maxExposure from .risk.correlationGroups where groupId=`ethGroup];
 };

/ Test 2: Check correlation limit - pass
test_correlationLimits_pass:{[]
  .risk.initCorrelationGroups[];

  / Small order in btcGroup (BTCUSD is member)
  result:.risk.checkCorrelationLimit[`BTCUSD;1.0;50000.0];
  .test.assert["Check passes"; result 0];
  .test.assertEqual["Reason empty"; `; result 1];
 };

/ Test 3: Check correlation limit - fail
test_correlationLimits_breach:{[]
  .risk.initCorrelationGroups[];

  / Large order that exceeds btcGroup limit (250K)
  result:.risk.checkCorrelationLimit[`BTCUSD;10.0;50000.0];
  .test.assert["Check fails"; not result 0];
  .test.assertEqual["Reason is correlationGroupLimitExceeded"; `correlationGroupLimitExceeded; result 1];
 };

/ Test 4: Update correlation exposure
test_correlationLimits_update:{[]
  .risk.initCorrelationGroups[];

  / Add exposure
  .risk.updateCorrelationExposure[`BTCUSD;1.0;50000.0];

  / Verify exposure updated
  exposure:first exec currentExposure from .risk.correlationGroups where groupId=`btcGroup;
  .test.assert["Exposure updated"; exposure > 0.0];
  .test.assertEqual["Exposure equals notional"; 50000.0; exposure];
 };

/ Test 5: Symbol not in any group
test_correlationLimits_noGroup:{[]
  .risk.initCorrelationGroups[];

  / Symbol not in any group should pass
  result:.risk.checkCorrelationLimit[`XYZUSD;1.0;10000.0];
  .test.assert["Check passes for ungrouped symbol"; result 0];
 };

/ Test 6: Set group limit
test_correlationLimits_setLimit:{[]
  .risk.initCorrelationGroups[];

  / Change limit
  .risk.setCorrelationGroupLimit[`btcGroup;500000.0];

  / Verify it was changed
  .test.assertEqual["Limit updated"; 500000.0; first exec maxExposure from .risk.correlationGroups where groupId=`btcGroup];
 };

/ Test 7: Event logging
test_correlationLimits_events:{[]
  .risk.initCorrelationGroups[];

  / Clear events
  delete from `.risk.correlationEvents;

  / Perform updates
  .risk.updateCorrelationExposure[`BTCUSD;1.0;50000.0];

  / Verify events logged
  .test.assert["Events logged"; 1 = count .risk.correlationEvents];
  .test.assertEqual["Action is updated"; `updated; first exec action from .risk.correlationEvents];
 };

/ Test 8: Multiple symbols in same group
test_correlationLimits_multiSymbol:{[]
  .risk.initCorrelationGroups[];

  / Add exposure for BTCUSD
  .risk.updateCorrelationExposure[`BTCUSD;1.0;50000.0];

  / Add exposure for BTCEUR (also in btcGroup)
  .risk.updateCorrelationExposure[`BTCEUR;1.0;30000.0];

  / Verify total exposure is sum
  exposure:first exec currentExposure from .risk.correlationGroups where groupId=`btcGroup;
  .test.assertEqual["Total exposure"; 80000.0; exposure];
 };

if[not `medusaRunAll in key `.; exit .test.run[`.]];
