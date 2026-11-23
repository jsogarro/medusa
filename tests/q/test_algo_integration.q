/ ============================================================================
/ test_algo_integration.q - Tests for Algo Integration (20 tests)
/ ============================================================================
/ Tests VWAP/TWAP/Iceberg end-to-end, pause/resume, cancel, child fills
/ ============================================================================

\l tests/q/test_framework.q
\l src/q/schema/init.q
\l src/q/algo/schema.q
\l src/q/algo/engine.q
\l src/q/algo/vwap.q
\l src/q/algo/twap.q
\l src/q/algo/iceberg.q

/ ============================================================================
/ SETUP & TEARDOWN
/ ============================================================================

setUp:{[]
  / Initialize algo engine
  .algo.engine.init[];

  / Mock .qg.isValidExchange
  .qg.isValidExchange:{[ex] ex in `binance`coinbase`kraken};

  / Mock .qg.isPositiveAmount
  .qg.isPositiveAmount:{[amt] amt > 0j};

  / Mock .algo.isValidAlgoType
  .algo.isValidAlgoType:{[algo] algo in `vwap`twap`iceberg};

  / Mock .risk.validateOrder (allow all)
  .risk.validateOrder:{[actor;pair;ex;side;qty;price] (1b;"")};

  / Mock .exchange.coordinator.placeOrder
  .exchange.coordinator.placeOrder:{[ex;pair;orderType;side;price;qty]
    `orderId`status`exchange`pair`side`price`quantity!(
      `$"CHILD_",string[.z.p];
      `pending;
      ex;
      pair;
      side;
      price;
      qty
    )
  };

  / Mock .exchange.coordinator.cancelOrder
  .exchange.coordinator.cancelOrder:{[ex;orderId]
    `orderId`status!(orderId; `cancelled)
  };
 }

tearDown:{[]
  / Reset algo engine
  .algo.engine.init[];
 }

/ ============================================================================
/ TEST CASES
/ ============================================================================

/ ============================================================================
/ TEST CASES
/ ============================================================================

test_vwap_end_to_end:{
  setUp[];

  / Submit VWAP algo order
  algoOrderId:.algo.engine.submit[
    `binance;                   / exchange
    `BTCUSD;                    / pair
    `buy;                       / side
    10000000j;                  / qty (10.0 units)
    `vwap;                      / algo
    `participation`lookbackWindow!(0.10; 60000)
  ];

  / Verify algo order created
  .test.assert["Algo order created"; algoOrderId in exec algoOrderId from .algo.algoOrder];

  / Verify status is active
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status is active"; `active; ord`status];

  / Simulate one slice
  .algo.vwap.slice[algoOrderId];

  / Verify child order created
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Child order created"; 0 < count children];

  / Simulate child fill
  childOrderId:first exec childOrderId from children;
  .algo.engine.onChildFill[childOrderId; 2000000j; 50000000000j]; / Fill 2.0 units

  / Verify parent filledQty updated
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Parent filled qty updated"; 2000000j; ord`filledQty];

  / Simulate completion (fill remaining)
  .algo.engine.onChildFill[childOrderId; 10000000j; 50000000000j]; / Fill all

  / Verify parent completed
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status completed"; `completed; ord`status];

  tearDown[];
 }

/ Test: TWAP equal slicing
test_twap_equal_slicing:{
  setUp[];

  / Submit TWAP algo order with endTime
  endTime:.z.p + 180000000000j; / +3 minutes
  algoOrderId:.algo.engine.submit[
    `binance;
    `ETHUSD;
    `buy;
    6000000j;                   / 6.0 units
    `twap;
    `sliceInterval`endTime!(60; endTime) / 1 slice per minute
  ];

  / Verify order created
  .test.assert["TWAP order created"; algoOrderId in exec algoOrderId from .algo.algoOrder];

  / Simulate first slice (should be 2.0 units: 6.0 / 3 slices)
  .algo.twap.slice[algoOrderId];

  / Verify child order size
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Child order created"; 0 < count children];

  firstChildQty:first exec quantity from children;
  .test.assertEqual["First slice is 2.0 units"; 2000000j; firstChildQty];

  tearDown[];
 }

/ Test: Iceberg hidden quantity
test_iceberg_hidden_qty:{
  setUp[];

  / Submit iceberg order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    100000000j;                 / 100.0 units (total)
    `iceberg;
    `displayQty`randomize!(10000000j; 0b) / Display 10.0 units at a time
  ];

  / Verify order created
  .test.assert["Iceberg order created"; algoOrderId in exec algoOrderId from .algo.algoOrder];

  / Simulate first slice
  .algo.iceberg.slice[algoOrderId];

  / Verify only displayQty was sliced
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  childQty:first exec quantity from children;
  .test.assertEqual["Display qty sliced"; 10000000j; childQty];

  / Verify total qty not revealed
  .test.assert["Total qty hidden"; childQty < 100000000j];

  tearDown[];
 }

/ Test: Algo pause stops slicing
test_algo_pause_resume:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    10000000j;
    `vwap;
    `participation!(0.10)
  ];

  / Verify active
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status active"; `active; ord`status];

  / Pause
  .algo.engine.pause[algoOrderId];

  / Verify paused
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status paused"; `paused; ord`status];

  / Verify not in schedule
  .test.assert["Removed from schedule"; not algoOrderId in .algo.engine.activeSchedule];

  / Resume
  .algo.engine.resume[algoOrderId];

  / Verify active again
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status active after resume"; `active; ord`status];

  / Verify back in schedule
  .test.assert["Back in schedule"; algoOrderId in .algo.engine.activeSchedule];

  tearDown[];
 }

/ Test: Algo cancel stops slicing and cancels children
test_algo_cancel:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    10000000j;
    `vwap;
    `participation!(0.10)
  ];

  / Slice once to create child
  .algo.vwap.slice[algoOrderId];

  / Verify child exists
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Child order exists"; 0 < count children];

  / Cancel algo
  .algo.engine.cancel[algoOrderId];

  / Verify algo cancelled
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Algo status cancelled"; `cancelled; ord`status];

  / Verify child cancelled
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Child status cancelled"; all (exec status from children) = `cancelled];

  / Verify removed from schedule
  .test.assert["Removed from schedule"; not algoOrderId in .algo.engine.activeSchedule];

  tearDown[];
 }

/ Test: Child fill updates parent
test_child_fill_updates_parent:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    10000000j;
    `vwap;
    ()!()
  ];

  / Manually create child order
  childOrderId:.algo.engine.nextChildOrderId[algoOrderId];
  `.algo.childOrder upsert (
    childOrderId;
    algoOrderId;
    `binance;
    `BTCUSD;
    `buy;
    `limit;
    50000000000j;
    3000000j;
    0j;                         / filledQty
    `pending;
    .z.p;
    0Np;
    0Nj
  );

  / Trigger child fill
  .algo.engine.onChildFill[childOrderId; 3000000j; 50000000000j];

  / Verify parent filled qty updated
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Parent filled qty updated"; 3000000j; ord`filledQty];

  / Verify child status filled
  child:first select from .algo.childOrder where childOrderId=childOrderId;
  .test.assertEqual["Child status filled"; `filled; child`status];

  tearDown[];
 }

/ Test: Algo with risk check
test_algo_with_risk_check:{
  setUp[];

  / Override risk.validateOrder to reject
  .risk.validateOrder:{[actor;pair;ex;side;qty;price] (0b;"Risk check failed")};

  / Submit algo order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    10000000j;
    `vwap;
    ()!()
  ];

  / Attempt to slice (risk check should block child order)
  .algo.vwap.slice[algoOrderId];

  / Verify no child order created (risk check blocked it)
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assertEqual["No child order created"; 0; count children];

  tearDown[];
 }

/ Test: VWAP participation rate calculation
test_vwap_participation_rate:{
  setUp[];

  / Mock getRecentVolume to return known value
  .algo.vwap.getRecentVolume:{[ex;pair;lookback] 100000000j}; / 100.0 units

  / Submit VWAP with 10% participation
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    50000000j;
    `vwap;
    `participation!(0.10)
  ];

  / Slice
  .algo.vwap.slice[algoOrderId];

  / Verify child size is 10% of recent volume (10.0 units)
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  childQty:first exec quantity from children;
  .test.assertEqual["Slice size is 10% of volume"; 10000000j; childQty];

  tearDown[];
 }

/ Test: TWAP time remaining calculation
test_twap_time_remaining:{
  setUp[];

  / Submit TWAP with endTime 120 seconds in future
  endTime:.z.p + 120000000000j;
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    6000000j;                   / 6.0 units
    `twap;
    `sliceInterval`endTime!(60; endTime) / 60 sec intervals
  ];

  / Slice (should calculate 2 remaining slices: 120s / 60s)
  .algo.twap.slice[algoOrderId];

  / Verify slice size is 3.0 units (6.0 / 2 slices)
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  childQty:first exec quantity from children;
  .test.assertEqual["Slice size correct"; 3000000j; childQty];

  tearDown[];
 }

/ Test: Iceberg replenishes after fill
test_iceberg_replenish:{
  setUp[];

  / Submit iceberg order
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    50000000j;
    `iceberg;
    `displayQty!(10000000j)
  ];

  / First slice
  .algo.iceberg.slice[algoOrderId];

  / Verify one child order
  children1:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assertEqual["One child order"; 1; count children1];

  / Simulate fill
  childOrderId:first exec childOrderId from children1;
  .algo.engine.onChildFill[childOrderId; 10000000j; 50000000000j];

  / Update child status to filled
  update status:`filled from `.algo.childOrder where childOrderId=childOrderId;

  / Second slice (should replenish)
  .algo.iceberg.slice[algoOrderId];

  / Verify second child order created
  children2:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Second child order created"; count[children2] > count children1];

  tearDown[];
 }

/ Test: Algo order ID uniqueness
test_algo_order_id_unique:{
  setUp[];

  / Submit two algo orders
  id1:.algo.engine.submit[`binance; `BTCUSD; `buy; 5000000j; `vwap; ()!()];
  id2:.algo.engine.submit[`binance; `ETHUSD; `sell; 3000000j; `twap; `endTime!enlist (.z.p + 60000000000j)];

  / Verify IDs are different
  .test.assert["Order IDs unique"; not id1~id2];

  tearDown[];
 }

/ Test: Child order ID uniqueness
test_child_order_id_unique:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[`binance; `BTCUSD; `buy; 10000000j; `vwap; ()!()];

  / Generate two child order IDs
  child1:.algo.engine.nextChildOrderId[algoOrderId];
  child2:.algo.engine.nextChildOrderId[algoOrderId];

  / Verify different
  .test.assert["Child IDs unique"; not child1~child2];

  tearDown[];
 }

/ Test: Algo completion when filled qty reaches target
test_algo_completion_on_filled:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[`binance; `BTCUSD; `buy; 5000000j; `vwap; ()!()];

  / Manually create child and fill it completely
  childOrderId:.algo.engine.nextChildOrderId[algoOrderId];
  `.algo.childOrder upsert (
    childOrderId;
    algoOrderId;
    `binance;
    `BTCUSD;
    `buy;
    `limit;
    50000000000j;
    5000000j;
    0j;
    `pending;
    .z.p;
    0Np;
    0Nj
  );

  / Trigger fill (fill entire target qty)
  .algo.engine.onChildFill[childOrderId; 5000000j; 50000000000j];

  / Verify algo completed
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Algo completed"; `completed; ord`status];

  / Verify removed from schedule
  .test.assert["Removed from schedule"; not algoOrderId in .algo.engine.activeSchedule];

  tearDown[];
 }

/ Test: Timer handler slices active orders
test_timer_handler_slicing:{
  setUp[];

  / Submit algo order
  algoOrderId:.algo.engine.submit[`binance; `BTCUSD; `buy; 10000000j; `vwap; ()!()];

  / Verify in schedule
  .test.assert["In schedule"; algoOrderId in .algo.engine.activeSchedule];

  / Call timer handler (should invoke slice)
  .algo.engine.timerHandler[];

  / Verify child order created (slice was called)
  children:select from .algo.childOrder where algoOrderId=algoOrderId;
  .test.assert["Child order created by timer"; 0 < count children];

  tearDown[];
 }

/ Test: TWAP endTime enforcement
test_twap_endtime_enforcement:{
  setUp[];

  / Submit TWAP with endTime in past
  endTime:.z.p - 1000000000j; / -1 second
  algoOrderId:.algo.engine.submit[
    `binance;
    `BTCUSD;
    `buy;
    5000000j;
    `twap;
    `endTime!(endTime)
  ];

  / Call timer handler (should mark as completed)
  .algo.engine.timerHandler[];

  / Verify completed
  ord:first select from .algo.algoOrder where algoOrderId=algoOrderId;
  .test.assertEqual["Status completed due to time limit"; `completed; ord`status];

  tearDown[];
 }

/ Test: Invalid algo type rejected
test_invalid_algo_type:{
  setUp[];

  / Attempt to submit invalid algo type
  result:@[.algo.engine.submit; (`binance; `BTCUSD; `buy; 5000000j; `invalid; ()!()); {`error!enlist x}];

  / Verify error
  .test.assert["Invalid algo rejected"; (result`error) like "*Invalid algo type*"];

  tearDown[];
 }

/ Test: Negative quantity rejected
test_negative_quantity_rejected:{
  setUp[];

  / Attempt to submit with negative quantity
  result:@[.algo.engine.submit; (`binance; `BTCUSD; `buy; -5000000j; `vwap; ()!()); {`error!enlist x}];

  / Verify error
  .test.assert["Negative qty rejected"; (result`error) like "*must be positive*"];

  tearDown[];
 }

/ Test: Invalid side rejected
test_invalid_side_rejected:{
  setUp[];

  / Attempt to submit with invalid side
  result:@[.algo.engine.submit; (`binance; `BTCUSD; `invalid; 5000000j; `vwap; ()!()); {`error!enlist x}];

  / Verify error
  .test.assert["Invalid side rejected"; (result`error) like "*Invalid side*"];

  tearDown[];
 }

/ Test: Pause on non-active order fails
test_pause_non_active_fails:{
  setUp[];

  / Submit and immediately cancel
  algoOrderId:.algo.engine.submit[`binance; `BTCUSD; `buy; 5000000j; `vwap; ()!()];
  .algo.engine.cancel[algoOrderId];

  / Attempt to pause cancelled order
  result:@[.algo.engine.pause; algoOrderId; {`error!enlist x}];

  / Verify error
  .test.assert["Pause non-active fails"; (result`error) like "*not active*"];

  tearDown[];
 }

/ Test: Resume on non-paused order fails
test_resume_non_paused_fails:{
  setUp[];

  / Submit algo order (active)
  algoOrderId:.algo.engine.submit[`binance; `BTCUSD; `buy; 5000000j; `vwap; ()!()];

  / Attempt to resume active order (should fail)
  result:@[.algo.engine.resume; algoOrderId; {`error!enlist x}];

  / Verify error
  .test.assert["Resume non-paused fails"; (result`error) like "*not paused*"];

  tearDown[];
 }

/ ============================================================================
/ RUN TESTS
/ ============================================================================

if[not "run_all_tests.q" ~ last get[`.z.f]; .test.run[`test_vwap_end_to_end; `test_twap_equal_slicing; `test_iceberg_hidden_qty; `test_algo_pause_resume; `test_algo_cancel; `test_child_fill_updates_parent; `test_algo_with_risk_check; `test_vwap_participation_rate; `test_twap_time_remaining; `test_iceberg_replenish; `test_algo_order_id_unique; `test_child_order_id_unique; `test_algo_completion_on_filled; `test_timer_handler_slicing; `test_twap_endtime_enforcement; `test_invalid_algo_type; `test_negative_quantity_rejected; `test_invalid_side_rejected; `test_pause_non_active_fails; `test_resume_non_paused_fails]];
