# Money Library (`money.q`)

Type-safe, currency-aware money operations for the Medusa trading system.

## Overview

The `.money` namespace provides a complete money type system that prevents currency confusion bugs (e.g., adding USD to BTC without conversion) while maintaining high performance through kdb+'s vectorized operations.

## Key Features

- **Type Safety**: All operations enforce currency matching or explicit conversion
- **Precision Handling**: Currency-specific decimal precision (8 for BTC, 2 for USD, 0 for JPY)
- **Currency Conversion**: Built-in forex rate table with automatic rate lookup
- **Rich Formatting**: Human-readable output with proper currency symbols
- **Helper Functions**: Zero values, absolute values, negation, and more

## Quick Start

```q
/ Load the library
\l src/q/lib/money.q

/ Create money values
usd: .money.new[100; `USD]        / $100.00
btc: .money.new[0.005; `BTC]      / 0.00500000 BTC

/ Arithmetic (same currency only)
sum: .money.add[usd; .money.new[50; `USD]]  / $150.00
diff: .money.sub[usd; .money.new[30; `USD]] / $70.00
prod: .money.mul[usd; 1.5]                   / $150.00
quot: .money.div[usd; 2]                     / $50.00

/ Comparisons
.money.gt[usd; .money.new[50; `USD]]        / 1b (true)
.money.eq[usd; usd]                          / 1b (true)

/ Currency conversion
eur: .money.convert[usd; `EUR]               / €85.50

/ Formatting
.money.fmt[usd]                              / "$100.00"
.money.fmt[btc]                              / "0.00500000 BTC"
```

## API Reference

### Currency Metadata

#### `.money.currencies`
Keyed table containing metadata for all supported currencies.

| Column | Type | Description |
|--------|------|-------------|
| `currency` | symbol | Currency code (BTC, USD, EUR, etc.) |
| `precision` | int | Decimal places (8 for BTC, 2 for USD) |
| `symbol` | string | Display symbol ($, €, ¥, etc.) |
| `name` | string | Full currency name |

**Example:**
```q
q).money.currencies
currency| precision symbol name
--------| --------------------------------
BTC     | 8         "BTC"  "Bitcoin"
USD     | 2         "$"    "US Dollar"
EUR     | 2         "€"    "Euro"
```

#### `.money.validCurrency[c]`
Check if currency code is supported.

**Parameters:**
- `c` (symbol): Currency code

**Returns:** boolean (1b if valid)

**Example:**
```q
q).money.validCurrency[`BTC]
1b
q).money.validCurrency[`INVALID]
0b
```

#### `.money.precision[c]`
Get decimal precision for a currency.

**Parameters:**
- `c` (symbol): Currency code

**Returns:** int (number of decimal places)

**Example:**
```q
q).money.precision[`BTC]
8
q).money.precision[`USD]
2
```

### Constructor

#### `.money.new[amt; c]`
Create a Money value.

**Parameters:**
- `amt` (number or string): Amount
- `c` (symbol): Currency code

**Returns:** dict with `amount` and `currency` keys

**Examples:**
```q
q).money.new[100; `USD]
amount  | 100f
currency| `USD

q).money.new["0.005"; `BTC]
amount  | 0.005
currency| `BTC

q).money.new[0.123456789; `BTC]  / Rounds to 8 decimals
amount  | 0.12345679
currency| `BTC
```

**Errors:**
- Throws if currency is invalid
- Throws if amount is negative
- Throws if amount cannot be parsed (for string input)

### Arithmetic Operations

All arithmetic operations require same currency or throw an error.

#### `.money.add[m1; m2]`
Add two Money values (same currency).

**Example:**
```q
q).money.add[.money.new[100;`USD]; .money.new[50;`USD]]
amount  | 150f
currency| `USD

q).money.add[.money.new[100;`USD]; .money.new[1;`BTC]]
'Currency mismatch: cannot add USD and BTC
```

#### `.money.sub[m1; m2]`
Subtract second Money from first (same currency).

**Note:** Allows negative results for P&L calculations.

**Example:**
```q
q).money.sub[.money.new[100;`USD]; .money.new[150;`USD]]
amount  | -50f
currency| `USD
```

#### `.money.mul[m; scalar]`
Multiply Money by a scalar (preserves currency).

**Example:**
```q
q).money.mul[.money.new[100;`USD]; 1.5]
amount  | 150f
currency| `USD

q).money.mul[.money.new[1;`BTC]; 0.01]  / 1% position
amount  | 0.01
currency| `BTC
```

#### `.money.div[m; scalar]`
Divide Money by a scalar (preserves currency).

**Example:**
```q
q).money.div[.money.new[100;`USD]; 3]
amount  | 33.33
currency| `USD
```

### Comparison Operations

All comparisons require same currency or throw an error.

#### `.money.eq[m1; m2]`
Check equality (same currency AND amount).

#### `.money.lt[m1; m2]`
Check if m1 < m2 (same currency).

#### `.money.gt[m1; m2]`
Check if m1 > m2 (same currency).

#### `.money.lte[m1; m2]`
Check if m1 <= m2 (same currency).

#### `.money.gte[m1; m2]`
Check if m1 >= m2 (same currency).

**Example:**
```q
q).money.gt[.money.new[100;`USD]; .money.new[50;`USD]]
1b

q).money.eq[.money.new[100;`USD]; .money.new[100;`EUR]]
0b  / Different currencies are never equal
```

### Formatting

#### `.money.fmt[m]`
Format Money value to human-readable string.

**Rules:**
- Fiat currencies (USD, EUR, GBP, JPY): Symbol prefix (e.g., "$100.50")
- Crypto currencies (BTC, ETH): Amount + code (e.g., "0.00500000 BTC")
- Precision matches currency rules

**Example:**
```q
q).money.fmt[.money.new[100.5; `USD]]
"$100.50"

q).money.fmt[.money.new[0.005; `BTC]]
"0.00500000 BTC"

q).money.fmt[.money.new[1000; `JPY]]
"¥1000"  / No decimals for JPY
```

### Currency Conversion

#### `.money.convert[m; targetCurrency]`
Convert Money to target currency using exchange rates.

**Parameters:**
- `m` (dict): Money value
- `targetCurrency` (symbol): Target currency code

**Returns:** dict (Money in target currency)

**Example:**
```q
q).money.convert[.money.new[100;`USD]; `EUR]
amount  | 85.5
currency| `EUR

q).money.convert[.money.new[1;`BTC]; `USD]
amount  | 50000f
currency| `USD
```

**Notes:**
- Uses `.money.rates` table for exchange rates
- Supports inverse rates (if USD→EUR exists, EUR→USD uses 1/rate)
- Same currency conversion returns original amount
- Throws if no rate found

#### `.money.rates`
Keyed table containing exchange rates.

**Schema:** `from` (symbol), `to` (symbol), `rate` (float)

**Example:**
```q
from to | rate
-------| --------
USD  USD| 1
USD  EUR| 0.855
EUR  USD| 1.17
BTC  USD| 50000
```

**Extending rates:**
```q
/ Add new rate
`.money.rates upsert (`GBP;`USD;1.27)
```

### Helper Functions

#### `.money.zero[c]`
Create zero Money for a currency.

**Example:**
```q
q).money.zero[`USD]
amount  | 0f
currency| `USD
```

#### `.money.isZero[m]`
Check if Money amount is zero.

**Example:**
```q
q).money.isZero[.money.zero[`USD]]
1b
```

#### `.money.abs[m]`
Get absolute value of Money.

**Example:**
```q
q).money.abs[.money.new[-100; `USD]]
amount  | 100f
currency| `USD
```

#### `.money.neg[m]`
Negate Money amount.

**Example:**
```q
q).money.neg[.money.new[100; `USD]]
amount  | -100f
currency| `USD
```

## Supported Currencies

| Code | Name | Precision | Symbol |
|------|------|-----------|--------|
| `BTC` | Bitcoin | 8 | BTC |
| `USD` | US Dollar | 2 | $ |
| `EUR` | Euro | 2 | € |
| `GBP` | British Pound | 2 | £ |
| `JPY` | Japanese Yen | 0 | ¥ |
| `ETH` | Ethereum | 18 | ETH |
| `USDT` | Tether | 2 | USDT |

## Usage Patterns

### Trade P&L Calculation

```q
/ Entry
entryPrice: .money.new[50000; `USD]
entryQty: 0.5
entryCost: .money.mul[entryPrice; entryQty]  / $25,000

/ Exit
exitPrice: .money.new[52000; `USD]
exitValue: .money.mul[exitPrice; entryQty]   / $26,000

/ P&L
pnl: .money.sub[exitValue; entryCost]        / $1,000
```

### Portfolio Valuation

```q
/ Calculate position values
btcValue: .money.mul[.money.new[50000;`USD]; 2.5]   / $125,000
ethValue: .money.mul[.money.new[3000;`USD]; 10.0]   / $30,000

/ Total portfolio
total: .money.add[btcValue; ethValue]                / $155,000
```

### Fee Calculation

```q
/ Trade size
trade: .money.new[10000; `USD]

/ 0.1% fee
fee: .money.mul[trade; 0.001]                        / $10

/ Net proceeds
net: .money.sub[trade; fee]                          / $9,990
```

### Risk Management

```q
/ Account balance
balance: .money.new[100000; `USD]

/ Risk 2% per trade
riskAmount: .money.mul[balance; 0.02]                / $2,000

/ Entry and stop
entry: .money.new[50000; `USD]
stop: .money.new[49000; `USD]
stopDist: .money.sub[entry; stop]                    / $1,000

/ Position size
posSize: riskAmount[`amount] % stopDist[`amount]     / 2.0 BTC
```

### Bulk Operations (Table-Based)

For performance with many money values, use table format:

```q
/ Portfolio table
portfolio: ([]
  currency: `BTC`ETH`USD;
  amount: 1.5 10.0 5000.0;
  price: (.money.new[50000;`USD]; .money.new[3000;`USD]; .money.new[1;`USD])
 )

/ Calculate values
portfolio: update value: {.money.mul[x;y]}[price;amount] from portfolio
```

## Error Handling

The library uses q's standard error signaling. All errors throw with descriptive messages:

```q
/ Invalid currency
.money.new[100; `INVALID]
'Invalid currency: INVALID

/ Currency mismatch
.money.add[.money.new[100;`USD]; .money.new[1;`BTC]]
'Currency mismatch: cannot add USD and BTC

/ Negative amount
.money.new[-100; `USD]
'Amount must be non-negative: -100

/ Division by zero
.money.div[.money.new[100;`USD]; 0]
'Division by zero

/ Missing exchange rate
.money.convert[.money.new[100;`GBP]; `JPY]
'No forex rate found for GBP to JPY
```

## Performance Considerations

### Single Values
- Money dictionaries are ~100 bytes each
- Dictionary lookup is O(1)
- Arithmetic operations are fast (< 1μs)

### Collections
For bulk operations on thousands of money values:
1. Convert to table format
2. Use vectorized operations
3. Store currency as enum type (4 bytes vs 16 bytes per value)

**Example:**
```q
/ Instead of list of Money dicts
/ Use table format for bulk operations
positions: ([]
  currency: `g#`BTC`BTC`ETH`ETH`USD;  / Grouped for efficiency
  amount: 0.5 0.3 10.0 5.0 1000.0
 )
```

## Testing

Run unit tests:
```bash
q tests/q/test_money.q
```

Run integration tests:
```bash
q tests/q/test_money_integration.q
```

Quick verification:
```bash
q tests/q/verify_money.q
```

## Extension Points

### Adding New Currencies

```q
/ Append to currencies table
`.money.currencies upsert (`DOGE; 2; "DOGE"; "Dogecoin")
```

### Adding Exchange Rates

```q
/ Add new rate
`.money.rates upsert (`DOGE;`USD;0.08)
```

### Custom Formatting

Override `.money.fmt` for custom display:

```q
/ Add thousand separators
.money.fmtCustom:{[m]
  / Custom formatting logic
  }
```

## Design Rationale

### Dictionary-Based Representation
- **Pros**: Type-safe, explicit currency, extensible metadata
- **Cons**: Slightly more memory than pairs
- **Alternative**: Pair-based `(amount;currency)` is more compact but less extensible

### Namespace-Based API
- **Pros**: Explicit, prevents name collisions, clear ownership
- **Cons**: More verbose than operator overloading
- **Alternative**: Could overload `+`, `-` operators but reduces clarity

### Precision Rules
- BTC: 8 decimals (satoshi level)
- Fiat: 2 decimals (cent level)
- ETH: 18 decimals (wei level)
- JPY: 0 decimals (no subunits)

Rounding occurs on construction and all operations to prevent floating-point drift.

## Common Gotchas

### 1. Currency Mismatch
```q
/ ERROR - different currencies
.money.add[.money.new[100;`USD]; .money.new[1;`BTC]]

/ CORRECT - convert first
usd: .money.new[100; `USD]
btcInUsd: .money.convert[.money.new[1;`BTC]; `USD]
.money.add[usd; btcInUsd]
```

### 2. Negative Amounts in Constructor
```q
/ ERROR - constructor rejects negative
.money.new[-100; `USD]

/ CORRECT - use subtraction or neg
zero: .money.zero[`USD]
.money.sub[zero; .money.new[100;`USD]]  / -$100
```

### 3. Precision Loss
```q
/ Be aware of rounding
.money.new[0.123456789; `BTC]  / → 0.12345679 (8 decimals)
.money.new[100.556; `USD]      / → 100.56 (2 decimals)
```

## License

Part of the Medusa trading system.
