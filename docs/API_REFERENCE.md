# Medusa API Reference

Complete API documentation for Python pricing models, q/kdb+ risk modules, and Electron IPC interface.

---

## Table of Contents

1. [Python Pricing API](#python-pricing-api)
   - [Bond Pricing](#bond-pricing)
   - [Options Pricing](#options-pricing)
   - [Yield Curve](#yield-curve)
2. [q/kdb+ Risk API](#qkdb-risk-api)
   - [Real-Time P&L](#real-time-pnl)
   - [Exposure Heatmap](#exposure-heatmap)
   - [Order Flow Risk](#order-flow-risk)
   - [Risk Snapshots](#risk-snapshots)
   - [Margin Calculations](#margin-calculations)
3. [Electron IPC API](#electron-ipc-api)
   - [KDB Connection](#kdb-connection)
   - [Order Management](#order-management)
   - [Risk Metrics](#risk-metrics)

---

## Python Pricing API

### Bond Pricing

**Module**: `medusa.pricing.bond`

**Classes**: `Bond` (dataclass), `BondPricer` (static methods)

#### `BondPricer.present_value(bond, ytm, settlement_date)`

Calculate bond present value (clean price).

**Parameters**:
- `bond` (Bond): Bond specification (CUSIP, coupon rate, maturity, face value, frequency, day count)
- `ytm` (float): Yield to maturity (annual, as decimal)
- `settlement_date` (date): Settlement date

**Returns**:
- `float`: Present value (clean price)

**Example**:
```python
from datetime import date
from medusa.pricing.bond import Bond, BondPricer, DayCountConvention

bond = Bond(
    cusip="912828YK0",
    coupon_rate=0.05,
    maturity_date=date(2030, 12, 31),
    face_value=100.0,
    coupon_frequency=2,
    day_count=DayCountConvention.THIRTY_360
)

price = BondPricer.present_value(bond, ytm=0.04, settlement_date=date(2026, 1, 1))
# Returns: 104.45
```

**Formula**:
$$
PV = \sum_{t=1}^{n} \frac{C}{(1 + y/f)^{t}} + \frac{F}{(1 + y/f)^{n}}
$$

---

#### `BondPricer.yield_to_maturity(bond, price, settlement_date, tol=1e-6, max_iter=100)`

Calculate yield to maturity using Newton-Raphson.

**Parameters**:
- `bond` (Bond): Bond specification
- `price` (float): Market price (clean)
- `settlement_date` (date): Settlement date
- `tol` (float): Convergence tolerance
- `max_iter` (int): Maximum iterations

**Returns**:
- `float`: Yield to maturity (annual, as decimal)

**Example**:
```python
ytm = BondPricer.yield_to_maturity(bond, price=104.45, settlement_date=date(2026, 1, 1))
# Returns: 0.04 (4%)
```

**Algorithm**: Newton-Raphson iterative solver with tolerance 1e-6.

---

#### `BondPricer.macaulay_duration(bond, ytm, settlement_date)`

Calculate Macaulay duration.

**Returns**:
- `float`: Macaulay duration in years

**Example**:
```python
duration = BondPricer.macaulay_duration(bond, ytm=0.04, settlement_date=date(2026, 1, 1))
# Returns: 4.38 years
```

**Formula**:
$$
D_{Mac} = \frac{1}{PV} \sum_{t=1}^{n} t \cdot \frac{CF_t}{(1 + y/f)^{t}}
$$

---

#### `BondPricer.modified_duration(bond, ytm, settlement_date)`

Calculate modified duration (price sensitivity to yield changes).

**Returns**:
- `float`: Modified duration in years

**Example**:
```python
mod_duration = BondPricer.modified_duration(bond, ytm=0.04, settlement_date=date(2026, 1, 1))
# Returns: 4.29
```

**Formula**:
$$
D_{\text{mod}} = \frac{D_{Mac}}{1 + y/f}
$$

**Interpretation**: A 1% increase in yield results in a price decrease of ~4.29%.

---

#### `BondPricer.convexity(bond, ytm, settlement_date)`

Calculate bond convexity (second-order price sensitivity).

**Returns**:
- `float`: Convexity

**Example**:
```python
convexity = BondPricer.convexity(bond, ytm=0.04, settlement_date=date(2026, 1, 1))
# Returns: 21.2
```

**Formula**:
$$
C = \frac{1}{PV \cdot (1+y/f)^2} \sum_{t=1}^{n} t(t+1) \cdot \frac{CF_t}{(1 + y/f)^{t}}
$$

**Price change approximation**:
$$
\Delta P \approx -D_{\text{mod}} \cdot \Delta y \cdot P + \frac{1}{2} C \cdot (\Delta y)^2 \cdot P
$$

---

#### `BondPricer.dv01(bond, ytm, settlement_date)`

Calculate DV01 (dollar value of one basis point).

**Returns**:
- `float`: DV01 (positive value)

**Example**:
```python
dv01 = BondPricer.dv01(bond, ytm=0.04, settlement_date=date(2026, 1, 1))
# Returns: 0.045 (price drops $0.045 for 1bp yield increase)
```

---

#### `BondPricer.accrued_interest(bond, settlement_date)`

Calculate accrued interest since last coupon.

**Returns**:
- `float`: Accrued interest amount

**Example**:
```python
accrued = BondPricer.accrued_interest(bond, settlement_date=date(2026, 1, 15))
# Returns: 0.625 (15 days of accrued interest)
```

---

### Options Pricing

**Module**: `medusa.models.options_pricing`

**Classes**: `OptionParams` (dataclass), `OptionType` (enum), `BlackScholesEngine` (static methods)

#### `BlackScholesEngine.price(params)`

Calculate European option price using Black-Scholes formula.

**Parameters**:
- `params` (OptionParams): Option parameters
  - `spot` (float): Current stock price
  - `strike` (float): Strike price
  - `time_to_expiry` (float): Time to expiration in years
  - `risk_free_rate` (float): Risk-free interest rate (annualized, decimal)
  - `volatility` (float): Volatility (annualized standard deviation, decimal)
  - `option_type` (OptionType): `OptionType.CALL` or `OptionType.PUT`
  - `dividend_yield` (float): Continuous dividend yield (default: 0.0)

**Returns**:
- `float`: Option price

**Example**:
```python
from medusa.models.options_pricing import BlackScholesEngine, OptionParams, OptionType

params = OptionParams(
    spot=100.0,
    strike=105.0,
    time_to_expiry=1.0,
    risk_free_rate=0.05,
    volatility=0.20,
    option_type=OptionType.CALL
)

call_price = BlackScholesEngine.price(params)
# Returns: 8.02
```

**Formula** (call):
$$
C = S \cdot e^{-qT} \cdot N(d_1) - K \cdot e^{-rT} \cdot N(d_2)
$$

**Formula** (put):
$$
P = K \cdot e^{-rT} \cdot N(-d_2) - S \cdot e^{-qT} \cdot N(-d_1)
$$

Where:
$$
d_1 = \frac{\ln(S/K) + (r - q + \sigma^2/2)T}{\sigma \sqrt{T}}
$$
$$
d_2 = d_1 - \sigma \sqrt{T}
$$

**Put-Call Parity**:
$$
C - P = S \cdot e^{-qT} - K \cdot e^{-rT}
$$

---

#### `BlackScholesEngine.greeks(params)`

Calculate option Greeks (delta, gamma, vega, theta, rho).

**Parameters**:
- `params` (OptionParams): Option parameters

**Returns**:
- `dict[str, float]`: Dictionary with keys:
  - `delta`: Delta (∂Price/∂S)
  - `gamma`: Gamma (∂²Price/∂S²) — same for call and put
  - `vega`: Vega (∂Price/∂σ) per 1% — same for call and put
  - `theta`: Theta (∂Price/∂T) per day
  - `rho`: Rho (∂Price/∂r) per 1%

**Example**:
```python
greeks = BlackScholesEngine.greeks(params)
# Returns:
# {
#   'delta': 0.60,   # Call delta (0.60), Put delta would be -0.40
#   'gamma': 0.019,
#   'vega': 0.39,    # Per 1% volatility change
#   'theta': -0.03,  # Per day
#   'rho': 0.53      # Per 1% rate change
# }
```

**Delta interpretation**:
- **Call**: Range [0, 1]. ATM call ≈ 0.5-0.6 delta
- **Put**: Range [-1, 0]. ATM put ≈ -0.4 to -0.5 delta
- **Relationship**: $\Delta_{\text{put}} = \Delta_{\text{call}} - e^{-qT}$ (or $-1$ if no dividends)

**Gamma interpretation**:
- Range: [0, ∞)
- Maximum at ATM options
- Measures rate of change of delta

**Vega interpretation**:
- Range: [0, ∞)
- Sensitivity to 1% change in implied volatility
- Highest for ATM options with long time to expiration

**Theta interpretation**:
- Range: (-∞, 0] for long positions
- Daily P&L from time decay
- Accelerates near expiration

**Rho interpretation**:
- Call rho > 0, Put rho < 0
- Change in option value for 1% change in risk-free rate

---

#### `BlackScholesEngine.implied_volatility(price, params, max_iter=100, tolerance=1e-5)`

Calculate implied volatility from option market price.

**Parameters**:
- `price` (float): Market option price
- `params` (OptionParams): Option parameters (with initial volatility guess)
- `max_iter` (int): Maximum iterations
- `tolerance` (float): Convergence tolerance

**Returns**:
- `float`: Implied volatility (annualized standard deviation, decimal)

**Example**:
```python
# Market call price is $8.02, solve for implied vol
test_params = OptionParams(
    spot=100.0,
    strike=105.0,
    time_to_expiry=1.0,
    risk_free_rate=0.05,
    volatility=0.20,  # Initial guess
    option_type=OptionType.CALL
)

iv = BlackScholesEngine.implied_volatility(price=8.02, params=test_params)
# Returns: 0.20 (20%)
```

**Algorithm**: Newton-Raphson with vega as derivative.

**Convergence**: Typically converges in 5-10 iterations.

---

### Yield Curve

**Module**: `medusa.pricing.yield_curve`

**Classes**: `YieldCurve`, `NelsonSiegelCurve`, `YieldCurveBootstrapper`

#### `YieldCurveBootstrapper.bootstrap(par_bonds, max_age_seconds=300)`

Bootstrap zero rates from par bond yields with staleness validation.

**Parameters**:
- `par_bonds` (pd.DataFrame): DataFrame with columns:
  - `tenor` (float): Maturity in years
  - `rate` (float): Par yield (annual, as decimal)
  - `frequency` (int): Coupon frequency (1, 2, or 4)
  - `timestamp` (datetime, optional): Data timestamp for freshness validation
- `max_age_seconds` (int): Maximum data age in seconds (default: 300 = 5 minutes)

**Returns**:
- `YieldCurve`: Bootstrapped zero curve

**Example**:
```python
import pandas as pd
from datetime import datetime, UTC
from medusa.pricing.yield_curve import YieldCurveBootstrapper

par_bonds = pd.DataFrame([
    {'tenor': 0.5, 'rate': 0.025, 'frequency': 2, 'timestamp': datetime.now(UTC)},
    {'tenor': 1.0, 'rate': 0.030, 'frequency': 2, 'timestamp': datetime.now(UTC)},
    {'tenor': 2.0, 'rate': 0.035, 'frequency': 2, 'timestamp': datetime.now(UTC)}
])

curve = YieldCurveBootstrapper.bootstrap(par_bonds)
# Returns: YieldCurve(tenors=[0.5, 1.0, 2.0], rates=[0.025, 0.0301, 0.0353])
```

**Algorithm**: Recursive bootstrapping — solve for each zero rate using previous zero rates.

**Raises**:
- `ValueError`: If data is stale (age > max_age_seconds) or missing required columns

---

#### `YieldCurve.interpolate(tenor, method='linear')`

Interpolate rate at given tenor.

**Parameters**:
- `tenor` (float): Target tenor in years
- `method` (str): Interpolation method (`'linear'` or `'cubic'`)

**Returns**:
- `float`: Interpolated rate (annual, as decimal)

**Example**:
```python
rate = curve.interpolate(1.5, method='linear')
# Returns: 0.0327 (interpolated between 1.0 and 2.0)
```

---

#### `YieldCurve.forward_rate(t1, t2)`

Calculate forward rate between two tenors.

**Parameters**:
- `t1` (float): Start tenor in years
- `t2` (float): End tenor in years

**Returns**:
- `float`: Forward rate (annualized)

**Example**:
```python
fwd_rate = curve.forward_rate(t1=1.0, t2=2.0)
# Returns: 0.0405 (4.05%)
```

**Formula**:
$$
f_{t_1, t_2} = \frac{r(t_2) \cdot t_2 - r(t_1) \cdot t_1}{t_2 - t_1}
$$

**Interpretation**: Expected 1-year rate starting in 1 year.

---

#### `YieldCurve.discount_factor(tenor)`

Calculate discount factor for a given tenor.

**Parameters**:
- `tenor` (float): Tenor in years

**Returns**:
- `float`: Discount factor

**Example**:
```python
df = curve.discount_factor(t=2.0)
# Returns: 0.9324
```

**Formula**:
$$
DF(t) = e^{-r(t) \cdot t}
$$

**Use Case**: Present value calculations.

---

#### `NelsonSiegelCurve.fit(curve, initial_tau=1.0)`

Fit Nelson-Siegel parameters to observed yield curve.

**Parameters**:
- `curve` (YieldCurve): Observed yield curve
- `initial_tau` (float): Initial guess for tau parameter

**Returns**:
- `NelsonSiegelCurve`: Fitted curve with β0, β1, β2, τ parameters

**Example**:
```python
from medusa.pricing.yield_curve import NelsonSiegelCurve

ns_curve = NelsonSiegelCurve.fit(curve, initial_tau=1.0)
# Returns: NelsonSiegelCurve(beta0=0.035, beta1=-0.01, beta2=0.005, tau=1.2)

# Get rate at any tenor
rate = ns_curve.rate(tenor=1.5)
# Returns: 0.0327
```

**Formula**:
$$
y(t) = \beta_0 + \beta_1 \frac{1-e^{-t/\tau}}{t/\tau} + \beta_2 \left( \frac{1-e^{-t/\tau}}{t/\tau} - e^{-t/\tau} \right)
$$

Where:
- β0 = long-term rate (level)
- β1 = short-term component (slope)
- β2 = medium-term component (curvature)
- τ = decay parameter

---

## q/kdb+ Risk API

### Real-Time P&L

**Namespace**: `.risk`

#### `.risk.realtimePnL`

**Table Schema**:
```q
realtimePnL:([]
  totalPnL:`float$();           / Total portfolio P&L
  realizedPnL:`float$();        / Closed positions only
  unrealizedPnL:`float$();      / Mark-to-market on open positions
  dayOpenPnL:`float$();         / P&L at market open
  dayChangePnL:`float$();       / Intraday change
  dayChangePct:`float$();       / Intraday % change
  lastUpdate:`timestamp$()
)
```

**Example Query**:
```q
/ Get current P&L snapshot
select from .risk.realtimePnL

/ Returns:
totalPnL  realizedPnL  unrealizedPnL  dayOpenPnL  dayChangePnL  dayChangePct  lastUpdate
-------------------------------------------------------------------------------------
1234.56   800.25       434.31         1000.00     234.56        23.46        2026-04-25D14:32:15.123456789
```

---

#### `.risk.pnlByStrategyRT`

**Keyed Table Schema**:
```q
pnlByStrategyRT:([strategy:`symbol$()]
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  totalPnL:`float$();
  tradeCount:`int$();
  winCount:`int$();
  lossCount:`int$();
  winRate:`float$();
  avgWin:`float$();
  avgLoss:`float$();
  sharpeRatio:`float$();
  maxDrawdown:`float$();
  lastUpdate:`timestamp$()
)
```

**Example Query**:
```q
/ Get P&L for all strategies
select from .risk.pnlByStrategyRT

/ Get P&L for specific strategy
select from .risk.pnlByStrategyRT where strategy=`arbitrage

/ Top 3 strategies by total P&L
3#`totalPnL xdesc select from .risk.pnlByStrategyRT
```

---

### Exposure Heatmap

**Namespace**: `.risk`

#### `.risk.exposureHeatmap`

**Table Schema**:
```q
exposureHeatmap:([]
  strategy:`symbol$();
  asset:`symbol$();
  exposure:`float$();           / Notional exposure ($)
  exposurePct:`float$();        / % of total portfolio
  concentrationAlert:`boolean$() / True if above threshold
)
```

**Example Query**:
```q
/ Get exposure heatmap
select from .risk.exposureHeatmap

/ Get concentration alerts
select from .risk.exposureHeatmap where concentrationAlert

/ Pivot heatmap by strategy and asset
select exposure by strategy, asset from .risk.exposureHeatmap
```

---

### Order Flow Risk

**Namespace**: `.risk`

#### `.risk.orderFlowMetrics`

**Table Schema**:
```q
orderFlowMetrics:([]
  time:`timestamp$();
  ordersPerSec:`float$();       / Orders submitted per second
  fillRate:`float$();           / Fill rate (0.0 to 1.0)
  rejectionRate:`float$();      / Rejection rate (0.0 to 1.0)
  avgFillTime:`float$();        / Average fill time (milliseconds)
  exchange:`symbol$()
)
```

**Example Query**:
```q
/ Get last 100 order flow metrics
-100#select from .risk.orderFlowMetrics

/ Get average fill rate by exchange
select avg fillRate by exchange from .risk.orderFlowMetrics

/ Get order flow metrics for last hour
select from .risk.orderFlowMetrics where time > .z.p - 01:00:00.0
```

---

### Risk Snapshots

**Namespace**: `.risk`

#### `.risk.riskSnapshot`

**Function**: `.risk.snapshot.create[]`

**Description**: Capture complete risk state snapshot (positions, P&L, Greeks, exposure, VaR).

**Frequency**: Every 1 second (stored to HDB for replay).

**Table Schema**:
```q
riskSnapshot:([]
  time:`timestamp$();
  totalPnL:`float$();
  totalExposure:`float$();
  var95:`float$();              / Value at Risk (95%)
  cvar95:`float$();             / Conditional VaR (95%)
  deltaExposure:`float$();      / Total delta (options)
  gammaExposure:`float$();      / Total gamma
  vegaExposure:`float$();       / Total vega
  thetaExposure:`float$();      / Total theta
  maxDrawdown:`float$();
  activeLimits:`int$()          / Number of active limit violations
)
```

**Example Query**:
```q
/ Get most recent snapshot
-1#select from .risk.riskSnapshot

/ Get snapshots for a specific time window
select from .risk.riskSnapshot where time within (14:30:00.0; 14:35:00.0)

/ Time-travel: What was risk state at 14:32:15?
select from .risk.riskSnapshot where time=14:32:15.0
```

---

### Margin Calculations

**Namespace**: `.risk`

#### `.risk.margin.calculate[symbol; qty; side]`

Calculate margin requirement for a trade.

**Parameters**:
- `symbol` (symbol): Instrument symbol (e.g., `BTCUSD`, `AAPL`)
- `qty` (long): Quantity
- `side` (symbol): `buy` or `sell`

**Returns**:
- `float`: Required margin ($)

**Example**:
```q
/ Calculate margin for 100 shares of AAPL
.risk.margin.calculate[`AAPL; 100; `buy]
/ Returns: 10000.0 (assuming 50% Reg T margin)

/ Calculate margin for 1 BTC
.risk.margin.calculate[`BTCUSD; 1000000; `buy]  / 1 BTC = 1,000,000 in 6-decimal fixed-point
/ Returns: 60000.0 (assuming $60K BTC price, 100% margin for crypto)
```

---

#### `.risk.margin.optionsMargin[contract; qty; side]`

Calculate options margin (Reg T + portfolio margining).

**Parameters**:
- `contract` (symbol): Options contract (e.g., `AAPL_250620C150`)
- `qty` (long): Number of contracts
- `side` (symbol): `buy` or `sell`

**Returns**:
- `dict`: Margin breakdown
  ```q
  `regT`portfolioMargin`required!10000.0 8500.0 8500.0
  ```

**Example**:
```q
/ Calculate margin for 10 AAPL call contracts
.risk.margin.optionsMargin[`AAPL_250620C150; 10; `sell]
/ Returns: `regT`portfolioMargin`required!10000.0 8500.0 8500.0
```

**Algorithms**:
- **Reg T**: Standard margin (naked: 100% stock + premium, covered: stock requirement)
- **Portfolio Margin**: Scenario-based (±15% stock moves, ±30% IV moves)

---

## Electron IPC API

**Namespace**: `window.kdb`

All IPC methods return `Promise<{ success: boolean; data?: any; error?: string }>`.

### KDB Connection

#### `window.kdb.connect(config)`

Connect to kdb+ Tickerplant and RDB.

**Parameters**:
- `config` (object):
  ```typescript
  {
    tp: { host: string; port: number },   // Tickerplant (default: localhost:5010)
    rdb: { host: string; port: number }   // RDB (default: localhost:5011)
  }
  ```

**Returns**:
```typescript
{ success: true } | { success: false; error: string }
```

**Example**:
```typescript
const result = await window.kdb.connect({
  tp: { host: 'localhost', port: 5010 },
  rdb: { host: 'localhost', port: 5011 }
})

if (result.success) {
  console.log('Connected to kdb+')
} else {
  console.error('Connection failed:', result.error)
}
```

---

#### `window.kdb.subscribe(table)`

Subscribe to real-time updates for a table.

**Parameters**:
- `table` (string): Table name (e.g., `'trade'`, `'quote'`, `'order'`)

**Returns**:
```typescript
{ success: true } | { success: false; error: string }
```

**Example**:
```typescript
await window.kdb.subscribe('trade')
await window.kdb.subscribe('quote')
```

---

#### `window.kdb.onUpdate(callback)`

Register callback for real-time table updates.

**Parameters**:
- `callback` (function): `(table: string, data: any) => void`

**Returns**:
- `function`: Cleanup function (call to unsubscribe)

**Example**:
```typescript
const unsubscribe = window.kdb.onUpdate((table, data) => {
  if (table === 'trade') {
    console.log('New trade:', data)
  }
})

// Later: cleanup
unsubscribe()
```

---

### Order Management

#### `window.kdb.placeOrder(order)`

Place a new order.

**Parameters**:
- `order` (object):
  ```typescript
  {
    exchange: string,    // 'bitstamp', 'coinbase', 'kraken', 'alpaca'
    symbol: string,      // 'BTCUSD', 'AAPL', etc.
    side: 'buy' | 'sell',
    qty: number,         // Quantity (will be converted to fixed-point)
    orderType: 'limit' | 'market' | 'stop' | 'stop_limit',
    price?: number,      // Required for limit/stop_limit
    stopPrice?: number,  // Required for stop/stop_limit
    strategy?: string    // Strategy name (optional)
  }
  ```

**Returns**:
```typescript
{
  success: true,
  data: {
    orderId: string,
    status: 'pending' | 'submitted',
    timestamp: number
  }
} | { success: false; error: string }
```

**Example**:
```typescript
const result = await window.kdb.placeOrder({
  exchange: 'bitstamp',
  symbol: 'BTCUSD',
  side: 'buy',
  qty: 0.1,
  orderType: 'limit',
  price: 60000.0,
  strategy: 'arbitrage'
})

if (result.success) {
  console.log('Order placed:', result.data.orderId)
}
```

---

#### `window.kdb.cancelOrder(orderId)`

Cancel an existing order.

**Parameters**:
- `orderId` (string): Order ID from `placeOrder()`

**Returns**:
```typescript
{ success: true, data: { status: 'cancelled' } } | { success: false; error: string }
```

**Example**:
```typescript
await window.kdb.cancelOrder('order_12345')
```

---

#### `window.kdb.getOrders()`

Get all active orders.

**Returns**:
```typescript
{
  success: true,
  data: Array<{
    orderId: string,
    exchange: string,
    symbol: string,
    side: 'buy' | 'sell',
    qty: number,
    price: number,
    orderType: string,
    status: string,
    timestamp: number
  }>
}
```

**Example**:
```typescript
const result = await window.kdb.getOrders()
console.log('Active orders:', result.data)
```

---

### Risk Metrics

#### `window.kdb.getRiskMetrics()`

Get current risk metrics snapshot.

**Returns**:
```typescript
{
  success: true,
  data: {
    totalPnL: number,
    realizedPnL: number,
    unrealizedPnL: number,
    dayChangePnL: number,
    dayChangePct: number,
    var95: number,
    cvar95: number,
    maxDrawdown: number,
    activeLimits: number,
    lastUpdate: number
  }
}
```

**Example**:
```typescript
const result = await window.kdb.getRiskMetrics()

if (result.success) {
  console.log('Total P&L:', result.data.totalPnL)
  console.log('VaR (95%):', result.data.var95)
}
```

---

#### `window.kdb.emergencyStop()`

**Emergency kill switch**: Cancel all orders and close all positions across all exchanges.

**Returns**:
```typescript
{ success: true } | { success: false; error: string }
```

**Keyboard Shortcut**: `Ctrl+Shift+E`

**Example**:
```typescript
if (confirm('KILL SWITCH: Cancel all orders and close all positions?')) {
  await window.kdb.emergencyStop()
}
```

---

#### `window.kdb.strategyControl(name, action)`

Control strategy lifecycle (pause/resume/stop).

**Parameters**:
- `name` (string): Strategy name
- `action` (string): `'pause'` | `'resume'` | `'stop'`

**Returns**:
```typescript
{ success: true } | { success: false; error: string }
```

**Example**:
```typescript
// Pause a strategy
await window.kdb.strategyControl('arbitrage', 'pause')

// Resume after review
await window.kdb.strategyControl('arbitrage', 'resume')

// Stop permanently
await window.kdb.strategyControl('arbitrage', 'stop')
```

---

## Error Handling

All API functions use consistent error handling patterns.

### Python

```python
try:
    price = price_bond(1000, 0.05, 0.04, 5.0)
except ValueError as e:
    print(f"Invalid input: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
```

### q/kdb+

```q
/ Use protected evaluation
result: @[.risk.margin.calculate; (`AAPL; 100; `buy); {`error!x}]

$[`error in key result;
    [0N!"Error: ", result`error];
    [0N!"Margin: ", string result]
]
```

### TypeScript/Electron

```typescript
try {
  const result = await window.kdb.placeOrder(order)
  
  if (!result.success) {
    console.error('Order failed:', result.error)
    return
  }
  
  console.log('Order placed:', result.data.orderId)
} catch (err) {
  console.error('Unexpected error:', err)
}
```

---

## Testing

All APIs have comprehensive test coverage:

- **Python pricing**: 68 tests (bond pricing, options pricing, yield curves) with golden values from Hull textbook
- **q/kdb+ risk**: 122 tests (risk validation, P&L calculation, margin calculations)
- **Electron IPC**: Manual testing (E2E tests planned with Playwright)

**Run tests**:
```bash
# Python
cd src/python && pytest tests/test_bond_pricing.py -v
cd src/python && pytest tests/test_options_pricing.py -v

# q/kdb+
q tests/q/test_risk.q
```

---

## Performance Notes

| Operation | Throughput | Latency |
|-----------|-----------|---------|
| `price_bond()` | 500K/sec | 2μs |
| `black_scholes_call()` | 1M/sec | 1μs |
| `calculate_krd()` | 100K/sec | 10μs |
| `.risk.margin.calculate` | 500K/sec | 2μs |
| `window.kdb.getRiskMetrics()` | 1K/sec | 1ms |

All pricing functions are vectorized (NumPy) for batch calculations.

---

## Examples

See `/examples/` directory for complete examples:

- `examples/bond_pricing_example.py` — Bond pricing and analytics
- `examples/options_pricing_example.py` — Options pricing and Greeks
- `examples/risk_monitoring_example.q` — Real-time risk monitoring in q
- `examples/electron_integration.ts` — Electron IPC integration

---

## Support

For issues or questions:
- GitHub Issues: [medusa/issues](https://github.com/yourorg/medusa/issues)
- Documentation: [medusa/docs](https://github.com/yourorg/medusa/docs)
- Email: support@example.com
