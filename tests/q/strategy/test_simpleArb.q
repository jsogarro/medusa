/ ============================================================================
/ test_simpleArb.q - Simple Arbitrage Strategy Tests
/ ============================================================================

/ Load dependencies
\l src/q/engine/types.q
\l src/q/engine/strategy.q
\l src/q/strategy/arb.q
\l src/q/strategy/simpleArb.q

/ Simple assertion framework
assert:{[cond;msg] if[not cond;-1 "FAIL: ",msg;exit 1]};

/ Test fixtures
.test.validConfig:`exchanges`pair`minProfitUSD`minProfitBps`maxPositionSize`maxOrderSize`enabled!(
  `GDAX`Kraken;
  `BTCUSD;
  5.0;
  50.0;
  10.0;
  2.0;
  1b
 );

.test.orderbooks:()!();
.test.orderbooks[`GDAX]:([]
  side:`ask`ask`bid`bid;
  price:100.50 101.00 99.50 99.00;
  volume:1.0 2.0 1.5 2.0
 );
.test.orderbooks[`Kraken]:([]
  side:`bid`bid`ask`ask;
  price:101.50 101.00 100.00 100.50;
  volume:0.5 1.0 1.0 2.0
 );

// ============================================================================
/ CONFIGURATION TESTS
// ============================================================================

-1 "\n=== Testing Configuration ===";

/ Test: Valid config passes validation
validatedConfig:.strategy.simpleArb.validateConfig[.test.validConfig];
assert[`exchanges in key validatedConfig; "Config should have exchanges"];
assert[`pair in key validatedConfig; "Config should have pair"];

/ Test: Missing exchanges fails
invalidConfig1:delete exchanges from .test.validConfig;
result:@[.strategy.simpleArb.validateConfig; invalidConfig1; {`error}];
assert[result ~ `error; "Missing exchanges should fail validation"];

/ Test: Single exchange fails (need at least 2)
invalidConfig2:.test.validConfig;
invalidConfig2[`exchanges]:enlist `GDAX;
result:@[.strategy.simpleArb.validateConfig; invalidConfig2; {`error}];
assert[result ~ `error; "Single exchange should fail validation"];

/ Test: Invalid exchange type fails
invalidConfig3:.test.validConfig;
invalidConfig3[`exchanges]:`GDAX; / atom instead of list
result:@[.strategy.simpleArb.validateConfig; invalidConfig3; {`error}];
assert[result ~ `error; "Non-list exchanges should fail validation"];

/ Test: Negative minProfitUSD fails
invalidConfig4:.test.validConfig;
invalidConfig4[`minProfitUSD]:-1.0;
result:@[.strategy.simpleArb.validateConfig; invalidConfig4; {`error}];
assert[result ~ `error; "Negative minProfitUSD should fail validation"];

-1 "Configuration tests: PASSED";

// ============================================================================
/ STRATEGY LIFECYCLE TESTS
// ============================================================================

-1 "\n=== Testing Strategy Lifecycle ===";

/ Test: Create strategy instance
strategy:.strategy.simpleArb.new[`testArb; "Test Arbitrage"; `actor1; .test.validConfig];
assert[strategy[`id] ~ `testArb; "Strategy should have correct ID"];
assert[strategy[`name] ~ "Test Arbitrage"; "Strategy should have correct name"];
assert[strategy[`status] ~ `init; "Strategy should start in init status"];
assert[strategy[`mode] ~ `dryrun; "Strategy should default to dryrun mode"];

/ Test: Strategy configuration is applied
assert[strategy[`config;`exchanges] ~ `GDAX`Kraken; "Config exchanges should be set"];
assert[strategy[`config;`pair] ~ `BTCUSD; "Config pair should be set"];

/ Test: setUp initializes state
strategy:.engine.strategy.setUp[strategy];
assert[strategy[`status] ~ `ready; "Strategy should be ready after setUp"];
assert[strategy[`state;`position] = 0.0; "Initial position should be 0"];
assert[strategy[`state;`tradesExecuted] = 0; "Initial trades should be 0"];
assert[strategy[`state;`totalProfit] = 0.0; "Initial profit should be 0"];

/ Test: start transitions to running
strategy:.engine.strategy.start[strategy];
assert[strategy[`status] ~ `running; "Strategy should be running after start"];

/ Test: tearDown transitions to stopped
strategy:.engine.strategy.tearDown[strategy];
assert[strategy[`status] ~ `stopped; "Strategy should be stopped after tearDown"];

-1 "Strategy lifecycle tests: PASSED";

// ============================================================================
/ OPPORTUNITY DETECTION TESTS
// ============================================================================

-1 "\n=== Testing Opportunity Detection ===";

/ Test: Detect opportunities from orderbooks
opportunities:.strategy.simpleArb.detectOpportunities[
  .test.orderbooks;
  `BTCUSD;
  `GDAX`Kraken
];

assert[0 < count opportunities; "Should detect at least one opportunity"];
assert[`buyExchange in cols opportunities; "Opportunity should have buyExchange"];
assert[`sellExchange in cols opportunities; "Opportunity should have sellExchange"];
assert[`profit in cols opportunities; "Opportunity should have profit"];
assert[`volume in cols opportunities; "Opportunity should have volume"];

/ Test: Opportunities are sorted by profit descending
if[1 < count opportunities;
  profits:exec profit from opportunities;
  assert[profits ~ desc profits; "Opportunities should be sorted by profit descending"];
];

/ Test: Empty orderbooks return no opportunities
emptyOrderbooks:()!();
emptyOpportunities:.strategy.simpleArb.detectOpportunities[emptyOrderbooks; `BTCUSD; `GDAX`Kraken];
assert[0 = count emptyOpportunities; "Empty orderbooks should return no opportunities"];

-1 "Opportunity detection tests: PASSED";

// ============================================================================
/ EXECUTION LOGIC TESTS
// ============================================================================

-1 "\n=== Testing Execution Logic ===";

/ Create fresh strategy for execution tests
strategy:.strategy.simpleArb.new[`execTest; "Exec Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

/ Mock opportunity that passes thresholds
goodOpportunity:`buyExchange`sellExchange`volume`revenue`fees`profit!(
  `GDAX;
  `Kraken;
  1.0;
  100.0;
  0.2;
  10.0 / $10 profit
 );

/ Test: Good opportunity is executed
initialTrades:strategy[`state;`tradesExecuted];
strategy:.strategy.simpleArb.evaluateAndExecute[strategy; goodOpportunity];
assert[strategy[`state;`tradesExecuted] = initialTrades + 1; "Trade should be executed"];
assert[strategy[`state;`totalProfit] = 10.0; "Profit should be accumulated"];

/ Mock opportunity below profit threshold
lowProfitOpportunity:`buyExchange`sellExchange`volume`revenue`fees`profit!(
  `GDAX;
  `Kraken;
  1.0;
  100.0;
  0.2;
  2.0 / $2 profit < $5 min
 );

/ Test: Low profit opportunity is rejected
beforeTrades:strategy[`state;`tradesExecuted];
strategy:.strategy.simpleArb.evaluateAndExecute[strategy; lowProfitOpportunity];
assert[strategy[`state;`tradesExecuted] = beforeTrades; "Low profit trade should be rejected"];

/ Mock opportunity below profit bps threshold
lowBpsOpportunity:`buyExchange`sellExchange`volume`revenue`fees`profit!(
  `GDAX;
  `Kraken;
  1.0;
  10000.0; / large revenue
  0.2;
  10.0 / $10 profit on $10k = 10 bps < 50 bps min
 );

/ Test: Low bps opportunity is rejected
beforeTrades:strategy[`state;`tradesExecuted];
strategy:.strategy.simpleArb.evaluateAndExecute[strategy; lowBpsOpportunity];
assert[strategy[`state;`tradesExecuted] = beforeTrades; "Low bps trade should be rejected"];

/ Test: Position limit enforcement
/ Set position near limit
strategy[`state;`position]:9.5; / maxPosition is 10.0
largeOpportunity:`buyExchange`sellExchange`volume`revenue`fees`profit!(
  `GDAX;
  `Kraken;
  1.0; / Would push position to 10.5
  100.0;
  0.2;
  15.0
 );
beforeTrades:strategy[`state;`tradesExecuted];
strategy:.strategy.simpleArb.evaluateAndExecute[strategy; largeOpportunity];
assert[strategy[`state;`tradesExecuted] = beforeTrades; "Position limit should prevent trade"];

-1 "Execution logic tests: PASSED";

// ============================================================================
/ TICK EXECUTION TESTS
// ============================================================================

-1 "\n=== Testing Tick Execution ===";

/ Create fresh strategy
strategy:.strategy.simpleArb.new[`tickTest; "Tick Test"; `actor1; .test.validConfig];
strategy:.engine.strategy.setUp[strategy];
strategy:.engine.strategy.start[strategy];

/ Create execution context with orderbooks
ctx:.engine.types.newExecContext[0; `harness];
ctx[`orderbooks]:.test.orderbooks;

/ Test: Tick execution
initialTrades:strategy[`state;`tradesExecuted];
strategy:.engine.strategy.tick[strategy; ctx];
/ Should have attempted to execute opportunities (may or may not execute depending on thresholds)
assert[`lastCheck in key strategy`state; "lastCheck should be updated in preTick"];

/ Test: Disabled strategy doesn't execute
strategy[`config;`enabled]:0b;
beforeTrades:strategy[`state;`tradesExecuted];
strategy:.engine.strategy.tick[strategy; ctx];
assert[strategy[`state;`tradesExecuted] = beforeTrades; "Disabled strategy should not execute"];

-1 "Tick execution tests: PASSED";

// ============================================================================
/ INTEGRATION TESTS
// ============================================================================

-1 "\n=== Integration Tests ===";

/ Test: Full strategy lifecycle
strategy:.strategy.simpleArb.new[`integrationTest; "Integration Test"; `actor1; .test.validConfig];

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
  strategy:.engine.strategy.preTick[strategy; ctx];
  strategy:.engine.strategy.tick[strategy; ctx];
  strategy:.engine.strategy.postTick[strategy; ctx];
];

/ Teardown
strategy:.engine.strategy.tearDown[strategy];
assert[strategy[`status] ~ `stopped; "Strategy should be stopped"];

-1 "Integration tests: PASSED";

-1 "\n=== All Simple Arbitrage Strategy Tests PASSED ===\n";
