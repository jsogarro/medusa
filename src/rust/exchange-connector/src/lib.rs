//! Exchange connector library for Medusa
//!
//! Provides async clients for cryptocurrency exchange APIs.

pub mod client;
pub mod exchanges;
pub mod feeds;
pub mod rate_limiter;
pub mod types;
pub mod websocket;

pub use client::{ExchangeClient, ExchangeError};
pub use exchanges::{BitstampClient, CoinbaseClient, KrakenClient};
pub use feeds::{BitstampFeed, CoinbaseFeed, KrakenFeed};
pub use rate_limiter::RateLimiter;
pub use types::{
    Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side, Trade,
};
pub use websocket::{WebSocketClient, WsConfig, WsMessage};
