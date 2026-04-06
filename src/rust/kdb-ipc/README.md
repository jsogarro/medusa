# kdb-ipc

Async kdb+ IPC protocol implementation for Rust.

## Purpose

Provides a Rust client for communicating with kdb+ processes using the kdb+ IPC binary protocol. Used by all Rust components to publish data to the Tickerplant and query RDB/HDB.

## Modules

- `client` — Async TCP client with connection management
- `encode` — Serialize Rust types to kdb+ IPC binary format
- `decode` — Deserialize kdb+ IPC responses to Rust types
- `types` — Rust representations of kdb+ types (atom, list, table, dict)
- `error` — Error types for IPC communication

## Supported kdb+ Types

| kdb+ Type | Rust Type | Encoding | Decoding |
|-----------|-----------|----------|----------|
| `boolean` | `bool` | Yes | Yes |
| `byte` | `u8` | Yes | Yes |
| `short` | `i16` | Yes | Yes |
| `int` | `i32` | Yes | Yes |
| `long` | `i64` | Yes | Yes |
| `real` | `f32` | Yes | Yes |
| `float` | `f64` | Yes | Yes |
| `char` | `char` | Yes | Yes |
| `symbol` | `String` | Yes | Yes |
| `timestamp` | `i64` (nanos) | Yes | Yes |
| `list` | `Vec<T>` | Yes | Yes |
| `dict` | `HashMap<K,V>` | Yes | Yes |
| `table` | `Table` | Yes | Yes |

## Usage

### Connecting

```rust
use kdb_ipc::client::KdbClient;

let client = KdbClient::connect("localhost", 5010, "user", "pass").await?;
```

### Synchronous Query

```rust
let result = client.query("select from trade where sym=`BTCUSD").await?;
```

### Async Message (Fire and Forget)

```rust
client.send_async(".u.upd", &["marketData", &data]).await?;
```

### Tickerplant Publishing

```rust
// Publish orderbook update
let data = vec![
    KObject::Symbol("BTCUSD".to_string()),
    KObject::Float(50000.0),
    KObject::Float(1.5),
];

client.send_async(".u.upd", &["orderbook", &data]).await?;
```

## Build

```bash
cargo build -p kdb-ipc
cargo test -p kdb-ipc
```

## Dependencies

- `tokio` — Async runtime
- `bytes` — Byte buffer utilities
- `tracing` — Logging
