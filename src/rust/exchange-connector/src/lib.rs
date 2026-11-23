//! Exchange connector library for Medusa
//!
//! Provides async clients for cryptocurrency and equity exchange APIs.

pub mod circuit_breaker;
pub mod client;
pub mod exchanges;
pub mod feeds;
pub mod rate_limiter;
pub mod retry;
pub mod types;
pub mod websocket;

pub use circuit_breaker::{
    CircuitBreaker, CircuitBreakerConfig, CircuitBreakerError, CircuitBreakerStatus, CircuitState,
};
pub use client::{ExchangeClient, ExchangeError};
pub use exchanges::{AlpacaClient, BinanceClient, BitstampClient, CoinbaseClient, KrakenClient};
pub use feeds::{AlpacaFeed, BinanceFeed, BitstampFeed, CoinbaseFeed, KrakenFeed};
pub use rate_limiter::RateLimiter;
pub use retry::{retry_with_backoff, RetryConfig};
pub use types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side, Trade};
pub use websocket::{WebSocketClient, WsConfig, WsMessage};
