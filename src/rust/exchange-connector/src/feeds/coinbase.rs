//! Coinbase WebSocket feed implementation
//!
//! WebSocket documentation: https://docs.cloud.coinbase.com/exchange/docs/websocket-overview

use crate::client::ExchangeError;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const COINBASE_WS_URL: &str = "wss://ws-feed.exchange.coinbase.com";

/// Coinbase WebSocket feed
pub struct CoinbaseFeed {
    client: WebSocketClient,
}

impl CoinbaseFeed {
    /// Create a new Coinbase WebSocket feed
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let config = WsConfig {
            url: COINBASE_WS_URL.to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (client, rx) = WebSocketClient::connect(config).await?;

        Ok((Self { client }, rx))
    }

    /// Subscribe to level2 orderbook for a product
    ///
    /// # Security
    /// Validates product_id format to prevent injection attacks.
    pub async fn subscribe_orderbook(&self, product_id: &str) -> Result<(), ExchangeError> {
        // Security: Validate product_id format (e.g., "BTC-USD")
        if !product_id.chars().all(|c| c.is_alphanumeric() || c == '-') {
            return Err(ExchangeError::InvalidRequest(
                "Product ID must contain only alphanumeric characters and hyphens".into()
            ));
        }

        let sub_msg = CoinbaseSubscribe {
            r#type: "subscribe".to_string(),
            product_ids: vec![product_id.to_uppercase()],
            channels: vec!["level2".to_string()],
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Coinbase level2 for: {}", product_id);
        self.client.send_text(&json).await
    }

    /// Subscribe to trades (matches channel) for a product
    ///
    /// # Security
    /// Validates product_id format.
    pub async fn subscribe_trades(&self, product_id: &str) -> Result<(), ExchangeError> {
        // Security: Validate product_id format
        if !product_id.chars().all(|c| c.is_alphanumeric() || c == '-') {
            return Err(ExchangeError::InvalidRequest(
                "Product ID must contain only alphanumeric characters and hyphens".into()
            ));
        }

        let sub_msg = CoinbaseSubscribe {
            r#type: "subscribe".to_string(),
            product_ids: vec![product_id.to_uppercase()],
            channels: vec!["matches".to_string()],
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Coinbase matches for: {}", product_id);
        self.client.send_text(&json).await
    }

    /// Parse Coinbase level2 snapshot into OrderBook
    pub fn parse_orderbook(text: &str) -> Result<OrderBook, ExchangeError> {
        let msg: CoinbaseLevel2Message = serde_json::from_str(text)?;

        if msg.r#type != "snapshot" && msg.r#type != "l2update" {
            return Err(ExchangeError::Other(format!(
                "Expected snapshot or l2update, got '{}'",
                msg.r#type
            )));
        }

        let parse_level = |level: &[String]| -> Result<PriceLevel, ExchangeError> {
            if level.len() < 2 {
                return Err(ExchangeError::Other("Invalid price level format".into()));
            }
            Ok(PriceLevel {
                price: level[0]
                    .parse()
                    .map_err(|_| ExchangeError::Other(format!("Invalid price: {}", level[0])))?,
                quantity: level[1]
                    .parse()
                    .map_err(|_| ExchangeError::Other(format!("Invalid quantity: {}", level[1])))?,
            })
        };

        let bids: Result<Vec<_>, _> = msg.bids.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = msg.asks.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair: msg.product_id.replace('-', "/"),
            exchange: "coinbase".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    /// Parse Coinbase match message into Trade
    pub fn parse_trade(text: &str) -> Result<Trade, ExchangeError> {
        let msg: CoinbaseMatchMessage = serde_json::from_str(text)?;

        if msg.r#type != "match" && msg.r#type != "last_match" {
            return Err(ExchangeError::Other(format!(
                "Expected match or last_match, got '{}'",
                msg.r#type
            )));
        }

        let timestamp = DateTime::parse_from_rfc3339(&msg.time)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        let side = if msg.side == "buy" {
            Side::Buy
        } else {
            Side::Sell
        };

        Ok(Trade {
            id: msg.trade_id.to_string(),
            pair: msg.product_id.replace('-', "/"),
            exchange: "coinbase".to_string(),
            price: msg.price.parse().unwrap_or(0.0),
            quantity: msg.size.parse().unwrap_or(0.0),
            side,
            timestamp,
            is_maker: Some(msg.maker_order_id.is_some()),
        })
    }
}

// Coinbase WebSocket message types
#[derive(Debug, Serialize)]
struct CoinbaseSubscribe {
    r#type: String,
    product_ids: Vec<String>,
    channels: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseLevel2Message {
    r#type: String,
    product_id: String,
    bids: Vec<Vec<String>>,
    asks: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseMatchMessage {
    r#type: String,
    trade_id: u64,
    product_id: String,
    side: String,
    size: String,
    price: String,
    time: String,
    maker_order_id: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_orderbook() {
        let json = r#"{
            "type": "snapshot",
            "product_id": "BTC-USD",
            "bids": [["50000.00", "0.5"], ["49999.00", "1.0"]],
            "asks": [["50001.00", "0.3"], ["50002.00", "0.8"]]
        }"#;

        let orderbook = CoinbaseFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.pair, "BTC/USD");
        assert_eq!(orderbook.exchange, "coinbase");
        assert_eq!(orderbook.bids.len(), 2);
        assert_eq!(orderbook.asks.len(), 2);
    }

    #[test]
    fn test_parse_trade() {
        let json = r#"{
            "type": "match",
            "trade_id": 12345,
            "product_id": "BTC-USD",
            "side": "buy",
            "size": "0.1",
            "price": "50000.00",
            "time": "2024-01-01T00:00:00.000000Z",
            "maker_order_id": "abc123"
        }"#;

        let trade = CoinbaseFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "BTC/USD");
        assert_eq!(trade.exchange, "coinbase");
        assert_eq!(trade.price, 50000.00);
        assert_eq!(trade.side, Side::Buy);
    }
}
