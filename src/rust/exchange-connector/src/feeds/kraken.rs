//! Kraken WebSocket feed implementation
//!
//! WebSocket documentation: https://docs.kraken.com/websockets/

use crate::client::ExchangeError;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::Utc;
use serde::Serialize;
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const KRAKEN_WS_URL: &str = "wss://ws.kraken.com/v2";

/// Kraken WebSocket feed
pub struct KrakenFeed {
    client: WebSocketClient,
}

impl KrakenFeed {
    /// Create a new Kraken WebSocket feed
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let config = WsConfig {
            url: KRAKEN_WS_URL.to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (client, rx) = WebSocketClient::connect(config).await?;

        Ok((Self { client }, rx))
    }

    /// Subscribe to orderbook for a trading pair
    ///
    /// # Security
    /// Validates pair format to prevent injection.
    pub async fn subscribe_orderbook(&self, pair: &str) -> Result<(), ExchangeError> {
        // Security: Validate pair format
        if !pair.chars().all(|c| c.is_alphanumeric() || c == '/') {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters and slashes".into(),
            ));
        }

        let sub_msg = KrakenSubscribeV2 {
            method: "subscribe".to_string(),
            params: KrakenSubscriptionParams {
                channel: "book".to_string(),
                symbol: vec![pair.to_uppercase()],
                depth: Some(10),
            },
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Kraken book for: {}", pair);
        self.client.send_text(&json).await
    }

    /// Subscribe to trades for a trading pair
    ///
    /// # Security
    /// Validates pair format.
    pub async fn subscribe_trades(&self, pair: &str) -> Result<(), ExchangeError> {
        // Security: Validate pair format
        if !pair.chars().all(|c| c.is_alphanumeric() || c == '/') {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters and slashes".into(),
            ));
        }

        let sub_msg = KrakenSubscribeV2 {
            method: "subscribe".to_string(),
            params: KrakenSubscriptionParams {
                channel: "trade".to_string(),
                symbol: vec![pair.to_uppercase()],
                depth: None,
            },
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Kraken trade for: {}", pair);
        self.client.send_text(&json).await
    }

    /// Parse Kraken orderbook message (WebSocket API v2)
    ///
    /// v2 sends JSON objects: {"channel": "book", "type": "snapshot"|"update", "data": [...]}
    pub fn parse_orderbook(text: &str) -> Result<OrderBook, ExchangeError> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        // v2 messages are JSON objects with channel field
        let channel = msg["channel"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing channel field".into()))?;

        if channel != "book" {
            return Err(ExchangeError::Other("Not a book message".into()));
        }

        // Extract data array
        let data_arr = msg["data"]
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Missing data array".into()))?;

        if data_arr.is_empty() {
            return Err(ExchangeError::Other("Empty data array".into()));
        }

        let data = &data_arr[0];

        let symbol = data["symbol"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing symbol in data".into()))?;

        let parse_level = |level: &serde_json::Value| -> Result<PriceLevel, ExchangeError> {
            let price = level["price"]
                .as_f64()
                .ok_or_else(|| ExchangeError::Other("Invalid price".into()))?;
            let qty = level["qty"]
                .as_f64()
                .ok_or_else(|| ExchangeError::Other("Invalid qty".into()))?;

            Ok(PriceLevel {
                price,
                quantity: qty,
            })
        };

        let bids = if let Some(b) = data["bids"].as_array() {
            b.iter().map(parse_level).collect::<Result<Vec<_>, _>>()?
        } else {
            vec![]
        };

        let asks = if let Some(a) = data["asks"].as_array() {
            a.iter().map(parse_level).collect::<Result<Vec<_>, _>>()?
        } else {
            vec![]
        };

        Ok(OrderBook {
            pair: symbol.to_string(),
            exchange: "kraken".to_string(),
            bids,
            asks,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    /// Parse Kraken trade message (WebSocket API v2)
    ///
    /// v2 sends JSON objects: {"channel": "trade", "type": "update", "data": [...]}
    pub fn parse_trade(text: &str) -> Result<Trade, ExchangeError> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        let channel = msg["channel"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing channel field".into()))?;

        if channel != "trade" {
            return Err(ExchangeError::Other("Not a trade message".into()));
        }

        let data_arr = msg["data"]
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Missing data array".into()))?;

        if data_arr.is_empty() {
            return Err(ExchangeError::Other("Empty data array".into()));
        }

        // Parse first trade from data array
        let trade_data = &data_arr[0];

        let symbol = trade_data["symbol"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing symbol".into()))?;

        let price = trade_data["price"]
            .as_f64()
            .ok_or_else(|| ExchangeError::Other("Invalid price".into()))?;

        let qty = trade_data["qty"]
            .as_f64()
            .ok_or_else(|| ExchangeError::Other("Invalid qty".into()))?;

        let side_str = trade_data["side"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Invalid side".into()))?;

        let side = if side_str == "buy" {
            Side::Buy
        } else {
            Side::Sell
        };

        // v2 uses RFC3339 timestamp strings
        let timestamp_str = trade_data["timestamp"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Invalid timestamp".into()))?;

        let timestamp = chrono::DateTime::parse_from_rfc3339(timestamp_str)
            .map_err(|e| ExchangeError::Other(format!("Failed to parse timestamp: {}", e)))?
            .with_timezone(&Utc);

        // Use trade_id if available, otherwise construct from timestamp
        let trade_id = if let Some(id) = trade_data["trade_id"].as_u64() {
            id.to_string()
        } else {
            format!("{}_{}", symbol, timestamp.timestamp_millis())
        };

        Ok(Trade {
            id: trade_id,
            pair: symbol.to_string(),
            exchange: "kraken".to_string(),
            price,
            quantity: qty,
            side,
            timestamp,
            is_maker: None,
        })
    }
}

// Kraken WebSocket v2 message types
#[derive(Debug, Serialize)]
struct KrakenSubscribeV2 {
    method: String,
    params: KrakenSubscriptionParams,
}

#[derive(Debug, Serialize)]
struct KrakenSubscriptionParams {
    channel: String,
    symbol: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    depth: Option<u32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_orderbook_v2() {
        let json = r#"{
            "channel": "book",
            "type": "snapshot",
            "data": [{
                "symbol": "BTC/USD",
                "bids": [{"price": 50000.0, "qty": 0.5}],
                "asks": [{"price": 50001.0, "qty": 0.3}]
            }]
        }"#;

        let orderbook = KrakenFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.pair, "BTC/USD");
        assert_eq!(orderbook.exchange, "kraken");
        assert_eq!(orderbook.bids.len(), 1);
        assert_eq!(orderbook.asks.len(), 1);
        assert_eq!(orderbook.bids[0].price, 50000.0);
        assert_eq!(orderbook.bids[0].quantity, 0.5);
    }

    #[test]
    fn test_parse_trade_v2() {
        let json = r#"{
            "channel": "trade",
            "type": "update",
            "data": [{
                "symbol": "BTC/USD",
                "price": 50000.0,
                "qty": 0.1,
                "side": "buy",
                "timestamp": "2024-04-25T12:00:00.000Z"
            }]
        }"#;

        let trade = KrakenFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "BTC/USD");
        assert_eq!(trade.exchange, "kraken");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.1);
        assert_eq!(trade.side, Side::Buy);
    }
}
