/ ============================================================================
/ test_settlement.q - T+1 Settlement and Freeriding Tests
/ ============================================================================

/ Load required modules
/ Change to src/q directory for module loading
system "cd ",getenv[`PWD],"/src/q"
\l schema/init.q
\l exchange/calendar.q
\l risk/init.q

/ Initialize schemas and risk system
.qg.loadAllSchemas[];
.qg.initAllTables[];
.risk.init[];

/ Test suite
.test.settlement:{
  tests:();

  / ═══════════════════════════════════════════════════════════════════
  / Setup
  / ═══════════════════════════════════════════════════════════════════

  -1 "\nTesting Settlement (T+1) and Freeriding...";

  / Initialize
  .risk.initSettlement[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 1: Initial state
  / ═══════════════════════════════════════════════════════════════════

  test1:{
    status:.risk.settlementStatus[];
    result:status[`unsettledCash] = 0.0;
    msg:"Initial unsettled cash = 0";
    (result;msg)
  };
  tests,:enlist test1[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 2: Record settlement (T+1)
  / ═══════════════════════════════════════════════════════════════════

  test2:{
    / Record a buy (negative cash proceeds)
    .risk.recordSettlement[.z.d;`AAPL;`buy;100.0;150.0];

    / Check tracking table
    tracking:select from .risk.settlementTracking;
    recorded:count[tracking] = 1;

    / Check settlement date is T+1 business day
    settleDate:first tracking`settleDate;
    expectedSettleDate:.exchange.calendar.getNextTradingDay[.z.d];
    correctDate:settleDate = expectedSettleDate;

    result:recorded and correctDate;
    msg:"Settlement recorded with T+1 settle date";
    (result;msg)
  };
  tests,:enlist test2[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 3: Unsettled cash accumulation (buy)
  / ═══════════════════════════════════════════════════════════════════

  test3:{
    / Buy 100 @ $150 = -$15,000 cash proceeds
    unsettled:.risk.getUnsettledCash[];
    expected:neg 100.0 * 150.0;
    result:unsettled = expected;
    msg:"Unsettled cash = -$15,000 from buy";
    (result;msg)
  };
  tests,:enlist test3[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 4: Unsettled cash accumulation (sell)
  / ═══════════════════════════════════════════════════════════════════

  test4:{
    / Record a sell (positive cash proceeds)
    .risk.recordSettlement[.z.d;`TSLA;`sell;50.0;200.0];

    / Unsettled cash should be -$15k + $10k = -$5k
    unsettled:.risk.getUnsettledCash[];
    expected:(neg 100.0 * 150.0) + (50.0 * 200.0);  / -15k + 10k = -5k
    result:unsettled = expected;
    msg:"Unsettled cash = -$5,000 (buy -$15k, sell +$10k)";
    (result;msg)
  };
  tests,:enlist test4[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 5: Crypto bypasses settlement (instant settlement)
  / ═══════════════════════════════════════════════════════════════════

  test5:{
    / Record crypto trade
    countBefore:count .risk.settlementTracking;
    .risk.recordSettlement[.z.d;`BTCUSD;`buy;1.0;50000.0];
    countAfter:count .risk.settlementTracking;

    / Should not record (crypto settles instantly)
    result:countBefore = countAfter;
    msg:"Crypto trades bypass settlement tracking";
    (result;msg)
  };
  tests,:enlist test5[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 6: Freeriding detection (sell before settlement)
  / ═══════════════════════════════════════════════════════════════════

  test6:{
    / Setup: Buy AAPL, then sell before settlement
    / (Already have buy from test 2)

    / Try to sell more than unsettled position
    checkResult:.risk.checkFreeridingViolation[`AAPL;`sell;150.0;150.0];
    rejected:not checkResult 0;
    reason:checkResult 1;

    result:rejected and reason=`freeridingViolation;
    msg:"Freeriding violation detected (sell 150 > buy 100)";
    (result;msg)
  };
  tests,:enlist test6[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 7: Freeriding allowed for settled position
  / ═══════════════════════════════════════════════════════════════════

  test7:{
    / Mark buy as settled
    update settled:1b, settledAt:.z.p from `.risk.settlementTracking where sym=`AAPL, side=`buy;

    / Now sell should pass (position settled)
    checkResult:.risk.checkFreeridingViolation[`AAPL;`sell;100.0;150.0];
    passed:checkResult 0;
    msg:"Sell allowed after settlement";
    (passed;msg)
  };
  tests,:enlist test7[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 8: Good faith violation (buy with unsettled funds)
  / ═══════════════════════════════════════════════════════════════════

  test8:{
    / Setup: Sell generates unsettled funds
    .risk.recordSettlement[.z.d;`MSFT;`sell;100.0;300.0];

    / Set cash balance to $0 (force use of unsettled funds)
    .risk.marginState[`cash]:0.0;

    / Try to buy with unsettled funds
    checkResult:.risk.checkGoodFaithViolation[`NVDA;`buy;50.0;200.0];
    passed:checkResult 0;  / Should warn but allow

    / Check violation was logged
    violations:select from .risk.freeridingViolations where violationType=`goodFaith;
    logged:count[violations] > 0;

    result:passed and logged;
    msg:"Good faith violation logged but order allowed";
    (result;msg)
  };
  tests,:enlist test8[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 9: Good faith restriction (3 violations)
  / ═══════════════════════════════════════════════════════════════════

  test9:{
    / Record 2 more good faith violations (total 3)
    .risk.checkGoodFaithViolation[`GOOGL;`buy;50.0;150.0];
    .risk.checkGoodFaithViolation[`AMZN;`buy;50.0;180.0];

    / Check restriction active
    summary:first .risk.goodFaithSummary;
    restricted:summary`restricted;

    / Next order should be rejected
    checkResult:.risk.checkGoodFaithViolation[`META;`buy;50.0;250.0];
    rejected:not checkResult 0;
    reason:checkResult 1;

    result:restricted and rejected and reason=`goodFaithRestricted;
    msg:"Good faith restriction after 3 violations";
    (result;msg)
  };
  tests,:enlist test9[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 10: Settlement processing (daily)
  / ═══════════════════════════════════════════════════════════════════

  test10:{
    / Process settlements
    .risk.processSettlements[];

    / All trades settling today or earlier should be marked settled
    unsettled:select from .risk.settlementTracking where not settled, settleDate <= .z.d;
    result:count[unsettled] = 0;
    msg:"Settlement processing marks trades as settled";
    (result;msg)
  };
  tests,:enlist test10[];

  / ═══════════════════════════════════════════════════════════════════
  / Test 11: Settlement disabled bypasses checks
  / ═══════════════════════════════════════════════════════════════════

  test11:{
    / Disable settlement
    .risk.settlementConfig[`enabled]:0b;

    / Should bypass freeriding check
    checkResult:.risk.checkFreeridingViolation[`AAPL;`sell;1000.0;150.0];
    passed:checkResult 0;
    msg:"Settlement checks bypassed when disabled";
    (passed;msg)
  };
  tests,:enlist test11[];

  / ═══════════════════════════════════════════════════════════════════
  / Results
  / ═══════════════════════════════════════════════════════════════════

  passed:sum tests[;0];
  total:count tests;
  -1 "\nSettlement Tests: ",string[passed],"/",string[total]," passed";

  if[passed < total;
    -1 "\nFailed tests:";
    failedIdx:where not tests[;0];
    {-1 "  - ",x} each tests[failedIdx;1];
  ];

  passed = total
 };

/ Run tests
.test.settlement[]

/ Exit with appropriate code
exit $[.test.settlement[];0;1]
