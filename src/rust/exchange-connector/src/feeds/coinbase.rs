//! Coinbase WebSocket feed implementation
//!
//! Supports both Exchange API (legacy) and Advanced Trade API WebSocket feeds.
//! - Exchange API: wss://ws-feed.exchange.coinbase.com
//! - Advanced Trade: wss://advanced-trade-ws.coinbase.com

use crate::client::{parse_side, ExchangeError};
use crate::feeds::check_trade;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const LEGACY_WS_URL: &str = "wss://ws-feed.exchange.coinbase.com";
const ADVANCED_WS_URL: &str = "wss://advanced-trade-ws.coinbase.com";

/// Coinbase WebSocket feed
pub struct CoinbaseFeed {
    client: WebSocketClient,
    use_advanced: bool,
}

impl CoinbaseFeed {
    /// Create a new Coinbase WebSocket feed
    ///
    /// # Environment Variables
    /// * `COINBASE_USE_ADVANCED_TRADE` - Set to "true" for Advanced Trade API (default: true)
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let use_advanced = std::env::var("COINBASE_USE_ADVANCED_TRADE")
            .unwrap_or_else(|_| "true".to_string())
            == "true";

        let url = if use_advanced {
            ADVANCED_WS_URL
        } else {
            LEGACY_WS_URL
        };

        let config = WsConfig {
            url: url.to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (client, rx) = WebSocketClient::connect(config).await?;

        Ok((
            Self {
                client,
                use_advanced,
            },
            rx,
        ))
    }

    /// Subscribe to level2 orderbook for a product
    ///
    /// # Security
    /// Validates product_id format to prevent injection attacks.
    pub async fn subscribe_orderbook(&self, product_id: &str) -> Result<(), ExchangeError> {
        // Security: Validate product_id format (e.g., "BTC-USD")
        if !product_id.chars().all(|c| c.is_alphanumeric() || c == '-') {
            return Err(ExchangeError::InvalidRequest(
                "Product ID must contain only alphanumeric characters and hyphens".into(),
            ));
        }

        let json = if self.use_advanced {
            serde_json::to_string(&CoinbaseAdvancedSubscribe {
                r#type: "subscribe".to_string(),
                product_ids: vec![product_id.to_uppercase()],
                channel: "level2".to_string(),
            })
        } else {
            serde_json::to_string(&CoinbaseLegacySubscribe {
                r#type: "subscribe".to_string(),
                product_ids: vec![product_id.to_uppercase()],
                channels: vec!["level2".to_string()],
            })
        }
        .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!(
            "Subscribing to Coinbase level2 for: {} (advanced: {})",
            product_id, self.use_advanced
        );
        self.client.send_text(&json).await
    }

    /// Subscribe to trades for a product
    ///
    /// # Security
    /// Validates product_id format.
    ///
    /// # Notes
    /// - Legacy API: uses "matches" channel
    /// - Advanced Trade: uses "market_trades" channel
    pub async fn subscribe_trades(&self, product_id: &str) -> Result<(), ExchangeError> {
        // Security: Validate product_id format
        if !product_id.chars().all(|c| c.is_alphanumeric() || c == '-') {
            return Err(ExchangeError::InvalidRequest(
                "Product ID must contain only alphanumeric characters and hyphens".into(),
            ));
        }

        let channel = if self.use_advanced {
            "market_trades"
        } else {
            "matches"
        };

        let json = if self.use_advanced {
            serde_json::to_string(&CoinbaseAdvancedSubscribe {
                r#type: "subscribe".to_string(),
                product_ids: vec![product_id.to_uppercase()],
                channel: channel.to_string(),
            })
        } else {
            serde_json::to_string(&CoinbaseLegacySubscribe {
                r#type: "subscribe".to_string(),
                product_ids: vec![product_id.to_uppercase()],
                channels: vec![channel.to_string()],
            })
        }
        .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Coinbase {} for: {}", channel, product_id);
        self.client.send_text(&json).await
    }

    /// Parse Coinbase level2 snapshot/update into OrderBook
    ///
    /// Handles both Legacy and Advanced Trade message formats.
    pub fn parse_orderbook(text: &str, use_advanced: bool) -> Result<OrderBook, ExchangeError> {
        if use_advanced {
            // Try Advanced Trade format first
            if let Ok(msg) = serde_json::from_str::<AdvancedTradeMessage>(text) {
                if msg.channel != "level2" && msg.channel != "l2_data" {
                    return Err(ExchangeError::Other(format!(
                        "Expected level2/l2_data channel, got '{}'",
                        msg.channel
                    )));
                }

                if let Some(event) = msg.events.first() {
                    let product_id = event.product_id.as_ref().ok_or_else(|| {
                        ExchangeError::Other("Missing product_id in event".into())
                    })?;

                    let mut bids = Vec::new();
                    let mut asks = Vec::new();

                    for update in &event.updates {
                        let price: f64 = update.price_level.parse().map_err(|_| {
                            ExchangeError::Other(format!("Invalid price: {}", update.price_level))
                        })?;
                        let quantity: f64 = update.new_quantity.parse().map_err(|_| {
                            ExchangeError::Other(format!(
                                "Invalid quantity: {}",
                                update.new_quantity
                            ))
                        })?;

                        let level = PriceLevel { price, quantity };

                        if update.side.to_uppercase() == "BID" {
                            bids.push(level);
                        } else {
                            asks.push(level);
                        }
                    }

                    return Ok(OrderBook {
                        pair: product_id.replace('-', "/"),
                        exchange: "coinbase".to_string(),
                        bids,
                        asks,
                        timestamp: Utc::now(),
                        sequence: None,
                    });
                }
            }
        }

        // Legacy Exchange API format
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

    /// Parse Coinbase trade message
    ///
    /// Handles both Legacy (match) and Advanced Trade (market_trades) formats.
    pub fn parse_trade(text: &str, use_advanced: bool) -> Result<Trade, ExchangeError> {
        if use_advanced {
            // Try Advanced Trade format
            if let Ok(msg) = serde_json::from_str::<AdvancedTradeMessage>(text) {
                if msg.channel != "market_trades" {
                    return Err(ExchangeError::Other(format!(
                        "Expected market_trades channel, got '{}'",
                        msg.channel
                    )));
                }

                if let Some(event) = msg.events.first() {
                    if let Some(trade) = event.trades.first() {
                        let timestamp = parse_time(&trade.time)?;
                        let side = parse_side(&trade.side)?;

                        return check_trade(Trade {
                            id: trade.trade_id.clone(), // String in Advanced Trade
                            pair: trade.product_id.replace('-', "/"),
                            exchange: "coinbase".to_string(),
                            price: parse_num("price", &trade.price)?,
                            quantity: parse_num("size", &trade.size)?,
                            side,
                            timestamp,
                            is_maker: None, // Not provided in Advanced Trade
                        });
                    }
                }
            }
        }

        // Legacy Exchange API format
        let msg: CoinbaseMatchMessage = serde_json::from_str(text)?;

        if msg.r#type != "match" && msg.r#type != "last_match" {
            return Err(ExchangeError::Other(format!(
                "Expected match or last_match, got '{}'",
                msg.r#type
            )));
        }

        let timestamp = parse_time(&msg.time)?;
        let side = parse_side(&msg.side)?;

        check_trade(Trade {
            id: msg.trade_id.to_string(),
            pair: msg.product_id.replace('-', "/"),
            exchange: "coinbase".to_string(),
            price: parse_num("price", &msg.price)?,
            quantity: parse_num("size", &msg.size)?,
            side,
            timestamp,
            is_maker: Some(msg.maker_order_id.is_some()),
        })
    }
}

fn parse_num(name: &str, s: &str) -> Result<f64, ExchangeError> {
    s.parse()
        .map_err(|_| ExchangeError::Other(format!("Invalid trade {name}: {s}")))
}

fn parse_time(s: &str) -> Result<DateTime<Utc>, ExchangeError> {
    DateTime::parse_from_rfc3339(s)
        .map(|dt| dt.with_timezone(&Utc))
        .map_err(|e| ExchangeError::Other(format!("Invalid trade time '{s}': {e}")))
}

// Coinbase WebSocket message types (both Legacy and Advanced Trade)
#[derive(Debug, Serialize)]
struct CoinbaseLegacySubscribe {
    r#type: String,
    product_ids: Vec<String>,
    channels: Vec<String>,
}

#[derive(Debug, Serialize)]
struct CoinbaseAdvancedSubscribe {
    r#type: String,
    product_ids: Vec<String>,
    channel: String,
}

// Legacy Exchange API message types
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

// Advanced Trade API message types
#[derive(Debug, Deserialize)]
struct AdvancedTradeMessage {
    channel: String,
    #[serde(default)]
    events: Vec<AdvancedTradeEvent>,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeEvent {
    #[allow(dead_code)]
    r#type: String,
    #[serde(default)]
    product_id: Option<String>,
    #[serde(default)]
    updates: Vec<AdvancedTradeUpdate>,
    #[serde(default)]
    trades: Vec<AdvancedTradeTrade>,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeUpdate {
    side: String, // "BID" or "OFFER"
    price_level: String,
    new_quantity: String,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeTrade {
    trade_id: String, // String in Advanced Trade!
    product_id: String,
    price: String,
    size: String,
    side: String, // "BUY" or "SELL" (uppercase)
    time: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_orderbook_legacy() {
        let json = r#"{
            "type": "snapshot",
            "product_id": "BTC-USD",
            "bids": [["50000.00", "0.5"], ["49999.00", "1.0"]],
            "asks": [["50001.00", "0.3"], ["50002.00", "0.8"]]
        }"#;

        let orderbook = CoinbaseFeed::parse_orderbook(json, false).unwrap();
        assert_eq!(orderbook.pair, "BTC/USD");
        assert_eq!(orderbook.exchange, "coinbase");
        assert_eq!(orderbook.bids.len(), 2);
        assert_eq!(orderbook.asks.len(), 2);
    }

    #[test]
    fn test_parse_trade_legacy() {
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

        let trade = CoinbaseFeed::parse_trade(json, false).unwrap();
        assert_eq!(trade.pair, "BTC/USD");
        assert_eq!(trade.exchange, "coinbase");
        assert_eq!(trade.price, 50000.00);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_parse_trade_advanced() {
        let json = r#"{
            "channel": "market_trades",
            "events": [{
                "type": "update",
                "trades": [{
                    "trade_id": "12345",
                    "product_id": "BTC-USD",
                    "price": "50000.00",
                    "size": "0.1",
                    "side": "BUY",
                    "time": "2024-01-01T00:00:00.000000Z"
                }]
            }]
        }"#;

        let trade = CoinbaseFeed::parse_trade(json, true).unwrap();
        assert_eq!(trade.pair, "BTC/USD");
        assert_eq!(trade.exchange, "coinbase");
        assert_eq!(trade.price, 50000.00);
        assert_eq!(trade.side, Side::Buy);
        assert_eq!(trade.id, "12345");
    }

    #[test]
    fn test_parse_orderbook_advanced_l2_data() {
        let json = r#"{
            "channel": "l2_data",
            "sequence_num": 42,
            "events": [{
                "type": "snapshot",
                "product_id": "BTC-USD",
                "updates": [
                    {
                        "side": "bid",
                        "price_level": "50000.00",
                        "new_quantity": "0.5"
                    },
                    {
                        "side": "offer",
                        "price_level": "50001.00",
                        "new_quantity": "0.3"
                    }
                ]
            }]
        }"#;

        let orderbook = CoinbaseFeed::parse_orderbook(json, true).unwrap();
        assert_eq!(orderbook.pair, "BTC/USD");
        assert_eq!(orderbook.bids.len(), 1);
        assert_eq!(orderbook.asks.len(), 1);
        assert_eq!(orderbook.bids[0].price, 50000.0);
        assert_eq!(orderbook.asks[0].quantity, 0.3);
    }

    #[test]
    fn test_advanced_subscribe_serialization() {
        let json = serde_json::to_string(&CoinbaseAdvancedSubscribe {
            r#type: "subscribe".to_string(),
            product_ids: vec!["BTC-USD".to_string()],
            channel: "market_trades".to_string(),
        })
        .unwrap();
        let payload: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(payload["type"], "subscribe");
        assert_eq!(payload["channel"], "market_trades");
        assert_eq!(payload["product_ids"][0], "BTC-USD");
        assert!(payload.get("channels").is_none());
    }

    #[test]
    fn test_legacy_subscribe_serialization() {
        let json = serde_json::to_string(&CoinbaseLegacySubscribe {
            r#type: "subscribe".to_string(),
            product_ids: vec!["BTC-USD".to_string()],
            channels: vec!["matches".to_string()],
        })
        .unwrap();
        let payload: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(payload["type"], "subscribe");
        assert_eq!(payload["channels"][0], "matches");
        assert_eq!(payload["product_ids"][0], "BTC-USD");
        assert!(payload.get("channel").is_none());
    }

    fn legacy(side: &str, price: &str, size: &str, time: &str) -> String {
        format!(
            r#"{{"type":"match","trade_id":1,"product_id":"BTC-USD","side":"{side}","size":"{size}","price":"{price}","time":"{time}"}}"#
        )
    }

    fn advanced(side: &str, price: &str, size: &str, time: &str) -> String {
        format!(
            r#"{{"channel":"market_trades","events":[{{"type":"update","trades":[{{"trade_id":"1","product_id":"BTC-USD","price":"{price}","size":"{size}","side":"{side}","time":"{time}"}}]}}]}}"#
        )
    }

    #[test]
    fn parse_trade_rejects_malformed_fields_on_both_formats() {
        let t = "2024-01-01T00:00:00.000000Z";
        assert!(CoinbaseFeed::parse_trade(&legacy("sell", "50000", "0.1", t), false).is_ok());
        assert!(CoinbaseFeed::parse_trade(&advanced("SELL", "50000", "0.1", t), true).is_ok());
        for (side, price, size, time) in [
            ("buy", "abc", "0.1", t),
            ("buy", "50000", "xyz", t),
            ("buy", "0", "0.1", t),
            ("buy", "50000", "0", t),
            ("buy", "NaN", "0.1", t),
            ("hold", "50000", "0.1", t),
            ("buy", "50000", "0.1", "yesterday"),
        ] {
            assert!(
                CoinbaseFeed::parse_trade(&legacy(side, price, size, time), false).is_err(),
                "legacy {side} {price} {size} {time}"
            );
            assert!(
                CoinbaseFeed::parse_trade(&advanced(side, price, size, time), true).is_err(),
                "advanced {side} {price} {size} {time}"
            );
        }
    }
}
