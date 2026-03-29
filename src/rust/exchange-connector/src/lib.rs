//! Exchange connector library for Medusa
//!
//! Provides async clients for cryptocurrency exchange APIs.

pub mod client;
pub mod types;

pub use client::{ExchangeClient, ExchangeError};
pub use types::{
    Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side, Trade,
};
