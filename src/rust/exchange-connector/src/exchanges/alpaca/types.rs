//! Alpaca API data types
//!
//! Matches Alpaca's JSON response schemas for equities trading.

use serde::{Deserialize, Serialize};

// ====================================================================
// ACCOUNT TYPES
// ====================================================================

#[derive(Debug, Deserialize)]
pub struct Account {
    pub id: String,
    pub account_number: String,
    pub status: String,
    /// Cash balance (string for precision)
    pub cash: String,
    /// Buying power (includes margin)
    pub buying_power: String,
    /// Total portfolio value
    pub portfolio_value: String,
    /// Equity value
    pub equity: String,
    /// Previous day's equity
    pub last_equity: String,
    /// Long market value
    pub long_market_value: String,
    /// Short market value
    pub short_market_value: String,
    /// Pattern day trader flag
    pub pattern_day_trader: bool,
    /// Trading blocked flag
    pub trading_blocked: bool,
    /// Transfers blocked flag
    pub transfers_blocked: bool,
    /// Account blocked flag
    pub account_blocked: bool,
    /// Number of day trades in rolling 5 day period
    pub daytrade_count: i32,
}

// ====================================================================
// ORDER TYPES
// ====================================================================

#[derive(Debug, Serialize)]
pub struct OrderRequest {
    pub symbol: String,
    /// Quantity (string for precision) - mutually exclusive with notional
    #[serde(skip_serializing_if = "Option::is_none")]
    pub qty: Option<String>,
    /// Dollar amount to buy/sell - mutually exclusive with qty
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notional: Option<String>,
    /// "buy" or "sell"
    pub side: String,
    /// "market", "limit", "stop", "stop_limit", "trailing_stop"
    #[serde(rename = "type")]
    pub order_type: String,
    /// "day", "gtc", "opg", "cls", "ioc", "fok"
    pub time_in_force: String,
    /// Required for limit orders
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit_price: Option<String>,
    /// Required for stop orders
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stop_price: Option<String>,
    /// Trade during extended hours
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extended_hours: Option<bool>,
    /// Client-generated order ID for tracking
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_order_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct Order {
    pub id: String,
    pub client_order_id: String,
    pub created_at: String,
    #[serde(default)]
    pub updated_at: Option<String>,
    #[serde(default)]
    pub submitted_at: Option<String>,
    #[serde(default)]
    pub filled_at: Option<String>,
    #[serde(default)]
    pub expired_at: Option<String>,
    #[serde(default)]
    pub canceled_at: Option<String>,
    #[serde(default)]
    pub failed_at: Option<String>,
    pub asset_id: String,
    pub symbol: String,
    pub asset_class: String,
    #[serde(default)]
    pub qty: Option<String>,
    #[serde(default)]
    pub notional: Option<String>,
    pub filled_qty: String,
    #[serde(default)]
    pub filled_avg_price: Option<String>,
    #[serde(rename = "type")]
    pub order_type: String,
    pub side: String,
    pub time_in_force: String,
    #[serde(default)]
    pub limit_price: Option<String>,
    #[serde(default)]
    pub stop_price: Option<String>,
    pub status: String,
    pub extended_hours: bool,
}

// ====================================================================
// POSITION TYPES
// ====================================================================

#[derive(Debug, Deserialize)]
pub struct Position {
    pub asset_id: String,
    pub symbol: String,
    pub exchange: String,
    pub asset_class: String,
    /// Quantity held (string for precision)
    pub qty: String,
    /// Average entry price
    pub avg_entry_price: String,
    /// "long" or "short"
    pub side: String,
    /// Current market value
    pub market_value: String,
    /// Cost basis
    pub cost_basis: String,
    /// Unrealized P&L (dollars)
    pub unrealized_pl: String,
    /// Unrealized P&L (percent)
    pub unrealized_plpc: String,
    /// Intraday unrealized P&L
    pub unrealized_intraday_pl: String,
    /// Intraday unrealized P&L (percent)
    pub unrealized_intraday_plpc: String,
    /// Current asset price
    pub current_price: String,
    /// Last day's price
    pub lastday_price: String,
    /// Change from last day
    pub change_today: String,
}

// ====================================================================
// MARKET DATA TYPES (Historical)
// ====================================================================

/// Bar (candlestick) response wrapper
#[derive(Debug, Deserialize)]
pub struct BarsResponse {
    pub bars: Vec<Bar>,
    #[serde(default)]
    pub next_page_token: Option<String>,
}

/// OHLCV bar
#[derive(Debug, Deserialize)]
pub struct Bar {
    /// Timestamp (RFC3339 format)
    #[serde(rename = "t")]
    pub timestamp: String,
    /// Open price
    #[serde(rename = "o")]
    pub open: f64,
    /// High price
    #[serde(rename = "h")]
    pub high: f64,
    /// Low price
    #[serde(rename = "l")]
    pub low: f64,
    /// Close price
    #[serde(rename = "c")]
    pub close: f64,
    /// Volume
    #[serde(rename = "v")]
    pub volume: u64,
    /// Number of trades
    #[serde(rename = "n")]
    pub trade_count: u64,
    /// Volume-weighted average price
    #[serde(rename = "vw")]
    pub vwap: f64,
}

/// Trade response wrapper
#[derive(Debug, Deserialize)]
pub struct TradesResponse {
    pub trades: Vec<AlpacaTrade>,
    #[serde(default)]
    pub next_page_token: Option<String>,
}

/// Individual trade
#[derive(Debug, Deserialize)]
pub struct AlpacaTrade {
    /// Timestamp (RFC3339 format)
    #[serde(rename = "t")]
    pub timestamp: String,
    /// Trade price
    #[serde(rename = "p")]
    pub price: f64,
    /// Trade size
    #[serde(rename = "s")]
    pub size: u64,
    /// Exchange code
    #[serde(rename = "x")]
    pub exchange: String,
    /// Trade ID
    #[serde(rename = "i")]
    pub id: u64,
    /// Trade conditions
    #[serde(rename = "c")]
    pub conditions: Vec<String>,
    /// Tape (A, B, C)
    #[serde(rename = "z")]
    pub tape: String,
}

/// Quote response wrapper
#[derive(Debug, Deserialize)]
pub struct QuotesResponse {
    pub quotes: Vec<Quote>,
    #[serde(default)]
    pub next_page_token: Option<String>,
}

/// Bid/ask quote
#[derive(Debug, Deserialize)]
pub struct Quote {
    /// Timestamp (RFC3339 format)
    #[serde(rename = "t")]
    pub timestamp: String,
    /// Bid exchange
    #[serde(rename = "bx")]
    pub bid_exchange: String,
    /// Bid price
    #[serde(rename = "bp")]
    pub bid_price: f64,
    /// Bid size
    #[serde(rename = "bs")]
    pub bid_size: u64,
    /// Ask exchange
    #[serde(rename = "ax")]
    pub ask_exchange: String,
    /// Ask price
    #[serde(rename = "ap")]
    pub ask_price: f64,
    /// Ask size
    #[serde(rename = "as")]
    pub ask_size: u64,
    /// Quote conditions
    #[serde(rename = "c")]
    pub conditions: Vec<String>,
    /// Tape (A, B, C)
    #[serde(rename = "z")]
    pub tape: String,
}

/// Snapshot response wrapper
#[derive(Debug, Deserialize)]
pub struct SnapshotResponse {
    pub symbol: String,
    #[serde(default)]
    pub latest_trade: Option<AlpacaTrade>,
    #[serde(default)]
    pub latest_quote: Option<Quote>,
    #[serde(default)]
    pub minute_bar: Option<Bar>,
    #[serde(default)]
    pub daily_bar: Option<Bar>,
    #[serde(default)]
    pub prev_daily_bar: Option<Bar>,
}

// ====================================================================
// WEBSOCKET MESSAGE TYPES
// ====================================================================

/// WebSocket authentication message
#[derive(Debug, Serialize)]
pub struct WsAuthMessage {
    pub action: String, // "auth"
    pub key: String,
    pub secret: String,
}

/// WebSocket subscription message
#[derive(Debug, Serialize)]
pub struct WsSubscribeMessage {
    pub action: String, // "subscribe"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub trades: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quotes: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bars: Option<Vec<String>>,
}

/// WebSocket message types (simplified enum for pattern matching)
#[derive(Debug, Deserialize)]
#[serde(tag = "T")]
pub enum WsMessage {
    /// Trade update ("T")
    #[serde(rename = "t")]
    Trade(AlpacaTrade),
    /// Quote update ("Q")
    #[serde(rename = "q")]
    Quote(Quote),
    /// Bar update ("B")
    #[serde(rename = "b")]
    Bar(Bar),
    /// Authentication success
    #[serde(rename = "success")]
    Success { msg: String },
    /// Error message
    #[serde(rename = "error")]
    Error { msg: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_order_request_serialization() {
        let req = OrderRequest {
            symbol: "AAPL".to_string(),
            qty: Some("100".to_string()),
            notional: None,
            side: "buy".to_string(),
            order_type: "market".to_string(),
            time_in_force: "day".to_string(),
            limit_price: None,
            stop_price: None,
            extended_hours: None,
            client_order_id: Some("test-001".to_string()),
        };

        let json = serde_json::to_string(&req).unwrap();
        assert!(json.contains("\"symbol\":\"AAPL\""));
        assert!(json.contains("\"qty\":\"100\""));
        assert!(!json.contains("notional")); // Should be omitted
    }

    #[test]
    fn test_order_deserialization() {
        let json = r#"{
            "id": "abc123",
            "client_order_id": "test-001",
            "created_at": "2026-01-15T10:30:00Z",
            "asset_id": "asset123",
            "symbol": "AAPL",
            "asset_class": "us_equity",
            "qty": "100",
            "filled_qty": "0",
            "type": "market",
            "side": "buy",
            "time_in_force": "day",
            "status": "accepted",
            "extended_hours": false
        }"#;

        let order: Order = serde_json::from_str(json).unwrap();
        assert_eq!(order.id, "abc123");
        assert_eq!(order.symbol, "AAPL");
        assert_eq!(order.qty, Some("100".to_string()));
    }

    #[test]
    fn test_bar_deserialization() {
        let json = r#"{
            "t": "2026-01-15T14:30:00Z",
            "o": 150.0,
            "h": 151.5,
            "l": 149.5,
            "c": 151.0,
            "v": 1000000,
            "n": 5000,
            "vw": 150.75
        }"#;

        let bar: Bar = serde_json::from_str(json).unwrap();
        assert_eq!(bar.open, 150.0);
        assert_eq!(bar.close, 151.0);
        assert_eq!(bar.volume, 1000000);
    }

    #[test]
    fn test_ws_auth_message_serialization() {
        let auth = WsAuthMessage {
            action: "auth".to_string(),
            key: "test-key".to_string(),
            secret: "test-secret".to_string(),
        };

        let json = serde_json::to_string(&auth).unwrap();
        assert!(json.contains("\"action\":\"auth\""));
        assert!(json.contains("\"key\":\"test-key\""));
    }

    #[test]
    fn test_ws_subscribe_message_serialization() {
        let sub = WsSubscribeMessage {
            action: "subscribe".to_string(),
            trades: Some(vec!["AAPL".to_string(), "TSLA".to_string()]),
            quotes: Some(vec!["AAPL".to_string()]),
            bars: None,
        };

        let json = serde_json::to_string(&sub).unwrap();
        assert!(json.contains("\"action\":\"subscribe\""));
        assert!(json.contains("\"trades\":[\"AAPL\",\"TSLA\"]"));
        assert!(!json.contains("bars")); // Should be omitted
    }
}
