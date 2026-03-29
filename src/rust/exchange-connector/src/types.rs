//! Common types for exchange data
//!
//! # Precision Note
//! Currently using f64 for prices and quantities. f64 provides ~15-16 significant digits,
//! which is sufficient for most crypto pairs but may not handle extreme precision requirements.
//! Future waves will migrate to rust_decimal or bigdecimal for production.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OrderBook {
    pub pair: String,
    pub exchange: String,
    pub bids: Vec<PriceLevel>,
    pub asks: Vec<PriceLevel>,
    pub timestamp: DateTime<Utc>,
    /// Sequence number for detecting missing updates (WebSocket)
    pub sequence: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct PriceLevel {
    pub price: f64,
    pub quantity: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Trade {
    pub id: String,
    pub pair: String,
    pub exchange: String,
    pub price: f64,
    pub quantity: f64,
    pub side: Side,
    pub timestamp: DateTime<Utc>,
    /// Whether this trade was the maker or taker side
    pub is_maker: Option<bool>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum Side {
    Buy,
    Sell,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Order {
    /// Unique order ID (set by exchange after placement, or client-generated for tracking)
    pub id: Option<String>,
    pub pair: String,
    pub exchange: String,
    pub side: Side,
    /// Price (ignored for Market orders)
    pub price: Option<f64>,
    pub quantity: f64,
    pub order_type: OrderType,
    pub status: OrderStatus,
    /// Client order ID for tracking before exchange assignment
    pub client_order_id: Option<String>,
    /// Filled quantity (for partial fills)
    pub filled_quantity: f64,
    /// Average fill price
    pub average_price: Option<f64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum OrderType {
    Limit,
    Market,
    /// Stop-loss orders (future expansion)
    StopLoss,
    /// Take-profit orders (future expansion)
    TakeProfit,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum OrderStatus {
    /// Order submitted but not yet confirmed
    Pending,
    /// Order accepted by exchange
    Open,
    /// Order partially filled
    PartiallyFilled,
    /// Order fully filled
    Filled,
    /// Order cancelled
    Cancelled,
    /// Order rejected by exchange
    Rejected,
    /// Order expired
    Expired,
}

/// Account balance information
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Balance {
    pub asset: String,
    pub exchange: String,
    /// Total balance (available + locked)
    pub total: f64,
    /// Available for trading
    pub available: f64,
    /// Locked in open orders
    pub locked: f64,
}
