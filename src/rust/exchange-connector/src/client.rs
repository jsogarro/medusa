//! Exchange client trait

use crate::types::{Order, OrderBook};
use async_trait::async_trait;

/// Common interface for exchange clients
#[async_trait]
pub trait ExchangeClient: Send + Sync {
    /// Get orderbook for a trading pair
    async fn get_orderbook(&self, pair: &str) -> anyhow::Result<OrderBook>;

    /// Place an order
    async fn place_order(&self, order: Order) -> anyhow::Result<String>;

    /// Cancel an order by ID
    async fn cancel_order(&self, order_id: &str) -> anyhow::Result<()>;
}
