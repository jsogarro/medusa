/ ============================================================================
/ test_coordinator.q - Tests for Exchange Coordinator (15 tests)
/ ============================================================================
/ Tests routing, mode enforcement, error handling, rate limiting
/ ============================================================================

\l tests/q/test_framework.q
\l src/q/exchange/coordinator.q

/ ============================================================================
/ SETUP & TEARDOWN
/ ============================================================================

setUp:{[]
  / Initialize coordinator
  .exchange.coordinator.init[];

  / Mock exchange registry (since we don't load full registry)
  .exchange.registry.isRegistered:{[ex] ex in `binance`coinbase`kraken};

  / Mock exchange.placeOrder (simulate exchange implementation)
  .exchange.placeOrder:{[ex;pair;orderType;side;price;qty]
    `orderId`status`exchange`pair`side`price`quantity!(
      `$"EXCH_ORD_",string[.z.p];
      `pending;
      ex;
      pair;
      side;
      price;
      qty
    )
  };

  / Mock exchange.cancelOrder
  .exchange.cancelOrder:{[ex;orderId]
    `orderId`status!( orderId; `cancelled)
  };

  / Mock exchange.getBalance
  .exchange.getBalance:{[ex;curr]
    `amount`available`reserved!(1000000000j; 900000000j; 100000000j)
  };

  / Mock exchange.getPosition
  .exchange.getPosition:{[ex;pair]
    `quantity`avgPrice`unrealizedPnL!(5000000j; 50000000000j; 250000000j)
  };

  / Mock risk.checkRateLimit (allow all by default)
  .risk.checkRateLimit:{[ex;pair] (1b;"")};
 }

tearDown:{[]
  / Reset coordinator state
  .exchange.coordinator.init[];
 }

/ ============================================================================
/ TEST CASES
/ ============================================================================

/ Test: Exchange selection verification
test_route_to_correct_exchange:{
  setUp[];

  / Connect to binance
  .exchange.coordinator.connect[`binance];

  / Place order on binance
  result:.exchange.coordinator.placeOrder[`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j];

  / Verify orderId contains exchange name
  .test.assert["Order routed to correct exchange"; (`binance~result`exchange)];

  / Verify order is in routing table
  .test.assert["Order in routing table"; 1 = count select from .exchange.coordinator.orderRouting where exchange=`binance];

  tearDown[];
 }

/ Test: Dry-run mode doesn't place real orders
test_mode_enforcement_dryrun:{
  setUp[];

  / Set mode to dryrun
  .exchange.coordinator.setMode[`dryrun];

  / Connect exchange
  .exchange.coordinator.connect[`coinbase];

  / Place order in dryrun mode
  result:.exchange.coordinator.placeOrder[`coinbase; `ETHUSD; `limit; `buy; 3000000000j; 2000000j];

  / Verify status is simulated
  .test.assertEqual["Status is simulated"; `simulated; result`status];

  / Verify order is in routing table with pending status
  routing:select from .exchange.coordinator.orderRouting where orderId=result`orderId;
  .test.assertEqual["Routing status is pending"; `pending; first exec status from routing];

  tearDown[];
 }

/ Test: Live mode calls exchange
test_mode_enforcement_live:{
  setUp[];

  / Set mode to live
  .exchange.coordinator.setMode[`live];

  / Connect exchange
  .exchange.coordinator.connect[`kraken];

  / Place order in live mode
  result:.exchange.coordinator.placeOrder[`kraken; `BTCUSD; `limit; `sell; 50000000000j; 1500000j];

  / Verify status is NOT simulated (should be pending from mock exchange)
  .test.assert["Status is not simulated"; not `simulated~result`status];

  / Verify order is in routing table
  .test.assert["Order in routing table"; 1 = count select from .exchange.coordinator.orderRouting where exchange=`kraken];

  tearDown[];
 }

/ Test: Graceful error on exchange failure
test_handle_exchange_error:{
  setUp[];

  / Override placeOrder to throw error
  .exchange.placeOrder:{[ex;pair;orderType;side;price;qty] '"Simulated exchange error"};

  / Connect exchange
  .exchange.coordinator.connect[`binance];
  .exchange.coordinator.setMode[`live];

  / Attempt to place order (should fail gracefully)
  result:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j); {`error!enlist x}];

  / Verify error was returned
  .test.assert["Error returned"; `error in key result];

  / Health should be marked down
  health:.exchange.coordinator.getHealthStatus[`binance];
  .test.assert["Error count incremented"; health[`errorCount] > 0];

  tearDown[];
 }

/ Test: Cancel order routing
test_cancel_order_routing:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`coinbase];

  / Place order
  orderResult:.exchange.coordinator.placeOrder[`coinbase; `BTCUSD; `limit; `buy; 50000000000j; 1000000j];
  orderId:orderResult`orderId;

  / Cancel order
  cancelResult:.exchange.coordinator.cancelOrder[`coinbase; orderId];

  / Verify cancel result
  .test.assertEqual["Order cancelled"; `cancelled; cancelResult`status];

  / Verify routing status updated
  routing:select from .exchange.coordinator.orderRouting where orderId=orderId;
  .test.assertEqual["Routing status cancelled"; `cancelled; first exec status from routing];

  tearDown[];
 }

/ Test: Rate limit check before order
test_rate_limit_check_before_order:{
  setUp[];

  / Override checkRateLimit to reject
  .risk.checkRateLimit:{[ex;pair] (0b;"Rate limit exceeded")};

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Attempt to place order (should fail rate check)
  result:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j); {`error!enlist x}];

  / Verify error mentions rate limit
  .test.assert["Rate limit error"; (result`error) like "*Rate limit*"];

  tearDown[];
 }

/ Test: Invalid inputs rejected
test_invalid_inputs_rejected:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Test invalid price (negative)
  result1:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; -1000j; 1000000j); {`error!enlist x}];
  .test.assert["Negative price rejected"; (result1`error) like "*Invalid price*"];

  / Test invalid quantity (zero)
  result2:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 0j); {`error!enlist x}];
  .test.assert["Zero quantity rejected"; (result2`error) like "*Invalid quantity*"];

  / Test invalid side
  result3:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `invalid; 50000000000j; 1000000j); {`error!enlist x}];
  .test.assert["Invalid side rejected"; (result3`error) like "*Invalid side*"];

  / Test null pair
  result4:@[.exchange.coordinator.placeOrder; (`binance; `; `limit; `buy; 50000000000j; 1000000j); {`error!enlist x}];
  .test.assert["Null pair rejected"; (result4`error) like "*Invalid pair*"];

  tearDown[];
 }

/ Test: Balance cache invalidation after order
test_balance_cache_invalidation:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Get balance (populates cache)
  bal1:.exchange.coordinator.getBalance[`binance; `USD];

  / Verify balance is cached
  .test.assert["Balance cached"; (`binance;`USD) in key .exchange.coordinator.balances];

  / Place order (should invalidate cache for this exchange)
  .exchange.coordinator.placeOrder[`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j];

  / Verify cache was cleared for this exchange
  .test.assert["Cache invalidated"; 0 = count select from .exchange.coordinator.balances where exchange=`binance];

  tearDown[];
 }

/ Test: Duplicate order detection (race condition prevention)
test_duplicate_order_detection:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Place first order
  result1:.exchange.coordinator.placeOrder[`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j];
  orderId:result1`orderId;

  / Manually insert duplicate routing entry (simulate race)
  .exchange.coordinator.orderRouting[orderId]:(`binance; .z.p; `pending);

  / Reset counter to force collision
  .exchange.coordinator.orderIdCounter-:1;

  / Attempt to place order with same ID (should fail)
  result2:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j); {`error!enlist x}];

  / Verify duplicate detected
  .test.assert["Duplicate detected"; (result2`error) like "*Duplicate order*"];

  tearDown[];
 }

/ Test: Connection validation before order
test_connection_validation:{
  setUp[];

  / Attempt to place order without connecting
  result:@[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j); {`error!enlist x}];

  / Verify error mentions not connected
  .test.assert["Not connected error"; (result`error) like "*not connected*"];

  tearDown[];
 }

/ Test: Health status tracking
test_health_status_tracking:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Successful operation
  .exchange.coordinator.placeOrder[`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j];

  / Check health (should be healthy)
  health1:.exchange.coordinator.getHealthStatus[`binance];
  .test.assertEqual["Error count zero after success"; 0j; health1`errorCount];

  / Override placeOrder to fail
  .exchange.placeOrder:{[ex;pair;orderType;side;price;qty] '"Test error"};

  / Failed operation (protected)
  @[.exchange.coordinator.placeOrder; (`binance; `BTCUSD; `limit; `buy; 50000000000j; 1000000j); ::];

  / Check health (should have error count)
  health2:.exchange.coordinator.getHealthStatus[`binance];
  .test.assert["Error count incremented"; health2[`errorCount] > 0];

  tearDown[];
 }

/ Test: Get balance for currency
test_get_balance_for_currency:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`kraken];

  / Get balance
  bal:.exchange.coordinator.getBalance[`kraken; `BTC];

  / Verify balance structure
  .test.assert["Amount present"; `amount in key bal];
  .test.assert["Available present"; `available in key bal];
  .test.assert["Reserved present"; `reserved in key bal];

  / Verify cached
  .test.assert["Balance cached"; (`kraken;`BTC) in key .exchange.coordinator.balances];

  tearDown[];
 }

/ Test: Get position for pair
test_get_position_for_pair:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`coinbase];

  / Get position
  pos:.exchange.coordinator.getPosition[`coinbase; `BTCUSD];

  / Verify position structure
  .test.assert["Quantity present"; `quantity in key pos];
  .test.assert["Avg price present"; `avgPrice in key pos];
  .test.assert["Unrealized PnL present"; `unrealizedPnL in key pos];

  / Verify cached
  .test.assert["Position cached"; (`coinbase;`BTCUSD) in key .exchange.coordinator.positions];

  tearDown[];
 }

/ Test: Disconnect clears cached data
test_disconnect_clears_cache:{
  setUp[];

  / Connect exchange
  .exchange.coordinator.connect[`binance];

  / Get balance and position (populate cache)
  .exchange.coordinator.getBalance[`binance; `USD];
  .exchange.coordinator.getPosition[`binance; `BTCUSD];

  / Verify cached
  .test.assert["Balance cached before disconnect"; 1 = count select from .exchange.coordinator.balances where exchange=`binance];
  .test.assert["Position cached before disconnect"; 1 = count select from .exchange.coordinator.positions where exchange=`binance];

  / Disconnect
  .exchange.coordinator.disconnect[`binance];

  / Verify cache cleared
  .test.assert["Balance cache cleared"; 0 = count select from .exchange.coordinator.balances where exchange=`binance];
  .test.assert["Position cache cleared"; 0 = count select from .exchange.coordinator.positions where exchange=`binance];

  tearDown[];
 }

/ Test: Unregistered exchange rejected
test_unregistered_exchange_rejected:{
  setUp[];

  / Attempt to connect to unregistered exchange
  result:@[.exchange.coordinator.connect; `fake_exchange; {`error!enlist x}];

  / Verify error
  .test.assert["Unregistered exchange rejected"; (result`error) like "*not registered*"];

  tearDown[];
 }

/ Run tests
if[not `medusaRunAll in key `.; exit .test.run[`.]];
