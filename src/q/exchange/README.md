# Exchange Wrapper Module

## Overview

The exchange wrapper module provides an abstract interface for interacting with cryptocurrency exchanges. It includes:

- **Base Interface** (`base.q`): Abstract exchange API with order lifecycle state machine
- **Registry** (`registry.q`): Dynamic dispatch to exchange-specific implementations
- **Stub Exchange** (`stub.q`): In-memory simulated exchange for testing

## Architecture

### Namespace Structure

```
.exchange                           # Base namespace
├── ORDER_TYPE                      # Order type enumeration
├── ORDER_STATE                     # Order state enumeration
├── ORDER_SIDE                      # Order side enumeration
├── validTransitions                # State transition table
├── placeOrder[...]                 # Place order (dispatches to impl)
├── cancelOrder[...]                # Cancel order (dispatches to impl)
├── getBalance[...]                 # Get balance (dispatches to impl)
├── getOrderbook[...]               # Get orderbook (dispatches to impl)
├── getOpenOrders[...]              # Get open orders (dispatches to impl)
├── getPosition[...]                # Get position (dispatches to impl)
│
├── .registry                       # Exchange registry
│   ├── implementations             # Dict of registered exchanges
│   ├── register[...]               # Register exchange implementation
│   ├── getImplementation[...]      # Get implementation by name
│   ├── listExchanges[]             # List registered exchanges
│   └── isRegistered[...]           # Check if exchange registered
│
└── .stub                           # Stub exchange implementation
    ├── config                      # Stub configuration
    ├── obParams                    # Orderbook parameters
    ├── balances                    # Currency balances
    ├── holds                       # Reserved balances
    ├── orders                      # Order table
    ├── fills                       # Fill table
    ├── init[...]                   # Initialize stub
    ├── setBalances[...]            # Set balances
    ├── setOBParams[...]            # Set orderbook params
    ├── placeOrder[...]             # Place order
    ├── cancelOrder[...]            # Cancel order
    ├── getBalance[...]             # Get balance
    ├── getOrderbook[...]           # Generate synthetic orderbook
    ├── getOpenOrders[...]          # Get open orders
    ├── getPosition[...]            # Get position (stub)
    └── registerStub[]              # Register stub with registry
```

## Order Lifecycle State Machine

The exchange wrapper enforces a strict order lifecycle state machine:

```
                    ┌──────────┐
                    │ pending  │
                    └────┬─────┘
                         │
           ┌─────────────┼─────────────┐
           │                           │
           ▼                           ▼
      ┌────────┐                  ┌──────────┐
      │  open  │                  │ rejected │
      └───┬────┘                  └──────────┘
          │
          ├──────────┬──────────┬──────────┐
          │          │          │          │
          ▼          ▼          ▼          ▼
    ┌─────────┐  ┌────────┐  ┌───────┐  ┌─────────┐
    │ partial │  │ filled │  │cancel │  │ expired │
    └────┬────┘  └────────┘  └───────┘  └─────────┘
         │
         ├──────────┬──────────┐
         │          │          │
         ▼          ▼          ▼
    ┌────────┐  ┌───────┐  ┌─────────┐
    │ filled │  │cancel │  │ expired │
    └────────┘  └───────┘  └─────────┘
```

**Valid Transitions:**
- `pending` → `open`, `rejected`
- `open` → `partially_filled`, `filled`, `cancelled`, `expired`
- `partially_filled` → `filled`, `cancelled`, `expired`
- `filled`, `cancelled`, `rejected`, `expired` → (terminal states)

## Usage Examples

### 1. Initialize Stub Exchange

```q
/ Load modules
\l src/q/exchange/base.q
\l src/q/exchange/registry.q
\l src/q/exchange/stub.q

/ Initialize stub
.exchange.stub.init[()!()];

/ Set balances
.exchange.stub.setBalances[`USD`BTC!(10000.0;1.0)];

/ Set orderbook parameters
.exchange.stub.setOBParams[`midPrice`spread`depth!(100.0;0.02;10)];

/ Register stub
.exchange.stub.registerStub[];
```

### 2. Place Market Order

```q
/ Place market buy order for 0.1 BTC
order:.exchange.placeOrder[
  `stub;                          / Exchange name
  `BTCUSD;                        / Trading pair
  `market;                        / Order type
  `buy;                           / Side
  0Nj;                            / Price (null for market)
  .qg.toVolume[0.1]               / Quantity (fixed precision)
];

/ Check order response
order`orderId      / Order ID
order`status       / Order status (filled/partially_filled)
order`filled       / Filled quantity
```

### 3. Place Limit Order

```q
/ Place limit sell order at $100
order:.exchange.placeOrder[
  `stub;
  `BTCUSD;
  `limit;
  `sell;
  .qg.toPrice[100.0];             / Price (fixed precision)
  .qg.toVolume[0.5]               / Quantity
];

/ Check order status
order`status       / open/filled/partially_filled
```

### 4. Cancel Order

```q
/ Cancel order by ID
result:.exchange.cancelOrder[`stub;order`orderId];

/ Check cancellation result
result`status      / Should be `cancelled
```

### 5. Query Balance

```q
/ Get USD balance
balUSD:.exchange.getBalance[`stub;`USD];

balUSD`total       / Total balance
balUSD`available   / Available (not in orders)
balUSD`reserved    / Reserved (in open orders)
```

### 6. Get Orderbook

```q
/ Get current orderbook
ob:.exchange.getOrderbook[`stub;`BTCUSD];

/ Inspect orderbook
bids:select from ob where side=`bid;  / Sorted descending by price
asks:select from ob where side=`ask;  / Sorted ascending by price

/ Best bid/ask
bestBid:max bids`price;
bestAsk:min asks`price;
spread:bestAsk - bestBid;
```

### 7. Get Open Orders

```q
/ Get all open orders for pair
openOrders:.exchange.getOpenOrders[`stub;`BTCUSD];

/ Filter by side
buyOrders:select from openOrders where side=`buy;
sellOrders:select from openOrders where side=`sell;
```

## Stub Exchange Details

### Configuration

The stub exchange supports the following configuration:

```q
config:`symbol`tickSize`minQty`maxQty`feeRate`latencyMs!(
  `;                   / Symbol (unused)
  0.01;                / Tick size for price rounding
  0.001;               / Minimum order quantity
  1000.0;              / Maximum order quantity
  0.001;               / Fee rate (0.1%)
  10                   / Latency in milliseconds
);
```

### Orderbook Generation

The stub generates synthetic orderbooks with configurable parameters:

```q
obParams:`midPrice`spread`depth`volatility`tickSize!(
  100.0;               / Mid price
  0.02;                / Bid-ask spread (2%)
  10;                  / Depth (10 levels per side)
  0.001;               / Volatility for random walk
  0.01                 / Tick size
);
```

**Generation Algorithm:**
1. Calculate bid mid = midPrice - (midPrice * spread / 2)
2. Calculate ask mid = midPrice + (midPrice * spread / 2)
3. Generate 10 price levels per side with geometric spacing
4. Generate quantities using exponential distribution
5. Sort bids descending, asks ascending

### Balance Tracking

The stub tracks balances with three states per currency:

- **Total**: Total balance amount
- **Available**: Total - holds (can place new orders)
- **Reserved**: Amount held for open orders

**Balance Operations:**
1. `placeHold[currency;amount]` - Reserve balance when placing order
2. `releaseHold[currency;amount]` - Release hold when canceling order
3. `updateBalance[currency;delta]` - Credit/debit balance after trade execution

### Order Matching

The stub matches orders against the synthetic orderbook:

**Market Orders:**
- Always match at best available price
- Fill up to available liquidity at each price level
- Cross multiple price levels if needed

**Limit Orders:**
- Only match if limit price crosses orderbook price
- Buy orders match at prices <= limit price
- Sell orders match at prices >= limit price

**Matching Algorithm:**
1. Generate synthetic orderbook
2. Filter opposing side (buy → match asks, sell → match bids)
3. Iterate price levels from best to worst
4. Fill quantity at each level up to order size
5. Update balances (deduct from buyer, credit to seller)
6. Record fills in fills table
7. Update order status (open → partially_filled → filled)

## Implementing a Real Exchange

To implement a real exchange (e.g., Coinbase, Kraken):

1. **Create implementation file**: `src/q/exchange/coinbase.q`

2. **Implement required functions**:

```q
\d .exchange.coinbase

/ Place order
placeOrder:{[pair;orderType;side;price;quantity]
  / Convert to exchange API format
  / Make HTTP request to exchange
  / Parse response
  / Return order dict
 };

/ Cancel order
cancelOrder:{[orderId]
  / Make HTTP request to cancel
  / Return cancellation result
 };

/ Get balance
getBalance:{[currency]
  / Make HTTP request for balance
  / Parse and return balance dict
 };

/ Get orderbook
getOrderbook:{[pair]
  / Make HTTP request for orderbook
  / Parse and return table
 };

/ Get open orders
getOpenOrders:{[pair]
  / Make HTTP request for open orders
  / Parse and return table
 };

/ Get position
getPosition:{[pair]
  / Make HTTP request for position
  / Parse and return position dict
 };

/ Register implementation
register:{[]
  impl:`placeOrder`cancelOrder`getBalance`getOrderbook`getOpenOrders`getPosition!(
    placeOrder;cancelOrder;getBalance;getOrderbook;getOpenOrders;getPosition
  );
  .exchange.registry.register[`coinbase;impl];
 };

\d .
```

3. **Load and register**:

```q
\l src/q/exchange/coinbase.q
.exchange.coinbase.register[];
```

4. **Use via standard interface**:

```q
/ Place order on real exchange
order:.exchange.placeOrder[`coinbase;`BTCUSD;`limit;`buy;price;qty];
```

## Testing

### Unit Tests

Run the test suite:

```q
\l tests/q/test_exchange.q
```

**Tests Included:**
- State machine transition validation
- Order parameter validation
- Balance initialization and holds
- Balance updates and insufficient balance errors
- Orderbook generation and structure
- Market order placement and execution
- Limit order placement and matching
- Order cancellation and hold release
- Registry registration and lookup

### Manual Testing

```q
/ Load modules
\l src/q/schema/types.q
\l src/q/exchange/base.q
\l src/q/exchange/registry.q
\l src/q/exchange/stub.q

/ Initialize
.exchange.stub.init[()!()];
.exchange.stub.setBalances[`USD`BTC!(10000.0;1.0)];
.exchange.stub.setOBParams[`midPrice`spread`depth!(100.0;0.02;10)];
.exchange.stub.registerStub[];

/ Place orders
order1:.exchange.placeOrder[`stub;`BTCUSD;`market;`buy;0Nj;.qg.toVolume[0.1]];
order2:.exchange.placeOrder[`stub;`BTCUSD;`limit;`sell;.qg.toPrice[110.0];.qg.toVolume[0.2]];

/ Check results
order1
order2
.exchange.getBalance[`stub;`USD]
.exchange.getBalance[`stub;`BTC]
.exchange.getOpenOrders[`stub;`BTCUSD]
```

## Dependencies

- `src/q/schema/types.q` - Type constants, validation, ID generator
- `src/q/lib/money.q` - Money type (for conversions, not used directly)

## Integration

The exchange wrapper integrates with:

- **Order Management** (`src/q/schema/order.q`) - Order table and CRUD
- **Trade Tracking** (`src/q/schema/trade.q`) - Trade execution recording
- **Balance Management** (`src/q/schema/exchange.q`) - Exchange balance table

**Typical Flow:**
1. Strategy decides to place order
2. Call `.exchange.placeOrder[]` → dispatches to implementation
3. Implementation places order on exchange
4. Order response returned with orderId and status
5. Record order in order table via `.qg.createOrder[]`
6. When filled, create trade via `.qg.createTrade[]`
7. Update balance table via `.qg.updateBalance[]`

## Performance

**Stub Exchange Benchmarks:**

- Order placement: < 1ms
- Order matching: < 5ms (10 orders)
- Orderbook generation: < 10ms
- Balance operations: < 0.1ms

**Real Exchange Considerations:**

- Rate limiting: Implement per-exchange rate limiters
- Connection pooling: Reuse HTTP connections
- Websocket subscriptions: For real-time orderbook updates
- Error handling: Retry logic for transient failures

## Security

**API Key Management:**
- Never hardcode API keys in source files
- Use environment variables or secure key stores
- Hash API keys before storing in database

**Order Validation:**
- Always validate order parameters before sending to exchange
- Enforce position limits and risk checks
- Log all order placement attempts for audit trail

**Balance Tracking:**
- Reconcile balances periodically with exchange API
- Alert on balance discrepancies
- Implement balance hold system to prevent overdraft

## Future Enhancements

1. **Historical Orderbook Replay** (from plan Phase 5)
   - Load orderbook snapshots from tick database
   - Replay for backtesting strategies

2. **Multi-Exchange Routing**
   - Smart order routing across multiple exchanges
   - Best execution logic

3. **Websocket Subscriptions**
   - Real-time orderbook updates
   - Trade execution notifications

4. **Rate Limiting**
   - Per-exchange rate limiters
   - Request queuing and throttling

5. **Connection Management**
   - Connection pooling
   - Automatic reconnection on disconnect

## References

- [Gryphon Exchange Wrapper](https://github.com/gryphon-project/gryphon/blob/master/gryphon/exchange/exchange.py)
- [Medusa Trading System Plans](/Users/ogarro/work/VAULT/Plans/medusa/)
- [q/kdb+ Reference](https://code.kx.com/q/ref/)
