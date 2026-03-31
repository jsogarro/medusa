/ ============================================================================
/ coordinator_example.q - Example Usage of Exchange Coordinator
/ ============================================================================

/ Load dependencies
\l src/q/exchange/base.q
\l src/q/exchange/registry.q
\l src/q/exchange/stub.q
\l src/q/exchange/coordinator.q

-1 "";
-1 "Exchange Coordinator Example";
-1 "=============================";
-1 "";

/ ============================================================================
/ 1. Initialize Coordinator
/ ============================================================================

-1 "1. Initializing coordinator...";
.exchange.coordinator.init[];
-1 "";

/ ============================================================================
/ 2. Register and Connect Exchanges
/ ============================================================================

-1 "2. Connecting to exchanges...";

/ Register stub implementations for demonstration
.exchange.registry.register[`kraken;.exchange.stub.implementation];
.exchange.registry.register[`coinbase;.exchange.stub.implementation];
.exchange.registry.register[`bitstamp;.exchange.stub.implementation];

/ Connect to exchanges
.exchange.coordinator.connect[`kraken];
.exchange.coordinator.connect[`coinbase];
.exchange.coordinator.connect[`bitstamp];

-1 "  Connected exchanges:";
show exec exchange from .exchange.coordinator.connections;
-1 "";

/ ============================================================================
/ 3. Check Exchange Health
/ ============================================================================

-1 "3. Checking exchange health...";
show .exchange.coordinator.getAllHealthStatus[];
-1 "";

/ ============================================================================
/ 4. Get Balances
/ ============================================================================

-1 "4. Fetching balances...";

/ Get USD balance on Kraken
krakenUSD:.exchange.coordinator.getBalance[`kraken;`USD];
-1 "  Kraken USD balance:";
show krakenUSD;

/ Get BTC balance on Coinbase
coinbaseBTC:.exchange.coordinator.getBalance[`coinbase;`BTC];
-1 "  Coinbase BTC balance:";
show coinbaseBTC;
-1 "";

/ ============================================================================
/ 5. Place Orders
/ ============================================================================

-1 "5. Placing orders...";

/ Place limit buy order on Kraken
buyOrder:.exchange.coordinator.placeOrder[`kraken;`BTCUSD;`limit;`buy;50000;0.01];
-1 "  Buy order placed on Kraken:";
show buyOrder;

/ Place limit sell order on Coinbase
sellOrder:.exchange.coordinator.placeOrder[`coinbase;`BTCUSD;`limit;`sell;51000;0.01];
-1 "  Sell order placed on Coinbase:";
show sellOrder;
-1 "";

/ ============================================================================
/ 6. Get Positions
/ ============================================================================

-1 "6. Fetching positions...";

/ Get BTCUSD position on Kraken
krakenPos:.exchange.coordinator.getPosition[`kraken;`BTCUSD];
-1 "  Kraken BTCUSD position:";
show krakenPos;

/ Get aggregate position across all exchanges
aggPos:.exchange.coordinator.getAggregatePosition[`BTCUSD];
-1 "  Aggregate BTCUSD position:";
show aggPos;
-1 "";

/ ============================================================================
/ 7. Monitor Order Routing
/ ============================================================================

-1 "7. Order routing table:";
show .exchange.coordinator.orderRouting;
-1 "";

/ ============================================================================
/ 8. Cleanup
/ ============================================================================

-1 "8. Disconnecting from exchanges...";
.exchange.coordinator.disconnect[`kraken];
.exchange.coordinator.disconnect[`coinbase];
.exchange.coordinator.disconnect[`bitstamp];

-1 "  All exchanges disconnected";
-1 "";
-1 "Example complete!";
-1 "";

/ Exit
\\
