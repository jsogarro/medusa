# Alpaca Phase 3 — PDT Rule, Margin, Settlement

## Overview

Phase 3 adds three regulatory compliance modules for Alpaca equity trading:

1. **PDT (Pattern Day Trader) Rule** — FINRA Rule 4210
2. **Margin Requirements** — Reg T initial margin (50%) and maintenance margin (30%)
3. **Settlement Tracking** — T+1 settlement for equities, freeriding detection

All three modules **only apply to equity symbols** — crypto is exempt.

## Files

| File | Purpose |
|------|---------|
| `pdt.q` | Day trade tracking, PDT rule enforcement |
| `margin.q` | Margin calculation, buying power checks |
| `settlement.q` | T+1 settlement tracking, freeriding/good faith violation detection |

## Integration

### Loaded in `risk/init.q`

```q
/ Load Phase 3: Alpaca equity regulations
\l risk/pdt.q
\l risk/margin.q
\l risk/settlement.q
```

### Initialized in `risk/schema.q`

```q
/ Initialize Phase 3 modules (if loaded)
if[not ()~key `.risk.initPDT; initPDT[]];
if[not ()~key `.risk.initMargin; initMargin[]];
if[not ()~key `.risk.initSettlement; initSettlement[]];
```

### Called in `risk/validate.q`

Three new pre-trade checks (equity only):

```q
/ Check 16: PDT rule
if[.schema.isEquity[sym];
  result:checkPDT[sym;side;qty];
  if[not result 0; logRiskEvent[...]; :result];
];

/ Check 17: Margin requirement
if[.schema.isEquity[sym];
  result:checkMarginAvailable[sym;qty;price];
  if[not result 0; logRiskEvent[...]; :result];
];

/ Check 18: Freeriding violation
if[.schema.isEquity[sym];
  result:checkFreeridingViolation[sym;side;qty;price];
  if[not result 0; logRiskEvent[...]; :result];
];
```

Post-fill settlement recording:

```q
onFill:{[strategy;sym;exchange;side;qty;price]
  / ... existing updates ...

  / Phase 3: Record settlement (equity only)
  if[.schema.isEquity[sym];
    recordSettlement[.z.d;sym;side;qty;price];
  ];
};
```

## PDT Rule (pdt.q)

### Regulatory Context

- **FINRA Rule 4210**: Pattern Day Trader definition
- **Day trade**: Round-trip buy+sell (or sell-short+buy-cover) same symbol same day
- **Threshold**: 4+ day trades in 5 business days triggers PDT restriction
- **Account minimum**: $25,000 equity required for PDT accounts

### Configuration

```q
.risk.pdtConfig  / Single-row table
enabled:           1b    / Enable/disable PDT checks
accountValue:      10000.0  / Current account equity
minAccountValue:   25000.0  / PDT threshold ($25k)
dayTradeWindow:    5i    / Rolling business days
maxDayTrades:      3i    / Warning threshold (4 triggers restriction)
```

### Functions

| Function | Description |
|----------|-------------|
| `initPDT[]` | Initialize PDT tracking |
| `checkPDT[sym;side;qty]` | Pre-trade check: (pass; reason; details) |
| `recordDayTrade[sym;openSide;closeSide;openQty;closeQty;pnl]` | Record day trade |
| `getDayTradeCount[]` | Get count for last 5 business days |
| `updateAccountValue[value]` | Sync account value from Alpaca API |
| `resetDayTrades[]` | Reset (for testing) |
| `pdtStatus[]` | Status summary dict |

### Behavior

- **Account >= $25k**: PDT rule bypassed (exempt)
- **3 day trades**: Warning logged, order allowed
- **4+ day trades**: Order rejected with `pdtBreach` reason
- **Crypto**: Always bypassed (24/7 market, no PDT)

### Tables

```q
dayTradeHistory   / Append-only log of all day trades
dayTradeSummary   / Aggregated count per date (keyed by date)
pdtAlerts         / Warning/breach alerts
```

## Margin (margin.q)

### Regulatory Context

- **Regulation T (Fed)**: 50% initial margin for equities
- **FINRA Rule 4210**: 25% minimum maintenance margin
- **House requirement**: 30% maintenance margin (typical)
- **Reg T leverage**: 2:1 overnight positions

### Configuration

```q
.risk.marginConfig  / Single-row table
enabled:              1b    / Enable/disable margin checks
initialMarginPct:     50.0  / Reg T: 50%
maintenanceMarginPct: 30.0  / House: 30% (FINRA min 25%)
minEquity:            2000.0   / Minimum equity for margin account
pdtMinEquity:         25000.0  / PDT minimum
```

### Functions

| Function | Description |
|----------|-------------|
| `initMargin[]` | Initialize margin tracking |
| `calcMarginRequirement[sym;qty;price]` | Calculate initial margin (50%) |
| `calcMaintenanceMargin[sym;qty;price]` | Calculate maintenance margin (30%) |
| `checkMarginAvailable[sym;qty;price]` | Pre-trade check: (pass; reason; details) |
| `updateMarginState[account]` | Sync from Alpaca account API |
| `detectMarginCall[]` | Check equity < maintenance margin |
| `marginStatus[]` | Status summary dict |
| `getMarginUtilization[]` | Margin used / equity (%) |

### Behavior

- **Initial margin**: 50% of notional value
- **Maintenance margin**: 30% of current market value
- **Buying power**: 2 * equity - margin_used
- **Margin call**: Triggered when equity < maintenance margin
- **Crypto**: Bypassed (no margin for crypto)

### Tables

```q
marginState          / Single-row: equity, buyingPower, cash, marginUsed, maintenanceMargin, marginCallActive
marginCallHistory    / Append-only log of margin calls
```

## Settlement (settlement.q)

### Regulatory Context

- **SEC T+1**: Equities settle 1 business day after trade date (since May 28, 2024)
- **Freeriding**: Buying with unsettled funds, selling before settlement
- **Good faith violation**: Buy, sell, buy cycle using unsettled proceeds
- **3 violations in 12 months**: 90-day cash-only restriction

### Configuration

```q
.risk.settlementConfig  / Single-row table
enabled:                 1b   / Enable/disable settlement checks
settlementDays:          1i   / T+1 for equities
maxGoodFaithViolations:  3i   / Restriction threshold
violationWindow:         365i / Days to track violations
```

### Functions

| Function | Description |
|----------|-------------|
| `initSettlement[]` | Initialize settlement tracking |
| `recordSettlement[tradeDate;sym;side;qty;price]` | Record trade settlement |
| `checkFreeridingViolation[sym;side;qty;price]` | Pre-trade check: (pass; reason; details) |
| `checkGoodFaithViolation[sym;side;qty;price]` | Pre-trade check: (pass; reason; details) |
| `getUnsettledCash[]` | Total unsettled cash |
| `processSettlements[]` | Mark settled trades (call daily) |
| `settlementStatus[]` | Status summary dict |

### Behavior

- **Settlement date**: T+1 business days from trade date
- **Unsettled cash tracking**: Positive=from sales, Negative=from buys
- **Freeriding**: Rejected if selling more than settled position
- **Good faith**: Warned if buying with unsettled funds (restricted after 3 violations)
- **Crypto**: Bypassed (instant settlement)

### Tables

```q
settlementTracking   / Append-only: all trades with settle dates
unsettledCash        / Aggregated by settle date (keyed)
freeridingViolations / Violation log
goodFaithSummary     / Violation count, restriction status
```

## Usage Example

```q
/ Initialize all Phase 3 modules
.risk.init[];  / Calls initPDT[], initMargin[], initSettlement[]

/ Pre-trade validation (equity order)
result:.risk.validateOrder[`strategy1; `AAPL; `alpaca; `buy; 100.0; 150.0];
/ Returns: (1b;`) if pass, (0b;`pdtBreach) if fail

/ Post-fill updates
.risk.onFill[`strategy1; `AAPL; `alpaca; `buy; 100.0; 150.0];
/ Records settlement, day trade detection happens here

/ Account sync (from Alpaca API)
account:`equity`buying_power`cash`maintenance_margin!(15000.0; 12000.0; 8000.0; 4500.0);
.risk.updateMarginState[account];
/ Updates margin state and PDT account value

/ Daily settlement processing
.risk.processSettlements[];
/ Marks trades settling today as settled

/ Status checks
.risk.pdtStatus[]
.risk.marginStatus[]
.risk.settlementStatus[]
```

## Notes

- All three modules **only apply to equities** — crypto is exempt
- T+1 settlement (not T+2) — SEC updated in May 2024
- PDT threshold is configurable (default $25k)
- Margin percentages are configurable (default 50% initial, 30% maintenance)
- Day trade detection requires position tracking (TODO: implement when position manager is complete)
