/ ============================================================================
/ order.q - Order Audit Implementation
/ ============================================================================
/
/ Verifies all orders in the local database match exchange records.
/ Detects: missing fills, incorrect statuses, orphaned orders,
/          fill amount discrepancies.
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - schema/order.q (.qg.order table)
/   - exchange/base.q (.exchange.getOpenOrders, etc.)
/
/ Usage:
/   .audit.ORDER.validate[]   / Run full order audit
/   .audit.run[`ORDER_AUDIT]  / Run via audit framework
/ ============================================================================

\d .audit

/ ============================================================================
/ ORDER AUDIT NAMESPACE
/ ============================================================================

ORDER.tolerance:0.000001f;

/ Fields used for comparison
ORDER.compareFields:`order_id`status`price`volume`filled_volume`volume_currency;

/ Compare two amounts within tolerance
/ @param a float - First amount
/ @param b float - Second amount
/ @return boolean - 1b if match within tolerance
ORDER.amountsMatch:{[a;b]
  abs[a - b] <= .audit.ORDER.tolerance
 };

/ Find orders on exchange but missing from local DB
/ @param localOrders table - Orders from local DB
/ @param exchangeOrders table - Orders from exchange API
/ @return table - Missing orders
ORDER.findMissing:{[localOrders;exchangeOrders]
  localIds:exec order_id from localOrders;
  exchangeIds:exec order_id from exchangeOrders;
  missingIds:exchangeIds except localIds;
  select from exchangeOrders where order_id in missingIds
 };

/ Find orders in local DB but not on exchange (orphaned)
/ @param localOrders table - Orders from local DB
/ @param exchangeOrders table - Orders from exchange API
/ @return table - Orphaned orders
ORDER.findOrphaned:{[localOrders;exchangeOrders]
  localIds:exec order_id from localOrders;
  exchangeIds:exec order_id from exchangeOrders;
  orphanedIds:localIds except exchangeIds;
  select from localOrders where order_id in orphanedIds
 };

/ Find orders with status mismatches between local and exchange
/ @param localOrders table - Local DB orders
/ @param exchangeOrders table - Exchange orders
/ @return table - Orders with status mismatch
ORDER.findStatusMismatches:{[localOrders;exchangeOrders]
  / Rename exchange status to avoid collision
  exOrders:(`order_id`exchangeStatus`exchangeFilledVol)!(exchangeOrders`order_id; exchangeOrders`status; exchangeOrders`filled_volume);
  exOrders:flip exOrders;
  exOrders:`order_id xkey exOrders;

  / Join and find mismatches
  joined:localOrders lj exOrders;
  select order_id, localStatus:status, exchangeStatus, price, volume, filled_volume, volume_currency
    from joined where not null exchangeStatus, not status=exchangeStatus
 };

/ Find orders with fill amount discrepancies
/ @param localOrders table - Local DB orders
/ @param exchangeOrders table - Exchange orders
/ @return table - Orders with fill mismatches
ORDER.findFilledMismatches:{[localOrders;exchangeOrders]
  exOrders:(`order_id`exchangeFilled)!(exchangeOrders`order_id; exchangeOrders`filled_volume);
  exOrders:flip exOrders;
  exOrders:`order_id xkey exOrders;

  joined:localOrders lj exOrders;
  joined:update delta:abs filled_volume - exchangeFilled from joined where not null exchangeFilled;
  select order_id, localFilled:filled_volume, exchangeFilled, delta, status, volume_currency
    from joined where not null exchangeFilled, delta>.audit.ORDER.tolerance
 };

/ ============================================================================
/ MAIN VALIDATION FUNCTION
/ ============================================================================

/ Main order audit — called by .audit.run[`ORDER_AUDIT]
/ @return dict - Standardized audit result
ORDER.validate:{[]
  / Fetch local orders from schema
  localOrders:$[`order in key `.qg; select order_id, status, price, volume, filled_volume, volume_currency from .qg.order; ([] order_id:`long$(); status:`symbol$(); price:`long$(); volume:`long$(); filled_volume:`long$(); volume_currency:`symbol$())];

  / Fetch exchange orders via coordinator
  exchangeOrders:@[{[] .exchange.coordinator.getAllOrders[]};::;{[e] ([] order_id:`long$(); status:`symbol$(); price:`long$(); volume:`long$(); filled_volume:`long$(); volume_currency:`symbol$())}];

  / If either source is empty, produce a warning rather than false positives
  if[(0=count localOrders) and 0=count exchangeOrders;
    :.audit.newResult[`ORDER_AUDIT;`PASS;();enlist "No orders to audit";`totalLocalOrders`totalExchangeOrders!(0;0)]
  ];

  / Run all checks
  missing:ORDER.findMissing[localOrders;exchangeOrders];
  orphaned:ORDER.findOrphaned[localOrders;exchangeOrders];
  statusMismatches:ORDER.findStatusMismatches[localOrders;exchangeOrders];
  filledMismatches:ORDER.findFilledMismatches[localOrders;exchangeOrders];

  / Build error and warning lists
  errors:();
  warnings:();

  if[0<count missing;
    errors,:enlist "Missing orders: ",(string count missing)," orders on exchange not in local DB"];
  if[0<count orphaned;
    warnings,:enlist "Orphaned orders: ",(string count orphaned)," orders in local DB not on exchange"];
  if[0<count statusMismatches;
    errors,:enlist "Status mismatches: ",(string count statusMismatches)," orders with different status"];
  if[0<count filledMismatches;
    errors,:enlist "Fill mismatches: ",(string count filledMismatches)," orders with different filled amounts"];

  status:$[0<count errors;`FAIL; 0<count warnings;`WARNING; `PASS];

  metrics:`totalLocalOrders`totalExchangeOrders`missingCount`orphanedCount`statusMismatchCount`filledMismatchCount!(
    count localOrders; count exchangeOrders; count missing; count orphaned;
    count statusMismatches; count filledMismatches);

  .audit.newResult[`ORDER_AUDIT;status;errors;warnings;metrics]
 };

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.audit.registerType[`ORDER_AUDIT; "Order Audit"; "Verifies all orders in DB match exchange records"; `.audit.ORDER.validate];

\d .
