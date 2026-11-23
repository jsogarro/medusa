//! Binance WebSocket feed implementation
//!
//! WebSocket documentation: https://binance-docs.github.io/apidocs/spot/en/#websocket-market-streams

use crate::client::ExchangeError;
use crate::feeds::check_trade;
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use crate::websocket::{ReconnectConfig, WebSocketClient, WsConfig, WsMessage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;

const BINANCE_WS_URL: &str = "wss://stream.binance.com:9443/ws";

/// Binance WebSocket feed
pub struct BinanceFeed {
    client: WebSocketClient,
}

impl BinanceFeed {
    /// Create a new Binance WebSocket feed
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let config = WsConfig {
            url: BINANCE_WS_URL.to_string(),
            heartbeat_interval: Duration::from_secs(60), // Binance sends ping every 3 minutes
            reconnect_config: ReconnectConfig::default(),
        };

        let (client, rx) = WebSocketClient::connect(config).await?;

        Ok((Self { client }, rx))
    }

    /// Subscribe to trades for a trading pair
    ///
    /// # Security
    /// Validates pair format to prevent injection.
    pub async fn subscribe_trades(&self, pair: &str) -> Result<(), ExchangeError> {
        // Security: Validate pair format
        if !pair.chars().all(|c| c.is_alphanumeric() || c == '/') {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters and slashes".into(),
            ));
        }

        // Binance expects lowercase symbol with no separator (btcusdt)
        let symbol = pair.replace('/', "").replace("USD", "USDT").to_lowercase();

        let sub_msg = BinanceSubscribe {
            method: "SUBSCRIBE".to_string(),
            params: vec![format!("{}@trade", symbol)],
            id: 1,
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Binance trades for: {}", pair);
        self.client.send_text(&json).await
    }

    /// Subscribe to orderbook depth updates for a trading pair
    ///
    /// # Arguments
    /// * `pair` - Trading pair (e.g., "BTC/USDT")
    /// * `update_speed` - Update speed: "100ms" or "1000ms" (default: "100ms")
    ///
    /// # Security
    /// Validates pair format.
    pub async fn subscribe_orderbook(
        &self,
        pair: &str,
        update_speed: Option<&str>,
    ) -> Result<(), ExchangeError> {
        // Security: Validate pair format
        if !pair.chars().all(|c| c.is_alphanumeric() || c == '/') {
            return Err(ExchangeError::InvalidRequest(
                "Pair must contain only alphanumeric characters and slashes".into(),
            ));
        }

        let symbol = pair.replace('/', "").replace("USD", "USDT").to_lowercase();

        let speed = update_speed.unwrap_or("100ms");
        let stream = format!("{}@depth@{}", symbol, speed);

        let sub_msg = BinanceSubscribe {
            method: "SUBSCRIBE".to_string(),
            params: vec![stream],
            id: 2,
        };

        let json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("JSON serialization error: {}", e)))?;

        debug!("Subscribing to Binance orderbook for: {}", pair);
        self.client.send_text(&json).await
    }

    /// Parse Binance trade message
    pub fn parse_trade(text: &str) -> Result<Trade, ExchangeError> {
        let msg: BinanceTradeMessage = serde_json::from_str(text)?;

        // Binance sends millisecond timestamps
        let timestamp =
            DateTime::from_timestamp_millis(msg.trade_time as i64).unwrap_or_else(Utc::now);

        // Denormalize symbol (BTCUSDT -> BTC/USDT)
        let pair = Self::denormalize_pair(&msg.s);

        // Side: true = buyer is maker (sell), false = seller is maker (buy)
        let side = if msg.m { Side::Sell } else { Side::Buy };

        let price: f64 = msg
            .p
            .parse()
            .map_err(|_| ExchangeError::Other(format!("Invalid price: {}", msg.p)))?;

        let quantity: f64 = msg
            .q
            .parse()
            .map_err(|_| ExchangeError::Other(format!("Invalid quantity: {}", msg.q)))?;

        check_trade(Trade {
            id: msg.t.to_string(),
            pair,
            exchange: "binance".to_string(),
            price,
            quantity,
            side,
            timestamp,
            is_maker: Some(msg.m),
        })
    }

    /// Parse Binance orderbook depth update message
    pub fn parse_orderbook(text: &str) -> Result<OrderBook, ExchangeError> {
        let msg: BinanceDepthMessage = serde_json::from_str(text)?;

        let pair = Self::denormalize_pair(&msg.s);

        let parse_level = |level: &[String]| -> Result<PriceLevel, ExchangeError> {
            if level.len() < 2 {
                return Err(ExchangeError::Other("Invalid price level format".into()));
            }

            let price: f64 = level[0]
                .parse()
                .map_err(|_| ExchangeError::Other(format!("Invalid price: {}", level[0])))?;

            let quantity: f64 = level[1]
                .parse()
                .map_err(|_| ExchangeError::Other(format!("Invalid quantity: {}", level[1])))?;

            Ok(PriceLevel { price, quantity })
        };

        let bids: Result<Vec<_>, _> = msg.b.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = msg.a.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair,
            exchange: "binance".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: Some(msg.u),
        })
    }

    /// Denormalize pair format (e.g., "BTCUSDT" -> "BTC/USDT")
    fn denormalize_pair(pair: &str) -> String {
        // Simple heuristic: if ends with USDT, split before it
        if let Some(base) = pair.strip_suffix("USDT") {
            format!("{}/USDT", base.to_uppercase())
        } else if let Some(base) = pair.strip_suffix("BTC") {
            format!("{}/BTC", base.to_uppercase())
        } else if let Some(base) = pair.strip_suffix("ETH") {
            format!("{}/ETH", base.to_uppercase())
        } else if let Some(base) = pair.strip_suffix("BNB") {
            format!("{}/BNB", base.to_uppercase())
        } else {
            // Fallback: assume first 3 chars are base, rest is quote
            if pair.len() > 3 {
                let (base, quote) = pair.split_at(3);
                format!("{}/{}", base.to_uppercase(), quote.to_uppercase())
            } else {
                pair.to_uppercase()
            }
        }
    }
}

// Binance WebSocket message types
#[derive(Debug, Serialize)]
struct BinanceSubscribe {
    method: String,
    params: Vec<String>,
    id: u32,
}

#[derive(Debug, Deserialize)]
struct BinanceTradeMessage {
    #[serde(rename = "e")]
    _event: String, // "trade"
    #[serde(rename = "E")]
    _event_time: u64, // Event time (ms)
    #[serde(rename = "s")]
    s: String, // Symbol (BTCUSDT)
    #[serde(rename = "t")]
    t: u64, // Trade ID
    #[serde(rename = "p")]
    p: String, // Price
    #[serde(rename = "q")]
    q: String, // Quantity
    #[serde(rename = "T")]
    trade_time: u64, // Trade time (ms)
    #[serde(rename = "m")]
    m: bool, // Is buyer maker?
}

#[derive(Debug, Deserialize)]
struct BinanceDepthMessage {
    #[serde(rename = "e")]
    _event: String, // "depthUpdate"
    #[serde(rename = "E")]
    _event_time: u64, // Event time (ms)
    #[serde(rename = "s")]
    s: String, // Symbol
    #[serde(rename = "U")]
    _first_update_id: u64, // First update ID in event
    #[serde(rename = "u")]
    u: u64, // Final update ID in event
    #[serde(rename = "b")]
    b: Vec<Vec<String>>, // Bids [price, quantity]
    #[serde(rename = "a")]
    a: Vec<Vec<String>>, // Asks [price, quantity]
}

#[cfg(test)]
mod tests {
    use super::*;

    // === Pair Denormalization Tests ===

    #[test]
    fn test_denormalize_pair_usdt() {
        assert_eq!(BinanceFeed::denormalize_pair("BTCUSDT"), "BTC/USDT");
        assert_eq!(BinanceFeed::denormalize_pair("ETHUSDT"), "ETH/USDT");
        assert_eq!(BinanceFeed::denormalize_pair("SOLUSDT"), "SOL/USDT");
    }

    #[test]
    fn test_denormalize_pair_btc_quote() {
        assert_eq!(BinanceFeed::denormalize_pair("ETHBTC"), "ETH/BTC");
    }

    #[test]
    fn test_denormalize_pair_fallback() {
        // Fallback: first 3 chars = base, rest = quote
        assert_eq!(BinanceFeed::denormalize_pair("XYZABC"), "XYZ/ABC");
    }

    // === Trade Message Parsing Tests ===

    #[test]
    fn test_parse_trade_message() {
        let json = r#"{
            "e": "trade",
            "E": 1640000000123,
            "s": "BTCUSDT",
            "t": 12345,
            "p": "67000.00",
            "q": "0.1",
            "T": 1640000000000,
            "m": false
        }"#;

        let trade = BinanceFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "BTC/USDT");
        assert_eq!(trade.exchange, "binance");
        assert_eq!(trade.id, "12345");
        assert_eq!(trade.price, 67000.00);
        assert_eq!(trade.quantity, 0.1);
        assert_eq!(trade.side, Side::Buy); // m=false means taker is buyer
        assert_eq!(trade.is_maker, Some(false));
    }

    #[test]
    fn test_parse_trade_message_sell_side() {
        let json = r#"{
            "e": "trade",
            "E": 1640000000123,
            "s": "ETHUSDT",
            "t": 67890,
            "p": "3500.50",
            "q": "2.5",
            "T": 1640000000000,
            "m": true
        }"#;

        let trade = BinanceFeed::parse_trade(json).unwrap();
        assert_eq!(trade.pair, "ETH/USDT");
        assert_eq!(trade.side, Side::Sell); // m=true means taker is seller
        assert_eq!(trade.is_maker, Some(true));
    }

    #[test]
    fn test_parse_trade_invalid_price() {
        let json = r#"{
            "e": "trade",
            "E": 1640000000123,
            "s": "BTCUSDT",
            "t": 12345,
            "p": "not_a_number",
            "q": "0.1",
            "T": 1640000000000,
            "m": false
        }"#;

        let result = BinanceFeed::parse_trade(json);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ExchangeError::Other(_)));
    }

    // === Orderbook Message Parsing Tests ===

    #[test]
    fn test_parse_depth_message() {
        let json = r#"{
            "e": "depthUpdate",
            "E": 1640000000123,
            "s": "BTCUSDT",
            "U": 1,
            "u": 2,
            "b": [
                ["67000.00", "0.5"],
                ["66999.00", "1.0"]
            ],
            "a": [
                ["67001.00", "0.3"],
                ["67002.00", "0.7"]
            ]
        }"#;

        let orderbook = BinanceFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.pair, "BTC/USDT");
        assert_eq!(orderbook.exchange, "binance");
        assert_eq!(orderbook.bids.len(), 2);
        assert_eq!(orderbook.asks.len(), 2);
        assert_eq!(orderbook.bids[0].price, 67000.00);
        assert_eq!(orderbook.bids[0].quantity, 0.5);
        assert_eq!(orderbook.asks[0].price, 67001.00);
        assert_eq!(orderbook.sequence, Some(2));
    }

    #[test]
    fn test_parse_depth_message_empty_levels() {
        let json = r#"{
            "e": "depthUpdate",
            "E": 1640000000123,
            "s": "BTCUSDT",
            "U": 1,
            "u": 2,
            "b": [],
            "a": []
        }"#;

        let orderbook = BinanceFeed::parse_orderbook(json).unwrap();
        assert_eq!(orderbook.bids.len(), 0);
        assert_eq!(orderbook.asks.len(), 0);
    }

    // === Subscription Message Format Tests ===

    #[test]
    fn test_subscription_message_format_trades() {
        let sub_msg = BinanceSubscribe {
            method: "SUBSCRIBE".to_string(),
            params: vec!["btcusdt@trade".to_string()],
            id: 1,
        };

        let json = serde_json::to_string(&sub_msg).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["method"], "SUBSCRIBE");
        assert_eq!(parsed["params"][0], "btcusdt@trade");
        assert_eq!(parsed["id"], 1);
    }

    #[test]
    fn test_subscription_message_format_depth() {
        let sub_msg = BinanceSubscribe {
            method: "SUBSCRIBE".to_string(),
            params: vec!["btcusdt@depth@100ms".to_string()],
            id: 2,
        };

        let json = serde_json::to_string(&sub_msg).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["method"], "SUBSCRIBE");
        assert_eq!(parsed["params"][0], "btcusdt@depth@100ms");
        assert_eq!(parsed["id"], 2);
    }

    // === Combined Stream URL Test ===

    #[test]
    fn test_combined_stream_url_construction() {
        // Test that multiple symbols can be combined
        let symbols = ["btcusdt@trade", "ethusdt@trade", "solusdt@trade"];
        let combined = symbols.join("/");

        assert_eq!(combined, "btcusdt@trade/ethusdt@trade/solusdt@trade");
    }

    #[test]
    fn parse_trade_rejects_non_positive_price_or_quantity() {
        let msg = |p: &str, q: &str| {
            format!(
                r#"{{"e":"trade","E":1,"s":"BTCUSDT","t":1,"p":"{p}","q":"{q}","T":1640000000000,"m":false}}"#
            )
        };
        assert!(BinanceFeed::parse_trade(&msg("50000", "0.1")).is_ok());
        assert!(BinanceFeed::parse_trade(&msg("0", "0.1")).is_err());
        assert!(BinanceFeed::parse_trade(&msg("50000", "0")).is_err());
        assert!(BinanceFeed::parse_trade(&msg("NaN", "0.1")).is_err());
        assert!(BinanceFeed::parse_trade(&msg("50000", "-1")).is_err());
    }
}
