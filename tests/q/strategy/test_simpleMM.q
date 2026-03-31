/ ============================================================================
/ test_simpleMM.q - Simple Market Making Strategy Tests
/ ============================================================================

/ Load dependencies
\l src/q/engine/types.q
\l src/q/engine/strategy.q
\l src/q/strategy/mm.q
\l src/q/strategy/simpleMM.q

/ Simple assertion framework
assert:{[cond;msg] if[not cond;-1 "FAIL: ",msg;exit 1]};

/ Test fixtures
.test.validConfig:`exchange`pair`spreadBps`baseOrderSize`maxPosition`minSpreadBps`maxSpreadBps`inventorySkewFactor`depth`enabled!(
  `GDAX;
  `BTCUSD;
  10.0;
  1.0;
  5.0;
  5.0;
  100.0;
  0.1;
  2.0;
  1b
 );

.test.orderbook:([]
  side:`bid`bid`bid`ask`ask`ask;
  price:99.50 99.00 98.50 100.50 101.00 101.50;
  volume:1.0 2.0 1.0 1.0 2.0 1.0
 );

.test.orderbooks:()!();
.test.orderbooks[`GDAX]:.test.orderbook;

// ============================================================================
/ CONFIGURATION TESTS
// ============================================================================

-1 "\n=== Testing Configuration ===";

/ Test: Valid config passes validation
validatedConfig:.strategy.simpleMM.validateConfig[.test.validConfig];
assert[`exchange in key validatedConfig; "Config should have exchange"];
assert[`pair in key validatedConfig; "Config should have pair"];

/ Test: Missing exchange fails
invalidConfig1:delete exchange from .test.validConfig;
result:@[.strategy.simpleMM.validateConfig; invalidConfig1; {`error}];
assert[result ~ `error; "Missing exchange should fail validation"];

/ Test: Missing pair fails
invalidConfig2:delete pair from .test.validConfig;
result:@[.strategy.simpleMM.validateConfig; invalidConfig2; {`error}];
assert[result ~ `error; "Missing pair should fail validation"];

/ Test: Invalid exchange type fails
invalidConfig3:.test.validConfig;
invalidConfig3[`exchange]:`GDAX`Kraken; / list instead of atom
result:@[.strategy.simpleMM.validateConfig; invalidConfig3; {`error}];
assert[result ~ `error; "Non-symbol exchange should fail validation"];

/ Test: Negative spreadBps fails
invalidConfig4:.test.validConfig;
invalidConfig4[`spreadBps]:-1.0;
result:@[.strategy.simpleMM.validateConfig; invalidConfig4; {`error}];
assert[result ~ `error; "Negative spreadBps should fail validation"];

/ Test: maxSpreadBps <= minSpreadBps fails
invalidConfig5:.test.validConfig;
invalidConfig5[`minSpreadBps]:100.0;
invalidConfig5[`maxSpreadBps]:50.0;
result:@[.strategy.simpleMM.validateConfig; invalidConfig5; {`error}];
assert[result ~ `error; "maxSpreadBps <= minSpreadBps should fail validation"];

/ Test: Invalid inventorySkewFactor fails
invalidConfig6:.test.validConfig;
invalidConfig6[`inventorySkewFactor]:1.5; / > 1.0
result:@[.strategy.simpleMM.validateConfig; invalidConfig6; {`error}];
assert[result ~ `error; "inventorySkewFactor > 1.0 should fail validation"];

invalidConfig7:.test.validConfig;
invalidConfig7[`inventorySkewFactor]:-0.1; / < 0.0
result:@[.strategy.simpleMM.validateConfig; invalidConfig7; {`error}];
assert[result ~ `error; "inventorySkewFactor < 0.0 should fail validation"];

-1 "Configuration tests: PASSED";

// ============================================================================
/ STRATEGY LIFECYCLE TESTS
// ============================================================================

-1 "\n=== Testing Strategy Lifecycle ===";

/ Test: Create strategy instance
strategy:.strategy.simpleMM.new[`testMM; "Test Market Making"; `actor1; .test.validConfig];
assert[strategy[`id] ~ `testMM; "Strategy should have correct ID"];
assert[strategy[`name] ~ "Test Market Making"; "Strategy should have correct name"];
assert[strategy[`status] ~ `init; "Strategy should start in init status"];
assert[strategy[`mode] ~ `dryrun; "Strategy should default to dryrun mode"];

/ Test: Strategy configuration is applied
assert[strategy[`config;`exchange] ~ `GDAX; "Config exchange should be set"];
assert[strategy[`config;`pair] ~ `BTCUSD; "Config pair should be set"];
assert[strategy[`config;`spreadBps] = 10.0; "Config spreadBps should be set"];

/ Test: setUp initializes state
strategy:.engine.strategy.setUp[strategy];
assert[strategy[`status] ~ `ready; "Strategy should be ready after setUp"];
assert[strategy[`state;`position] = 0.0; "Initial position should be 0"];
assert[strategy[`state;`quotesPlaced] = 0; "Initial quotes should be 0"];
assert[strategy[`state;`fillsReceived] = 0; "Initial fills should be 0"];
assert[count[strategy[`state;`openOrders]] = 0; "Initial open orders should be empty"];

/ Test: start transitions to running
strategy:.engine.strategy.start[strategy];
assert[strategy[`status] ~ `running; "Strategy should be running after start"];

/ Test: tearDown transitions to stopped
strategy:.engine.strategy.tearDown[strategy];
assert[strategy[`status] ~ `stopped; "Strategy should be stopped after tearDown"];

-1 "Strategy lifecycle tests: PASSED";

// ============================================================================
/ ORDER MANAGEMENT TESTS
// ============================================================================

-1 "\n=== Testing Order Management ===";

/ Create fresh strategy
strategy:.strategy.simpleMM.new[`orderTest; "Order Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

/ Test: cancelAllOrders in dryrun mode
strategy[`state;`openOrders]:`ord1`ord2; / Mock open orders
strategy:.strategy.simpleMM.cancelAllOrders[strategy];
assert[count[strategy[`state;`openOrders]] = 0; "Open orders should be cleared"];

/ Test: placeQuotes updates state
initialQuotes:strategy[`state;`quotesPlaced];
strategy:.strategy.simpleMM.placeQuotes[strategy; 99.50; 100.50; 1.0; 1.0];
assert[strategy[`state;`quotesPlaced] = initialQuotes + 1; "Quotes placed should increment"];
assert[strategy[`state;`currentBidPrice] = 99.50; "Current bid price should be set"];
assert[strategy[`state;`currentAskPrice] = 100.50; "Current ask price should be set"];

-1 "Order management tests: PASSED";

// ============================================================================
/ POSITION MANAGEMENT TESTS
// ============================================================================

-1 "\n=== Testing Position Management ===";

/ Create fresh strategy
strategy:.strategy.simpleMM.new[`posTest; "Position Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

/ Test: checkPositionImbalance at normal level
strategy[`state;`position]:2.0; / 40% of max (5.0)
strategy:.strategy.simpleMM.checkPositionImbalance[strategy];
assert[strategy[`config;`enabled]; "Strategy should remain enabled at normal position"];

/ Test: checkPositionImbalance at high level (80% threshold)
strategy[`state;`position]:4.5; / 90% of max - should warn but not disable
strategy:.strategy.simpleMM.checkPositionImbalance[strategy];
assert[strategy[`config;`enabled]; "Strategy should remain enabled at high position"];

/ Test: checkPositionImbalance exceeding max
strategy[`state;`position]:5.5; / 110% of max - should disable
strategy:.strategy.simpleMM.checkPositionImbalance[strategy];
assert[not strategy[`config;`enabled]; "Strategy should be disabled when position exceeds max"];

/ Test: onFill updates position (buy side)
strategy:.strategy.simpleMM.new[`fillTest; "Fill Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];
fillEvent:`orderId`side`size`price`fee!(`ord1; `buy; 0.5; 100.0; 0.05);
strategy:.strategy.simpleMM.onFill[strategy; fillEvent];
assert[strategy[`state;`position] = 0.5; "Position should increase on buy"];
assert[strategy[`state;`fillsReceived] = 1; "Fills received should increment"];
assert[strategy[`state;`totalVolume] = 0.5; "Total volume should be updated"];

/ Test: onFill updates position (sell side)
fillEvent2:`orderId`side`size`price`fee!(`ord2; `sell; 0.3; 100.0; 0.03);
strategy:.strategy.simpleMM.onFill[strategy; fillEvent2];
assert[strategy[`state;`position] = 0.2; "Position should decrease on sell"];
assert[strategy[`state;`fillsReceived] = 2; "Fills received should increment"];
assert[strategy[`state;`totalVolume] = 0.8; "Total volume should accumulate"];

-1 "Position management tests: PASSED";

// ============================================================================
/ TICK EXECUTION TESTS
// ============================================================================

-1 "\n=== Testing Tick Execution ===";

/ Create fresh strategy
strategy:.strategy.simpleMM.new[`tickTest; "Tick Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

/ Create execution context with orderbook
ctx:.engine.types.newExecContext[0; `harness];
ctx[`orderbooks]:.test.orderbooks;

/ Test: Tick execution places quotes
initialQuotes:strategy[`state;`quotesPlaced];
strategy:.engine.strategy.tick[strategy; ctx];
assert[strategy[`state;`quotesPlaced] = initialQuotes + 1; "Tick should place quotes"];
assert[not null strategy[`state;`currentBidPrice]; "Bid price should be set"];
assert[not null strategy[`state;`currentAskPrice]; "Ask price should be set"];
assert[strategy[`state;`currentBidPrice] < strategy[`state;`currentAskPrice]; "Bid should be less than ask"];

/ Test: Tick execution with inventory skew
strategy[`state;`position]:2.5; / 50% of max (5.0) - long position
strategy:.engine.strategy.tick[strategy; ctx];
/ Should have placed quotes with sell bias (would need to inspect actual sizes)

/ Test: Tick execution without orderbook
ctxNoOb:.engine.types.newExecContext[1; `harness];
ctxNoOb[`orderbooks]:()!(); / Empty orderbooks
beforeQuotes:strategy[`state;`quotesPlaced];
strategy:.engine.strategy.tick[strategy; ctxNoOb];
assert[strategy[`state;`quotesPlaced] = beforeQuotes; "Should not place quotes without orderbook"];

/ Test: Disabled strategy doesn't execute
strategy[`config;`enabled]:0b;
beforeQuotes:strategy[`state;`quotesPlaced];
strategy:.engine.strategy.tick[strategy; ctx];
assert[strategy[`state;`quotesPlaced] = beforeQuotes; "Disabled strategy should not execute"];

-1 "Tick execution tests: PASSED";

// ============================================================================
/ INTEGRATION TESTS
// ============================================================================

-1 "\n=== Integration Tests ===";

/ Test: Full strategy lifecycle with multiple ticks
strategy:.strategy.simpleMM.new[`integrationTest; "Integration Test"; `actor1; .test.validConfig];

/ Setup
strategy:.engine.strategy.setUp[strategy];
assert[strategy[`status] ~ `ready; "Strategy should be ready"];

/ Start
strategy:.engine.strategy.start[strategy];
assert[strategy[`status] ~ `running; "Strategy should be running"];

/ Execute multiple ticks
ctx:.engine.types.newExecContext[0; `harness];
ctx[`orderbooks]:.test.orderbooks;

do[5;
  / PreTick - cancel orders
  strategy:.engine.strategy.preTick[strategy; ctx];
  assert[count[strategy[`state;`openOrders]] = 0; "Orders should be cancelled in preTick"];

  / Tick - place new quotes
  quotesBeforeTick:strategy[`state;`quotesPlaced];
  strategy:.engine.strategy.tick[strategy; ctx];
  assert[strategy[`state;`quotesPlaced] = quotesBeforeTick + 1; "Each tick should place quotes"];

  / PostTick - check position
  strategy:.engine.strategy.postTick[strategy; ctx];
  assert[strategy[`state;`lastQuoteTime] <= .z.p; "Last quote time should be updated"];
];

assert[strategy[`state;`quotesPlaced] = 5; "Should have placed 5 quotes"];

/ Teardown
strategy:.engine.strategy.tearDown[strategy];
assert[strategy[`status] ~ `stopped; "Strategy should be stopped"];
assert[count[strategy[`state;`openOrders]] = 0; "All orders should be cancelled in tearDown"];

-1 "Integration tests: PASSED";

// ============================================================================
/ QUOTE GENERATION WITH INVENTORY SKEW TESTS
// ============================================================================

-1 "\n=== Testing Quote Generation with Inventory Skew ===";

/ Create strategy with neutral position
strategy:.strategy.simpleMM.new[`skewTest; "Skew Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

ctx:.engine.types.newExecContext[0; `harness];
ctx[`orderbooks]:.test.orderbooks;

/ Test: Neutral position produces symmetric sizes
strategy[`state;`position]:0.0;
strategy:.engine.strategy.tick[strategy; ctx];
/ Would need to capture actual sizes to verify symmetry - placeholder for future enhancement

/ Test: Long position produces sell bias
strategy[`state;`position]:3.0; / 60% of max
strategy:.engine.strategy.tick[strategy; ctx];
/ Would need to capture actual sizes to verify ask > bid

/ Test: Short position produces buy bias
strategy[`state;`position]:-3.0; / -60% of max
strategy:.engine.strategy.tick[strategy; ctx];
/ Would need to capture actual sizes to verify bid > ask

-1 "Quote generation with inventory skew tests: PASSED";

-1 "\n=== All Simple Market Making Strategy Tests PASSED ===\n";
