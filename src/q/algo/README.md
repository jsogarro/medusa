# Execution Algorithm Engine

**P0 Production Gap Closed** — VWAP, TWAP, and Iceberg execution algorithms for Medusa.

## Overview

The Execution Algorithm Engine sits on top of the existing exchange coordinator and risk management system. It breaks large parent orders into smaller child orders ("slices") according to configurable algorithms.

### Architecture

```
┌─────────────────────────────────────────┐
│       Execution Algorithm Engine         │
│  (.algo namespace)                       │
│                                          │
│  ┌──────────────────────────────────┐  │
│  │  Orchestrator (engine.q)         │  │
│  │  - submit, pause, cancel, resume │  │
│  │  - Timer-based scheduler         │  │
│  │  - Child fill → parent update    │  │
│  └──────────────────────────────────┘  │
│           ↓       ↓       ↓             │
│     ┌─────┐  ┌─────┐  ┌────────┐      │
│     │VWAP │  │TWAP │  │Iceberg │      │
│     └─────┘  └─────┘  └────────┘      │
└─────────────────────────────────────────┘
           ↓                    ↑
┌─────────────────────┐  ┌──────────────┐
│ Exchange Coordinator│  │ Risk Validate│
│ (.exchange.coordin..│  │ (.risk)      │
└─────────────────────┘  └──────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `schema.q` | Table schemas: `algoOrder`, `childOrder`, `executionBenchmark` |
| `engine.q` | Orchestrator: order lifecycle, timer, child management |
| `vwap.q` | Volume-Weighted Average Price algorithm |
| `twap.q` | Time-Weighted Average Price algorithm |
| `iceberg.q` | Iceberg (hidden liquidity) algorithm |
| `init.q` | Initialization entry point |

## Tables

### `algoOrder` (Parent Orders)

Keyed by `algoOrderId`.

| Column | Type | Description |
|--------|------|-------------|
| `algoOrderId` | symbol | Unique algo order ID (PK) |
| `exchange` | symbol | Exchange name |
| `pair` | symbol | Trading pair (e.g., `BTCUSD`) |
| `side` | symbol | `buy` or `sell` |
| `targetQty` | long | Total target quantity (fixed precision) |
| `filledQty` | long | Quantity filled so far |
| `algo` | symbol | Algorithm type (`vwap`, `twap`, `iceberg`) |
| `algoParams` | dict | Algorithm-specific parameters |
| `benchmark` | symbol | Benchmark type (`arrival`, `vwap`) |
| `benchmarkPrice` | long | Benchmark price for TCA |
| `status` | symbol | `active`, `paused`, `cancelled`, `completed` |
| `startTime` | timestamp | Algorithm start time |
| `endTime` | timestamp | Algorithm end time (null for no limit) |
| `createdAt` | timestamp | Order creation timestamp |
| `completedAt` | timestamp | Completion timestamp (null if incomplete) |

### `childOrder` (Slices)

Keyed by `childOrderId`. Foreign key to `algoOrder` via `algoOrderId`.

| Column | Type | Description |
|--------|------|-------------|
| `childOrderId` | symbol | Unique child order ID (PK) |
| `algoOrderId` | symbol | Parent algo order ID (FK) |
| `exchange` | symbol | Exchange name |
| `pair` | symbol | Trading pair |
| `side` | symbol | `buy` or `sell` |
| `orderType` | symbol | `market` or `limit` |
| `price` | long | Order price (null for market) |
| `quantity` | long | Order quantity (fixed precision) |
| `filledQty` | long | Quantity filled |
| `status` | symbol | Order status |
| `submitTime` | timestamp | Submission timestamp |
| `fillTime` | timestamp | Fill timestamp (null if not filled) |
| `avgFillPrice` | long | Average fill price (null until filled) |

### `executionBenchmark` (TCA)

Keyed by `(time; exchange; pair)`.

| Column | Type | Description |
|--------|------|-------------|
| `time` | timestamp | Timestamp (PK component) |
| `exchange` | symbol | Exchange name (PK component) |
| `pair` | symbol | Trading pair (PK component) |
| `benchmarkType` | symbol | `arrival`, `vwap`, `mid`, `last` |
| `price` | long | Benchmark price (fixed precision) |
| `volume` | long | Volume (for VWAP calculation) |

## API

### Submit Algo Order

```q
algoOrderId: .algo.engine.submit[
  exchange;   / symbol - Exchange name
  pair;       / symbol - Trading pair
  side;       / symbol - `buy or `sell
  qty;        / long   - Target quantity (fixed precision)
  algo;       / symbol - `vwap, `twap, or `iceberg
  params      / dict   - Algorithm parameters
];
```

### Pause/Resume/Cancel

```q
.algo.engine.pause[algoOrderId];   / Stop slicing, keep children open
.algo.engine.resume[algoOrderId];  / Resume slicing
.algo.engine.cancel[algoOrderId];  / Cancel all children, mark completed
```

### Child Fill Callback

```q
.algo.engine.onChildFill[
  childOrderId;   / symbol - Child order ID
  filledQty;      / long   - Filled quantity
  avgFillPrice    / long   - Average fill price
];
```

## Algorithms

### VWAP (Volume-Weighted Average Price)

**Strategy**: Slice orders proportionally to market volume.

**Parameters**:
- `participation` (float): Participation rate (0.0 - 1.0). Default: 0.10 (10%)
- `lookbackWindow` (long): Lookback window in milliseconds. Default: 60000 (1 minute)
- `orderType` (symbol): `limit` or `market`. Default: `limit`
- `priceOffset` (long): Price offset from best price. Default: 0j

**Example**:
```q
algoId: .algo.engine.submit[
  `bitstamp;
  `BTCUSD;
  `buy;
  100000000j;  / 100.0 BTC
  `vwap;
  `participation`lookbackWindow!(0.15; 120000)  / 15%, 2-minute window
];
```

**Slicing Logic**:
- Every timer tick (1 second), check recent market volume
- Slice size = `participation` × recent volume
- Cap at remaining quantity
- Submit limit order at best price + offset

### TWAP (Time-Weighted Average Price)

**Strategy**: Distribute order evenly over time.

**Parameters**:
- `sliceInterval` (long): Seconds between slices. Default: 60
- `endTime` (timestamp): **Required**. Algorithm end time.
- `orderType` (symbol): `limit` or `market`. Default: `limit`
- `priceOffset` (long): Price offset from best price. Default: 0j

**Example**:
```q
endTime: .z.p + 0D00:30:00;  / 30 minutes from now

algoId: .algo.engine.submit[
  `coinbase;
  `ETHUSD;
  `sell;
  50000000j;  / 50.0 ETH
  `twap;
  `sliceInterval`endTime!(30; endTime)  / 30-second slices
];
```

**Slicing Logic**:
- Calculate slices remaining = `timeRemaining` ÷ `sliceInterval`
- Slice size = `remainingQty` ÷ `slicesRemaining`
- Submit equal-sized slices at regular intervals

### Iceberg

**Strategy**: Show only a fraction of the total order, replenish on fills.

**Parameters**:
- `displayQty` (long): Display quantity per slice (fixed precision). Default: 10000000j (10.0 units)
- `randomize` (boolean): Randomize display qty ±20%. Default: 1b
- `orderType` (symbol): `limit` or `market`. Default: `limit`
- `priceOffset` (long): Price offset from best price. Default: 0j

**Example**:
```q
algoId: .algo.engine.submit[
  `kraken;
  `BTCUSD;
  `buy;
  200000000j;  / 200.0 BTC
  `iceberg;
  `displayQty`randomize!(15000000j; 1b)  / Display 15.0 ±20%
];
```

**Slicing Logic**:
- Check if pending child orders exist — if yes, wait for fill
- When child fills, immediately submit next slice
- Randomize display quantity ±20% to avoid detection

## Integration Points

### Risk Validation

Every child order submission calls:
```q
.risk.validateOrder[`algo; pair; exchange; side; qty; price]
```

If validation fails, the slice is skipped and logged.

### Exchange Coordinator

Child orders are submitted via:
```q
.exchange.coordinator.placeOrder[exchange; pair; orderType; side; price; quantity]
```

Child order cancellations via:
```q
.exchange.coordinator.cancelOrder[exchange; orderId]
```

### Progress Publishing

Progress updates are published to the tickerplant (if `.u.pub` exists):
```q
.u.pub[`algoProgress; (algoOrderId; filledQty; targetQty; avgFillPrice)]
```

Subscribers can track algo order progress in real-time.

## Timer Mechanism

The engine uses `.z.ts` (timer handler) to periodically slice active algo orders:

- Interval: 1 second (1000ms)
- Enabled automatically when first algo order is submitted
- Disabled when no active orders remain
- Each algo order is processed once per timer tick

## TCA (Transaction Cost Analysis)

The engine tracks benchmark prices for TCA:

- **Arrival price**: Best price at order submission time
- **VWAP**: Volume-weighted average price over execution period

Compare `avgFillPrice` from child orders against benchmark to measure execution quality.

## Usage Example

```q
/ Load the algo engine
\l src/q/algo/init.q

/ Submit a VWAP order
vwapId: .algo.engine.submit[`bitstamp; `BTCUSD; `buy; 100000000j; `vwap; `participation!(0.10)];

/ Monitor progress
select from .algo.algoOrder where algoOrderId=vwapId;
select from .algo.childOrder where algoOrderId=vwapId;

/ Pause if needed
.algo.engine.pause[vwapId];

/ Resume
.algo.engine.resume[vwapId];

/ Cancel
.algo.engine.cancel[vwapId];
```

## Testing

Tests are in `tests/q/test_algo_engine.q`:

```bash
cd <repo root>
q tests/q/test_algo_engine.q
```

Test coverage:
- ✅ Parent order creation
- ✅ VWAP slice sizing (participation rate)
- ✅ TWAP equal slicing
- ✅ Iceberg randomization
- ✅ Child fill → parent update
- ✅ Pause/resume/cancel lifecycle

## Dependencies

**Required before loading**:
- `.qg` namespace: validation functions (`isValidExchange`, `isPositiveAmount`, etc.)
- `.exchange.coordinator`: order placement and cancellation
- `.risk.validateOrder`: pre-trade risk checks

**Optional**:
- `.u.pub`: Tickerplant publish (for progress updates)

## Fixed Precision

All prices and quantities use 6-decimal fixed precision (type `long`):
- 1.0 BTC = `1000000j`
- $50,000.00 = `50000000000j`

See `src/q/lib/money.q` for currency-aware arithmetic.

## Future Enhancements

- [ ] POV (Percent of Volume) algorithm
- [ ] Implementation Shortfall algorithm
- [ ] Adaptive VWAP (adjust participation dynamically)
- [ ] Smart order router (multi-exchange VWAP)
- [ ] Real-time TCA dashboard
- [ ] Integration with actual orderbook table (currently uses dummy prices)
- [ ] Integration with actual trade table (currently uses dummy volumes)

## License

Part of the Medusa algorithmic trading system.
