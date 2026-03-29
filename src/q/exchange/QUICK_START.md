# Exchange Wrapper Quick Start Guide

## 5-Minute Tutorial

### 1. Load Modules

```q
/ Load Medusa system (includes exchange wrapper)
\l src/q/init.q
```

### 2. Initialize Stub Exchange

```q
/ Initialize stub with default config
.exchange.stub.init[()!()];

/ Set starting balances
.exchange.stub.setBalances[`USD`BTC`ETH!(10000.0;1.0;10.0)];

/ Configure orderbook generation
.exchange.stub.setOBParams[
  `midPrice`spread`depth`volatility`tickSize!(100.0;0.02;10;0.001;0.01)
];

/ Register stub with registry
.exchange.stub.registerStub[];
```

### 3. Place Your First Order

```q
/ Market buy order for 0.1 BTC
order:.exchange.placeOrder[
  `stub;                          / Exchange name
  `BTCUSD;                        / Trading pair
  `market;                        / Order type
  `buy;                           / Side
  0Nj;                            / Price (null for market)
  .qg.toVolume[0.1]               / Quantity (0.1 BTC)
];

/ Inspect result
order`orderId      / Order ID (1j)
order`status       / Status (`filled or `partially_filled)
order`filled       / Filled quantity
```

### 4. Check Balances

```q
/ Get BTC balance
btc:.exchange.getBalance[`stub;`BTC];
btc`total          / Total balance
btc`available      / Available (not in orders)
btc`reserved       / Reserved (in open orders)

/ Get USD balance
usd:.exchange.getBalance[`stub;`USD];
```

### 5. Place Limit Order

```q
/ Limit sell order at $110
limitOrder:.exchange.placeOrder[
  `stub;
  `BTCUSD;
  `limit;
  `sell;
  .qg.toPrice[110.0];             / Limit price ($110)
  .qg.toVolume[0.2]               / Sell 0.2 BTC
];

/ Check if filled
limitOrder`status                 / `open (no match at $110)
```

### 6. View Orderbook

```q
/ Get current orderbook
ob:.exchange.getOrderbook[`stub;`BTCUSD];

/ View bids (sorted descending)
bids:select from ob where side=`bid;
bids

/ View asks (sorted ascending)
asks:select from ob where side=`ask;
asks

/ Calculate mid price
bestBid:max bids`price;
bestAsk:min asks`price;
mid:(bestBid + bestAsk) % 2.0;
```

### 7. Cancel Order

```q
/ Cancel the limit order
.exchange.cancelOrder[`stub;limitOrder`orderId];

/ Check balance hold released
btc:.exchange.getBalance[`stub;`BTC];
btc`available      / Should increase by 0.2 BTC
btc`reserved       / Should decrease by 0.2 BTC
```

### 8. View Open Orders

```q
/ Get all open orders
openOrders:.exchange.getOpenOrders[`stub;`BTCUSD];
openOrders

/ Filter by side
buyOrders:select from openOrders where side=`buy;
sellOrders:select from openOrders where side=`sell;
```

---

## Common Patterns

### Pattern 1: Check Before Trade

```q
/ Check balance before placing order
usdBalance:.exchange.getBalance[`stub;`USD];
requiredUSD:0.5 * 100.0;  / 0.5 BTC at $100

if[usdBalance[`available] >= requiredUSD;
  / Place order
  order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[100.0];.qg.toVolume[0.5]];
  -1 "Order placed: ",string order`orderId;
;
  -1 "Insufficient balance"
];
```

### Pattern 2: Iterate Open Orders

```q
/ Cancel all open orders
openOrders:.exchange.getOpenOrders[`stub;`BTCUSD];
{[order]
  .exchange.cancelOrder[`stub;order`orderId];
  -1 "Cancelled order: ",string order`orderId;
}each openOrders;
```

### Pattern 3: Calculate Fill Rate

```q
/ Place order and check fill
order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[100.0];.qg.toVolume[1.0]];

/ Calculate fill percentage
fillPct:100.0 * (.qg.fromVolume[order`filled]) % .qg.fromVolume[order`quantity];
-1 "Order ",string[order`orderId]," filled: ",string[fillPct],"%";
```

### Pattern 4: Monitor Spread

```q
/ Get spread
ob:.exchange.getOrderbook[`stub;`BTCUSD];
bids:select from ob where side=`bid;
asks:select from ob where side=`ask;

bestBid:max bids`price;
bestAsk:min asks`price;
spread:bestAsk - bestBid;
spreadPct:100.0 * spread % bestBid;

-1 "Spread: $",string[spread]," (",string[spreadPct],"%)";
```

### Pattern 5: VWAP Calculation

```q
/ Calculate volume-weighted average price from orderbook
bids:select from ob where side=`bid;
vwap:(sum bids[`price] * bids[`quantity]) % sum bids`quantity;
-1 "VWAP (bids): $",string vwap;
```

---

## Troubleshooting

### Issue: "Exchange not registered"

**Solution**: Register the stub exchange
```q
.exchange.stub.registerStub[];
```

### Issue: "Insufficient available balance"

**Solution**: Check holds and balances
```q
bal:.exchange.getBalance[`stub;`USD];
bal`available   / Check available balance
bal`reserved    / Check reserved balance

/ Cancel open orders to release holds
openOrders:.exchange.getOpenOrders[`stub;`BTCUSD];
{.exchange.cancelOrder[`stub;x`orderId]}each openOrders;
```

### Issue: "Invalid order type"

**Solution**: Use valid order types
```q
.exchange.ORDER_TYPE   / List valid types: `market`limit`stop_loss`take_profit
```

### Issue: "Cannot cancel order in status: filled"

**Solution**: Can only cancel open/partially_filled orders
```q
order:.exchange.placeOrder[`stub;`BTCUSD;`limit;`buy;.qg.toPrice[50.0];.qg.toVolume[0.1]];
if[order[`status] in `open`partially_filled;
  .exchange.cancelOrder[`stub;order`orderId]
];
```

---

## Debugging Commands

```q
/ Show all registered exchanges
.exchange.registry.listExchanges[]

/ Check if exchange is registered
.exchange.registry.isRegistered[`stub]

/ View stub state
.exchange.stub.balances           / Current balances
.exchange.stub.holds              / Current holds
.exchange.stub.orders             / All orders
.exchange.stub.fills              / All fills

/ View order lifecycle states
.exchange.ORDER_STATE             / Valid states

/ View valid state transitions
.exchange.validTransitions        / Transition table

/ Check if transition is valid
.exchange.isValidTransition[`open;`filled]
```

---

## Configuration Options

### Stub Exchange Config

```q
/ Override stub config
.exchange.stub.init[
  `tickSize`minQty`maxQty`feeRate`latencyMs!(0.01;0.001;1000.0;0.002;5)
];
```

### Orderbook Parameters

```q
/ Change orderbook parameters
.exchange.stub.setOBParams[
  `midPrice`spread`depth`volatility!(200.0;0.01;20;0.0005)
];
```

### Multiple Currencies

```q
/ Set balances for multiple currencies
.exchange.stub.setBalances[
  `USD`EUR`BTC`ETH`USDT!(10000.0;9000.0;1.0;10.0;10000.0)
];
```

---

## Next Steps

1. **Read Full Documentation**: See `src/q/exchange/README.md`
2. **Run Tests**: Execute `q tests/q/test_exchange.q`
3. **Study Examples**: Review test file for usage patterns
4. **Implement Real Exchange**: Follow guide in README.md

---

## API Reference

### Exchange Interface

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `.exchange.placeOrder` | `exchangeName;pair;orderType;side;price;quantity` | `dict` | Place order |
| `.exchange.cancelOrder` | `exchangeName;orderId` | `dict` | Cancel order |
| `.exchange.getBalance` | `exchangeName;currency` | `dict` | Get balance |
| `.exchange.getOrderbook` | `exchangeName;pair` | `table` | Get orderbook |
| `.exchange.getOpenOrders` | `exchangeName;pair` | `table` | Get open orders |
| `.exchange.getPosition` | `exchangeName;pair` | `dict` | Get position |

### Stub Exchange Functions

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `.exchange.stub.init` | `cfg:dict` | `dict` | Initialize stub |
| `.exchange.stub.setBalances` | `balDict:dict` | `()` | Set balances |
| `.exchange.stub.setOBParams` | `params:dict` | `()` | Set orderbook params |
| `.exchange.stub.registerStub` | `()` | `()` | Register with registry |

### Registry Functions

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `.exchange.registry.register` | `exchangeName;impl` | `symbol` | Register exchange |
| `.exchange.registry.getImplementation` | `exchangeName` | `dict` | Get implementation |
| `.exchange.registry.listExchanges` | `()` | `symbol[]` | List exchanges |
| `.exchange.registry.isRegistered` | `exchangeName` | `boolean` | Check registration |

---

## Help & Support

- **Documentation**: `src/q/exchange/README.md`
- **Tests**: `tests/q/test_exchange.q`
- **Validation**: `scripts/test_exchange_load.q`
- **Implementation Summary**: `IMPLEMENTATION_SUMMARY.md`
