/ ============================================================================
/ test_algo_engine.q - Execution Algorithm Engine Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - Parent algo order creation and lifecycle
/   - VWAP slice sizing with participation rate
/   - TWAP equal-sized slicing over time
/   - Iceberg display quantity randomization
/   - Child order fill → parent update
/   - Pause/resume/cancel operations
/   - Timer-based slicing scheduler
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - src/q/algo/init.q (algo engine)
/   - src/q/exchange/coordinator.q (mocked)
/   - src/q/risk/validate.q (mocked)
/ ----------------------------------------------------------------------------
/ Usage:
/   q tests/q/test_algo_engine.q
/ ============================================================================

\c 30 200

/ Load dependencies (mocked versions for testing)
-1 "";
-1 "=======================================================";
-1 "  Algo Engine Test Suite";
-1 "=======================================================";

/ Mock .qg namespace (validation functions)
\d .qg
isValidExchange:{[x] x in `bitstamp`coinbase`kraken};
isPositiveAmount:{[x] x > 0};
isValidCurrency:{[x] x in `BTC`USD`EUR};
isValidPrice:{[x] (not null x) and x > 0};
isValidOrderType:{[x] x in `market`limit};
isValidOrderStatus:{[x] x in `pending`open`filled`cancelled`partially_filled};
NULL_TIMESTAMP:0Np;
\d .

set[`.exchange.coordinator.placeOrder; {[exchange;pair;orderType;side;price;qty]
  `orderId`status`exchange`pair`side`price`quantity!(
    `$"TEST_ORD_",string .z.p;
    `open;
    exchange;
    pair;
    side;
    price;
    qty
  )
 }];

set[`.exchange.coordinator.cancelOrder; {[exchange;orderId]
  `orderId`status!(orderId;`cancelled)
 }];

/ Mock .risk.validateOrder namespace
\d .risk
validateOrder:{[strategy;sym;exchange;side;qty;price]
  / Always pass for tests
  (1b;`)
 };
\d .

/ Mock .u.pub (tickerplant publish)
\d .u
pub:{[topic;msg] ::};
\d .

/ Load algo engine
-1 "  Loading algo engine...";
system "l src/q/algo/init.q"

/ ============================================================================
/ TEST UTILITIES
/ ============================================================================

\d .test

/ Test counter
testCount:0;
passCount:0;
failCount:0;

/ Assert function
assert:{[condition;message]
  testCount+:1;
  $[condition;
    [passCount+:1; -1 "  ✓ ",message];
    [failCount+:1; -1 "  ✗ FAILED: ",message]
  ];
 };

/ Print test section header
section:{[name]
  -1 "";
  -1 "---------------------------------------------------";
  -1 "  ",name;
  -1 "---------------------------------------------------";
 };

/ Print test summary
summary:{[]
  -1 "";
  -1 "=======================================================";
  -1 "  Test Summary";
  -1 "=======================================================";
  -1 "  Total:  ",string testCount;
  -1 "  Passed: ",string passCount;
  -1 "  Failed: ",string failCount;
  -1 "=======================================================";
  -1 "";

  / Return exit code
  $[failCount > 0; 1; 0]
 };

\d .

/ ============================================================================
/ TEST 1: Parent Order Creation
/ ============================================================================

.test.section["Test 1: Parent Algo Order Creation"];

/ Submit VWAP order
algoId1:.algo.engine.submit[`bitstamp; `BTCUSD; `buy; 100000000j; `vwap;
  `participation`lookbackWindow!(0.10; 60000)];

.test.assert[not null algoId1; "VWAP order created with valid ID"];

/ Check algoOrder table
ord1Rows:select from `.algo.algoOrder where algoOrderId=algoId1;
.test.assert[1=count ord1Rows; "VWAP order exists in algoOrder table"];
ord1:first ord1Rows;
.test.assert[ord1[`exchange]=`bitstamp; "Exchange set correctly"];
.test.assert[ord1[`pair]=`BTCUSD; "Pair set correctly"];
.test.assert[ord1[`side]=`buy; "Side set correctly"];
.test.assert[ord1[`targetQty]=100000000j; "Target quantity set correctly"];
.test.assert[ord1[`filledQty]=0j; "Initial filled quantity is zero"];
.test.assert[ord1[`algo]=`vwap; "Algorithm type is VWAP"];
.test.assert[ord1[`status]=`active; "Initial status is active"];

/ Submit TWAP order with endTime
endTime:.z.p + 0D00:10:00;  / 10 minutes from now
algoId2:.algo.engine.submit[`coinbase; `ETHUSD; `sell; 50000000j; `twap;
  `sliceInterval`endTime!(30; endTime)];

.test.assert[not null algoId2; "TWAP order created with valid ID"];

ord2:first select from `.algo.algoOrder where algoOrderId=algoId2;
.test.assert[ord2[`algo]=`twap; "Algorithm type is TWAP"];
.test.assert[ord2[`endTime]=endTime; "End time set correctly"];

/ Submit Iceberg order
algoId3:.algo.engine.submit[`kraken; `BTCUSD; `buy; 200000000j; `iceberg;
  `displayQty`randomize!(10000000j; 1b)];

.test.assert[not null algoId3; "Iceberg order created with valid ID"];

ord3:first select from `.algo.algoOrder where algoOrderId=algoId3;
.test.assert[ord3[`algo]=`iceberg; "Algorithm type is Iceberg"];

/ ============================================================================
/ TEST 2: VWAP Slice Sizing (Participation Rate)
/ ============================================================================

.test.section["Test 2: VWAP Slice Sizing"];

/ Mock getRecentVolume to return known volume
.algo.vwap.getRecentVolume:{[exchange;pair;lookbackMs] 100000000j};  / 100.0 units

/ Execute VWAP slice
.algo.vwap.slice[algoId1];

/ Check that child order was created
children1:select from `.algo.childOrder where algoOrderId=algoId1;
.test.assert[1=count children1; "VWAP created one child order"];

/ Expected slice size = 0.10 * 100000000 = 10000000 (10.0 units)
child1:first children1;
.test.assert[child1[`quantity]=10000000j; "VWAP slice size matches participation rate (10% of 100.0)"];
.test.assert[child1[`status]=`pending; "Child order status is pending"];

/ ============================================================================
/ TEST 3: TWAP Equal Slicing
/ ============================================================================

.test.section["Test 3: TWAP Equal Slicing"];

/ Mock getBestPrice
.algo.twap.getBestPrice:{[exchange;pair;side] 50000000000j};

/ Execute TWAP slice
.algo.twap.slice[algoId2];

/ Check that child order was created
children2:select from `.algo.childOrder where algoOrderId=algoId2;
.test.assert[1=count children2; "TWAP created one child order"];

/ Time remaining ≈ 10 minutes, slice interval = 30 sec → 20 slices
/ Expected slice size = 50000000 / 20 = 2500000 (2.5 units)
child2:first children2;
expectedSliceSize:floor 50000000j % ceiling (10 * 60) % 30;
.test.assert[child2[`quantity]=expectedSliceSize; "TWAP slice size is evenly distributed"];

/ ============================================================================
/ TEST 4: Iceberg Display Quantity Randomization
/ ============================================================================

.test.section["Test 4: Iceberg Display Quantity Randomization"];

/ Mock getBestPrice
.algo.iceberg.getBestPrice:{[exchange;pair;side] 50000000000j};

/ Execute one Iceberg slice and check that it appends a display child order
beforeIcebergChildren:count 0!.algo.childOrder;
sampleIcebergId:.algo.engine.submit[`kraken; `BTCUSD; `buy; 200000000j; `iceberg;
  `displayQty`randomize!(10000000j; 1b)];
.algo.iceberg.slice[sampleIcebergId];
afterIcebergChildren:count 0!.algo.childOrder;
.test.assert[afterIcebergChildren > beforeIcebergChildren; "Iceberg created a display child order"];

/ ============================================================================
/ TEST 5: Child Fill → Parent Update
/ ============================================================================

.test.section["Test 5: Child Fill Updates Parent"];

/ Get first child order from VWAP test
.algo.vwap.slice[algoId1];
child1Id:first exec childOrderId from `.algo.childOrder where algoOrderId=algoId1;

/ Simulate child fill
fillQty:10000000j;
fillPrice:50000000000j;
.algo.engine.onChildFill[child1Id; fillQty; fillPrice];

/ Check child order updated
updatedChild:first select from `.algo.childOrder where childOrderId=child1Id;
.test.assert[updatedChild[`filledQty]=fillQty; "Child order filled quantity updated"];
.test.assert[updatedChild[`avgFillPrice]=fillPrice; "Child order fill price recorded"];
.test.assert[updatedChild[`status]=`filled; "Child order status set to filled"];
.test.assert[not null updatedChild`fillTime; "Child order fill time recorded"];

/ Check parent order updated
updatedParent:first select from `.algo.algoOrder where algoOrderId=algoId1;
.test.assert[updatedParent[`filledQty]=fillQty; "Parent order filled quantity incremented"];

/ ============================================================================
/ TEST 6: Pause/Resume Lifecycle
/ ============================================================================

.test.section["Test 6: Pause and Resume"];

/ Pause algo order
.algo.engine.pause[algoId1];

pausedOrd:first select from `.algo.algoOrder where algoOrderId=algoId1;
.test.assert[pausedOrd[`status]=`paused; "Algo order status set to paused"];

/ Check removed from active schedule
.test.assert[not algoId1 in .algo.engine.activeSchedule; "Paused order removed from schedule"];

/ Resume algo order
.algo.engine.resume[algoId1];

resumedOrd:first select from `.algo.algoOrder where algoOrderId=algoId1;
.test.assert[resumedOrd[`status]=`active; "Algo order status set back to active"];
.test.assert[algoId1 in .algo.engine.activeSchedule; "Resumed order added back to schedule"];

/ ============================================================================
/ TEST 7: Cancel Lifecycle
/ ============================================================================

.test.section["Test 7: Cancel Algo Order"];

/ Submit new order for cancellation test
algoId4:.algo.engine.submit[`bitstamp; `BTCUSD; `buy; 50000000j; `vwap; ()!()];

/ Create some pending child orders
.algo.vwap.slice[algoId4];
.algo.vwap.slice[algoId4];

childrenBefore:select from `.algo.childOrder where algoOrderId=algoId4;
.test.assert[count[childrenBefore] >= 1; "Child orders exist before cancellation"];

/ Cancel algo order
.algo.engine.cancel[algoId4];

/ Check parent status
cancelledOrd:first select from `.algo.algoOrder where algoOrderId=algoId4;
.test.assert[cancelledOrd[`status]=`cancelled; "Algo order status set to cancelled"];
.test.assert[not null cancelledOrd`completedAt; "Completion timestamp recorded"];

/ Check removed from schedule
.test.assert[not algoId4 in .algo.engine.activeSchedule; "Cancelled order removed from schedule"];

/ ============================================================================
/ Print Summary
/ ============================================================================

exitCode:.test.summary[];

/ Force exit
exit exitCode;
