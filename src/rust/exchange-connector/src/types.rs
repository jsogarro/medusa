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

#[cfg(test)]
mod tests {
    use super::*;

    // ====================================================================
    // EDGE CASE TESTS
    // ====================================================================

    #[test]
    fn test_orderbook_empty() {
        let ob = OrderBook {
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            bids: vec![],
            asks: vec![],
            timestamp: Utc::now(),
            sequence: None,
        };
        assert_eq!(ob.bids.len(), 0, "Empty orderbook should have no bids");
        assert_eq!(ob.asks.len(), 0, "Empty orderbook should have no asks");
    }

    #[test]
    fn test_price_level_zero_quantity() {
        let level = PriceLevel {
            price: 100.0,
            quantity: 0.0,
        };
        assert_eq!(level.quantity, 0.0, "Should handle zero quantity");
    }

    #[test]
    fn test_price_level_negative_values() {
        // Note: Production code should validate these, but types should not panic
        let level = PriceLevel {
            price: -100.0,
            quantity: -10.0,
        };
        assert!(level.price < 0.0);
        assert!(level.quantity < 0.0);
    }

    #[test]
    fn test_price_level_max_values() {
        let level = PriceLevel {
            price: f64::MAX,
            quantity: f64::MAX,
        };
        assert!(level.price.is_finite());
        assert!(level.quantity.is_finite());
    }

    #[test]
    fn test_order_partial_fill() {
        let mut order = Order {
            id: Some("123".to_string()),
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            side: Side::Buy,
            price: Some(50000.0),
            quantity: 1.0,
            order_type: OrderType::Limit,
            status: OrderStatus::PartiallyFilled,
            client_order_id: None,
            filled_quantity: 0.5,
            average_price: Some(49990.0),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        assert_eq!(order.filled_quantity, 0.5);
        assert!(order.filled_quantity < order.quantity);

        // Simulate complete fill
        order.filled_quantity = 1.0;
        order.status = OrderStatus::Filled;
        assert_eq!(order.filled_quantity, order.quantity);
    }

    #[test]
    fn test_order_zero_quantity() {
        let order = Order {
            id: None,
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            side: Side::Buy,
            price: Some(50000.0),
            quantity: 0.0,
            order_type: OrderType::Limit,
            status: OrderStatus::Pending,
            client_order_id: None,
            filled_quantity: 0.0,
            average_price: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        // Should not panic with zero quantity
        assert_eq!(order.quantity, 0.0);
    }

    #[test]
    fn test_order_market_no_price() {
        let order = Order {
            id: None,
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            side: Side::Buy,
            price: None, // Market order has no price
            quantity: 1.0,
            order_type: OrderType::Market,
            status: OrderStatus::Pending,
            client_order_id: Some("client-123".to_string()),
            filled_quantity: 0.0,
            average_price: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        assert!(order.price.is_none(), "Market order should have no price");
        assert!(order.client_order_id.is_some());
    }

    #[test]
    fn test_balance_consistency() {
        let balance = Balance {
            asset: "BTC".to_string(),
            exchange: "test".to_string(),
            total: 10.0,
            available: 7.0,
            locked: 3.0,
        };
        assert_eq!(
            balance.available + balance.locked,
            balance.total,
            "Available + locked should equal total"
        );
    }

    #[test]
    fn test_balance_zero_values() {
        let balance = Balance {
            asset: "BTC".to_string(),
            exchange: "test".to_string(),
            total: 0.0,
            available: 0.0,
            locked: 0.0,
        };
        assert_eq!(balance.total, 0.0);
    }

    #[test]
    fn test_balance_all_locked() {
        let balance = Balance {
            asset: "USD".to_string(),
            exchange: "test".to_string(),
            total: 1000.0,
            available: 0.0,
            locked: 1000.0,
        };
        assert_eq!(balance.available, 0.0);
        assert_eq!(balance.locked, balance.total);
    }

    #[test]
    fn test_side_serialization() {
        let buy = Side::Buy;
        let sell = Side::Sell;

        let buy_json = serde_json::to_string(&buy).unwrap();
        let sell_json = serde_json::to_string(&sell).unwrap();

        assert_eq!(buy_json, r#""buy""#);
        assert_eq!(sell_json, r#""sell""#);
    }

    #[test]
    fn test_order_type_serialization() {
        let market = OrderType::Market;
        let limit = OrderType::Limit;

        let market_json = serde_json::to_string(&market).unwrap();
        let limit_json = serde_json::to_string(&limit).unwrap();

        assert_eq!(market_json, r#""market""#);
        assert_eq!(limit_json, r#""limit""#);
    }

    #[test]
    fn test_order_status_serialization() {
        let pending = OrderStatus::Pending;
        let filled = OrderStatus::Filled;

        let pending_json = serde_json::to_string(&pending).unwrap();
        let filled_json = serde_json::to_string(&filled).unwrap();

        assert_eq!(pending_json, r#""pending""#);
        assert_eq!(filled_json, r#""filled""#);
    }

    #[test]
    fn test_trade_maker_taker() {
        let maker_trade = Trade {
            id: "1".to_string(),
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            price: 50000.0,
            quantity: 0.1,
            side: Side::Buy,
            timestamp: Utc::now(),
            is_maker: Some(true),
        };
        assert_eq!(maker_trade.is_maker, Some(true));

        let taker_trade = Trade {
            is_maker: Some(false),
            ..maker_trade
        };
        assert_eq!(taker_trade.is_maker, Some(false));
    }

    #[test]
    fn test_orderbook_sequence_number() {
        let ob_with_seq = OrderBook {
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            bids: vec![],
            asks: vec![],
            timestamp: Utc::now(),
            sequence: Some(12345),
        };
        assert_eq!(ob_with_seq.sequence, Some(12345));

        let ob_no_seq = OrderBook {
            sequence: None,
            ..ob_with_seq
        };
        assert!(ob_no_seq.sequence.is_none());
    }

    #[test]
    fn test_order_overflow_filled_quantity() {
        // Test that filled_quantity can exceed quantity (shouldn't happen, but type allows it)
        let order = Order {
            id: Some("123".to_string()),
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            side: Side::Buy,
            price: Some(50000.0),
            quantity: 1.0,
            order_type: OrderType::Limit,
            status: OrderStatus::Filled,
            client_order_id: None,
            filled_quantity: 1.5, // More than quantity!
            average_price: Some(50000.0),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        // Type system allows this, validation should catch it
        assert!(order.filled_quantity > order.quantity);
    }
}
