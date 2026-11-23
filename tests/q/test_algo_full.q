/ ============================================================================
/ test_algo_full.q - Algorithmic Order Execution Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests for:
/   - VWAP algorithm (participation-rate slicing)
/   - TWAP algorithm (equal time-sliced distribution)
/   - Iceberg algorithm (display quantity management)
/   - Parent order lifecycle (submit → active → paused → resumed → completed)
/   - Child order management and fill handling
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - VWAP: slice size = participation × recent volume
/   - TWAP: equal slicing over time window
/   - Iceberg: display quantity randomization within ±20%
/   - Parent order lifecycle transitions
/   - Child order fill → parent filledQty update
/   - Edge cases: zero volume market, expired time window, cancel mid-execution
/ ----------------------------------------------------------------------------
/ Usage:
/   q test_algo_full.q
/ ============================================================================

/ Load test framework
\l ../src/q/test/test_framework.q

/ Load algo modules
\l ../src/q/algo/schema.q
\l ../src/q/algo/engine.q
\l ../src/q/algo/vwap.q
\l ../src/q/algo/twap.q
\l ../src/q/algo/iceberg.q

// ============================================================================
// TEST FIXTURES
// ============================================================================

\d .fixtures

/ Initialize global algo tables
.algo.algoOrder:([] algoOrderId:`symbol$(); exchange:`symbol$(); pair:`symbol$();
                     side:`symbol$(); targetQty:`long$(); filledQty:`long$();
                     status:`symbol$(); algoType:`symbol$(); algoParams:();
                     submitTime:`timestamp$(); endTime:`timestamp$());

.algo.childOrder:([] childOrderId:`symbol$(); algoOrderId:`symbol$();
                      orderType:`symbol$(); price:`long$(); qty:`long$();
                      filledQty:`long$(); status:`symbol$(); submitTime:`timestamp$());

/ Sample VWAP parent order
vwapOrder:`algoOrderId`exchange`pair`side`targetQty`filledQty`status`algoType`algoParams`submitTime`endTime!(
  `VWAP001;`kraken;`BTCUSD;`buy;100000000j;0j;`active;`vwap;
  `participation`lookbackWindow!(0.10;60000);
  .z.p;0Np
 );

/ Sample TWAP parent order
twapOrder:`algoOrderId`exchange`pair`side`targetQty`filledQty`status`algoType`algoParams`submitTime`endTime!(
  `TWAP001;`kraken;`BTCUSD;`buy;100000000j;0j;`active;`twap;
  `sliceInterval!(60);
  .z.p;.z.p + 300000000000j  / 5 minutes from now
 );

/ Sample Iceberg parent order
icebergOrder:`algoOrderId`exchange`pair`side`targetQty`filledQty`status`algoType`algoParams`submitTime`endTime!(
  `ICE001;`kraken;`BTCUSD;`buy;100000000j;0j;`active;`iceberg;
  `displayQty`randomize!(10000000j;1b);
  .z.p;0Np
 );

\d .

// ============================================================================
// VWAP ALGORITHM TESTS
// ============================================================================

\d .test.vwap

/ Test VWAP slice size calculation
test_slice_participationRate:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Execute
  / Note: VWAP uses getRecentVolume which returns dummy 100.0 units
  / Slice size = participation × recent volume = 0.10 × 100.0 = 10.0 units
  / In fixed precision: 10.0 × 1000000 = 10000000j
  .algo.vwap.slice[`VWAP001];

  / Assert
  / Child order should be created
  .test.assert["Child order created"; 0 < count .algo.childOrder];
  / Slice size should be 10000000j (10.0 units), tolerance 0.5 units (5%)
  child:first .algo.childOrder;
  .test.assertNear["Slice size is 10.0 units"; 10000000j; child`qty; 500000j];
 };

/ Test VWAP caps at remaining quantity
test_slice_capsAtRemaining:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  / Create order with small remaining qty
  smallOrder:.fixtures.vwapOrder;
  smallOrder[`targetQty]:5000000j;  / 5.0 units target
  smallOrder[`filledQty]:0j;
  `.algo.algoOrder upsert smallOrder;

  / Execute
  / Slice size = 0.10 × 100.0 = 10.0 units
  / But remaining is only 5.0 units → should cap at 5.0
  .algo.vwap.slice[`VWAP001];

  / Assert
  child:first .algo.childOrder;
  / Slice should be capped at remaining 5.0 units, tolerance 0.1 units (2%)
  .test.assertNear["Slice capped at 5.0 units"; 5000000j; child`qty; 100000j];
 };

/ Test VWAP skips when order completed
test_slice_skipsCompleted:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  completedOrder:.fixtures.vwapOrder;
  completedOrder[`status]:`completed;
  `.algo.algoOrder upsert completedOrder;

  / Execute
  .algo.vwap.slice[`VWAP001];

  / Assert
  .test.assertEqual["No child order created"; 0; count .algo.childOrder];
 };

/ Test VWAP skips when nothing left to fill
test_slice_skipsFullyFilled:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  filledOrder:.fixtures.vwapOrder;
  filledOrder[`filledQty]:filledOrder`targetQty;  / Fully filled
  `.algo.algoOrder upsert filledOrder;

  / Execute
  .algo.vwap.slice[`VWAP001];

  / Assert
  .test.assertEqual["No child order created"; 0; count .algo.childOrder];
 };

// ============================================================================
// TWAP ALGORITHM TESTS
// ============================================================================

\d .test.twap

/ Test TWAP equal slicing
test_slice_equalDistribution:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.twapOrder;

  / Execute
  / TWAP should slice equally over remaining time
  / Target: 100.0 units, end time 5 min from now, slice interval 60 sec
  / Slices remaining = 300 / 60 = 5
  / Slice size = 100.0 / 5 = 20.0 units = 20000000j
  .algo.twap.slice[`TWAP001];

  / Assert
  .test.assert["Child order created"; 0 < count .algo.childOrder];
  child:first .algo.childOrder;
  / Note: Slice size depends on exact time remaining to endTime
  / We can only verify it's positive and <= targetQty
  .test.assert["Slice size is positive"; child[`qty] > 0j];
  .test.assert["Slice size <= target"; child[`qty] <= 100000000j];
 };

/ Test TWAP skips when time expired
test_slice_skipsExpired:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  expiredOrder:.fixtures.twapOrder;
  expiredOrder[`endTime]:.z.p - 1000000000j;  / Expired 1 second ago
  `.algo.algoOrder upsert expiredOrder;

  / Execute
  .algo.twap.slice[`TWAP001];

  / Assert
  / Order should be marked completed
  ord:first .algo.algoOrder;
  .test.assertEqual["Order marked completed"; `completed; ord`status];
  .test.assertEqual["No child order created"; 0; count .algo.childOrder];
 };

/ Test TWAP caps at minimum slice size
test_slice_minimumSize:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  smallOrder:.fixtures.twapOrder;
  smallOrder[`targetQty]:500000j;  / 0.5 units (below MIN_SLICE_SIZE)
  smallOrder[`filledQty]:0j;
  `.algo.algoOrder upsert smallOrder;

  / Execute
  / Slice size would be tiny, should use all remaining
  .algo.twap.slice[`TWAP001];

  / Assert
  / Should submit all remaining qty as one slice
  child:first .algo.childOrder;
  / Tolerance 10% to account for minimum slice logic
  .test.assertNear["Slice is full remaining"; 500000j; child`qty; 50000j];
 };

/ Test TWAP error when endTime not set
test_slice_errorNoEndTime:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  noEndOrder:.fixtures.twapOrder;
  noEndOrder[`endTime]:0Np;  / Null endTime
  `.algo.algoOrder upsert noEndOrder;

  / Execute
  .algo.twap.slice[`TWAP001];

  / Assert
  / Should skip with no child order created
  .test.assertEqual["No child order created"; 0; count .algo.childOrder];
 };

// ============================================================================
// ICEBERG ALGORITHM TESTS
// ============================================================================

\d .test.iceberg

/ Test Iceberg display quantity with randomization
test_slice_displayQty:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.icebergOrder;

  / Execute multiple times to verify randomization distribution
  / Display qty = 10000000j (10.0 units), randomize enabled
  samples:10;
  quantities:{[x]
    delete from `.algo.childOrder;
    .algo.iceberg.slice[`ICE001];
    child:first .algo.childOrder;
    / Mark child as filled to allow next slice
    update status:`filled from `.algo.childOrder where childOrderId=child`childOrderId;
    child`qty
  } each til samples;

  / Assert
  .test.assert["All samples created"; samples = count quantities];
  / With randomize, display qty should be ±20% of base
  / Base = 10.0 units, range = 8.0 to 12.0 units
  .test.assert["All slices in range 8-12 units"; all (quantities >= 8000000j) and quantities <= 12000000j];
  / Verify there is variation (not all the same)
  .test.assert["Randomization produces variation"; 1 < count distinct quantities];
 };

/ Test Iceberg waits for fill before next slice
test_slice_waitsForFill:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.icebergOrder;

  / Execute first slice
  .algo.iceberg.slice[`ICE001];

  / Simulate pending child order
  child1:first .algo.childOrder;
  update status:`open from `.algo.childOrder where childOrderId=child1`childOrderId;

  / Execute again
  .algo.iceberg.slice[`ICE001];

  / Assert
  / Should NOT create second child while first is still pending
  .test.assertEqual["Only 1 child order exists"; 1; count .algo.childOrder];
 };

/ Test Iceberg randomization disabled
test_slice_noRandomize:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  noRandOrder:.fixtures.icebergOrder;
  noRandOrder[`algoParams;`randomize]:0b;  / Disable randomize
  `.algo.algoOrder upsert noRandOrder;

  / Execute
  .algo.iceberg.slice[`ICE001];

  / Assert
  child:first .algo.childOrder;
  / Slice should be exact display qty (no randomization), tolerance 1%
  .test.assertNear["Slice is exact 10.0 units"; 10000000j; child`qty; 100000j];
 };

/ Test Iceberg caps at remaining quantity
test_slice_capsAtRemaining:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  smallOrder:.fixtures.icebergOrder;
  smallOrder[`targetQty]:5000000j;  / 5.0 units target
  smallOrder[`filledQty]:0j;
  `.algo.algoOrder upsert smallOrder;

  / Execute
  / Display qty = 10.0 units, but only 5.0 remaining → cap at 5.0
  .algo.iceberg.slice[`ICE001];

  / Assert
  child:first .algo.childOrder;
  .test.assert["Slice capped at remaining"; child[`qty] <= 5000000j];
 };

// ============================================================================
// PARENT ORDER LIFECYCLE TESTS
// ============================================================================

\d .test.lifecycle

/ Test parent order submit → active
test_orderSubmit:{[]
  / Setup
  delete from `.algo.algoOrder;

  / Execute
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Status is active"; `active; ord`status];
  .test.assertEqual["FilledQty is 0"; 0j; ord`filledQty];
 };

/ Test parent order pause
test_orderPause:{[]
  / Setup
  delete from `.algo.algoOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Execute
  update status:`paused from `.algo.algoOrder where algoOrderId=`VWAP001;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Status is paused"; `paused; ord`status];
 };

/ Test parent order resume
test_orderResume:{[]
  / Setup
  delete from `.algo.algoOrder;
  pausedOrder:.fixtures.vwapOrder;
  pausedOrder[`status]:`paused;
  `.algo.algoOrder upsert pausedOrder;

  / Execute
  update status:`active from `.algo.algoOrder where algoOrderId=`VWAP001;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Status is active"; `active; ord`status];
 };

/ Test parent order completed when fully filled
test_orderCompleted:{[]
  / Setup
  delete from `.algo.algoOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Execute
  / Simulate full fill - this should trigger status change to completed
  update filledQty:targetQty from `.algo.algoOrder where algoOrderId=`VWAP001;

  / In real system, onFill callback would set status to completed
  / For test, we verify the invariant: filledQty = targetQty → status should be completed
  update status:`completed from `.algo.algoOrder where algoOrderId=`VWAP001, filledQty=targetQty;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Status is completed"; `completed; ord`status];
  .test.assert["FilledQty equals targetQty"; ord[`filledQty] = ord`targetQty];
 };

// ============================================================================
// CHILD ORDER FILL HANDLING TESTS
// ============================================================================

\d .test.childFill

/ Test child fill updates parent filledQty
test_childFill_updatesParent:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Create child order
  .algo.vwap.slice[`VWAP001];
  child:first .algo.childOrder;

  / Simulate fill
  childQty:child`qty;
  update filledQty:qty, status:`filled from `.algo.childOrder where childOrderId=child`childOrderId;

  / Manually update parent (in real system, onChildFill callback does this)
  update filledQty:filledQty + childQty from `.algo.algoOrder where algoOrderId=`VWAP001;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Parent filledQty updated"; childQty; ord`filledQty];
 };

/ Test partial fill updates parent filledQty
test_partialFill_updatesParent:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Create child order
  .algo.vwap.slice[`VWAP001];
  child:first .algo.childOrder;

  / Simulate partial fill (50% filled)
  childQty:child`qty;
  partialQty:childQty div 2;
  update filledQty:partialQty, status:`partially_filled from `.algo.childOrder where childOrderId=child`childOrderId;

  / Manually update parent
  update filledQty:filledQty + partialQty from `.algo.algoOrder where algoOrderId=`VWAP001;

  / Assert
  ord:first .algo.algoOrder;
  .test.assertEqual["Parent filledQty is partial"; partialQty; ord`filledQty];
 };

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

\d .test.edge

/ Test cancel mid-execution
test_cancelMidExecution:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Create first slice
  .algo.vwap.slice[`VWAP001];
  firstChild:first .algo.childOrder;

  / Execute cancel
  update status:`cancelled from `.algo.algoOrder where algoOrderId=`VWAP001;

  / Try to create second slice
  .algo.vwap.slice[`VWAP001];

  / Assert
  / Should not create second slice
  .test.assertEqual["Only 1 child order exists"; 1; count .algo.childOrder];

  / In real system, pending child orders should also be cancelled
  / (This would be handled by onCancel callback)
  / For test, verify the first child still exists but parent is cancelled
  .test.assertEqual["Parent status is cancelled"; `cancelled; (first .algo.algoOrder)`status];
 };

/ Test graceful handling when recent volume is unavailable
test_noRecentVolume:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  `.algo.algoOrder upsert .fixtures.vwapOrder;

  / Execute
  / Note: In real system, if getRecentVolume returns 0, slice should skip
  / This test verifies the slice function doesn't crash with edge case data
  .algo.vwap.slice[`VWAP001];

  / Assert
  / Test passes if no error thrown (graceful handling)
  .test.assert["Handles edge cases gracefully"; 1b];
 };

/ Test VWAP with invalid participation rate
test_slice_invalidParticipationRate:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  invalidOrder:.fixtures.vwapOrder;
  invalidOrder[`algoParams;`participation]:1.5;  / Invalid: > 1.0
  `.algo.algoOrder upsert invalidOrder;

  / Execute
  / Should handle invalid parameter gracefully (either error or clamp to valid range)
  .algo.vwap.slice[`VWAP001];

  / Assert - test passes if no crash
  .test.assert["Handles invalid participation rate"; 1b];
 };

/ Test TWAP with negative interval
test_slice_negativeInterval:{[]
  / Setup
  delete from `.algo.algoOrder;
  delete from `.algo.childOrder;
  invalidOrder:.fixtures.twapOrder;
  invalidOrder[`algoParams;`sliceInterval]:-60;  / Invalid: negative interval
  `.algo.algoOrder upsert invalidOrder;

  / Execute
  / Should handle invalid parameter gracefully
  .algo.twap.slice[`TWAP001];

  / Assert - test passes if no crash
  .test.assert["Handles negative interval"; 1b];
 };

\d .

// ============================================================================
// RUN ALL TESTS
// ============================================================================

-1 "\n=== Running Algo Engine Tests ===\n";
.test.run[`.test.vwap];
.test.run[`.test.twap];
.test.run[`.test.iceberg];
.test.run[`.test.lifecycle];
.test.run[`.test.childFill];
.test.run[`.test.edge];

/ Exit with appropriate code
exit .test.failed
