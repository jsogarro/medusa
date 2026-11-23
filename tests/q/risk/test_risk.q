/ Comprehensive Tests for Risk Management Module
/ Tests schema, position limits, order size limits, exposure limits,
/ drawdown monitoring, emergency stop, and validation pipeline

/ Change to src/q/ directory so risk/init.q can resolve \l paths
system "cd src/q";  / run from the repo root

/ Load the risk management module
\l risk/init.q

/ ═══════════════════════════════════════════════════════════════════
/ Test Framework
/ ═══════════════════════════════════════════════════════════════════

.tst.passed:0;
.tst.failed:0;
.tst.errors:();

.tst.assert:{[cond;msg]
  $[cond;
    [.tst.passed+:1; -1 "  PASS: ",msg];
    [.tst.failed+:1; .tst.errors,:enlist msg; -1 "  FAIL: ",msg]
  ];
 };

.tst.assertEqual:{[expected;actual;msg]
  .tst.assert[expected~actual;msg," (expected: ",(-3!expected),", got: ",(-3!actual),")"];
 };

.tst.run:{[]
  -1 "";
  -1 "========================================";
  -1 "  Test Results";
  -1 "========================================";
  -1 "  Passed: ",string .tst.passed;
  -1 "  Failed: ",string .tst.failed;
  if[0<count .tst.errors;
    -1 "  Errors:";
    {-1 "    - ",x} each .tst.errors;
  ];
  -1 "========================================";
  if[.tst.failed>0; exit 1];
  -1 "All tests passed!";
 };

/ ═══════════════════════════════════════════════════════════════════
/ 1. Schema & Initialization Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n1. SCHEMA & INITIALIZATION TESTS";
-1 "=====================================";

.risk.init[];

/ Check tables exist with correct schemas
.tst.assert[.Q.qt .risk.positionLimits;"positionLimits table exists"];
.tst.assert[.Q.qt .risk.globalPositionLimits;"globalPositionLimits table exists"];
.tst.assert[.Q.qt .risk.orderSizeLimits;"orderSizeLimits table exists"];
.tst.assert[.Q.qt .risk.globalOrderSizeLimits;"globalOrderSizeLimits table exists"];
.tst.assert[.Q.qt .risk.exposureLimits;"exposureLimits table exists"];
.tst.assert[.Q.qt .risk.globalExposureLimit;"globalExposureLimit table exists"];
.tst.assert[.Q.qt .risk.drawdownState;"drawdownState table exists"];
.tst.assert[.Q.qt .risk.emergencyStopState;"emergencyStopState table exists"];
.tst.assert[.Q.qt .risk.riskEvents;"riskEvents table exists"];

/ Check default global position limits
.tst.assertEqual[2;count .risk.globalPositionLimits;"Default global position limits set (2 symbols)"];
.tst.assert[`BTCUSD in exec sym from .risk.globalPositionLimits;"BTCUSD in default global limits"];
.tst.assert[`ETHUSD in exec sym from .risk.globalPositionLimits;"ETHUSD in default global limits"];

/ Check default global order size limits
.tst.assertEqual[1000j;first .risk.globalOrderSizeLimits`maxOrderQty;"Default global maxOrderQty is 1000"];
.tst.assertEqual[100000j;first .risk.globalOrderSizeLimits`maxDailyVolume;"Default global maxDailyVolume is 100000"];
.tst.assertEqual[0j;first .risk.globalOrderSizeLimits`dailyVolume;"Default global dailyVolume is 0"];

/ Check default global exposure limit
.tst.assertEqual[1000000.0;first .risk.globalExposureLimit`maxNotional;"Default global exposure limit is 1000000.0"];
.tst.assertEqual[0.0;first .risk.globalExposureLimit`currentNotional;"Default global exposure current is 0.0"];

/ Check default drawdown state
.tst.assertEqual[20.0;first exec maxDrawdownPct from .risk.drawdownState;"Default max drawdown is 20%"];
.tst.assertEqual[0b;first exec breached from .risk.drawdownState;"Default drawdown breached is false"];

/ Check default emergency stop state
.tst.assertEqual[0b;first exec active from .risk.emergencyStopState;"Default emergency stop inactive"];

/ Check risk events table is empty
.tst.assertEqual[0;count .risk.riskEvents;"Risk events table starts empty"];

/ ═══════════════════════════════════════════════════════════════════
/ 2. Position Limits Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n2. POSITION LIMITS TESTS";
-1 "=========================";

.risk.init[];

/ Test setPositionLimit
.risk.setPositionLimit[`strategy1;`BTCUSD;5j;5j];
row:first select from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.tst.assertEqual[5j;row`maxLongQty;"setPositionLimit sets maxLongQty"];
.tst.assertEqual[5j;row`maxShortQty;"setPositionLimit sets maxShortQty"];
.tst.assertEqual[0j;row`currentPosition;"setPositionLimit initializes currentPosition to 0"];

/ Test checkPositionLimit passes within limits
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;3j];
.tst.assertEqual[1b;result 0;"checkPositionLimit passes for order within limits"];

/ Test checkPositionLimit fails exceeding long limit
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;10j];
.tst.assertEqual[0b;result 0;"checkPositionLimit fails for buy exceeding long limit"];
.tst.assertEqual[`strategyLongLimitExceeded;result 1;"Reason is strategyLongLimitExceeded"];

/ Test checkPositionLimit fails exceeding short limit
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`sell;10j];
.tst.assertEqual[0b;result 0;"checkPositionLimit fails for sell exceeding short limit"];
.tst.assertEqual[`strategyShortLimitExceeded;result 1;"Reason is strategyShortLimitExceeded"];

/ Test updatePosition increments correctly
.risk.updatePosition[`strategy1;`BTCUSD;3j];
.tst.assertEqual[3j;first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;"updatePosition increments position (buy)"];

.risk.updatePosition[`strategy1;`BTCUSD;-2j];
.tst.assertEqual[1j;first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;"updatePosition decrements position (sell)"];

/ Test boundary: position at exactly the limit passes
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;5j;5j];
.risk.updatePosition[`strategy1;`BTCUSD;4j];
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;1j];
.tst.assertEqual[1b;result 0;"Position at exactly limit passes (boundary)"];

/ Test boundary: position 1 over the limit fails
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;2j];
.tst.assertEqual[0b;result 0;"Position 1 over limit fails (boundary)"];

/ Test global position limits checked
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
/ Global default for BTCUSD is 10 long
.risk.updatePosition[`strategy1;`BTCUSD;9j];
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;2j];
.tst.assertEqual[0b;result 0;"Global position limit checked after strategy limit"];
.tst.assertEqual[`globalLongLimitExceeded;result 1;"Reason is globalLongLimitExceeded"];

/ ═══════════════════════════════════════════════════════════════════
/ 3. Order Size Limits Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n3. ORDER SIZE LIMITS TESTS";
-1 "===========================";

.risk.init[];

/ Test setOrderSizeLimit
.risk.setOrderSizeLimit[`strategy1;100j;5000j];
row:first select from .risk.orderSizeLimits where strategy=`strategy1;
.tst.assertEqual[100j;row`maxOrderQty;"setOrderSizeLimit sets maxOrderQty"];
.tst.assertEqual[5000j;row`maxDailyVolume;"setOrderSizeLimit sets maxDailyVolume"];
.tst.assertEqual[0j;row`dailyVolume;"setOrderSizeLimit initializes dailyVolume to 0"];

/ Test checkOrderSizeLimit passes within limits
result:.risk.checkOrderSizeLimit[`strategy1;50j];
.tst.assertEqual[1b;result 0;"checkOrderSizeLimit passes for order within limits"];

/ Test checkOrderSizeLimit fails for order exceeding max
result:.risk.checkOrderSizeLimit[`strategy1;200j];
.tst.assertEqual[0b;result 0;"checkOrderSizeLimit fails for order exceeding max"];
.tst.assertEqual[`strategyOrderSizeExceeded;result 1;"Reason is strategyOrderSizeExceeded"];

/ Test daily volume accumulates correctly
.risk.updateDailyVolume[`strategy1;1000j];
.tst.assertEqual[1000j;first exec dailyVolume from .risk.orderSizeLimits where strategy=`strategy1;"Daily volume accumulates correctly"];

.risk.updateDailyVolume[`strategy1;2000j];
.tst.assertEqual[3000j;first exec dailyVolume from .risk.orderSizeLimits where strategy=`strategy1;"Daily volume accumulates multiple times"];

/ Test checkOrderSizeLimit fails when daily volume would be exceeded
/ Current volume is 3000, max is 5000
/ Need order that: (a) doesn't exceed maxOrderQty=100, and (b) makes 3000+order>5000
/ So we need order >= 2001. But that exceeds maxOrderQty.
/ Solution: update limits to have higher maxOrderQty but same maxDaily
update maxOrderQty:3000j from `.risk.orderSizeLimits where strategy=`strategy1;
result:.risk.checkOrderSizeLimit[`strategy1;2100j];
.tst.assertEqual[0b;result 0;"checkOrderSizeLimit fails when daily volume exceeded"];
.tst.assertEqual[`strategyDailyVolumeExceeded;result 1;"Reason is strategyDailyVolumeExceeded"];

/ Test global order size limits checked
.risk.init[];
.risk.setOrderSizeLimit[`strategy1;2000j;200000j];
/ Global default maxOrderQty is 1000
result:.risk.checkOrderSizeLimit[`strategy1;1500j];
.tst.assertEqual[0b;result 0;"Global order size limit checked"];
.tst.assertEqual[`globalOrderSizeExceeded;result 1;"Reason is globalOrderSizeExceeded"];

/ Test resetDailyVolume clears counters
.risk.init[];
.risk.setOrderSizeLimit[`strategy1;100j;5000j];
.risk.updateDailyVolume[`strategy1;1000j];
.risk.resetDailyVolume[];
.tst.assertEqual[0j;first exec dailyVolume from .risk.orderSizeLimits where strategy=`strategy1;"resetDailyVolume clears strategy counter"];
.tst.assertEqual[0j;first .risk.globalOrderSizeLimits`dailyVolume;"resetDailyVolume clears global counter"];

/ ═══════════════════════════════════════════════════════════════════
/ 4. Exposure Limits Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n4. EXPOSURE LIMITS TESTS";
-1 "=========================";

.risk.init[];

/ Test setExposureLimit
.risk.setExposureLimit[`bitstamp;100000.0];
row:first select from .risk.exposureLimits where exchange=`bitstamp;
.tst.assertEqual[100000.0;row`maxNotional;"setExposureLimit sets maxNotional"];
.tst.assertEqual[0.0;row`currentNotional;"setExposureLimit initializes currentNotional to 0"];

/ Test checkExposureLimit passes within limits
result:.risk.checkExposureLimit[`bitstamp;10j;5000.0];
.tst.assertEqual[1b;result 0;"checkExposureLimit passes for order within limits"];

/ Test checkExposureLimit fails for exchange limit
.risk.updateExposure[`bitstamp;`BTCUSD;10j;9000.0];
result:.risk.checkExposureLimit[`bitstamp;5j;5000.0];
.tst.assertEqual[0b;result 0;"checkExposureLimit fails for exchange limit"];
.tst.assertEqual[`exchangeExposureLimitExceeded;result 1;"Reason is exchangeExposureLimitExceeded"];

/ Test global exposure limit checked
.risk.init[];
.risk.setExposureLimit[`bitstamp;2000000.0];
/ Global default is 1000000.0
.risk.updateExposure[`bitstamp;`BTCUSD;100j;9000.0];
/ currentNotional now 900000
result:.risk.checkExposureLimit[`bitstamp;20j;6000.0];
/ Would add 120000, total 1020000 > 1000000
.tst.assertEqual[0b;result 0;"checkExposureLimit fails for global limit"];
.tst.assertEqual[`globalExposureLimitExceeded;result 1;"Reason is globalExposureLimitExceeded"];

/ Test updateExposure increments correctly
.risk.init[];
.risk.setExposureLimit[`bitstamp;100000.0];
.risk.updateExposure[`bitstamp;`BTCUSD;5j;10000.0];
.tst.assertEqual[50000.0;first exec currentNotional from .risk.exposureLimits where exchange=`bitstamp;"updateExposure increments exchange exposure"];
.tst.assertEqual[50000.0;first .risk.globalExposureLimit`currentNotional;"updateExposure increments global exposure"];

/ Test recalcExposure resets and recalculates
.risk.init[];
.risk.setExposureLimit[`bitstamp;100000.0];
.risk.setExposureLimit[`coinbase;100000.0];
posTable:([] exchange:`bitstamp`bitstamp`coinbase; sym:`BTCUSD`ETHUSD`BTCUSD; qty:5 10 3j; lastPrice:50000.0 3000.0 50000.0);
.risk.recalcExposure[posTable];
.tst.assertEqual[280000.0;first exec currentNotional from .risk.exposureLimits where exchange=`bitstamp;"recalcExposure calculates bitstamp exposure"];
.tst.assertEqual[150000.0;first exec currentNotional from .risk.exposureLimits where exchange=`coinbase;"recalcExposure calculates coinbase exposure"];
.tst.assertEqual[430000.0;first .risk.globalExposureLimit`currentNotional;"recalcExposure calculates global exposure"];

/ ═══════════════════════════════════════════════════════════════════
/ 5. Drawdown Monitor Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n5. DRAWDOWN MONITOR TESTS";
-1 "==========================";

.risk.init[];

/ Test updatePnL tracks peak correctly
breached:.risk.updatePnL[10000.0];
.tst.assertEqual[10000.0;first exec peakPnL from .risk.drawdownState;"updatePnL sets initial peak"];
.tst.assertEqual[0b;breached;"No drawdown breach when PnL goes up"];

breached:.risk.updatePnL[15000.0];
.tst.assertEqual[15000.0;first exec peakPnL from .risk.drawdownState;"updatePnL updates peak on new high"];
.tst.assertEqual[0b;breached;"No breach on new peak"];

/ Test drawdown calculated correctly
breached:.risk.updatePnL[12000.0];
expectedDrawdown:100.0*(15000.0-12000.0)%15000.0;
.tst.assertEqual[expectedDrawdown;first exec drawdownPct from .risk.drawdownState;"Drawdown calculated correctly"];
.tst.assertEqual[0b;breached;"Drawdown below 20% does not breach"];

/ Test drawdown above threshold triggers breach
breached:.risk.updatePnL[10000.0];
actualDrawdown:first exec drawdownPct from .risk.drawdownState;
.tst.assert[actualDrawdown>20.0;"Drawdown exceeds 20% threshold"];
.tst.assertEqual[1b;breached;"Drawdown above threshold triggers breach"];
.tst.assertEqual[1b;first exec breached from .risk.drawdownState;"Drawdown state marked as breached"];

/ Test checkDrawdownHalt returns fail after breach
result:.risk.checkDrawdownHalt[];
.tst.assertEqual[0b;result 0;"checkDrawdownHalt fails after breach"];
.tst.assertEqual[`drawdownHaltActive;result 1;"Reason is drawdownHaltActive"];

/ Test setMaxDrawdown changes threshold
.risk.init[];
.risk.setMaxDrawdown[15.0];
.tst.assertEqual[15.0;first exec maxDrawdownPct from .risk.drawdownState;"setMaxDrawdown changes threshold"];

/ Test resetDrawdown clears state
.risk.init[];
.risk.updatePnL[10000.0];
.risk.updatePnL[5000.0];
.risk.resetDrawdown[];
.tst.assertEqual[0.0;first exec peakPnL from .risk.drawdownState;"resetDrawdown clears peakPnL"];
.tst.assertEqual[0.0;first exec currentPnL from .risk.drawdownState;"resetDrawdown clears currentPnL"];
.tst.assertEqual[0b;first exec breached from .risk.drawdownState;"resetDrawdown clears breached flag"];

/ ═══════════════════════════════════════════════════════════════════
/ 6. Emergency Stop Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n6. EMERGENCY STOP TESTS";
-1 "========================";

.risk.init[];

/ Test default state is inactive
.tst.assertEqual[0b;first exec active from .risk.emergencyStopState;"Default emergency stop inactive"];

/ Test checkEmergencyStop passes when inactive
result:.risk.checkEmergencyStop[];
.tst.assertEqual[1b;result 0;"checkEmergencyStop passes when inactive"];

/ Test activateEmergencyStop sets active state
.risk.activateEmergencyStop[`userRequest;`admin];
.tst.assertEqual[1b;first exec active from .risk.emergencyStopState;"activateEmergencyStop sets active"];
.tst.assertEqual[`admin;first exec activatedBy from .risk.emergencyStopState;"activateEmergencyStop records user"];
.tst.assertEqual[`userRequest;first exec reason from .risk.emergencyStopState;"activateEmergencyStop records reason"];

/ Test checkEmergencyStop fails when active
result:.risk.checkEmergencyStop[];
.tst.assertEqual[0b;result 0;"checkEmergencyStop fails when active"];
.tst.assertEqual[`emergencyStopActive;result 1;"Reason is emergencyStopActive"];

/ Test deactivateEmergencyStop clears active state
.risk.deactivateEmergencyStop[`admin];
.tst.assertEqual[0b;first exec active from .risk.emergencyStopState;"deactivateEmergencyStop clears active"];

/ Test checkEmergencyStop passes after deactivation
result:.risk.checkEmergencyStop[];
.tst.assertEqual[1b;result 0;"checkEmergencyStop passes after deactivation"];

/ Test activation logs risk event
.risk.init[];
initialCount:count .risk.riskEvents;
.risk.activateEmergencyStop[`test;`system];
.tst.assertEqual[initialCount+1;count .risk.riskEvents;"activateEmergencyStop logs risk event"];
lastEvent:last select from .risk.riskEvents;
.tst.assertEqual[`emergencyStop;lastEvent`eventType;"Event type is emergencyStop"];
.tst.assertEqual[`critical;lastEvent`severity;"Event severity is critical"];

/ ═══════════════════════════════════════════════════════════════════
/ 7. Pre-Trade Validation Pipeline Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n7. PRE-TRADE VALIDATION PIPELINE TESTS";
-1 "========================================";

.risk.init[];

/ Test validateOrder passes when all checks pass
update maxLongQty:100j from `.risk.globalPositionLimits where sym=`BTCUSD;
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;500000.0];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[1b;result 0;"validateOrder passes when all checks pass"];

/ Test validateOrder fails on emergency stop (first check)
.risk.init[];
.risk.activateEmergencyStop[`test;`admin];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[0b;result 0;"validateOrder fails on emergency stop"];
.tst.assertEqual[`emergencyStopActive;result 1;"Reason is emergencyStopActive"];

/ Test validateOrder fails on drawdown halt (second check)
.risk.init[];
.risk.updatePnL[10000.0];
.risk.updatePnL[5000.0];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[0b;result 0;"validateOrder fails on drawdown halt"];
.tst.assertEqual[`drawdownHaltActive;result 1;"Reason is drawdownHaltActive"];

/ Test validateOrder fails on order size (third check)
.risk.init[];
.risk.setOrderSizeLimit[`strategy1;10j;5000j];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;50j;50000.0];
.tst.assertEqual[0b;result 0;"validateOrder fails on order size"];
.tst.assertEqual[`strategyOrderSizeExceeded;result 1;"Reason is strategyOrderSizeExceeded"];

/ Test validateOrder fails on position limit (fourth check)
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;5j;5j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[0b;result 0;"validateOrder fails on position limit"];
.tst.assertEqual[`strategyLongLimitExceeded;result 1;"Reason is strategyLongLimitExceeded"];

/ Test validateOrder fails on exposure limit (fifth check)
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;50000.0];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[0b;result 0;"validateOrder fails on exposure limit"];
.tst.assertEqual[`exchangeExposureLimitExceeded;result 1;"Reason is exchangeExposureLimitExceeded"];

/ Test short-circuits: only first failure returned
.risk.init[];
.risk.activateEmergencyStop[`test;`admin];
.risk.updatePnL[10000.0];
.risk.updatePnL[5000.0];
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[`emergencyStopActive;result 1;"Short-circuits on first failure (emergency stop before drawdown)"];

/ ═══════════════════════════════════════════════════════════════════
/ 8. Post-Fill Updates (onFill) Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n8. POST-FILL UPDATES (onFill) TESTS";
-1 "=====================================";

.risk.init[];

/ Test onFill updates position correctly (buy)
/ SETUP: Configure all required limits before trading
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[10j;first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;"onFill updates position (buy)"];

/ Test onFill updates position correctly (sell)
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`sell;5j;50000.0];
.tst.assertEqual[5j;first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;"onFill updates position (sell)"];

/ Test onFill updates daily volume
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;5000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[10j;first exec dailyVolume from .risk.orderSizeLimits where strategy=`strategy1;"onFill updates daily volume"];

/ Test onFill updates exposure
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[500000.0;first exec currentNotional from .risk.exposureLimits where exchange=`bitstamp;"onFill updates exposure"];

/ Test buy vs sell correctly signed
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
buyPos:first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`sell;10j;50000.0];
sellPos:first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.tst.assertEqual[0j;sellPos;"Buy followed by sell returns to 0 position"];

/ ═══════════════════════════════════════════════════════════════════
/ 9. Integration: Full Order Lifecycle Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n9. INTEGRATION: FULL ORDER LIFECYCLE TESTS";
-1 "============================================";

/ Test: Init → set limits → validate pass → fill → validate pass → fill → validate fail
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;10j;10j];
.risk.setOrderSizeLimit[`strategy1;100j;5000j];
.risk.setExposureLimit[`bitstamp;1000000.0];

/ First order passes
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[1b;result 0;"Lifecycle: First order passes validation"];

/ Fill first order
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];

/ Second order passes
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[1b;result 0;"Lifecycle: Second order passes validation"];

/ Fill second order (now at position limit of 10)
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];

/ Third order fails (position exhausted)
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[0b;result 0;"Lifecycle: Third order fails (position exhausted)"];
.tst.assertEqual[`strategyLongLimitExceeded;result 1;"Lifecycle: Reason is position limit"];

/ Test: Init → set limits → validate pass → PnL update triggers drawdown → validate fail
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];

/ Initial validation passes
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[1b;result 0;"Lifecycle: Validation passes before drawdown"];

/ Simulate PnL drawdown
.risk.updatePnL[10000.0];
.risk.updatePnL[5000.0];

/ Now validation fails due to drawdown
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[0b;result 0;"Lifecycle: Validation fails after drawdown breach"];
.tst.assertEqual[`drawdownHaltActive;result 1;"Lifecycle: Reason is drawdown halt"];

/ Test: Init → emergency stop → validate fail → deactivate → validate pass
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];

/ Activate emergency stop
.risk.activateEmergencyStop[`test;`admin];

/ Validation fails
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[0b;result 0;"Lifecycle: Validation fails during emergency stop"];

/ Deactivate emergency stop
.risk.deactivateEmergencyStop[`admin];

/ Validation now passes
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
.tst.assertEqual[1b;result 0;"Lifecycle: Validation passes after emergency stop deactivation"];

/ ═══════════════════════════════════════════════════════════════════
/ 10. Risk Event Logging Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n10. RISK EVENT LOGGING TESTS";
-1 "=============================";

.risk.init[];

/ Test events logged by validateOrder on rejection
.risk.setPositionLimit[`strategy1;`BTCUSD;5j;5j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
initialCount:count .risk.riskEvents;
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;10j;50000.0];
.tst.assertEqual[initialCount+1;count .risk.riskEvents;"validateOrder logs event on rejection"];

/ Test event has correct eventType
lastEvent:last select from .risk.riskEvents;
.tst.assertEqual[`positionLimitBreach;lastEvent`eventType;"Event type is positionLimitBreach"];

/ Test event has correct severity
.tst.assertEqual[`warning;lastEvent`severity;"Event severity is warning"];

/ Test event has correct action
.tst.assertEqual[`reject;lastEvent`action;"Event action is reject"];

/ Test logRiskEvent inserts into riskEvents table
.risk.init[];
initialCount:count .risk.riskEvents;
.risk.logRiskEvent[.z.p;`testEvent;`strategy1;`BTCUSD;`bitstamp;`testDetails`value!(100;200);`testAction;`info];
.tst.assertEqual[initialCount+1;count .risk.riskEvents;"logRiskEvent inserts into riskEvents table"];

newEvent:last select from .risk.riskEvents;
.tst.assertEqual[`testEvent;newEvent`eventType;"logRiskEvent sets eventType"];
.tst.assertEqual[`strategy1;newEvent`strategy;"logRiskEvent sets strategy"];
.tst.assertEqual[`BTCUSD;newEvent`sym;"logRiskEvent sets sym"];
.tst.assertEqual[`bitstamp;newEvent`exchange;"logRiskEvent sets exchange"];
.tst.assertEqual[`testAction;newEvent`action;"logRiskEvent sets action"];
.tst.assertEqual[`info;newEvent`severity;"logRiskEvent sets severity"];

/ ═══════════════════════════════════════════════════════════════════
/ 11. Test Coverage: Unconfigured Limits Rejection (Fail-Safe Behavior)
/ ═══════════════════════════════════════════════════════════════════

-1 "\n11. TEST COVERAGE: UNCONFIGURED LIMITS REJECTION";
-1 "==================================================";

/ Test: checkPositionLimit rejects when no strategy limit configured
/ NOTE: init sets global limits for BTCUSD, so strategy-level will fail first
.risk.init[];
result:.risk.checkPositionLimit[`strategy1;`BTCUSD;`buy;5j];
.tst.assertEqual[0b;result 0;"checkPositionLimit rejects when no strategy limit configured"];
.tst.assertEqual[`noStrategyLimitConfigured;result 1;"Reason is noStrategyLimitConfigured"];

/ Test: checkPositionLimit rejects when no global limit configured
/ Use XRPUSD which has no default global limit
.risk.init[];
.risk.setPositionLimit[`strategy1;`XRPUSD;100j;100j];
result:.risk.checkPositionLimit[`strategy1;`XRPUSD;`buy;5j];
.tst.assertEqual[0b;result 0;"checkPositionLimit rejects when no global limit configured"];
.tst.assertEqual[`noGlobalLimitConfigured;result 1;"Reason is noGlobalLimitConfigured"];

/ Test: checkOrderSizeLimit rejects when no strategy limit configured
/ NOTE: init sets global order size limits, but no strategy limits
.risk.init[];
result:.risk.checkOrderSizeLimit[`strategy1;5j];
.tst.assertEqual[0b;result 0;"checkOrderSizeLimit rejects when no strategy limit configured"];
.tst.assertEqual[`noStrategyOrderLimitConfigured;result 1;"Reason is noStrategyOrderLimitConfigured"];

/ Test: checkExposureLimit rejects when no exchange limit configured
/ Use kraken which has no default exchange limit
.risk.init[];
result:.risk.checkExposureLimit[`kraken;5j;50000.0];
.tst.assertEqual[0b;result 0;"checkExposureLimit rejects when no exchange limit configured"];
.tst.assertEqual[`noExchangeLimitConfigured;result 1;"Reason is noExchangeLimitConfigured"];

/ ═══════════════════════════════════════════════════════════════════
/ 12. Test Coverage: Concurrent Strategy Trading & Global Limits
/ ═══════════════════════════════════════════════════════════════════

-1 "\n12. TEST COVERAGE: CONCURRENT STRATEGY TRADING";
-1 "================================================";

/ Test: Multiple strategies trading same symbol, global limit enforced
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;100j;100j];
.risk.setPositionLimit[`strategy2;`BTCUSD;100j;100j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setOrderSizeLimit[`strategy2;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
/ Global default for BTCUSD is 10 long
/ Strategy1 fills 6, strategy2 fills 4 — total 10 at global limit
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;6j;50000.0];
.risk.onFill[`strategy2;`BTCUSD;`bitstamp;`buy;4j;50000.0];
/ Total position now 10 (exactly at global limit)
totalPos:first exec currentPosition from .risk.globalPositionLimits where sym=`BTCUSD;
.tst.assertEqual[10j;totalPos;"Concurrent strategies: global position accumulates correctly"];
/ Next order from strategy1 should fail (global limit — even 1 more would exceed)
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`buy;1j;50000.0];
.tst.assertEqual[0b;result 0;"Concurrent strategies: global limit enforced"];
.tst.assertEqual[`globalLongLimitExceeded;result 1;"Reason is globalLongLimitExceeded"];

/ ═══════════════════════════════════════════════════════════════════
/ 13. Test Coverage: Short Selling (Negative Positions)
/ ═══════════════════════════════════════════════════════════════════

-1 "\n13. TEST COVERAGE: SHORT SELLING";
-1 "==================================";

/ Test: Short position increments correctly
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;10j;10j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`sell;5j;50000.0];
pos:first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.tst.assertEqual[-5j;pos;"Short position is negative"];

/ Test: Short limit enforced
result:.risk.validateOrder[`strategy1;`BTCUSD;`bitstamp;`sell;10j;50000.0];
.tst.assertEqual[0b;result 0;"Short limit enforced"];
.tst.assertEqual[`strategyShortLimitExceeded;result 1;"Reason is strategyShortLimitExceeded"];

/ Test: Short to flat to long transition
.risk.init[];
.risk.setPositionLimit[`strategy1;`BTCUSD;10j;10j];
.risk.setOrderSizeLimit[`strategy1;100j;50000j];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`sell;5j;50000.0];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;5j;50000.0];
posFlat:first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.tst.assertEqual[0j;posFlat;"Short to flat position"];
.risk.onFill[`strategy1;`BTCUSD;`bitstamp;`buy;3j;50000.0];
posLong:first exec currentPosition from .risk.positionLimits where strategy=`strategy1,sym=`BTCUSD;
.tst.assertEqual[3j;posLong;"Flat to long position"];

/ ═══════════════════════════════════════════════════════════════════
/ 14. Test Coverage: recalcExposure After Real Fills
/ ═══════════════════════════════════════════════════════════════════

-1 "\n14. TEST COVERAGE: recalcExposure AFTER REAL FILLS";
-1 "====================================================";

/ Test: recalcExposure correctly recalculates from position table
.risk.init[];
.risk.setExposureLimit[`bitstamp;1000000.0];
.risk.setExposureLimit[`coinbase;1000000.0];
/ Simulate position table
posTable:([] exchange:`bitstamp`bitstamp`coinbase; sym:`BTCUSD`ETHUSD`BTCUSD; qty:5 10 3j; lastPrice:50000.0 3000.0 50000.0);
/ Expected exposures: bitstamp=5*50000+10*3000=280000, coinbase=3*50000=150000
.risk.recalcExposure[posTable];
bitstampExposure:first exec currentNotional from .risk.exposureLimits where exchange=`bitstamp;
coinbaseExposure:first exec currentNotional from .risk.exposureLimits where exchange=`coinbase;
.tst.assertEqual[280000.0;bitstampExposure;"recalcExposure calculates bitstamp exposure correctly"];
.tst.assertEqual[150000.0;coinbaseExposure;"recalcExposure calculates coinbase exposure correctly"];

/ Test: recalcExposure resets exposure before recalc (idempotent)
/ Manually set exposure to wrong value
update currentNotional:999999.0 from `.risk.exposureLimits where exchange=`bitstamp;
/ Recalc should fix it
.risk.recalcExposure[posTable];
bitstampExposureFixed:first exec currentNotional from .risk.exposureLimits where exchange=`bitstamp;
.tst.assertEqual[280000.0;bitstampExposureFixed;"recalcExposure resets and recalculates (idempotent)"];

/ ═══════════════════════════════════════════════════════════════════
/ 15. Robustness & Safety Tests (Table Corruption, Invalid Inputs)
/ ═══════════════════════════════════════════════════════════════════

-1 "\n15. ROBUSTNESS & SAFETY TESTS";
-1 "================================";

/ Test: Invalid PnL (null) is rejected by updatePnL
.risk.init[];
result:.risk.updatePnL[0n];
.tst.assertEqual[0b;result;"updatePnL rejects null PnL"];

/ Test: Invalid PnL (infinity) is rejected by updatePnL
result:.risk.updatePnL[0w];
.tst.assertEqual[0b;result;"updatePnL rejects infinite PnL"];

/ Test: drawdownState corruption detected by checkDrawdownHalt
.risk.init[];
/ Corrupt the table by inserting an extra row
`.risk.drawdownState insert (0.0;0.0;0.0;20.0;0b;.z.p);
result:.risk.checkDrawdownHalt[];
.tst.assertEqual[0b;result 0;"checkDrawdownHalt fails when drawdownState corrupted"];
.tst.assertEqual[`drawdownStateCorrupted;result 1;"Reason is drawdownStateCorrupted"];

/ Test: emergencyStopState corruption detected by checkEmergencyStop
.risk.init[];
/ Corrupt the table by deleting all rows
delete from `.risk.emergencyStopState;
result:.risk.checkEmergencyStop[];
.tst.assertEqual[0b;result 0;"checkEmergencyStop fails when emergencyStopState corrupted"];
.tst.assertEqual[`emergencyStopStateCorrupted;result 1;"Reason is emergencyStopStateCorrupted"];

/ Test: globalOrderSizeLimits corruption detected by checkOrderSizeLimit
.risk.init[];
.risk.setOrderSizeLimit[`strategy1;100j;5000j];
/ Corrupt the table by adding an extra row
`.risk.globalOrderSizeLimits upsert ([] maxOrderQty:enlist 2000j; maxDailyVolume:enlist 200000j; dailyVolume:enlist 0j; lastResetDate:enlist .z.d);
result:.risk.checkOrderSizeLimit[`strategy1;50j];
.tst.assertEqual[0b;result 0;"checkOrderSizeLimit fails when globalOrderSizeLimits corrupted"];
.tst.assertEqual[`globalOrderLimitCorrupted;result 1;"Reason is globalOrderLimitCorrupted"];

/ Test: globalExposureLimit corruption detected by checkExposureLimit
.risk.init[];
.risk.setExposureLimit[`bitstamp;100000.0];
/ Corrupt the table by deleting all rows
delete from `.risk.globalExposureLimit;
result:.risk.checkExposureLimit[`bitstamp;10j;5000.0];
.tst.assertEqual[0b;result 0;"checkExposureLimit fails when globalExposureLimit corrupted"];
.tst.assertEqual[`globalExposureLimitCorrupted;result 1;"Reason is globalExposureLimitCorrupted"];

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests and Report Results
/ ═══════════════════════════════════════════════════════════════════

.tst.run[];

/ Exit with success
exit 0
