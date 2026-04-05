//! Exchange-specific trade parsing and normalization
//!
//! Provides adapters for each exchange that parse raw WebSocket messages
//! and REST responses into normalized Trade structs.

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use exchange_connector::types::{Side, Trade};
use serde::{Deserialize, Serialize};
use tracing::warn;

/// Normalized trade representation before conversion to exchange_connector::Trade
#[derive(Debug, Clone, PartialEq)]
pub struct NormalizedTrade {
    pub exchange: String,
    pub symbol: String,
    pub trade_id: String,
    pub price: f64,
    pub quantity: f64,
    pub side: Side,
    pub timestamp: DateTime<Utc>,
}

impl NormalizedTrade {
    /// Convert to exchange_connector::Trade
    pub fn into_trade(self) -> Trade {
        Trade {
            id: self.trade_id,
            pair: self.symbol,
            exchange: self.exchange,
            price: self.price,
            quantity: self.quantity,
            side: self.side,
            timestamp: self.timestamp,
            is_maker: None,
        }
    }
}

/// Trait for exchange-specific trade parsing
#[allow(dead_code)]
#[async_trait]
pub trait TradeAdapter: Send + Sync {
    /// Returns the exchange name
    fn exchange_name(&self) -> &str;

    /// Build WebSocket subscribe message for given symbols
    fn build_subscribe_message(&self, symbols: &[String]) -> String;

    /// Parse WebSocket message into normalized trades
    fn parse_message(&self, text: &str) -> Result<Vec<NormalizedTrade>>;

    /// Fetch recent trades via REST API (for backfill)
    async fn fetch_recent_trades(&self, symbol: &str, limit: usize) -> Result<Vec<NormalizedTrade>>;
}

// ============================================================================
// Bitstamp Adapter
// ============================================================================

pub struct BitstampTradeAdapter {
    rest_url: String,
}

impl BitstampTradeAdapter {
    pub fn new(rest_url: String) -> Self {
        Self { rest_url }
    }
}

#[derive(Debug, Deserialize)]
struct BitstampMessage {
    event: String,
    channel: Option<String>,
    data: Option<BitstampTradeData>,
}

#[derive(Debug, Deserialize)]
struct BitstampTradeData {
    id: u64,
    amount: f64,
    price: f64,
    #[serde(rename = "type")]
    trade_type: u8, // 0 = buy, 1 = sell
    timestamp: String,
}

#[derive(Debug, Deserialize)]
struct BitstampRestTrade {
    tid: u64,
    amount: String,
    price: String,
    #[serde(rename = "type")]
    trade_type: String, // "0" or "1"
    date: String,
}

#[async_trait]
impl TradeAdapter for BitstampTradeAdapter {
    fn exchange_name(&self) -> &str {
        "bitstamp"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        // Subscribe to all symbols
        let mut messages = Vec::new();
        for symbol in symbols {
            let msg = format!(
                r#"{{"event":"bts:subscribe","data":{{"channel":"live_trades_{}"}}}}"#,
                symbol.to_lowercase()
            );
            messages.push(msg);
        }
        messages.join("\n")
    }

    fn parse_message(&self, text: &str) -> Result<Vec<NormalizedTrade>> {
        let msg: BitstampMessage = serde_json::from_str(text)
            .context("Failed to parse Bitstamp message")?;

        if msg.event != "trade" {
            return Ok(vec![]); // Not a trade message
        }

        let data = msg.data.ok_or_else(|| anyhow!("Missing data field"))?;
        let channel = msg.channel.ok_or_else(|| anyhow!("Missing channel field"))?;

        // Extract symbol from channel: "live_trades_btcusd" -> "btcusd"
        let symbol = channel
            .strip_prefix("live_trades_")
            .ok_or_else(|| anyhow!("Invalid channel format"))?
            .to_uppercase();

        let side = if data.trade_type == 0 {
            Side::Buy
        } else {
            Side::Sell
        };

        // Parse timestamp (Unix seconds as string)
        let timestamp = data.timestamp.parse::<i64>()
            .context("Failed to parse timestamp")?;
        let dt = DateTime::from_timestamp(timestamp, 0)
            .ok_or_else(|| anyhow!("Invalid timestamp"))?;

        Ok(vec![NormalizedTrade {
            exchange: "bitstamp".to_string(),
            symbol,
            trade_id: data.id.to_string(),
            price: data.price,
            quantity: data.amount,
            side,
            timestamp: dt,
        }])
    }

    async fn fetch_recent_trades(&self, symbol: &str, limit: usize) -> Result<Vec<NormalizedTrade>> {
        let url = format!(
            "{}/transactions/{}/?sort=desc&limit={}",
            self.rest_url,
            symbol.to_lowercase(),
            limit.min(1000)
        );

        let response = reqwest::get(&url).await
            .context("Failed to fetch Bitstamp trades")?;

        let trades: Vec<BitstampRestTrade> = response.json().await
            .context("Failed to parse Bitstamp REST response")?;

        trades
            .into_iter()
            .map(|t| {
                let side = if t.trade_type == "0" {
                    Side::Buy
                } else {
                    Side::Sell
                };

                let timestamp = t.date.parse::<i64>()
                    .context("Failed to parse timestamp")?;
                let dt = DateTime::from_timestamp(timestamp, 0)
                    .ok_or_else(|| anyhow!("Invalid timestamp"))?;

                let price = t.price.parse::<f64>()
                    .context("Failed to parse price")?;
                let quantity = t.amount.parse::<f64>()
                    .context("Failed to parse quantity")?;

                Ok(NormalizedTrade {
                    exchange: "bitstamp".to_string(),
                    symbol: symbol.to_uppercase(),
                    trade_id: t.tid.to_string(),
                    price,
                    quantity,
                    side,
                    timestamp: dt,
                })
            })
            .collect()
    }
}

// ============================================================================
// Coinbase Adapter
// ============================================================================

pub struct CoinbaseTradeAdapter {
    rest_url: String,
}

impl CoinbaseTradeAdapter {
    pub fn new(rest_url: String) -> Self {
        Self { rest_url }
    }
}

#[derive(Debug, Deserialize)]
struct CoinbaseMessage {
    #[serde(rename = "type")]
    msg_type: String,
    trade_id: Option<u64>,
    price: Option<String>,
    size: Option<String>,
    side: Option<String>,
    time: Option<String>,
    product_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseRestTrade {
    trade_id: u64,
    price: String,
    size: String,
    side: String,
    time: String,
}

#[async_trait]
impl TradeAdapter for CoinbaseTradeAdapter {
    fn exchange_name(&self) -> &str {
        "coinbase"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        serde_json::json!({
            "type": "subscribe",
            "product_ids": symbols,
            "channels": ["matches"]
        })
        .to_string()
    }

    fn parse_message(&self, text: &str) -> Result<Vec<NormalizedTrade>> {
        let msg: CoinbaseMessage = serde_json::from_str(text)
            .context("Failed to parse Coinbase message")?;

        if msg.msg_type != "match" {
            return Ok(vec![]); // Not a trade message
        }

        let trade_id = msg.trade_id.ok_or_else(|| anyhow!("Missing trade_id"))?;
        let price_str = msg.price.ok_or_else(|| anyhow!("Missing price"))?;
        let size_str = msg.size.ok_or_else(|| anyhow!("Missing size"))?;
        let side_str = msg.side.ok_or_else(|| anyhow!("Missing side"))?;
        let time_str = msg.time.ok_or_else(|| anyhow!("Missing time"))?;
        let product_id = msg.product_id.ok_or_else(|| anyhow!("Missing product_id"))?;

        let price = price_str.parse::<f64>()
            .context("Failed to parse price")?;
        let quantity = size_str.parse::<f64>()
            .context("Failed to parse size")?;

        let side = match side_str.as_str() {
            "buy" => Side::Buy,
            "sell" => Side::Sell,
            _ => return Err(anyhow!("Invalid side: {}", side_str)),
        };

        let dt = DateTime::parse_from_rfc3339(&time_str)
            .context("Failed to parse timestamp")?
            .with_timezone(&Utc);

        Ok(vec![NormalizedTrade {
            exchange: "coinbase".to_string(),
            symbol: product_id,
            trade_id: trade_id.to_string(),
            price,
            quantity,
            side,
            timestamp: dt,
        }])
    }

    async fn fetch_recent_trades(&self, symbol: &str, limit: usize) -> Result<Vec<NormalizedTrade>> {
        let url = format!(
            "{}/products/{}/trades?limit={}",
            self.rest_url,
            symbol,
            limit.min(100)
        );

        let response = reqwest::get(&url).await
            .context("Failed to fetch Coinbase trades")?;

        let trades: Vec<CoinbaseRestTrade> = response.json().await
            .context("Failed to parse Coinbase REST response")?;

        trades
            .into_iter()
            .map(|t| {
                let side = match t.side.as_str() {
                    "buy" => Side::Buy,
                    "sell" => Side::Sell,
                    _ => return Err(anyhow!("Invalid trade side: {}", t.side)),
                };

                let dt = DateTime::parse_from_rfc3339(&t.time)
                    .context("Failed to parse timestamp")?
                    .with_timezone(&Utc);

                let price = t.price.parse::<f64>()
                    .context("Failed to parse price")?;
                let quantity = t.size.parse::<f64>()
                    .context("Failed to parse size")?;

                Ok(NormalizedTrade {
                    exchange: "coinbase".to_string(),
                    symbol: symbol.to_string(),
                    trade_id: t.trade_id.to_string(),
                    price,
                    quantity,
                    side,
                    timestamp: dt,
                })
            })
            .collect()
    }
}

// ============================================================================
// Kraken Adapter
// ============================================================================

pub struct KrakenTradeAdapter {
    rest_url: String,
}

impl KrakenTradeAdapter {
    pub fn new(rest_url: String) -> Self {
        Self { rest_url }
    }
}

#[derive(Debug, Serialize)]
struct KrakenSubscribe {
    event: String,
    pair: Vec<String>,
    subscription: KrakenSubscription,
}

#[derive(Debug, Serialize)]
struct KrakenSubscription {
    name: String,
}

#[derive(Debug, Deserialize)]
struct KrakenRestResponse {
    result: Option<serde_json::Value>,
}

#[async_trait]
impl TradeAdapter for KrakenTradeAdapter {
    fn exchange_name(&self) -> &str {
        "kraken"
    }

    fn build_subscribe_message(&self, symbols: &[String]) -> String {
        let msg = KrakenSubscribe {
            event: "subscribe".to_string(),
            pair: symbols.to_vec(),
            subscription: KrakenSubscription {
                name: "trade".to_string(),
            },
        };
        serde_json::to_string(&msg).unwrap_or_default()
    }

    fn parse_message(&self, text: &str) -> Result<Vec<NormalizedTrade>> {
        let value: serde_json::Value = serde_json::from_str(text)
            .context("Failed to parse Kraken message")?;

        // Kraken trade messages are arrays: [channelID, [[price, volume, time, side, orderType, misc], ...], "trade", "XBT/USD"]
        if !value.is_array() {
            return Ok(vec![]); // Not a trade array
        }

        let arr = value.as_array().ok_or_else(|| anyhow!("Expected array"))?;
        if arr.len() < 4 {
            return Ok(vec![]); // Not enough elements
        }

        // Check if this is a trade message
        let msg_type = arr[2].as_str().unwrap_or("");
        if msg_type != "trade" {
            return Ok(vec![]); // Not a trade
        }

        let symbol = arr[3]
            .as_str()
            .ok_or_else(|| anyhow!("Missing symbol"))?
            .to_string();

        let trades_array = arr[1]
            .as_array()
            .ok_or_else(|| anyhow!("Missing trades array"))?;

        let mut normalized_trades = Vec::new();

        for trade_data in trades_array {
            let trade_arr = trade_data
                .as_array()
                .ok_or_else(|| anyhow!("Invalid trade format"))?;

            if trade_arr.len() < 6 {
                continue; // Skip malformed trade
            }

            let price_str = trade_arr[0].as_str().unwrap_or("0");
            let volume_str = trade_arr[1].as_str().unwrap_or("0");
            let time_str = trade_arr[2].as_str().unwrap_or("0");
            let side_str = trade_arr[3].as_str().unwrap_or("b");

            let price = price_str.parse::<f64>().unwrap_or(0.0);
            let quantity = volume_str.parse::<f64>().unwrap_or(0.0);
            let timestamp_f64 = time_str.parse::<f64>().unwrap_or(0.0);

            let side = if side_str == "b" {
                Side::Buy
            } else {
                Side::Sell
            };

            let timestamp_secs = timestamp_f64.trunc() as i64;
            let nanos_raw = (timestamp_f64.fract() * 1_000_000_000.0) as u32;
            let timestamp_nanos = nanos_raw.min(999_999_999);

            if nanos_raw > 999_999_999 {
                warn!("Kraken timestamp nanoseconds clamped from {} to 999999999 (malformed data)", nanos_raw);
            }

            let dt = DateTime::from_timestamp(timestamp_secs, timestamp_nanos)
                .ok_or_else(|| anyhow!("Invalid timestamp"))?;

            // Kraken doesn't provide trade IDs in WebSocket, so we construct one
            let trade_id = format!("{}_{}", timestamp_secs, timestamp_nanos);

            normalized_trades.push(NormalizedTrade {
                exchange: "kraken".to_string(),
                symbol: symbol.clone(),
                trade_id,
                price,
                quantity,
                side,
                timestamp: dt,
            });
        }

        Ok(normalized_trades)
    }

    async fn fetch_recent_trades(&self, symbol: &str, limit: usize) -> Result<Vec<NormalizedTrade>> {
        let url = format!(
            "{}/Trades?pair={}&count={}",
            self.rest_url,
            symbol,
            limit.min(1000)
        );

        let response = reqwest::get(&url).await
            .context("Failed to fetch Kraken trades")?;

        let resp: KrakenRestResponse = response.json().await
            .context("Failed to parse Kraken REST response")?;

        let result = resp.result.ok_or_else(|| anyhow!("Missing result field"))?;

        // Kraken REST response: {"result": {"XXBTZUSD": [[price, volume, time, buy/sell, market/limit, misc], ...]}}
        let result_obj = result.as_object()
            .ok_or_else(|| anyhow!("Result is not an object"))?;

        let mut all_trades = Vec::new();

        for (_pair_key, trades_value) in result_obj {
            let trades_arr = trades_value.as_array()
                .ok_or_else(|| anyhow!("Trades value is not an array"))?;

            for trade_data in trades_arr {
                let trade_arr = trade_data.as_array()
                    .ok_or_else(|| anyhow!("Trade is not an array"))?;

                if trade_arr.len() < 6 {
                    continue;
                }

                let price_str = trade_arr[0].as_str().unwrap_or("0");
                let volume_str = trade_arr[1].as_str().unwrap_or("0");
                let time_f64 = trade_arr[2].as_f64().unwrap_or(0.0);
                let side_str = trade_arr[3].as_str().unwrap_or("b");

                let price = price_str.parse::<f64>().unwrap_or(0.0);
                let quantity = volume_str.parse::<f64>().unwrap_or(0.0);

                let side = if side_str == "b" {
                    Side::Buy
                } else {
                    Side::Sell
                };

                let timestamp_secs = time_f64.trunc() as i64;
                let nanos_raw = (time_f64.fract() * 1_000_000_000.0) as u32;
                let timestamp_nanos = nanos_raw.min(999_999_999);

                if nanos_raw > 999_999_999 {
                    warn!("Kraken REST timestamp nanoseconds clamped from {} to 999999999 (malformed data)", nanos_raw);
                }

                let dt = DateTime::from_timestamp(timestamp_secs, timestamp_nanos)
                    .ok_or_else(|| anyhow!("Invalid timestamp"))?;

                let trade_id = format!("{}_{}", timestamp_secs, timestamp_nanos);

                all_trades.push(NormalizedTrade {
                    exchange: "kraken".to_string(),
                    symbol: symbol.to_string(),
                    trade_id,
                    price,
                    quantity,
                    side,
                    timestamp: dt,
                });
            }
        }

        Ok(all_trades)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalized_trade_conversion() {
        let normalized = NormalizedTrade {
            exchange: "test".to_string(),
            symbol: "BTC-USD".to_string(),
            trade_id: "123".to_string(),
            price: 50000.0,
            quantity: 0.5,
            side: Side::Buy,
            timestamp: Utc::now(),
        };

        let trade = normalized.clone().into_trade();
        assert_eq!(trade.exchange, "test");
        assert_eq!(trade.pair, "BTC-USD");
        assert_eq!(trade.id, "123");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.5);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_bitstamp_subscribe_message() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["btcusd".to_string(), "ethusd".to_string()]);
        assert!(msg.contains("live_trades_btcusd"));
        assert!(msg.contains("live_trades_ethusd"));
    }

    #[test]
    fn test_bitstamp_parse_trade() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        let json = r#"{"event":"trade","channel":"live_trades_btcusd","data":{"id":123456,"amount":0.5,"price":50000.0,"type":0,"timestamp":"1640000000"}}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].exchange, "bitstamp");
        assert_eq!(trades[0].symbol, "BTCUSD");
        assert_eq!(trades[0].price, 50000.0);
        assert_eq!(trades[0].quantity, 0.5);
        assert_eq!(trades[0].side, Side::Buy);
    }

    #[test]
    fn test_coinbase_subscribe_message() {
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["BTC-USD".to_string()]);
        assert!(msg.contains("matches"));
        assert!(msg.contains("BTC-USD"));
    }

    #[test]
    fn test_coinbase_parse_trade() {
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let json = r#"{"type":"match","trade_id":123,"price":"50000.00","size":"0.5","side":"buy","time":"2024-01-01T00:00:00.000000Z","product_id":"BTC-USD"}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].exchange, "coinbase");
        assert_eq!(trades[0].symbol, "BTC-USD");
        assert_eq!(trades[0].price, 50000.0);
        assert_eq!(trades[0].quantity, 0.5);
        assert_eq!(trades[0].side, Side::Buy);
    }

    #[test]
    fn test_kraken_subscribe_message() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["XBT/USD".to_string()]);
        assert!(msg.contains("trade"));
        assert!(msg.contains("XBT/USD"));
    }
}
