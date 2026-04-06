# gds-common

Shared infrastructure for Guardian Data System (GDS) subscribers.

## Purpose

Provides reusable components shared across all GDS binary crates: health monitoring, exponential backoff for reconnection, and kdb+ Tickerplant publishing utilities.

## Modules

- `backoff` — Exponential backoff with jitter for reconnection
- `config` — Shared configuration (TP host/port, exchange settings)
- `health` — Health check endpoint and status reporting
- `publisher` — kdb+ Tickerplant publisher with batching and error handling

## Components

### ExponentialBackoff

Retry strategy with exponential backoff and jitter to prevent thundering herd.

```rust
use gds_common::ExponentialBackoff;

let mut backoff = ExponentialBackoff::new(1.0, 60.0, 2.0);

loop {
    match attempt_connection().await {
        Ok(_) => {
            backoff.reset();
            break;
        }
        Err(e) => {
            let delay = backoff.next_delay();
            tokio::time::sleep(delay).await;
        }
    }
}
```

### HealthMonitor

Tracks last update time and reports staleness.

```rust
use gds_common::HealthMonitor;
use std::time::Duration;

let monitor = HealthMonitor::new(Duration::from_secs(30));

// Update on every message
monitor.record_update();

// Check health
if monitor.is_stale() {
    eprintln!("No data received in 30 seconds!");
}
```

### KdbPublisher

High-level abstraction for publishing to kdb+ Tickerplant.

```rust
use gds_common::KdbPublisher;

let publisher = KdbPublisher::connect("localhost", 5010, "user", "pass").await?;

// Publish single update
publisher.publish_orderbook("BTCUSD", "coinbase", "bid", 50000.0, 1.5).await?;

// Batch publish (more efficient)
let batch = vec![/* multiple records */];
publisher.publish_batch("orderbook", batch).await?;
```

### GdsConfig

Centralized configuration with environment variable support.

```rust
use gds_common::GdsConfig;

let config = GdsConfig {
    tp_host: "localhost".to_string(),
    tp_port: 5010,
    tp_user: "".to_string(),
    tp_password: std::env::var("KDB_PASSWORD").unwrap_or_default(),
    health_timeout_secs: 30,
    exchanges: vec![
        ExchangeConfig::bitstamp(),
        ExchangeConfig::coinbase(),
        ExchangeConfig::kraken(),
    ],
};
```

## Build

```bash
cargo build -p gds-common
cargo test -p gds-common
```

## Dependencies

- `kdb-ipc` — kdb+ IPC protocol
- `tokio` — Async runtime
- `tracing` — Logging
- `serde` — Configuration serialization
