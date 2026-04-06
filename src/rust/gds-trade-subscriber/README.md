# gds-trade-subscriber

Real-time trade data subscriber for kdb+.

## Purpose

Subscribes to WebSocket trade streams from multiple exchanges and publishes to the kdb+ Tickerplant for downstream strategy consumption.

## Architecture

```
Exchange WebSocket → Trade Subscriber → Tickerplant (port 5010) → RDB → Strategies
```

## Features

- Per-exchange WebSocket trade stream subscription
- Trade normalization to Medusa schema format
- Automatic reconnection with exponential backoff
- Health monitoring via gds-common
- Optional one-time backfill on startup (via REST)
- Trade deduplication (prevents duplicate publishes)
- Publishes via `.u.upd[`trade;data]`

## Command Line Interface

```bash
gds-trade-subscriber \
  --tp-host localhost \
  --tp-port 5010 \
  --tp-user myuser \
  --health-timeout 30 \
  --backfill
```

### Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--tp-host` | `localhost` | Tickerplant host |
| `--tp-port` | `5010` | Tickerplant port |
| `--tp-user` | `""` | kdb+ username (empty for no auth) |
| `--health-timeout` | `30` | Health check timeout (seconds) |
| `--backfill` | `false` | Enable one-time REST backfill on startup |

### Environment Variables

- `KDB_PASSWORD` — kdb+ password (required if TP has authentication)
- `BACKFILL_TRADES` — Set to `"true"` to enable backfill (alternative to `--backfill` flag)

## Running

### Development

```bash
export KDB_PASSWORD="secret"
cargo run -p gds-trade-subscriber
```

### Production with Backfill

```bash
export KDB_PASSWORD="secret"
export BACKFILL_TRADES="true"
./target/release/gds-trade-subscriber \
  --tp-host production-tp \
  --tp-port 5010 \
  --health-timeout 60
```

## Data Flow

1. On startup: Connect to Tickerplant
2. Optional: Backfill recent trades via REST (one-time per symbol)
3. For each enabled exchange:
   - Subscribe to WebSocket trade stream
   - Normalize trade data to Medusa schema
   - Deduplicate trades (track trade IDs)
   - Publish to Tickerplant
4. Health monitoring: Alert if no data received within timeout

## Trade Schema

Published to kdb+ as:

```q
trade:([]
    sym:`symbol$();
    exchange:`symbol$();
    side:`symbol$();
    price:`float$();
    quantity:`float$();
    trade_id:`long$();
    timestamp:`timestamp$()
)
```

## Exchange-Specific Handling

### Bitstamp

- WebSocket channel: `live_trades_{symbol}`
- Trade ID field: `id`
- Side detection: `type` field (0=buy, 1=sell)
- REST backfill: `https://www.bitstamp.net/api/v2/transactions/{symbol}/`

### Coinbase

- WebSocket channel: `matches`
- Trade ID field: `trade_id` (numeric)
- Side detection: `side` field (buy/sell)
- REST backfill: `https://api.exchange.coinbase.com/products/{symbol}/trades`

### Kraken

- WebSocket channel: `trade`
- Trade ID: Generated from timestamp + price (Kraken doesn't provide trade IDs)
- Side detection: `type` field (b=buy, s=sell)
- REST backfill: `https://api.kraken.com/0/public/Trades?pair={symbol}`

## Deduplication

Trade IDs are tracked in memory (last 10,000 per symbol) to prevent duplicate publishes. This is critical when:

- Reconnecting to WebSocket streams
- Backfilling historical trades
- Handling replayed messages from exchanges

## Build

```bash
cargo build -p gds-trade-subscriber
cargo build --release -p gds-trade-subscriber  # Optimized
cargo test -p gds-trade-subscriber
```

## Shutdown

Send SIGTERM or SIGINT (Ctrl+C) for graceful shutdown:

1. Disconnect from all WebSocket streams
2. Close kdb+ connection
3. Exit cleanly

## Dependencies

- `exchange-connector` — Exchange WebSocket feeds
- `gds-common` — Health, backoff, publisher
- `kdb-ipc` — kdb+ IPC protocol
- `tokio` — Async runtime
- `clap` — CLI argument parsing
- `tracing` — Logging
