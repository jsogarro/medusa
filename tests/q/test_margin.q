/ ============================================================================
/ test_margin.q - Reg T Margin Requirements Tests
/ ============================================================================

/ Load required modules
/ Change to src/q directory for module loading
system "cd ",getenv[`PWD],"/src/q"
\l schema/init.q
\l risk/init.q

/ Initialize schemas and risk system
.qg.loadAllSchemas[];
.qg.initAllTables[];
.risk.init[];

/ Test suite
.test.margin:{
  tests:();

  / ═══════════════════════════════════════════════════════════════════
  / Setup
  / ═══════════════════════════════════════════════════════════════════

  -1 "\nTesting Margin Requirements...";

  / Initialize
  .risk.initMargin[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 1: Initial state
  / ═══════════════════════════════════════════════════════════════════

  test1:{
    status:.risk.marginStatus[];
    result:status[`equity] = 0.0;
    msg:"Initial equity = 0";
    (result;msg)
  };
  tests,:enlist test1[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 2: Calculate initial margin (50% for equities)
  / ═══════════════════════════════════════════════════════════════════

  test2:{
    / Order: Buy 100 shares at $150
    margin:.risk.calcMarginRequirement[`AAPL;100.0;150.0];
    expected:100.0 * 150.0 * 0.5;  / 50% of $15,000 = $7,500
    result:margin = expected;
    msg:"Initial margin = 50% of notional ($7,500)";
    (result;msg)
  };
  tests,:enlist test2[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 3: Calculate maintenance margin (30% house requirement)
  / ═══════════════════════════════════════════════════════════════════

  test3:{
    / Position: 100 shares at $150
    maintMargin:.risk.calcMaintenanceMargin[`AAPL;100.0;150.0];
    expected:100.0 * 150.0 * 0.3;  / 30% of $15,000 = $4,500
    result:maintMargin = expected;
    msg:"Maintenance margin = 30% of notional ($4,500)";
    (result;msg)
  };
  tests,:enlist test3[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 4: Crypto bypasses margin (no margin for crypto)
  / ═══════════════════════════════════════════════════════════════════

  test4:{
    margin:.risk.calcMarginRequirement[`BTCUSD;1.0;50000.0];
    result:margin = 0.0;
    msg:"Crypto orders bypass margin calculation";
    (result;msg)
  };
  tests,:enlist test4[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 5: Sufficient buying power
  / ═══════════════════════════════════════════════════════════════════

  test5:{
    / Set buying power to $20,000
    .risk.marginState[`buyingPower]:20000.0;
    .risk.marginState[`equity]:15000.0;

    / Order requires $7,500 margin (buy 100 @ $150)
    checkResult:.risk.checkMarginAvailable[`AAPL;100.0;150.0];
    passed:checkResult 0;
    msg:"Order passes with sufficient buying power ($20k > $7.5k)";
    (passed;msg)
  };
  tests,:enlist test5[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 6: Insufficient buying power
  / ═══════════════════════════════════════════════════════════════════

  test6:{
    / Set buying power to $5,000 (insufficient)
    .risk.marginState[`buyingPower]:5000.0;

    / Order requires $7,500 margin
    checkResult:.risk.checkMarginAvailable[`AAPL;100.0;150.0];
    rejected:not checkResult 0;
    reason:checkResult 1;

    result:rejected and reason=`insufficientMargin;
    msg:"Order rejected with insufficient buying power ($5k < $7.5k)";
    (result;msg)
  };
  tests,:enlist test6[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 7: Margin call detection (equity < maintenance)
  / ═══════════════════════════════════════════════════════════════════

  test7:{
    / Simulate account state: equity drops below maintenance margin
    account:`equity`buying_power`cash`maintenance_margin!(5000.0;2000.0;3000.0;6000.0);
    .risk.updateMarginState[account];

    / Check margin call flag
    state:first .risk.marginState;
    inCall:state`marginCallActive;

    / Check history
    calls:select from .risk.marginCallHistory where callType=`maintenance;
    logged:count[calls] > 0;

    result:inCall and logged;
    msg:"Margin call detected when equity < maintenance ($5k < $6k)";
    (result;msg)
  };
  tests,:enlist test7[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 8: Margin call resolution
  / ═══════════════════════════════════════════════════════════════════

  test8:{
    / Deposit funds to resolve margin call
    account:`equity`buying_power`cash`maintenance_margin!(10000.0;8000.0;7000.0;6000.0);
    .risk.updateMarginState[account];

    / Check margin call cleared
    state:first .risk.marginState;
    cleared:not state`marginCallActive;

    / Check history updated
    calls:select from .risk.marginCallHistory where callType=`maintenance, resolved;
    resolved:count[calls] > 0;

    result:cleared and resolved;
    msg:"Margin call resolved when equity > maintenance ($10k > $6k)";
    (result;msg)
  };
  tests,:enlist test8[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 9: Buying power calculation (2:1 leverage)
  / ═══════════════════════════════════════════════════════════════════

  test9:{
    / Account: $10k equity, $2k margin used
    bp:.risk.calcBuyingPower[10000.0;2000.0];
    expected:2.0 * 10000.0 - 2000.0;  / 2*10k - 2k = $18k
    result:bp = expected;
    msg:"Buying power = 2*equity - margin_used ($18k)";
    (result;msg)
  };
  tests,:enlist test9[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 10: Margin disabled bypasses checks
  / ═══════════════════════════════════════════════════════════════════

  test10:{
    / Disable margin
    .risk.marginConfig[`enabled]:0b;

    / Set buying power to $0 (would normally reject)
    .risk.marginState[`buyingPower]:0.0;

    / Should pass even with no buying power
    checkResult:.risk.checkMarginAvailable[`AAPL;100.0;150.0];
    passed:checkResult 0;
    msg:"Margin check bypassed when disabled";
    (passed;msg)
  };
  tests,:enlist test10[];

  / ═══════════════════════════════════════════════════════════════════
  / Results
  / ═══════════════════════════════════════════════════════════════════

  passed:sum tests[;0];
  total:count tests;
  -1 "\nMargin Tests: ",string[passed],"/",string[total]," passed";

  if[passed < total;
    -1 "\nFailed tests:";
    failedIdx:where not tests[;0];
    {-1 "  - ",x} each tests[failedIdx;1];
  ];

  passed = total
 };

/ Run tests
.test.margin[]

/ Exit with appropriate code
exit $[.test.margin[];0;1]
