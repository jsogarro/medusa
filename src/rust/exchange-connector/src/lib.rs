//! Exchange connector library for Medusa
//!
//! Provides async clients for cryptocurrency exchange APIs.

pub mod client;
pub mod types;

pub use client::ExchangeClient;
pub use types::{Order, OrderBook, OrderType, PriceLevel, Side, Trade};
