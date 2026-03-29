//! Kraken WebSocket feed implementation
//!
//! WebSocket documentation: https://docs.kraken.com/websockets/

use crate::client::ExchangeError;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const KRAKEN_WS_URL: &str = "wss://ws.kraken.com";

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
                "Pair must contain only alphanumeric characters and slashes".into()
            ));
        }

        let sub_msg = KrakenSubscribe {
            event: "subscribe".to_string(),
            pair: vec![pair.to_uppercase()],
            subscription: KrakenSubscription {
                name: "book".to_string(),
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
                "Pair must contain only alphanumeric characters and slashes".into()
            ));
        }

        let sub_msg = KrakenSubscribe {
            event: "subscribe".to_string(),
            pair: vec![pair.to_uppercase()],
            subscription: KrakenSubscription {
                name: "trade".to_string(),
                depth: None,
            },
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Kraken trade for: {}", pair);
        self.client.send_text(&json).await
    }

    /// Parse Kraken orderbook message
    ///
    /// Kraken sends orderbook updates as arrays: [channelID, data, channelName, pair]
    pub fn parse_orderbook(text: &str) -> Result<OrderBook, ExchangeError> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        // Kraken book messages are arrays
        let arr = msg
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Expected array message".into()))?;

        if arr.len() < 4 {
            return Err(ExchangeError::Other("Invalid orderbook message format".into()));
        }

        // Extract pair from last element
        let pair = arr[3]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing pair in message".into()))?;

        // Data is in second element
        let data = &arr[1];
        let book_data: KrakenBookData = serde_json::from_value(data.clone())?;

        let parse_level = |level: &[serde_json::Value]| -> Result<PriceLevel, ExchangeError> {
            if level.len() < 2 {
                return Err(ExchangeError::Other("Invalid price level format".into()));
            }
            Ok(PriceLevel {
                price: level[0]
                    .as_str()
                    .and_then(|s| s.parse().ok())
                    .ok_or_else(|| ExchangeError::Other("Invalid price".into()))?,
                quantity: level[1]
                    .as_str()
                    .and_then(|s| s.parse().ok())
                    .ok_or_else(|| ExchangeError::Other("Invalid quantity".into()))?,
            })
        };

        let bids = if let Some(b) = &book_data.b {
            b.iter().map(|l| parse_level(l)).collect::<Result<Vec<_>, _>>()?
        } else {
            vec![]
        };

        let asks = if let Some(a) = &book_data.a {
            a.iter().map(|l| parse_level(l)).collect::<Result<Vec<_>, _>>()?
        } else {
            vec![]
        };

        Ok(OrderBook {
            pair: pair.to_string(),
            exchange: "kraken".to_string(),
            bids,
            asks,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    /// Parse Kraken trade message
    pub fn parse_trade(text: &str) -> Result<Trade, ExchangeError> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        let arr = msg
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Expected array message".into()))?;

        if arr.len() < 4 {
            return Err(ExchangeError::Other("Invalid trade message format".into()));
        }

        let pair = arr[3]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing pair in message".into()))?;

        let trades_data = arr[1]
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Expected trades array".into()))?;

        if trades_data.is_empty() {
            return Err(ExchangeError::Other("Empty trades array".into()));
        }

        // Parse first trade
        let trade_arr = trades_data[0]
            .as_array()
            .ok_or_else(|| ExchangeError::Other("Invalid trade format".into()))?;

        if trade_arr.len() < 6 {
            return Err(ExchangeError::Other("Incomplete trade data".into()));
        }

        let price: f64 = trade_arr[0]
            .as_str()
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| ExchangeError::Other("Invalid price".into()))?;

        let quantity: f64 = trade_arr[1]
            .as_str()
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| ExchangeError::Other("Invalid quantity".into()))?;

        let timestamp_f64 = trade_arr[2]
            .as_f64()
            .ok_or_else(|| ExchangeError::Other("Invalid timestamp".into()))?;

        let side_str = trade_arr[3]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Invalid side".into()))?;

        let side = if side_str == "b" { Side::Buy } else { Side::Sell };

        let timestamp = DateTime::from_timestamp(timestamp_f64 as i64, 0).unwrap_or_else(Utc::now);

        Ok(Trade {
            id: format!("{}_{}", pair, timestamp_f64),
            pair: pair.to_string(),
            exchange: "kraken".to_string(),
            price,
            quantity,
            side,
            timestamp,
            is_maker: None,
        })
    }
}

// Kraken WebSocket message types
#[derive(Debug, Serialize)]
struct KrakenSubscribe {
    event: String,
    pair: Vec<String>,
    subscription: KrakenSubscription,
}

#[derive(Debug, Serialize)]
struct KrakenSubscription {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    depth: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct KrakenBookData {
    #[serde(rename = "b")]
    b: Option<Vec<Vec<serde_json::Value>>>, // bids
    #[serde(rename = "a")]
    a: Option<Vec<Vec<serde_json::Value>>>, // asks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_orderbook() {
        let json = r#"[
            0,
            {
                "b": [["50000.00", "0.5", "1640000000.123"]],
                "a": [["50001.00", "0.3", "1640000000.124"]]
            },
            "book-10",
            "XBT/USD"
        ]"#;

        let orderbook = KrakenFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.pair, "XBT/USD");
        assert_eq!(orderbook.exchange, "kraken");
        assert_eq!(orderbook.bids.len(), 1);
        assert_eq!(orderbook.asks.len(), 1);
    }

    #[test]
    fn test_parse_trade() {
        let json = r#"[
            0,
            [
                ["50000.00", "0.1", 1640000000.123, "b", "m", ""]
            ],
            "trade",
            "XBT/USD"
        ]"#;

        let trade = KrakenFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "XBT/USD");
        assert_eq!(trade.exchange, "kraken");
        assert_eq!(trade.price, 50000.00);
        assert_eq!(trade.side, Side::Buy);
    }
}
