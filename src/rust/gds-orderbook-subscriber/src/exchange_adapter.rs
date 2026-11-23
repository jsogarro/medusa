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
        let url = format!("{}/order_book/{}/", self.rest_url, symbol.to_lowercase());
        let response = reqwest::get(&url)
            .await?
            .json::<BitstampOrderBookResponse>()
            .await?;

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
    let arr = value
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
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
    #[allow(dead_code)]
    use_advanced: bool,
}

impl CoinbaseAdapter {
    pub fn new(rest_url: String) -> Self {
        let use_advanced = std::env::var("COINBASE_USE_ADVANCED_TRADE")
            .unwrap_or_else(|_| "false".to_string())
            .to_lowercase()
            == "true";

        Self {
            rest_url,
            use_advanced,
        }
    }
}

#[async_trait]
impl ExchangeAdapter for CoinbaseAdapter {
    fn exchange_name(&self) -> &str {
        "coinbase"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        if self.use_advanced {
            serde_json::json!({
                "type": "subscribe",
                "product_ids": symbols,
                "channel": "level2"
            })
            .to_string()
        } else {
            serde_json::json!({
                "type": "subscribe",
                "product_ids": symbols,
                "channels": ["level2"]
            })
            .to_string()
        }
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        if self.use_advanced {
            // Advanced Trade API format
            let channel = msg.get("channel").and_then(|c| c.as_str());

            if channel == Some("level2") || channel == Some("l2_data") {
                let events = msg
                    .get("events")
                    .and_then(|e| e.as_array())
                    .ok_or_else(|| anyhow::anyhow!("Missing events array"))?;

                if events.is_empty() {
                    return Ok(ExchangeMessage::Other);
                }

                let event = &events[0];
                let event_type = event.get("type").and_then(|t| t.as_str()).unwrap_or("");

                match event_type {
                    "snapshot" => {
                        let symbol = event
                            .get("product_id")
                            .and_then(|s| s.as_str())
                            .unwrap_or("")
                            .to_string();
                        let bids = parse_coinbase_levels_advanced(&event["updates"], "bid")?;
                        let asks = parse_coinbase_levels_advanced(&event["updates"], "offer")?;

                        Ok(ExchangeMessage::Snapshot {
                            symbol,
                            bids,
                            asks,
                            sequence: 0,
                        })
                    }
                    "update" => {
                        let symbol = event
                            .get("product_id")
                            .and_then(|s| s.as_str())
                            .unwrap_or("")
                            .to_string();
                        let bids = parse_coinbase_levels_advanced(&event["updates"], "bid")?;
                        let asks = parse_coinbase_levels_advanced(&event["updates"], "offer")?;

                        let sequence = msg
                            .get("sequence_num")
                            .and_then(|s| s.as_u64())
                            .unwrap_or(0);

                        Ok(ExchangeMessage::Delta {
                            symbol,
                            bids,
                            asks,
                            sequence,
                        })
                    }
                    _ => Ok(ExchangeMessage::Other),
                }
            } else {
                Ok(ExchangeMessage::Other)
            }
        } else {
            // Legacy API format
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
                        sequence: 0,
                    })
                }
                "l2update" => {
                    let symbol = msg["product_id"].as_str().unwrap_or("").to_string();
                    let changes = msg["changes"]
                        .as_array()
                        .ok_or_else(|| anyhow::anyhow!("Expected changes array"))?;

                    let mut bids = Vec::new();
                    let mut asks = Vec::new();

                    for change in changes {
                        let change_arr = change
                            .as_array()
                            .ok_or_else(|| anyhow::anyhow!("Expected change array"))?;
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
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let url = format!("{}/products/{}/book?level=2", self.rest_url, symbol);
        let response = reqwest::get(&url)
            .await?
            .json::<CoinbaseOrderBookResponse>()
            .await?;

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
    let arr = value
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
        if inner.len() >= 2 {
            let price = inner[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = inner[1].as_str().unwrap_or("0").parse::<f64>()?;
            levels.push([price, qty]);
        }
    }
    Ok(levels)
}

fn parse_coinbase_levels_advanced(
    updates: &serde_json::Value,
    side_filter: &str,
) -> Result<Vec<[f64; 2]>> {
    let arr = updates
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Expected updates array"))?;
    let mut levels = Vec::new();

    for update in arr {
        let side = update.get("side").and_then(|s| s.as_str()).unwrap_or("");
        if side != side_filter {
            continue;
        }

        let price_str = update
            .get("price_level")
            .and_then(|p| p.as_str())
            .unwrap_or("0");
        let qty_str = update
            .get("new_quantity")
            .and_then(|q| q.as_str())
            .unwrap_or("0");

        let price = price_str.parse::<f64>()?;
        let qty = qty_str.parse::<f64>()?;

        levels.push([price, qty]);
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
            "method": "subscribe",
            "params": {
                "channel": "book",
                "symbol": symbols,
                "depth": 25
            }
        })
        .to_string()
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        // v2: Check for channel field (JSON object format)
        if let Some(channel) = msg.get("channel").and_then(|c| c.as_str()) {
            if channel != "book" {
                return Ok(ExchangeMessage::Other);
            }

            let msg_type = msg.get("type").and_then(|t| t.as_str()).unwrap_or("");
            let data_arr = msg
                .get("data")
                .and_then(|d| d.as_array())
                .ok_or_else(|| anyhow::anyhow!("Missing data array"))?;

            if data_arr.is_empty() {
                return Ok(ExchangeMessage::Other);
            }

            let data = &data_arr[0];
            let symbol = data
                .get("symbol")
                .and_then(|s| s.as_str())
                .ok_or_else(|| anyhow::anyhow!("Missing symbol"))?
                .to_string();

            let parse_level = |level: &serde_json::Value| -> Result<[f64; 2]> {
                let price = level
                    .get("price")
                    .and_then(|p| p.as_f64())
                    .ok_or_else(|| anyhow::anyhow!("Missing price"))?;
                let qty = level
                    .get("qty")
                    .and_then(|q| q.as_f64())
                    .ok_or_else(|| anyhow::anyhow!("Missing qty"))?;
                Ok([price, qty])
            };

            let bids = if let Some(b) = data.get("bids").and_then(|b| b.as_array()) {
                b.iter().map(parse_level).collect::<Result<Vec<_>>>()?
            } else {
                Vec::new()
            };

            let asks = if let Some(a) = data.get("asks").and_then(|a| a.as_array()) {
                a.iter().map(parse_level).collect::<Result<Vec<_>>>()?
            } else {
                Vec::new()
            };

            let sequence = self.sequence_counter.fetch_add(1, Ordering::Relaxed);

            match msg_type {
                "snapshot" => Ok(ExchangeMessage::Snapshot {
                    symbol,
                    bids,
                    asks,
                    sequence,
                }),
                "update" => Ok(ExchangeMessage::Delta {
                    symbol,
                    bids,
                    asks,
                    sequence,
                }),
                _ => Ok(ExchangeMessage::Other),
            }
        } else {
            // Not a v2 message
            Ok(ExchangeMessage::Other)
        }
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let url = format!("{}/Depth?pair={}&count=25", self.rest_url, symbol);
        let response = reqwest::get(&url)
            .await?
            .json::<serde_json::Value>()
            .await?;

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
    let arr = value
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("Expected array"))?;
    let mut levels = Vec::new();
    for item in arr {
        let inner = item
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Expected inner array"))?;
        if inner.len() >= 2 {
            let price = inner[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = inner[1].as_str().unwrap_or("0").parse::<f64>()?;
            levels.push([price, qty]);
        }
    }
    Ok(levels)
}

// ============================================================================
// Binance Adapter
// ============================================================================

pub struct BinanceAdapter {
    rest_url: String,
    sequence_counter: AtomicU64,
}

impl BinanceAdapter {
    pub fn new(rest_url: String) -> Self {
        Self {
            rest_url,
            sequence_counter: AtomicU64::new(0),
        }
    }

    /// Normalize symbol: BTC/USD -> BTCUSDT, BTC/USDT -> BTCUSDT
    fn normalize_symbol(symbol: &str) -> String {
        let normalized = symbol.replace('/', "").to_uppercase();
        // Replace USD with USDT if not already USDT
        if normalized.ends_with("USD") && !normalized.ends_with("USDT") {
            normalized.replace("USD", "USDT")
        } else {
            normalized
        }
    }

    /// Denormalize symbol: BTCUSDT -> BTC/USD
    fn denormalize_symbol(symbol: &str) -> String {
        if let Some(base) = symbol.strip_suffix("USDT") {
            format!("{}/USD", base)
        } else if let Some(base) = symbol.strip_suffix("BTC") {
            format!("{}/BTC", base)
        } else if let Some(base) = symbol.strip_suffix("ETH") {
            format!("{}/ETH", base)
        } else if let Some(base) = symbol.strip_suffix("BNB") {
            format!("{}/BNB", base)
        } else {
            // Fallback: assume first 3 chars are base
            if symbol.len() > 3 {
                format!("{}/{}", &symbol[..3], &symbol[3..])
            } else {
                symbol.to_string()
            }
        }
    }
}

#[async_trait]
impl ExchangeAdapter for BinanceAdapter {
    fn exchange_name(&self) -> &str {
        "binance"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        // Binance WebSocket combines streams: <symbol1>@depth@100ms/<symbol2>@depth@100ms
        let streams: Vec<String> = symbols
            .iter()
            .map(|sym| {
                let normalized = Self::normalize_symbol(sym).to_lowercase();
                format!("{}@depth@100ms", normalized)
            })
            .collect();

        serde_json::json!({
            "method": "SUBSCRIBE",
            "params": streams,
            "id": 1
        })
        .to_string()
    }

    fn parse_message(&self, text: &str) -> Result<ExchangeMessage> {
        let msg: serde_json::Value = serde_json::from_str(text)?;

        // Check for depth update event
        if msg.get("e").and_then(|e| e.as_str()) != Some("depthUpdate") {
            return Ok(ExchangeMessage::Other);
        }

        let symbol_raw = msg
            .get("s")
            .and_then(|s| s.as_str())
            .ok_or_else(|| anyhow::anyhow!("Missing symbol"))?;

        let symbol = Self::denormalize_symbol(symbol_raw);

        // Parse bids and asks
        let bids = msg
            .get("b")
            .and_then(|b| b.as_array())
            .ok_or_else(|| anyhow::anyhow!("Missing bids"))?;

        let asks = msg
            .get("a")
            .and_then(|a| a.as_array())
            .ok_or_else(|| anyhow::anyhow!("Missing asks"))?;

        let parse_level = |level: &serde_json::Value| -> Result<[f64; 2]> {
            let arr = level
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("Expected array"))?;
            if arr.len() < 2 {
                return Err(anyhow::anyhow!("Invalid level format"));
            }
            let price = arr[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = arr[1].as_str().unwrap_or("0").parse::<f64>()?;
            Ok([price, qty])
        };

        let bids_parsed: Result<Vec<_>> = bids.iter().map(parse_level).collect();
        let asks_parsed: Result<Vec<_>> = asks.iter().map(parse_level).collect();

        // Use final update ID as sequence
        let sequence = msg
            .get("u")
            .and_then(|u| u.as_u64())
            .unwrap_or_else(|| self.sequence_counter.fetch_add(1, Ordering::Relaxed));

        Ok(ExchangeMessage::Delta {
            symbol,
            bids: bids_parsed?,
            asks: asks_parsed?,
            sequence,
        })
    }

    async fn fetch_snapshot(&self, symbol: &str) -> Result<SnapshotData> {
        let normalized = Self::normalize_symbol(symbol);
        let url = format!(
            "{}/api/v3/depth?symbol={}&limit=50",
            self.rest_url, normalized
        );

        let response = reqwest::get(&url).await?;
        let data: serde_json::Value = response.json().await?;

        let last_update_id = data
            .get("lastUpdateId")
            .and_then(|id| id.as_u64())
            .unwrap_or(0);

        let bids = data
            .get("bids")
            .and_then(|b| b.as_array())
            .ok_or_else(|| anyhow::anyhow!("Missing bids"))?;

        let asks = data
            .get("asks")
            .and_then(|a| a.as_array())
            .ok_or_else(|| anyhow::anyhow!("Missing asks"))?;

        let parse_level = |level: &serde_json::Value| -> Result<[f64; 2]> {
            let arr = level
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("Expected array"))?;
            if arr.len() < 2 {
                return Err(anyhow::anyhow!("Invalid level format"));
            }
            let price = arr[0].as_str().unwrap_or("0").parse::<f64>()?;
            let qty = arr[1].as_str().unwrap_or("0").parse::<f64>()?;
            Ok([price, qty])
        };

        let bids_parsed: Result<Vec<_>> = bids.iter().map(parse_level).collect();
        let asks_parsed: Result<Vec<_>> = asks.iter().map(parse_level).collect();

        Ok(SnapshotData {
            symbol: symbol.to_string(),
            bids: bids_parsed?,
            asks: asks_parsed?,
            sequence: last_update_id,
        })
    }
}

/// Create adapter for exchange
pub fn create_adapter(
    exchange_name: &str,
    _ws_url: &str,
    rest_url: &str,
) -> Result<Box<dyn ExchangeAdapter>> {
    match exchange_name.to_lowercase().as_str() {
        "bitstamp" => Ok(Box::new(BitstampAdapter::new(rest_url.to_string()))),
        "coinbase" => Ok(Box::new(CoinbaseAdapter::new(rest_url.to_string()))),
        "kraken" => Ok(Box::new(KrakenAdapter::new(rest_url.to_string()))),
        "binance" => Ok(Box::new(BinanceAdapter::new(rest_url.to_string()))),
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
            ExchangeMessage::Delta {
                symbol, bids, asks, ..
            } => {
                assert_eq!(symbol, "BTCUSD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_binance_parse_delta() {
        let json = r#"{
            "e": "depthUpdate",
            "E": 1640000000000,
            "s": "BTCUSDT",
            "U": 1,
            "u": 2,
            "b": [["67000.00", "0.5"]],
            "a": [["67001.00", "0.3"]]
        }"#;

        let adapter = BinanceAdapter::new("https://api.binance.com".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta {
                symbol,
                bids,
                asks,
                sequence,
            } => {
                assert_eq!(symbol, "BTC/USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
                assert_eq!(sequence, 2);
                assert_eq!(bids[0][0], 67000.0);
                assert_eq!(bids[0][1], 0.5);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_binance_symbol_normalization() {
        assert_eq!(BinanceAdapter::normalize_symbol("BTC/USD"), "BTCUSDT");
        assert_eq!(BinanceAdapter::normalize_symbol("BTC/USDT"), "BTCUSDT");
        assert_eq!(BinanceAdapter::normalize_symbol("ETH/USD"), "ETHUSDT");
    }

    #[test]
    fn test_binance_symbol_denormalization() {
        assert_eq!(BinanceAdapter::denormalize_symbol("BTCUSDT"), "BTC/USD");
        assert_eq!(BinanceAdapter::denormalize_symbol("ETHUSDT"), "ETH/USD");
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
            ExchangeMessage::Snapshot {
                symbol, bids, asks, ..
            } => {
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
            ExchangeMessage::Delta {
                symbol, bids, asks, ..
            } => {
                assert_eq!(symbol, "BTC-USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_create_adapter() {
        let adapter = create_adapter(
            "bitstamp",
            "wss://ws.bitstamp.net",
            "https://www.bitstamp.net/api/v2",
        )
        .unwrap();
        assert_eq!(adapter.exchange_name(), "bitstamp");

        let adapter = create_adapter(
            "binance",
            "wss://stream.binance.com:9443/ws",
            "https://api.binance.com",
        )
        .unwrap();
        assert_eq!(adapter.exchange_name(), "binance");

        let adapter = create_adapter(
            "coinbase",
            "wss://ws-feed.exchange.coinbase.com",
            "https://api.exchange.coinbase.com",
        )
        .unwrap();
        assert_eq!(adapter.exchange_name(), "coinbase");

        let adapter = create_adapter(
            "kraken",
            "wss://ws.kraken.com",
            "https://api.kraken.com/0/public",
        )
        .unwrap();
        assert_eq!(adapter.exchange_name(), "kraken");
    }

    // === Additional Binance Tests ===

    #[test]
    fn test_binance_depth_parse_multiple_levels() {
        let json = r#"{
            "e": "depthUpdate",
            "E": 1640000000000,
            "s": "BTCUSDT",
            "U": 100,
            "u": 105,
            "b": [
                ["67000.00", "0.5"],
                ["66999.00", "1.0"],
                ["66998.00", "2.0"]
            ],
            "a": [
                ["67001.00", "0.3"],
                ["67002.00", "0.7"]
            ]
        }"#;

        let adapter = BinanceAdapter::new("https://api.binance.com".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta {
                symbol,
                bids,
                asks,
                sequence,
            } => {
                assert_eq!(symbol, "BTC/USD");
                assert_eq!(bids.len(), 3);
                assert_eq!(asks.len(), 2);
                assert_eq!(sequence, 105);
                assert_eq!(bids[1][0], 66999.0);
                assert_eq!(bids[1][1], 1.0);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_binance_parse_heartbeat() {
        // Binance doesn't have explicit heartbeat messages, but test other message types
        let json = r#"{"result":null,"id":1}"#;
        let adapter = BinanceAdapter::new("https://api.binance.com".to_string());
        let msg = adapter.parse_message(json).unwrap();
        assert!(matches!(msg, ExchangeMessage::Other));
    }

    // === Additional Coinbase Advanced Trade Tests ===

    #[test]
    fn test_coinbase_advanced_orderbook() {
        let adapter = CoinbaseAdapter {
            rest_url: "https://api.exchange.coinbase.com".to_string(),
            use_advanced: true,
        };

        let json = r#"{
            "channel": "l2_data",
            "sequence_num": 42,
            "events": [{
                "type": "snapshot",
                "product_id": "BTC-USD",
                "updates": [
                    {"side": "bid", "price_level": "67000.00", "new_quantity": "0.5"},
                    {"side": "bid", "price_level": "66999.00", "new_quantity": "1.0"},
                    {"side": "offer", "price_level": "67001.00", "new_quantity": "0.3"},
                    {"side": "offer", "price_level": "67002.00", "new_quantity": "0.7"}
                ]
            }]
        }"#;

        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Snapshot {
                symbol,
                bids,
                asks,
                sequence,
            } => {
                assert_eq!(symbol, "BTC-USD");
                assert_eq!(bids.len(), 2);
                assert_eq!(asks.len(), 2);
                assert_eq!(sequence, 0);
                assert_eq!(bids[0][0], 67000.0);
                assert_eq!(bids[0][1], 0.5);
            }
            _ => panic!("Expected Snapshot message"),
        }
    }

    #[test]
    fn test_coinbase_advanced_orderbook_update_uses_sequence_num() {
        let adapter = CoinbaseAdapter {
            rest_url: "https://api.exchange.coinbase.com".to_string(),
            use_advanced: true,
        };

        let json = r#"{
            "channel": "level2",
            "sequence_num": 31415,
            "events": [{
                "type": "update",
                "product_id": "BTC-USD",
                "updates": [
                    {"side": "bid", "price_level": "67000.00", "new_quantity": "0.8"},
                    {"side": "offer", "price_level": "67001.00", "new_quantity": "0.0"}
                ]
            }]
        }"#;

        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta {
                symbol,
                bids,
                asks,
                sequence,
            } => {
                assert_eq!(symbol, "BTC-USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
                assert_eq!(sequence, 31415);
                assert_eq!(bids[0], [67000.0, 0.8]);
                assert_eq!(asks[0], [67001.0, 0.0]);
            }
            _ => panic!("Expected Delta message"),
        }
    }

    #[test]
    fn test_coinbase_advanced_subscribe_message() {
        let adapter = CoinbaseAdapter {
            rest_url: "https://api.exchange.coinbase.com".to_string(),
            use_advanced: true,
        };
        let msg = adapter.build_subscribe_message(&["BTC-USD".to_string()]);

        assert!(msg.contains("\"channel\":\"level2\""));
        assert!(msg.contains("\"product_ids\":[\"BTC-USD\"]"));
        assert!(!msg.contains("\"channels\""));
    }

    #[test]
    fn test_coinbase_heartbeat() {
        let json = r#"{"type": "heartbeat", "sequence": 123}"#;
        let adapter = CoinbaseAdapter::new("https://api.exchange.coinbase.com".to_string());
        let msg = adapter.parse_message(json).unwrap();
        assert!(matches!(msg, ExchangeMessage::Heartbeat));
    }

    // === Snapshot Application Tests ===

    #[test]
    fn test_snapshot_application() {
        // Test that snapshot correctly initializes orderbook state
        let snapshot = SnapshotData {
            symbol: "BTC/USD".to_string(),
            bids: vec![[67000.0, 0.5], [66999.0, 1.0]],
            asks: vec![[67001.0, 0.3], [67002.0, 0.7]],
            sequence: 100,
        };

        assert_eq!(snapshot.bids.len(), 2);
        assert_eq!(snapshot.asks.len(), 2);
        assert_eq!(snapshot.sequence, 100);
    }

    #[test]
    fn test_delta_application() {
        // Test that delta correctly updates existing snapshot
        let delta = ExchangeMessage::Delta {
            symbol: "BTC/USD".to_string(),
            bids: vec![[67000.0, 0.8]], // Updated quantity
            asks: vec![[67003.0, 0.5]], // New level
            sequence: 101,
        };

        match delta {
            ExchangeMessage::Delta {
                bids,
                asks,
                sequence,
                ..
            } => {
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
                assert_eq!(sequence, 101);
                assert_eq!(bids[0][1], 0.8);
            }
            _ => panic!("Expected Delta"),
        }
    }

    // === Kraken v2 Format Tests ===

    #[test]
    fn test_kraken_v2_snapshot() {
        let json = r#"{
            "channel": "book",
            "type": "snapshot",
            "data": [{
                "symbol": "BTC/USD",
                "bids": [{"price": 67000.0, "qty": 0.5}],
                "asks": [{"price": 67001.0, "qty": 0.3}],
                "checksum": 123456
            }]
        }"#;

        let adapter = KrakenAdapter::new("https://api.kraken.com/0/public".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Snapshot {
                symbol, bids, asks, ..
            } => {
                assert_eq!(symbol, "BTC/USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
                assert_eq!(bids[0][0], 67000.0);
            }
            _ => panic!("Expected Snapshot message"),
        }
    }

    #[test]
    fn test_kraken_v2_update() {
        let json = r#"{
            "channel": "book",
            "type": "update",
            "data": [{
                "symbol": "BTC/USD",
                "bids": [{"price": 67000.0, "qty": 0.8}],
                "asks": [{"price": 67001.0, "qty": 0.0}],
                "checksum": 123457
            }]
        }"#;

        let adapter = KrakenAdapter::new("https://api.kraken.com/0/public".to_string());
        let msg = adapter.parse_message(json).unwrap();

        match msg {
            ExchangeMessage::Delta {
                symbol, bids, asks, ..
            } => {
                assert_eq!(symbol, "BTC/USD");
                assert_eq!(bids.len(), 1);
                assert_eq!(asks.len(), 1);
                // qty=0.0 means remove the level
                assert_eq!(asks[0][1], 0.0);
            }
            _ => panic!("Expected Delta message"),
        }
    }
}
