//! Exchange-specific message parsing and REST API adapters
//!
//! Provides normalized ExchangeMessage enum and adapter implementations
//! for Bitstamp, Coinbase, and Kraken exchanges.

use anyhow::Result;
use async_trait::async_trait;
use serde::Deserialize;
use std::sync::atomic::{AtomicU64, Ordering};

/// Normalized exchange message types
#[derive(Debug, Clone)]
pub enum ExchangeMessage {
    /// Full orderbook snapshot
    Snapshot {
        symbol: String,
        bids: Vec<[f64; 2]>,
        asks: Vec<[f64; 2]>,
        sequence: u64,
    },
    /// Incremental orderbook delta
    Delta {
        symbol: String,
        bids: Vec<[f64; 2]>,
        asks: Vec<[f64; 2]>,
        sequence: u64,
    },
    /// Heartbeat/ping message
    Heartbeat,
    /// Other message types (ignored)
    Other,
}

/// Snapshot data from REST API
#[derive(Debug, Clone)]
pub struct SnapshotData {
    pub symbol: String,
    pub bids: Vec<[f64; 2]>,
    pub asks: Vec<[f64; 2]>,
    pub sequence: u64,
}

/// Exchange adapter trait for parsing WebSocket messages and fetching REST snapshots
#[allow(dead_code)]
#[async_trait]
pub trait ExchangeAdapter: Send + Sync {
    /// Exchange name
    fn exchange_name(&self) -> &str;

    /// Build WebSocket subscribe message
    fn build_subscribe_message(&self, symbols: &[String]) -> String;

    /// Parse WebSocket message
    fn parse_message(&self, text: &str) -> Result<ExchangeMessage>;

    /// Fetch orderbook snapshot from REST API
    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData>;
}

// ============================================================================
// Bitstamp Adapter
// ============================================================================

pub struct BitstampAdapter {
    rest_url: String,
}

impl BitstampAdapter {
    pub fn new(rest_url: String) -> Self {
        Self { rest_url }
    }
}

#[async_trait]
impl ExchangeAdapter for BitstampAdapter {
    fn exchange_name(&self) -> &str {
        "bitstamp"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        // Bitstamp requires individual subscribe messages per symbol
        // Return first symbol's subscribe message (caller should send one per symbol)
        if let Some(symbol) = symbols.first() {
            let channel = format!("diff_order_book_{}", symbol.to_lowercase());
            serde_json::json!({
                "event": "bts:subscribe",
                "data": {
                    "channel": channel
                }
            })
            .to_string()
        } else {
            String::new()
        }
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        let event = msg["event"].as_str().unwrap_or("");

        match event {
            "data" => {
                let channel = msg["channel"].as_str().unwrap_or("");
                if !channel.starts_with("diff_order_book_") {
                    return Ok(ExchangeMessage::Other);
                }

                let symbol = channel
                    .strip_prefix("diff_order_book_")
                    .unwrap_or("")
                    .to_uppercase();

                let data = &msg["data"];
                let bids = parse_bitstamp_levels(&data["bids"])?;
                let asks = parse_bitstamp_levels(&data["asks"])?;

                // Bitstamp doesn't provide sequence numbers, use timestamp as proxy
                let sequence = data["microtimestamp"]
                    .as_str()
                    .and_then(|s| s.parse::<u64>().ok())
                    .unwrap_or(0);

                Ok(ExchangeMessage::Delta {
                    symbol,
                    bids,
                    asks,
                    sequence,
                })
            }
            "bts:subscription_succeeded" => Ok(ExchangeMessage::Other),
            "bts:heartbeat" => Ok(ExchangeMessage::Heartbeat),
            _ => Ok(ExchangeMessage::Other),
        }
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let url = format!(
            "{}/order_book/{}/",
            self.rest_url,
            symbol.to_lowercase()
        );
        let response = reqwest::get(&url).await?.json::<BitstampOrderBookResponse>().await?;

        let bids = parse_bitstamp_levels(&serde_json::to_value(&response.bids)?)?;
        let asks = parse_bitstamp_levels(&serde_json::to_value(&response.asks)?)?;

        let sequence = response
            .microtimestamp
            .parse::<u64>()
            .unwrap_or(response.timestamp);

        Ok(SnapshotData {
            symbol: symbol.to_uppercase(),
            bids,
            asks,
            sequence,
        })
    }
}

#[derive(Debug, Deserialize)]
struct BitstampOrderBookResponse {
    timestamp: u64,
    microtimestamp: String,
    bids: Vec<Vec<String>>,
    asks: Vec<Vec<String>>,
}

fn parse_bitstamp_levels(value: &serde_json::Value) -> Result<Vec<[f64; 2]>> {
    let arr = value.as_array().ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item.as_array().ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
        if inner.len() >= 2 {
            let price = inner[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = inner[1].as_str().unwrap_or("0").parse::<f64>()?;
            levels.push([price, qty]);
        }
    }
    Ok(levels)
}

// ============================================================================
// Coinbase Adapter
// ============================================================================

pub struct CoinbaseAdapter {
    rest_url: String,
}

impl CoinbaseAdapter {
    pub fn new(rest_url: String) -> Self {
        Self { rest_url }
    }
}

#[async_trait]
impl ExchangeAdapter for CoinbaseAdapter {
    fn exchange_name(&self) -> &str {
        "coinbase"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        serde_json::json!({
            "type": "subscribe",
            "product_ids": symbols,
            "channels": ["level2"]
        })
        .to_string()
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        let msg_type = msg["type"].as_str().unwrap_or("");

        match msg_type {
            "snapshot" => {
                let symbol = msg["product_id"].as_str().unwrap_or("").to_string();
                let bids = parse_coinbase_levels(&msg["bids"])?;
                let asks = parse_coinbase_levels(&msg["asks"])?;

                Ok(ExchangeMessage::Snapshot {
                    symbol,
                    bids,
                    asks,
                    sequence: 0, // Snapshots don't have sequence
                })
            }
            "l2update" => {
                let symbol = msg["product_id"].as_str().unwrap_or("").to_string();
                let changes = msg["changes"].as_array().ok_or_else(|| anyhow::anyhow!("Expected changes array"))?;

                let mut bids = Vec::new();
                let mut asks = Vec::new();

                for change in changes {
                    let change_arr = change.as_array().ok_or_else(|| anyhow::anyhow!("Expected change array"))?;
                    if change_arr.len() >= 3 {
                        let side = change_arr[0].as_str().unwrap_or("");
                        let price = change_arr[1].as_str().unwrap_or("0").parse::<f64>()?;
                        let size = change_arr[2].as_str().unwrap_or("0").parse::<f64>()?;

                        match side {
                            "buy" => bids.push([price, size]),
                            "sell" => asks.push([price, size]),
                            _ => {}
                        }
                    }
                }

                let sequence = msg["time"]
                    .as_str()
                    .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    .map(|dt| dt.timestamp_micros() as u64)
                    .unwrap_or(0);

                Ok(ExchangeMessage::Delta {
                    symbol,
                    bids,
                    asks,
                    sequence,
                })
            }
            "subscriptions" | "heartbeat" => Ok(ExchangeMessage::Heartbeat),
            _ => Ok(ExchangeMessage::Other),
        }
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let url = format!("{}/products/{}/book?level=2", self.rest_url, symbol);
        let response = reqwest::get(&url).await?.json::<CoinbaseOrderBookResponse>().await?;

        let bids = parse_coinbase_levels(&serde_json::to_value(&response.bids)?)?;
        let asks = parse_coinbase_levels(&serde_json::to_value(&response.asks)?)?;

        Ok(SnapshotData {
            symbol: symbol.to_string(),
            bids,
            asks,
            sequence: response.sequence.unwrap_or(0),
        })
    }
}

#[derive(Debug, Deserialize)]
struct CoinbaseOrderBookResponse {
    sequence: Option<u64>,
    bids: Vec<Vec<String>>,
    asks: Vec<Vec<String>>,
}

fn parse_coinbase_levels(value: &serde_json::Value) -> Result<Vec<[f64; 2]>> {
    let arr = value.as_array().ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item.as_array().ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
        if inner.len() >= 2 {
            let price = inner[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = inner[1].as_str().unwrap_or("0").parse::<f64>()?;
            levels.push([price, qty]);
        }
    }
    Ok(levels)
}

// ============================================================================
// Kraken Adapter
// ============================================================================

pub struct KrakenAdapter {
    rest_url: String,
    sequence_counter: AtomicU64,
}

impl KrakenAdapter {
    pub fn new(rest_url: String) -> Self {
        Self {
            rest_url,
            sequence_counter: AtomicU64::new(0),
        }
    }
}

#[async_trait]
impl ExchangeAdapter for KrakenAdapter {
    fn exchange_name(&self) -> &str {
        "kraken"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        serde_json::json!({
            "event": "subscribe",
            "pair": symbols,
            "subscription": {
                "name": "book",
                "depth": 25
            }
        })
        .to_string()
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        // Kraken uses different message formats
        if let Some(event) = msg.get("event") {
            let event_str = event.as_str().unwrap_or("");
            match event_str {
                "heartbeat" => return Ok(ExchangeMessage::Heartbeat),
                "systemStatus" | "subscriptionStatus" => return Ok(ExchangeMessage::Other),
                _ => {}
            }
        }

        // Array format: [channelID, data, "book-depth", "PAIR"]
        if let Some(arr) = msg.as_array() {
            if arr.len() >= 4 && arr[2].as_str() == Some("book-25") {
                let symbol = arr[3].as_str().unwrap_or("").replace('/', "");
                let data = &arr[1];

                // Check if snapshot (has both 'as' and 'bs' keys)
                let has_asks = data.get("as").is_some() || data.get("a").is_some();
                let has_bids = data.get("bs").is_some() || data.get("b").is_some();

                if has_asks && has_bids {
                    // Snapshot
                    let bids = parse_kraken_levels(data.get("bs").or(data.get("b")).unwrap_or(&serde_json::Value::Null))?;
                    let asks = parse_kraken_levels(data.get("as").or(data.get("a")).unwrap_or(&serde_json::Value::Null))?;

                    return Ok(ExchangeMessage::Snapshot {
                        symbol,
                        bids,
                        asks,
                        sequence: 0,
                    });
                } else {
                    // Delta update
                    let bids = if let Some(b) = data.get("b") {
                        parse_kraken_levels(b)?
                    } else {
                        Vec::new()
                    };

                    let asks = if let Some(a) = data.get("a") {
                        parse_kraken_levels(a)?
                    } else {
                        Vec::new()
                    };

                    // Use atomic counter for guaranteed monotonic sequence
                    let sequence = self.sequence_counter.fetch_add(1, Ordering::Relaxed);

                    return Ok(ExchangeMessage::Delta {
                        symbol,
                        bids,
                        asks,
                        sequence,
                    });
                }
            }
        }

        Ok(ExchangeMessage::Other)
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let url = format!("{}/Depth?pair={}&count=25", self.rest_url, symbol);
        let response = reqwest::get(&url).await?.json::<serde_json::Value>().await?;

        // Kraken REST response format: {"error":[], "result": {"XXBTZUSD": {...}}}
        let result = response["result"]
            .as_object()
            .and_then(|obj| obj.values().next())
            .ok_or_else(|| anyhow::anyhow!("Invalid Kraken response format"))?;

        let bids = parse_kraken_levels(&result["bids"])?;
        let asks = parse_kraken_levels(&result["asks"])?;

        Ok(SnapshotData {
            symbol: symbol.replace('/', ""),
            bids,
            asks,
            sequence: 0,
        })
    }
}

fn parse_kraken_levels(value: &serde_json::Value) -> Result<Vec<[f64; 2]>> {
    let arr = value.as_array().ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item.as_array().ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
        if inner.len() >= 2 {
            let price = inner[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = inner[1].as_str().unwrap_or("0").parse::<f64>()?;
            levels.push([price, qty]);
        }
    }
    Ok(levels)
}

/// Create adapter for exchange
pub fn create_adapter(exchange_name: &str, _ws_url: &str, rest_url: &str) -> Result<Box<dyn ExchangeAdapter>> {
    match exchange_name.to_lowercase().as_str() {
        "bitstamp" => Ok(Box::new(BitstampAdapter::new(rest_url.to_string()))),
        "coinbase" => Ok(Box::new(CoinbaseAdapter::new(rest_url.to_string()))),
        "kraken" => Ok(Box::new(KrakenAdapter::new(rest_url.to_string()))),
        _ => Err(anyhow::anyhow!("Unknown exchange: {}", exchange_name)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitstamp_parse_delta() {
        let json = r#"{
            "event": "data",
            "channel": "diff_order_book_btcusd",
            "data": {
                "timestamp": "1640000000",
                "microtimestamp": "1640000000000000",
                "bids": [["50000.00", "0.5"]],
                "asks": [["50001.00", "0.3"]]
            }
        }"#;

        let adapter = BitstampAdapter::new("https://example.com".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta { symbol, bids, asks, .. } => {
                assert_eq!(symbol, "BTCUSD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_coinbase_parse_snapshot() {
        let json = r#"{
            "type": "snapshot",
            "product_id": "BTC-USD",
            "bids": [["50000.00", "0.5"]],
            "asks": [["50001.00", "0.3"]]
        }"#;

        let adapter = CoinbaseAdapter::new("https://example.com".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Snapshot { symbol, bids, asks, .. } => {
                assert_eq!(symbol, "BTC-USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
            }
            _ => panic!("Expected Snapshot message"),
        }
    }

    #[test]
    fn test_coinbase_parse_l2update() {
        let json = r#"{
            "type": "l2update",
            "product_id": "BTC-USD",
            "time": "2021-01-01T00:00:00.000000Z",
            "changes": [
                ["buy", "50000.00", "0.5"],
                ["sell", "50001.00", "0.3"]
            ]
        }"#;

        let adapter = CoinbaseAdapter::new("https://example.com".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta { symbol, bids, asks, .. } => {
                assert_eq!(symbol, "BTC-USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_create_adapter() {
        let adapter = create_adapter("bitstamp", "wss://ws.bitstamp.net", "https://www.bitstamp.net/api/v2").unwrap();
        assert_eq!(adapter.exchange_name(), "bitstamp");

        let adapter = create_adapter("coinbase", "wss://ws-feed.exchange.coinbase.com", "https://api.exchange.coinbase.com").unwrap();
        assert_eq!(adapter.exchange_name(), "coinbase");

        let adapter = create_adapter("kraken", "wss://ws.kraken.com", "https://api.kraken.com/0/public").unwrap();
        assert_eq!(adapter.exchange_name(), "kraken");
    }
}
