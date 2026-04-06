# exchange-connector

Async exchange API clients for Medusa.

## Purpose

Provides REST and WebSocket clients for cryptocurrency exchanges (Bitstamp, Coinbase, Kraken). Used by `exchange-daemon` and GDS subscribers to connect to exchange APIs.

## Modules

- `client` — Shared HTTP client with authentication
- `exchanges/` — Per-exchange implementations (REST endpoints, WS streams)
- `feeds/` — WebSocket feed abstraction
- `rate_limiter` — Per-exchange rate limiting
- `types` — Shared data types (orderbook, trade, ticker)
- `websocket` — WebSocket connection management with reconnection

## Supported Exchanges

| Exchange | REST | WebSocket | Rate Limiting |
|----------|------|-----------|---------------|
| Bitstamp | Yes  | Yes       | 8000 req/10min |
| Coinbase | Yes  | Yes       | 10 req/sec |
| Kraken   | Yes  | Yes       | 15 req/sec |

## Usage

```rust
use exchange_connector::exchanges::bitstamp::BitstampClient;

let client = BitstampClient::new(config).await?;
let orderbook = client.get_orderbook("btcusd").await?;
```

### WebSocket Feeds

```rust
use exchange_connector::feeds::BitstampFeed;

let feed = BitstampFeed::new(config);
feed.subscribe_orderbook("btcusd").await?;

while let Some(event) = feed.next().await {
    match event {
        WsMessage::Orderbook(ob) => println!("Orderbook: {:?}", ob),
        WsMessage::Trade(trade) => println!("Trade: {:?}", trade),
        WsMessage::Error(err) => eprintln!("Error: {}", err),
    }
}
```

## Build

```bash
cargo build -p exchange-connector
cargo test -p exchange-connector
```

## Dependencies

- `tokio` — Async runtime
- `reqwest` — HTTP client
- `tokio-tungstenite` — WebSocket client
- `serde` / `serde_json` — Serialization
