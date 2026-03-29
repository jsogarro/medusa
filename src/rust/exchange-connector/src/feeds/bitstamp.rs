//! Bitstamp WebSocket feed implementation
//!
//! WebSocket documentation: https://www.bitstamp.net/websocket/v2/

use crate::client::ExchangeError;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const BITSTAMP_WS_URL: &str = "wss://ws.bitstamp.net";

/// Bitstamp WebSocket feed
pub struct BitstampFeed {
    client: WebSocketClient,
}

impl BitstampFeed {
    /// Create a new Bitstamp WebSocket feed
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let config = WsConfig {
            url: BITSTAMP_WS_URL.to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (client, rx) = WebSocketClient::connect(config).await?;

        Ok((Self { client }, rx))
    }

    /// Subscribe to orderbook for a trading pair
    ///
    /// # Security
    /// Validates pair contains only alphanumeric characters to prevent injection.
    ///
    /// # Example
    /// ```no_run
    /// # use exchange_connector::feeds::BitstampFeed;
    /// # async fn example() {
    /// let (feed, mut rx) = BitstampFeed::new().await.unwrap();
    /// feed.subscribe_orderbook("btcusd").await.unwrap();
    /// # }
    /// ```
    pub async fn subscribe_orderbook(&self, pair: &str) -> Result<(), ExchangeError> {
        // Security: Validate pair format to prevent injection
        if !pair.chars().all(|c| c.is_alphanumeric()) {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters".into()
            ));
        }
        let channel = format!("order_book_{}", pair.to_lowercase());
        self.subscribe(&channel).await
    }

    /// Subscribe to trades for a trading pair
    ///
    /// # Security
    /// Validates pair format before subscription.
    pub async fn subscribe_trades(&self, pair: &str) -> Result<(), ExchangeError> {
        // Security: Validate pair format
        if !pair.chars().all(|c| c.is_alphanumeric()) {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters".into()
            ));
        }
        let channel = format!("live_trades_{}", pair.to_lowercase());
        self.subscribe(&channel).await
    }

    /// Subscribe to a channel
    async fn subscribe(&self, channel: &str) -> Result<(), ExchangeError> {
        let sub_msg = BitstampSubscribe {
            event: "bts:subscribe".to_string(),
            data: BitstampSubscribeData {
                channel: channel.to_string(),
            },
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Bitstamp channel: {}", channel);
        self.client.send_text(&json).await
    }

    /// Unsubscribe from a channel
    pub async fn unsubscribe(&self, channel: &str) -> Result<(), ExchangeError> {
        let unsub_msg = BitstampSubscribe {
            event: "bts:unsubscribe".to_string(),
            data: BitstampSubscribeData {
                channel: channel.to_string(),
            },
        };

        let json = serde_json::to_string(&unsub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Unsubscribing from Bitstamp channel: {}", channel);
        self.client.send_text(&json).await
    }

    /// Parse Bitstamp WebSocket message into OrderBook
    pub fn parse_orderbook(text: &str) -> Result<OrderBook, ExchangeError> {
        let msg: BitstampMessage = serde_json::from_str(text)?;

        if msg.event != "data" {
            return Err(ExchangeError::Other(format!(
                "Expected 'data' event, got '{}'",
                msg.event
            )));
        }

        // Extract pair from channel (e.g., "order_book_btcusd" -> "BTC/USD")
        let pair = msg
            .channel
            .strip_prefix("order_book_")
            .ok_or_else(|| ExchangeError::Other("Invalid orderbook channel".into()))?;
        let normalized_pair = format!(
            "{}/{}",
            &pair[..3].to_uppercase(),
            &pair[3..].to_uppercase()
        );

        let data: BitstampOrderBookData = serde_json::from_value(msg.data)
            .map_err(|e| ExchangeError::Other(format!("Failed to parse orderbook data: {}", e)))?;

        // Parse timestamp
        let timestamp = data
            .timestamp
            .parse::<i64>()
            .ok()
            .and_then(|ts| DateTime::from_timestamp(ts, 0))
            .unwrap_or_else(Utc::now);

        // Parse price levels
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

        let bids: Result<Vec<_>, _> = data.bids.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = data.asks.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair: normalized_pair,
            exchange: "bitstamp".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp,
            sequence: None,
        })
    }

    /// Parse Bitstamp WebSocket message into Trade
    pub fn parse_trade(text: &str) -> Result<Trade, ExchangeError> {
        let msg: BitstampMessage = serde_json::from_str(text)?;

        if msg.event != "trade" {
            return Err(ExchangeError::Other(format!(
                "Expected 'trade' event, got '{}'",
                msg.event
            )));
        }

        // Extract pair from channel
        let pair = msg
            .channel
            .strip_prefix("live_trades_")
            .ok_or_else(|| ExchangeError::Other("Invalid trades channel".into()))?;
        let normalized_pair = format!(
            "{}/{}",
            &pair[..3].to_uppercase(),
            &pair[3..].to_uppercase()
        );

        let data: BitstampTradeData = serde_json::from_value(msg.data)
            .map_err(|e| ExchangeError::Other(format!("Failed to parse trade data: {}", e)))?;

        let timestamp = DateTime::from_timestamp(data.timestamp, 0).unwrap_or_else(Utc::now);

        // Bitstamp trade type: 0 = buy, 1 = sell
        let side = if data.trade_type == 0 {
            Side::Buy
        } else {
            Side::Sell
        };

        Ok(Trade {
            id: data.id.to_string(),
            pair: normalized_pair,
            exchange: "bitstamp".to_string(),
            price: data.price,
            quantity: data.amount,
            side,
            timestamp,
            is_maker: None,
        })
    }
}

// Bitstamp WebSocket message types
#[derive(Debug, Serialize, Deserialize)]
struct BitstampSubscribe {
    event: String,
    data: BitstampSubscribeData,
}

#[derive(Debug, Serialize, Deserialize)]
struct BitstampSubscribeData {
    channel: String,
}

#[derive(Debug, Deserialize)]
struct BitstampMessage {
    event: String,
    channel: String,
    data: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct BitstampOrderBookData {
    timestamp: String,
    bids: Vec<Vec<String>>,
    asks: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct BitstampTradeData {
    id: u64,
    timestamp: i64,
    amount: f64,
    price: f64,
    #[serde(rename = "type")]
    trade_type: u8, // 0 = buy, 1 = sell
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_orderbook() {
        let json = r#"{
            "event": "data",
            "channel": "order_book_btcusd",
            "data": {
                "timestamp": "1640000000",
                "bids": [["50000.00", "0.5"], ["49999.00", "1.0"]],
                "asks": [["50001.00", "0.3"], ["50002.00", "0.8"]]
            }
        }"#;

        let orderbook = BitstampFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.pair, "BTC/USD");
        assert_eq!(orderbook.exchange, "bitstamp");
        assert_eq!(orderbook.bids.len(), 2);
        assert_eq!(orderbook.asks.len(), 2);
        assert_eq!(orderbook.bids[0].price, 50000.00);
        assert_eq!(orderbook.bids[0].quantity, 0.5);
    }

    #[test]
    fn test_parse_trade() {
        let json = r#"{
            "event": "trade",
            "channel": "live_trades_btcusd",
            "data": {
                "id": 12345,
                "timestamp": 1640000000,
                "amount": 0.1,
                "price": 50000.00,
                "type": 0
            }
        }"#;

        let trade = BitstampFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "BTC/USD");
        assert_eq!(trade.exchange, "bitstamp");
        assert_eq!(trade.price, 50000.00);
        assert_eq!(trade.quantity, 0.1);
        assert_eq!(trade.side, Side::Buy);
    }
}
