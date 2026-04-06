# gds-orderbook-subscriber

Real-time orderbook data subscriber for kdb+.

## Purpose

Subscribes to orderbook updates from multiple exchanges via WebSocket and publishes to the kdb+ Tickerplant. Handles initial REST snapshot bootstrap, sequence validation, and gap recovery.

## Architecture

```
Exchange WebSocket → Orderbook Subscriber → Tickerplant (port 5010) → RDB → Strategies
```

## Features

- WebSocket subscription per exchange (Bitstamp, Coinbase, Kraken)
- Initial orderbook snapshot via REST (one-time bootstrap per symbol)
- Sequence number validation and gap detection
- Automatic reconnection with exponential backoff
- Health monitoring with configurable staleness timeout
- Publishes via `.u.upd[`orderbook;data]`

## Command Line Interface

```bash
gds-orderbook-subscriber \
  --tp-host localhost \
  --tp-port 5010 \
  --tp-user myuser \
  --health-timeout 30
```

### Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--tp-host` | `localhost` | Tickerplant host |
| `--tp-port` | `5010` | Tickerplant port |
| `--tp-user` | `""` | kdb+ username (empty for no auth) |
| `--health-timeout` | `30` | Health check timeout (seconds) |

### Environment Variables

- `KDB_PASSWORD` — kdb+ password (required if TP has authentication)

## Running

### Development

```bash
export KDB_PASSWORD="secret"
cargo run -p gds-orderbook-subscriber
```

### Production

```bash
export KDB_PASSWORD="secret"
./target/release/gds-orderbook-subscriber \
  --tp-host production-tp \
  --tp-port 5010 \
  --health-timeout 60
```

## Data Flow

1. On startup: Connect to Tickerplant
2. For each enabled exchange:
   - Fetch initial orderbook snapshot via REST
   - Subscribe to WebSocket orderbook stream
   - Validate sequence numbers for each update
   - Detect gaps and request snapshots as needed
   - Publish normalized orderbook updates to TP
3. Health monitoring: Alert if no data received within timeout

## Orderbook Schema

Published to kdb+ as:

```q
orderbook:([]
    sym:`symbol$();
    exchange:`symbol$();
    side:`symbol$();
    price:`float$();
    quantity:`float$();
    timestamp:`timestamp$()
)
```

## Exchange-Specific Handling

### Bitstamp

- WebSocket channel: `order_book_{symbol}`
- Snapshot via REST: `https://www.bitstamp.net/api/v2/order_book/{symbol}/`
- Sequence validation: `microtimestamp` field

### Coinbase

- WebSocket channel: `level2`
- Snapshot via REST: `https://api.exchange.coinbase.com/products/{symbol}/book?level=2`
- Sequence validation: `sequence` field

### Kraken

- WebSocket channel: `book`
- Snapshot via REST: `https://api.kraken.com/0/public/Depth?pair={symbol}`
- No sequence validation (Kraken doesn't provide sequence numbers)

## Build

```bash
cargo build -p gds-orderbook-subscriber
cargo build --release -p gds-orderbook-subscriber  # Optimized
cargo test -p gds-orderbook-subscriber
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
