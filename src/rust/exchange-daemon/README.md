# exchange-daemon

Long-running bridge between exchange APIs and kdb+.

## Purpose

Daemon process that connects to exchanges via `exchange-connector` and publishes market data to the kdb+ Tickerplant via `kdb-ipc`. Handles connection lifecycle, reconnection, and graceful shutdown.

## Architecture

```
Exchange APIs → exchange-connector → exchange-daemon → kdb-ipc → Tickerplant (port 5010)
```

## Features

- Connects to kdb+ Tickerplant on startup
- Initializes orderbook schema in kdb+
- Publishes mock orderbook data (Wave 3 testing only)
- Handles SIGTERM/SIGINT for graceful shutdown
- Connection retry with exponential backoff

## Command Line Interface

```bash
exchange-daemon \
  --kdb-host localhost \
  --kdb-port 5010 \
  --kdb-user myuser \
  --publish-interval 5
```

### Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--kdb-host` | `localhost` | kdb+ Tickerplant host |
| `--kdb-port` | `5001` | kdb+ Tickerplant port |
| `--kdb-user` | `""` | kdb+ username (empty for no auth) |
| `--publish-interval` | `5` | Mock data publish interval (seconds) |

### Environment Variables

- `KDB_PASSWORD` — kdb+ password (not passed via CLI for security)

## Running

### Development

```bash
export KDB_PASSWORD="secret"
cargo run -p exchange-daemon -- --kdb-port 5010
```

### Production

```bash
export KDB_PASSWORD="secret"
./target/release/exchange-daemon \
  --kdb-host production-tp \
  --kdb-port 5010 \
  --kdb-user readonly
```

## Build

```bash
cargo build -p exchange-daemon
cargo build --release -p exchange-daemon  # Optimized
cargo test -p exchange-daemon
```

## Schema Initialization

On startup, the daemon creates the `orderbook` table:

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

## Shutdown

Send SIGTERM or SIGINT (Ctrl+C) for graceful shutdown:

1. Cancel publisher task
2. Close kdb+ connection
3. Exit cleanly

## Dependencies

- `exchange-connector` — Exchange API clients
- `kdb-ipc` — kdb+ IPC protocol
- `tokio` — Async runtime
- `clap` — CLI argument parsing
- `tracing` — Logging
