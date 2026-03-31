/ ============================================================================
/ test_coordinator.q - Tests for Exchange Coordinator
/ ============================================================================

/ Simple assertion helper
assert:{[cond;msg] if[not cond;'"FAIL: ",msg]};

/ Load coordinator module
\l src/q/exchange/base.q
\l src/q/exchange/registry.q
\l src/q/exchange/stub.q
\l src/q/exchange/coordinator.q

/ ============================================================================
/ TEST: Initialization
/ ============================================================================

.test.coord.testInit:{[]
  / Initialize coordinator
  result:.exchange.coordinator.init[];

  / Verify initialization
  assert[result; "init should return 1b"];
  assert[0=count .exchange.coordinator.connections; "connections should be empty after init"];
  assert[0=count .exchange.coordinator.balances; "balances should be empty after init"];
  assert[0=count .exchange.coordinator.positions; "positions should be empty after init"];

  -1 "  PASS: testInit";
 };

/ ============================================================================
/ TEST: Connection Management
/ ============================================================================

.test.coord.testConnect:{[]
  / Initialize coordinator
  .exchange.coordinator.init[];

  / Register stub exchange
  .exchange.registry.register[`stub;.exchange.stub.implementation];

  / Connect to stub exchange
  result:.exchange.coordinator.connect[`stub];

  / Verify connection
  assert[result; "connect should return 1b"];
  assert[1=count .exchange.coordinator.connections; "connections should have 1 entry"];
  assert[.exchange.coordinator.isConnected[`stub]; "stub should be connected"];

  / Verify connection details
  conn:.exchange.coordinator.connections[`stub];
  assert[conn`connected; "connected flag should be true"];

  -1 "  PASS: testConnect";
 };

.test.coord.testDisconnect:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Disconnect
  result:.exchange.coordinator.disconnect[`stub];

  / Verify disconnection
  assert[result; "disconnect should return 1b"];
  assert[not .exchange.coordinator.isConnected[`stub]; "stub should not be connected"];
  assert[0=count .exchange.coordinator.connections; "connections should be empty"];

  -1 "  PASS: testDisconnect";
 };

/ ============================================================================
/ TEST: Order Routing
/ ============================================================================

.test.coord.testPlaceOrder:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Place order
  result:.exchange.coordinator.placeOrder[`stub;`BTCUSD;`limit;`buy;50000;0.01];

  / Verify result
  assert[`orderId in key result; "result should contain orderId"];
  assert[`status in key result; "result should contain status"];
  assert[result[`status] in `open`pending; "status should be open or pending"];

  / Verify routing was recorded
  assert[result`orderId in key .exchange.coordinator.orderRouting; "order should be in routing table"];

  -1 "  PASS: testPlaceOrder";
 };

/ ============================================================================
/ TEST: Balance Management
/ ============================================================================

.test.coord.testGetBalance:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Get balance
  balance:.exchange.coordinator.getBalance[`stub;`USD];

  / Verify balance
  assert[`amount in key balance; "balance should contain amount"];
  assert[`available in key balance; "balance should contain available"];
  assert[`reserved in key balance; "balance should contain reserved"];

  / Verify cache
  cacheKey:(`stub;`USD);
  assert[cacheKey in key .exchange.coordinator.balances; "balance should be cached"];

  -1 "  PASS: testGetBalance";
 };

.test.coord.testBalanceCache:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Get balance (first call - cache miss)
  balance1:.exchange.coordinator.getBalance[`stub;`USD];

  / Get balance again (second call - should hit cache)
  balance2:.exchange.coordinator.getBalance[`stub;`USD];

  / Verify both calls return same result
  assert[balance1[`amount] = balance2[`amount]; "cached balance should match"];

  -1 "  PASS: testBalanceCache";
 };

/ ============================================================================
/ TEST: Position Aggregation
/ ============================================================================

.test.coord.testGetPosition:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Get position
  position:.exchange.coordinator.getPosition[`stub;`BTCUSD];

  / Verify position
  assert[`quantity in key position; "position should contain quantity"];
  assert[`avgPrice in key position; "position should contain avgPrice"];

  -1 "  PASS: testGetPosition";
 };

/ ============================================================================
/ TEST: Health Monitoring
/ ============================================================================

.test.coord.testHealthStatus:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Get health status
  status:.exchange.coordinator.getHealthStatus[`stub];

  / Verify status
  assert[`status in key status; "health should contain status"];
  assert[status[`status] in `healthy`stale`disconnected; "status should be valid"];

  -1 "  PASS: testHealthStatus";
 };

.test.coord.testHealthDegradation:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Simulate N errors to trigger health degradation
  / (Direct manipulation of health state for testing)
  i:0;
  while[i < .exchange.coordinator.maxErrorCount;
    .exchange.coordinator.updateHealth[`stub;0b];
    i+:1;
  ];

  / Verify exchange is marked unhealthy
  assert[not .exchange.coordinator.isConnected[`stub]; "exchange should be disconnected after max errors"];

  / Verify error count
  conn:.exchange.coordinator.connections[`stub];
  assert[conn[`errorCount] = .exchange.coordinator.maxErrorCount; "error count should equal max"];

  -1 "  PASS: testHealthDegradation";
 };

/ ============================================================================
/ TEST: Mode Enforcement
/ ============================================================================

.test.coord.testModeEnforcement:{[]
  / Initialize coordinator
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];

  / Verify default mode is dryrun
  assert[.exchange.coordinator.coordinatorMode = `dryrun; "default mode should be dryrun"];

  / Place order in dry-run mode
  result:.exchange.coordinator.placeOrder[`stub;`BTCUSD;`limit;`buy;50000;0.01];

  / Verify order was simulated
  assert[result[`status] = `simulated; "order should be simulated in dry-run mode"];

  / Switch to live mode
  .exchange.coordinator.setMode[`live];
  assert[.exchange.coordinator.coordinatorMode = `live; "mode should be live"];

  / Place order in live mode
  result2:.exchange.coordinator.placeOrder[`stub;`BTCUSD;`limit;`buy;50000;0.01];

  / Verify order was actually placed (not simulated)
  assert[not result2[`status] = `simulated; "order should not be simulated in live mode"];

  -1 "  PASS: testModeEnforcement";
 };

/ ============================================================================
/ TEST: Input Validation
/ ============================================================================

.test.coord.testInputValidation:{[]
  / Initialize and connect
  .exchange.coordinator.init[];
  .exchange.registry.register[`stub;.exchange.stub.implementation];
  .exchange.coordinator.connect[`stub];
  .exchange.coordinator.setMode[`live];

  / Test negative price
  result:@[.exchange.coordinator.placeOrder;(`stub;`BTCUSD;`limit;`buy;-100;0.01);{x}];
  assert[10h = type result; "negative price should throw error"];

  / Test zero price
  result:@[.exchange.coordinator.placeOrder;(`stub;`BTCUSD;`limit;`buy;0;0.01);{x}];
  assert[10h = type result; "zero price should throw error"];

  / Test negative volume
  result:@[.exchange.coordinator.placeOrder;(`stub;`BTCUSD;`limit;`buy;50000;-0.01);{x}];
  assert[10h = type result; "negative volume should throw error"];

  / Test zero volume
  result:@[.exchange.coordinator.placeOrder;(`stub;`BTCUSD;`limit;`buy;50000;0);{x}];
  assert[10h = type result; "zero volume should throw error"];

  / Test invalid side
  result:@[.exchange.coordinator.placeOrder;(`stub;`BTCUSD;`limit;`invalid;50000;0.01);{x}];
  assert[10h = type result; "invalid side should throw error"];

  / Test null pair
  result:@[.exchange.coordinator.placeOrder;(`stub;`;`limit;`buy;50000;0.01);{x}];
  assert[10h = type result; "null pair should throw error"];

  -1 "  PASS: testInputValidation";
 };

/ Test: rapid sequential orders are individually tracked (q is single-threaded)
.test.coord.testSequentialOrderDedup:{[]
  .exchange.coordinator.init[];
  .exchange.coordinator.connect[`stub];
  .exchange.coordinator.setMode[`live];

  / Place 3 rapid orders — each should get unique orderId
  r1:.exchange.coordinator.placeOrder[`stub;`BTCUSD;`limit;`buy;50000;0.01];
  r2:.exchange.coordinator.placeOrder[`stub;`BTCUSD;`limit;`buy;50000;0.01];
  r3:.exchange.coordinator.placeOrder[`stub;`ETHUSD;`limit;`sell;3000;0.5];

  / All should succeed with distinct orderIds
  assert[not r1[`orderId] ~ r2[`orderId]; "Sequential orders should have unique IDs"];
  assert[not r2[`orderId] ~ r3[`orderId]; "Sequential orders should have unique IDs"];

  / Routing table should have all 3
  assert[3 <= count .exchange.coordinator.orderRouting; "All 3 orders should be routed"];

  -1 "  PASS: testSequentialOrderDedup";
 };

/ ============================================================================
/ RUN ALL TESTS
/ ============================================================================

.test.coord.runAll:{[]
  -1 "";
  -1 "Running Exchange Coordinator Tests...";
  -1 "======================================";

  .test.coord.testInit[];
  .test.coord.testConnect[];
  .test.coord.testDisconnect[];
  .test.coord.testPlaceOrder[];
  .test.coord.testGetBalance[];
  .test.coord.testBalanceCache[];
  .test.coord.testGetPosition[];
  .test.coord.testHealthStatus[];
  .test.coord.testHealthDegradation[];
  .test.coord.testModeEnforcement[];
  .test.coord.testInputValidation[];
  .test.coord.testSequentialOrderDedup[];

  -1 "";
  -1 "All Exchange Coordinator Tests Passed!";
  -1 "";
 };

/ Run tests
.test.coord.runAll[];

/ Exit
\\
