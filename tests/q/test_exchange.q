/ ============================================================================
/ test_exchange.q - Exchange Wrapper and Stub Tests
/ ============================================================================
/
/ Tests:
/   - Exchange base interface validation
/   - Order lifecycle state machine
/   - Stub exchange initialization
/   - Order placement (market and limit)
/   - Order cancellation
/   - Balance tracking and holds
/   - Order matching logic
/   - Orderbook generation
/ ============================================================================

/ Load dependencies
\l ../src/q/schema/types.q
\l ../src/q/exchange/base.q
\l ../src/q/exchange/registry.q
\l ../src/q/exchange/stub.q

/ Test utilities
\d .test

/ Test counter
passed:0;
failed:0;
testName:`$();

/ Assert function
assert:{[condition;msg]
  $[condition;
    [passed+::1; -1 "  ✓ ",msg];
    [failed+::1; -1 "  ✗ ",msg; '"Assertion failed"]
  ]
 };

/ Test setup
setup:{[]
  / Initialize stub exchange
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[`USD`BTC!(10000.0;1.0)];
  .exchange.stub.setOBParams[`midPrice`spread`depth!(100.0;0.02;10)];

  / Register stub
  .exchange.stub.registerStub[];
 };

/ Test teardown
teardown:{[]
  / Clear state
  .exchange.stub.balances::()!();
  .exchange.stub.holds::()!();
  .exchange.stub.orders::0#.exchange.stub.ordersSchema;
  .exchange.stub.fills::0#.exchange.stub.fillsSchema;
  .exchange.stub.nextOrderId::1j;
 };

/ Run single test
runTest:{[name;testFn]
  testName::name;
  -1 "\nTest: ",string name;
  setup[];
  result:@[testFn;::;{[e] failed+::1; -1 "  ✗ Exception: ",e; e}];
  teardown[];
  result
 };

\d .

/ ============================================================================
/ TESTS - STATE MACHINE
/ ============================================================================

testValidTransitions:{[]
  / Test valid transitions
  .test.assert[.exchange.isValidTransition[`pending;`open];"pending -> open"];
  .test.assert[.exchange.isValidTransition[`pending;`rejected];"pending -> rejected"];
  .test.assert[.exchange.isValidTransition[`open;`partially_filled];"open -> partially_filled"];
  .test.assert[.exchange.isValidTransition[`open;`filled];"open -> filled"];
  .test.assert[.exchange.isValidTransition[`open;`cancelled];"open -> cancelled"];
  .test.assert[.exchange.isValidTransition[`partially_filled;`filled];"partially_filled -> filled"];
  .test.assert[.exchange.isValidTransition[`partially_filled;`cancelled];"partially_filled -> cancelled"];

  / Test invalid transitions
  .test.assert[not .exchange.isValidTransition[`filled;`open];"filled -> open (invalid)"];
  .test.assert[not .exchange.isValidTransition[`cancelled;`open];"cancelled -> open (invalid)"];
  .test.assert[not .exchange.isValidTransition[`rejected;`open];"rejected -> open (invalid)"];
 };

/ ============================================================================
/ TESTS - VALIDATION
/ ============================================================================

testOrderValidation:{[]
  / Valid order types
  .test.assert[.exchange.isValidOrderType[`market];"market is valid"];
  .test.assert[.exchange.isValidOrderType[`limit];"limit is valid"];
  .test.assert[not .exchange.isValidOrderType[`invalid];"invalid type rejected"];

  / Valid order states
  .test.assert[.exchange.isValidOrderState[`pending];"pending is valid"];
  .test.assert[.exchange.isValidOrderState[`filled];"filled is valid"];
  .test.assert[not .exchange.isValidOrderState[`invalid];"invalid state rejected"];

  / Valid order sides
  .test.assert[.exchange.isValidOrderSide[`buy];"buy is valid"];
  .test.assert[.exchange.isValidOrderSide[`sell];"sell is valid"];
  .test.assert[not .exchange.isValidOrderSide[`invalid];"invalid side rejected"];
 };

/ ============================================================================
/ TESTS - BALANCE OPERATIONS
/ ============================================================================

testBalanceInit:{[]
  / Test balance initialization
  .test.assert[.exchange.stub.getTotalBalance[`USD] = 10000.0;"USD balance correct"];
  .test.assert[.exchange.stub.getTotalBalance[`BTC] = 1.0;"BTC balance correct"];
  .test.assert[.exchange.stub.getAvailableBalance[`USD] = 10000.0;"Available USD correct"];
  .test.assert[.exchange.stub.getAvailableBalance[`BTC] = 1.0;"Available BTC correct"];
 };

testBalanceHolds:{[]
  / Place hold
  .exchange.stub.placeHold[`USD;1000.0];
  .test.assert[.exchange.stub.getTotalBalance[`USD] = 10000.0;"Total unchanged after hold"];
  .test.assert[.exchange.stub.getAvailableBalance[`USD] = 9000.0;"Available reduced by hold"];

  / Release hold
  .exchange.stub.releaseHold[`USD;500.0];
  .test.assert[.exchange.stub.getAvailableBalance[`USD] = 9500.0;"Available increased after release"];
 };

testBalanceUpdate:{[]
  / Credit balance
  .exchange.stub.updateBalance[`USD;500.0];
  .test.assert[.exchange.stub.getTotalBalance[`USD] = 10500.0;"Balance increased"];

  / Debit balance
  .exchange.stub.updateBalance[`USD;-1000.0];
  .test.assert[.exchange.stub.getTotalBalance[`USD] = 9500.0;"Balance decreased"];
 };

testInsufficientBalance:{[]
  / Test insufficient balance error
  result:@[{.exchange.stub.placeHold[`USD;20000.0]; 0b};::;{1b}];
  .test.assert[result;"Insufficient balance error thrown"];
 };

/ ============================================================================
/ TESTS - ORDERBOOK GENERATION
/ ============================================================================

testOrderbookGen:{[]
  ob:.exchange.stub.genOrderbook[];

  / Check structure
  .test.assert[20 = count ob;"20 levels (10 bid + 10 ask)"];
  .test.assert[2 = count distinct ob`side;"Both sides present"];

  / Get bids and asks
  bids:select from ob where side=`bid;
  asks:select from ob where side=`ask;

  / Check counts
  .test.assert[10 = count bids;"10 bid levels"];
  .test.assert[10 = count asks;"10 ask levels"];

  / Check price ordering
  .test.assert[bids[`price] ~ desc bids`price;"Bids descending"];
  .test.assert[asks[`price] ~ asc asks`price;"Asks ascending"];

  / Check spread
  bestBid:max bids`price;
  bestAsk:min asks`price;
  .test.assert[bestAsk > bestBid;"Positive spread"];
 };

/ ============================================================================
/ TESTS - ORDER PLACEMENT
/ ============================================================================

testMarketBuyOrder:{[]
  / Place market buy order
  order:.exchange.placeOrder[`stub;`BTCUSD;`market;`buy;0Nj;.qg.toVolume[0.1]];

  / Check order response
  .test.assert[order[`orderId] = 1j;"Order ID assigned"];
  .test.assert[order[`status] in `filled`partially_filled;"Order executed"];
  .test.assert[order[`filled] > 0j;"Some quantity filled"];

  / Check balance changes
  btcBalance:.exchange.stub.getTotalBalance[`BTC];
  .test.assert[btcBalance > 1.0;"BTC balance increased"];
 };

testLimitBuyOrder:{[]
  / Place limit buy order at mid price
  midPrice:.qg.toPrice[100.0];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;midPrice;.qg.toVolume[0.1]];

  / Check order response
  .test.assert[order[`orderId] = 1j;"Order ID assigned"];
  .test.assert[order[`status] in `open`filled`partially_filled;"Order placed"];
 };

testLimitSellOrder:{[]
  / Place limit sell order at mid price
  midPrice:.qg.toPrice[100.0];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`sell;midPrice;.qg.toVolume[0.1]];

  / Check order response
  .test.assert[order[`orderId] = 1j;"Order ID assigned"];
  .test.assert[order[`status] in `open`filled`partially_filled;"Order placed"];

  / Check BTC balance decreased (hold placed)
  btcAvailable:.exchange.stub.getAvailableBalance[`BTC];
  .test.assert[btcAvailable < 1.0;"BTC hold placed"];
 };

testOrderHolds:{[]
  / Place limit buy order (should place hold on USD)
  midPrice:.qg.toPrice[100.0];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;midPrice;.qg.toVolume[0.5]];

  / Check hold placed
  usdAvailable:.exchange.stub.getAvailableBalance[`USD];
  .test.assert[usdAvailable < 10000.0;"USD hold placed for buy order"];
 };

/ ============================================================================
/ TESTS - ORDER CANCELLATION
/ ============================================================================

testCancelOrder:{[]
  / Place order that won't match (low price)
  lowPrice:.qg.toPrice[50.0];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;lowPrice;.qg.toVolume[0.1]];

  / Verify order is open
  .test.assert[order[`status] = `open;"Order is open"];

  / Cancel order
  result:.exchange.cancelOrder[`stub;order`orderId];
  .test.assert[result[`status] = `cancelled;"Order cancelled"];

  / Verify hold released
  usdAvailable:.exchange.stub.getAvailableBalance[`USD];
  .test.assert[usdAvailable = 10000.0;"Hold released after cancel"];
 };

testCancelFilledOrder:{[]
  / Place market order (will fill immediately)
  order:.exchange.placeOrder[`stub;`BTCUSD;`market;`buy;0Nj;.qg.toVolume[0.1]];

  / Attempt to cancel filled order
  result:@[{.exchange.cancelOrder[`stub;x]; 0b};order`orderId;{1b}];
  .test.assert[result;"Cannot cancel filled order"];
 };

/ ============================================================================
/ TESTS - EDGE CASES & ERROR PATHS
/ ============================================================================

testEmptyOrderbook:{[]
  / Generate orderbook with zero depth
  .exchange.stub.setOBParams[`midPrice`spread`depth!(100.0;0.02;0)];
  ob:.exchange.stub.genOrderbook[];
  .test.assert[0 = count ob;"Empty orderbook has zero rows"];
 };

testZeroQuantityOrder:{[]
  / Test zero quantity order (should fail validation)
  result:@[{.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[100.0];0j]; 0b};::;{1b}];
  .test.assert[result;"Zero quantity order rejected"];
 };

testNegativeQuantityOrder:{[]
  / Test negative quantity (should fail validation)
  result:@[{.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[100.0];-1j]; 0b};::;{1b}];
  .test.assert[result;"Negative quantity order rejected"];
 };

testInvalidOrderType:{[]
  / Test invalid order type
  result:@[{.exchange.validateOrderParams[`invalid;`buy;.qg.toPrice[100.0];.qg.toVolume[1.0]]; 0b};::;{1b}];
  .test.assert[result;"Invalid order type rejected"];
 };

testInvalidOrderSide:{[]
  / Test invalid side
  result:@[{.exchange.validateOrderParams[`limit;`invalid;.qg.toPrice[100.0];.qg.toVolume[1.0]]; 0b};::;{1b}];
  .test.assert[result;"Invalid order side rejected"];
 };

testLimitOrderWithoutPrice:{[]
  / Test limit order with null price
  result:@[{.exchange.validateOrderParams[`limit;`buy;0Nj;.qg.toVolume[1.0]]; 0b};::;{1b}];
  .test.assert[result;"Limit order without price rejected"];
 };

testMarketOrderWithPrice:{[]
  / Market order CAN have a price (it will be ignored), so this should succeed
  result:.exchange.validateOrderParams[`market;`buy;.qg.toPrice[100.0];.qg.toVolume[1.0]];
  .test.assert[result;"Market order with price is valid"];
 };

testBalanceUnderflow:{[]
  / Test balance cannot go negative
  result:@[{.exchange.stub.updateBalance[`USD;-20000.0]; 0b};::;{1b}];
  .test.assert[result;"Balance underflow prevented"];
 };

testHoldExceedsAvailable:{[]
  / Test cannot hold more than available
  result:@[{.exchange.stub.placeHold[`USD;15000.0]; 0b};::;{1b}];
  .test.assert[result;"Hold exceeding available rejected"];
 };

testReleaseHoldExceedingCurrent:{[]
  / Place a hold, then try to release more
  .exchange.stub.placeHold[`USD;1000.0];
  result:@[{.exchange.stub.releaseHold[`USD;2000.0]; 0b};::;{1b}];
  .test.assert[result;"Cannot release more than held"];
 };

testReleaseHoldOnNonExistentCurrency:{[]
  / Try to release hold on currency with no holds
  result:@[{.exchange.stub.releaseHold[`EUR;100.0]; 0b};::;{1b}];
  .test.assert[result;"Cannot release hold on non-existent currency"];
 };

testCancelNonExistentOrder:{[]
  / Attempt to cancel non-existent order ID
  result:@[{.exchange.cancelOrder[`stub;99999j]; 0b};::;{1b}];
  .test.assert[result;"Cannot cancel non-existent order"];
 };

testCancelAlreadyCancelledOrder:{[]
  / Place and cancel order
  lowPrice:.qg.toPrice[50.0];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;lowPrice;.qg.toVolume[0.1]];
  .exchange.cancelOrder[`stub;order`orderId];

  / Try to cancel again
  result:@[{.exchange.cancelOrder[`stub;order`orderId]; 0b};::;{1b}];
  .test.assert[result;"Cannot cancel already cancelled order"];
 };

testInvalidTransitions:{[]
  / Test additional invalid state transitions
  .test.assert[not .exchange.isValidTransition[`filled;`cancelled];"filled -> cancelled (invalid)"];
  .test.assert[not .exchange.isValidTransition[`rejected;`filled];"rejected -> filled (invalid)"];
  .test.assert[not .exchange.isValidTransition[`expired;`open];"expired -> open (invalid)"];
  .test.assert[not .exchange.isValidTransition[`cancelled;`filled];"cancelled -> filled (invalid)"];
 };

testInvalidStateNames:{[]
  / Test invalid state names
  .test.assert[not .exchange.isValidTransition[`invalid;`open];"invalid state name rejected"];
  .test.assert[not .exchange.isValidTransition[`open;`invalid];"invalid target state rejected"];
 };

testOrderMatchingWithEmptyOrderbook:{[]
  / Set depth to 0 to create empty orderbook
  .exchange.stub.setOBParams[`midPrice`spread`depth!(100.0;0.02;0)];

  / Place order (should stay open with no fills)
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[100.0];.qg.toVolume[0.1]];

  .test.assert[order[`filled] = 0j;"No fills with empty orderbook"];
  .test.assert[order[`status] = `open;"Order stays open"];
 };

testMaxQuantityOrder:{[]
  / Test very large quantity order
  .exchange.stub.setBalances[`USD`BTC!(1000000.0;100.0)];
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`sell;.qg.toPrice[100.0];.qg.toVolume[50.0]];

  .test.assert[order[`orderId] > 0j;"Large quantity order accepted"];
  .test.assert[order[`quantity] = .qg.toVolume[50.0];"Quantity preserved"];
 };

testConcurrentOrderPlacement:{[]
  / Place multiple orders rapidly
  orders:();
  orders,:enlist .exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[99.0];.qg.toVolume[0.1]];
  orders,:enlist .exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[98.0];.qg.toVolume[0.1]];
  orders,:enlist .exchange.placeOrder[`stub;`BTCUSD;`limit;`sell;.qg.toPrice[101.0];.qg.toVolume[0.1]];

  .test.assert[3 = count orders;"All orders placed"];
  / All should have unique order IDs
  .test.assert[3 = count distinct orders[;`orderId];"Unique order IDs"];
 };

testBalanceAfterPartialFill:{[]
  / Place order that will partially fill
  initialUSD:.exchange.stub.getTotalBalance[`USD];
  order:.exchange.placeOrder[`stub;`BTCUSD;`market;`buy;0Nj;.qg.toVolume[0.5]];

  / Check balance changed
  finalUSD:.exchange.stub.getTotalBalance[`USD];
  .test.assert[finalUSD < initialUSD;"USD balance decreased after buy"];

  btcBalance:.exchange.stub.getTotalBalance[`BTC];
  .test.assert[btcBalance > 1.0;"BTC balance increased"];
 };

testGetOpenOrdersForPair:{[]
  / Place orders on different pairs
  order1:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[90.0];.qg.toVolume[0.1]];
  order2:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[89.0];.qg.toVolume[0.1]];
  order3:.exchange.placeOrder[`stub;`ETHUSD;`limit;`buy;.qg.toPrice[2000.0];.qg.toVolume[1.0]];

  / Get BTCUSD orders only
  btcOrders:.exchange.getOpenOrders[`stub;`BTCUSD];
  .test.assert[2 = count btcOrders;"Two BTCUSD orders"];
  .test.assert[all btcOrders[`pair]=`BTCUSD;"All orders for BTCUSD"];
 };

testRegistryUnregister:{[]
  / Test unregister function
  .exchange.stub.registerStub[];
  .test.assert[.exchange.registry.isRegistered[`stub];"Stub registered"];

  .exchange.registry.unregister[`stub];
  .test.assert[not .exchange.registry.isRegistered[`stub];"Stub unregistered"];

  / Re-register for other tests
  .exchange.stub.registerStub[];
 };

testRegistryInvalidImplementation:{[]
  / Test registering invalid implementation (missing functions)
  badImpl:`placeOrder`cancelOrder!({x};{y});  / Missing required functions
  result:@[{.exchange.registry.register[`bad;x]; 0b};badImpl;{1b}];
  .test.assert[result;"Invalid implementation rejected"];
 };

testRegistryNonFunctionValues:{[]
  / Test registering with non-function values
  badImpl:`placeOrder`cancelOrder`getBalance`getOrderbook`getOpenOrders`getPosition!(
    {x};{y};`notAFunction;"alsoNotAFunction";{z};{w}
  );
  result:@[{.exchange.registry.register[`bad;x]; 0b};badImpl;{1b}];
  .test.assert[result;"Non-function values rejected"];
 };

/ ============================================================================
/ TESTS - REGISTRY
/ ============================================================================

testRegistryLookup:{[]
  / Test registry lookup
  impl:.exchange.registry.getImplementation[`stub];
  .test.assert[99h = type impl;"Implementation is dict"];
  .test.assert[`placeOrder in key impl;"placeOrder function present"];
  .test.assert[`cancelOrder in key impl;"cancelOrder function present"];
 };

testRegistryList:{[]
  / Test list exchanges
  exchanges:.exchange.registry.listExchanges[];
  .test.assert[`stub in exchanges;"Stub exchange listed"];
 };

/ ============================================================================
/ TEST RUNNER
/ ============================================================================

runAllTests:{[]
  -1 "\n========================================";
  -1 "  Exchange Wrapper & Stub Tests";
  -1 "========================================";

  / State machine tests
  .test.runTest[`testValidTransitions;testValidTransitions];

  / Validation tests
  .test.runTest[`testOrderValidation;testOrderValidation];

  / Balance tests
  .test.runTest[`testBalanceInit;testBalanceInit];
  .test.runTest[`testBalanceHolds;testBalanceHolds];
  .test.runTest[`testBalanceUpdate;testBalanceUpdate];
  .test.runTest[`testInsufficientBalance;testInsufficientBalance];

  / Orderbook tests
  .test.runTest[`testOrderbookGen;testOrderbookGen];

  / Order placement tests
  .test.runTest[`testMarketBuyOrder;testMarketBuyOrder];
  .test.runTest[`testLimitBuyOrder;testLimitBuyOrder];
  .test.runTest[`testLimitSellOrder;testLimitSellOrder];
  .test.runTest[`testOrderHolds;testOrderHolds];

  / Order cancellation tests
  .test.runTest[`testCancelOrder;testCancelOrder];
  .test.runTest[`testCancelFilledOrder;testCancelFilledOrder];

  / Registry tests
  .test.runTest[`testRegistryLookup;testRegistryLookup];
  .test.runTest[`testRegistryList;testRegistryList];

  / Edge case tests - Orderbook
  .test.runTest[`testEmptyOrderbook;testEmptyOrderbook];
  .test.runTest[`testOrderMatchingWithEmptyOrderbook;testOrderMatchingWithEmptyOrderbook];

  / Edge case tests - Order validation
  .test.runTest[`testZeroQuantityOrder;testZeroQuantityOrder];
  .test.runTest[`testNegativeQuantityOrder;testNegativeQuantityOrder];
  .test.runTest[`testInvalidOrderType;testInvalidOrderType];
  .test.runTest[`testInvalidOrderSide;testInvalidOrderSide];
  .test.runTest[`testLimitOrderWithoutPrice;testLimitOrderWithoutPrice];
  .test.runTest[`testMarketOrderWithPrice;testMarketOrderWithPrice];
  .test.runTest[`testMaxQuantityOrder;testMaxQuantityOrder];

  / Edge case tests - Balance
  .test.runTest[`testBalanceUnderflow;testBalanceUnderflow];
  .test.runTest[`testHoldExceedsAvailable;testHoldExceedsAvailable];
  .test.runTest[`testReleaseHoldExceedingCurrent;testReleaseHoldExceedingCurrent];
  .test.runTest[`testReleaseHoldOnNonExistentCurrency;testReleaseHoldOnNonExistentCurrency];
  .test.runTest[`testBalanceAfterPartialFill;testBalanceAfterPartialFill];

  / Edge case tests - Order cancellation
  .test.runTest[`testCancelNonExistentOrder;testCancelNonExistentOrder];
  .test.runTest[`testCancelAlreadyCancelledOrder;testCancelAlreadyCancelledOrder];

  / Edge case tests - State machine
  .test.runTest[`testInvalidTransitions;testInvalidTransitions];
  .test.runTest[`testInvalidStateNames;testInvalidStateNames];

  / Edge case tests - Multiple orders
  .test.runTest[`testConcurrentOrderPlacement;testConcurrentOrderPlacement];
  .test.runTest[`testGetOpenOrdersForPair;testGetOpenOrdersForPair];

  / Edge case tests - Registry
  .test.runTest[`testRegistryUnregister;testRegistryUnregister];
  .test.runTest[`testRegistryInvalidImplementation;testRegistryInvalidImplementation];
  .test.runTest[`testRegistryNonFunctionValues;testRegistryNonFunctionValues];

  / Summary
  -1 "\n========================================";
  -1 "  Test Results";
  -1 "========================================";
  -1 "  Passed: ",string .test.passed;
  -1 "  Failed: ",string .test.failed;
  -1 "========================================";

  / Exit with status code
  exit $[.test.failed = 0; 0; 1];
 };

/ Run tests
runAllTests[]
