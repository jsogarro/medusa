//! Exchange client trait and error types

use crate::types::{Balance, Order, OrderBook};
use async_trait::async_trait;
use thiserror::Error;

/// Exchange-specific errors for fine-grained error handling
#[derive(Debug, Error)]
pub enum ExchangeError {
    /// Network error (retryable)
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    /// Rate limit exceeded (retryable with backoff)
    #[error("Rate limit exceeded: {0}")]
    RateLimit(String),

    /// Invalid request parameters (not retryable)
    #[error("Invalid request: {0}")]
    InvalidRequest(String),

    /// Authentication error (not retryable)
    #[error("Authentication failed: {0}")]
    Authentication(String),

    /// Insufficient balance (not retryable)
    #[error("Insufficient balance: {0}")]
    InsufficientBalance(String),

    /// Order not found (not retryable)
    #[error("Order not found: {0}")]
    OrderNotFound(String),

    /// Exchange unavailable (retryable)
    #[error("Exchange unavailable: {0}")]
    Unavailable(String),

    /// JSON parsing error
    #[error("JSON parsing error: {0}")]
    JsonParse(#[from] serde_json::Error),

    /// Generic error
    #[error("Exchange error: {0}")]
    Other(String),
}

impl ExchangeError {
    /// Returns true if this error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            ExchangeError::Network(_)
                | ExchangeError::RateLimit(_)
                | ExchangeError::Unavailable(_)
        )
    }
}

/// Common interface for exchange clients
///
/// # Design Notes
/// - Uses thiserror for library error types (better than anyhow for public APIs)
/// - All methods return Result<T, ExchangeError> for fine-grained error handling
/// - Trait is Send + Sync for use across async tasks
/// - WebSocket subscription methods will be added in Wave 2
#[async_trait]
pub trait ExchangeClient: Send + Sync {
    /// Get orderbook snapshot for a trading pair
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError>;

    /// Get account balance for a specific asset or all assets
    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError>;

    /// Get all open orders for a trading pair or all pairs
    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError>;

    /// Get order status by ID
    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError>;

    /// Place a new order
    ///
    /// Returns the exchange-assigned order ID
    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError>;

    /// Cancel an order by ID
    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError>;

    /// Cancel all open orders for a trading pair or all pairs
    async fn cancel_all_orders(&self, pair: Option<&str>) -> Result<u32, ExchangeError>;

    // WebSocket subscription methods to be added in Wave 2:
    // - subscribe_orderbook
    // - subscribe_trades
    // - subscribe_orders (private channel)
}
