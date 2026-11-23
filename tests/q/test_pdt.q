/ ============================================================================
/ test_pdt.q - Pattern Day Trader Rule Tests
/ ============================================================================

/ Bootstrap minimal environment
system "cd ",getenv[`PWD],"/src/q"

/ Manually define isEquity/isCrypto for testing
.schema.isEquity:{[sym] not sym in `BTCUSD`ETHUSD`SOLUSD};
.schema.isCrypto:{[sym] sym in `BTCUSD`ETHUSD`SOLUSD};

/ Load calendar
\l exchange/calendar.q

/ Define risk namespace
\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ PDT State Tables (copied from pdt.q)
/ ═══════════════════════════════════════════════════════════════════

pdtConfig:([]
  enabled:enlist 1b;
  accountValue:enlist 10000.0;
  minAccountValue:enlist 25000.0;
  dayTradeWindow:enlist 5i;
  maxDayTrades:enlist 3i;
  lastUpdate:enlist .z.p
 );

dayTradeHistory:([]
  time:`timestamp$();
  date:`date$();
  sym:`symbol$();
  openSide:`symbol$();
  closeSide:`symbol$();
  openQty:`float$();
  closeQty:`float$();
  pnl:`float$()
 );

dayTradeSummary:([date:`date$()]
  dayTradeCount:`int$();
  firstTrade:`timestamp$();
  lastTrade:`timestamp$()
 );

pdtAlerts:([]
  time:`timestamp$();
  alertType:`symbol$();
  dayTradeCount:`int$();
  accountValue:`float$();
  minAccountValue:`float$();
  message:()
 );

\d .

/ Now load PDT module
\l risk/pdt.q

/ Initialize
.risk.initPDT[];

/ Test suite
.test.pdt:{
  tests:();

  -1 "\nTesting PDT Rule...";

  / Test 1: Initial state
  test1:{
    status:.risk.pdtStatus[];
    result:status[`currentDayTrades] = 0i;
    msg:"Initial day trade count = 0";
    (result;msg)
  };
  tests,:enlist test1[];

  / Test 2: Account above $25k threshold
  test2:{
    .risk.updateAccountValue[30000.0];
    result:.risk.checkPDT[`AAPL;`buy;100.0];
    passed:result 0;
    msg:"PDT check passes when account >= $25k";
    (passed;msg)
  };
  tests,:enlist test2[];

  / Test 3: Account below $25k, no day trades
  test3:{
    .risk.updateAccountValue[10000.0];
    result:.risk.checkPDT[`AAPL;`buy;100.0];
    passed:result 0;
    msg:"PDT check passes with $10k account and 0 day trades";
    (passed;msg)
  };
  tests,:enlist test3[];

  / Test 4: Record 3 day trades
  test4:{
    .risk.recordDayTrade[`AAPL;`buy;`sell;100.0;100.0;50.0];
    .risk.recordDayTrade[`TSLA;`buy;`sell;50.0;50.0;25.0];
    .risk.recordDayTrade[`MSFT;`buy;`sell;75.0;75.0;30.0];
    count:.risk.getDayTradeCount[];
    result:count = 3i;
    msg:"3 day trades recorded correctly";
    (result;msg)
  };
  tests,:enlist test4[];

  / Test 5: Warning at 3 day trades
  test5:{
    checkResult:.risk.checkPDT[`NVDA;`buy;100.0];
    passed:checkResult 0;
    alerts:select from .risk.pdtAlerts where alertType=`warning;
    warned:count[alerts] > 0;
    result:passed and warned;
    msg:"Warning logged at 3 day trades, order allowed";
    (result;msg)
  };
  tests,:enlist test5[];

  / Test 6: Breach at 4th day trade
  test6:{
    .risk.recordDayTrade[`NVDA;`buy;`sell;100.0;100.0;40.0];
    checkResult:.risk.checkPDT[`GOOGL;`buy;100.0];
    rejected:not checkResult 0;
    reason:checkResult 1;
    result:rejected and reason=`pdtBreach;
    msg:"4th day trade triggers PDT breach";
    (result;msg)
  };
  tests,:enlist test6[];

  / Test 7: Crypto bypasses PDT
  test7:{
    result:.risk.checkPDT[`BTCUSD;`buy;1.0];
    passed:result 0;
    msg:"Crypto orders bypass PDT rule";
    (passed;msg)
  };
  tests,:enlist test7[];

  / Test 8: Reset clears state
  test8:{
    .risk.resetDayTrades[];
    count:.risk.getDayTradeCount[];
    result:count = 0i;
    msg:"Reset clears day trade history";
    (result;msg)
  };
  tests,:enlist test8[];

  / Results
  passed:sum tests[;0];
  total:count tests;
  -1 "\nPDT Tests: ",string[passed],"/",string[total]," passed";

  if[passed < total;
    -1 "\nFailed tests:";
    failedIdx:where not tests[;0];
    {-1 "  - ",x} each tests[failedIdx;1];
  ];

  passed = total
 };

/ Run tests
.test.pdt[]

/ Exit with appropriate code
exit $[.test.pdt[];0;1]
