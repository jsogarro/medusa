//! Alpaca to kdb+ Tickerplant bridge
//!
//! Converts Alpaca market data to kdb+ IPC messages and publishes to Tickerplant.

use super::types::{AlpacaTrade, Bar, Quote};
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use kdb_ipc::types::KObject;
use kdb_ipc::KdbClient;
use tracing::{debug, info};

/// Publisher that sends Alpaca market data to kdb+ Tickerplant via `.u.upd`
pub struct AlpacaKdbBridge {
    client: KdbClient,
}

impl AlpacaKdbBridge {
    /// Connect to the Tickerplant
    pub async fn connect(host: &str, port: u16, user: &str, password: &str) -> Result<Self> {
        let client = KdbClient::connect(host, port, user, password)
            .await
            .context("Failed to connect to Tickerplant")?;

        info!(
            "Alpaca bridge connected to Tickerplant at {}:{}",
            host, port
        );
        Ok(Self { client })
    }

    /// Publish an equity trade to the Tickerplant
    ///
    /// Publishes to `.u.upd[`equityTrade;data]`
    ///
    /// Schema: (timestamp; exchange; symbol; trade_id; price; size; side; value)
    pub async fn publish_trade(&mut self, symbol: &str, trade: &AlpacaTrade) -> Result<()> {
        let ts = parse_alpaca_timestamp(&trade.timestamp)?;
        let ts_str = format_kdb_timestamp(&ts);

        // Determine side from trade conditions if available
        // Alpaca doesn't directly indicate buy/sell in trade data
        // We'll set to "unknown" and let downstream consumers infer from context
        let side = "unknown";
        let value = trade.price * trade.size as f64;

        let query = format!(
            ".u.upd[`equityTrade;enlist(`{ts};`alpaca;`{sym};`{tid};{price};{size};`{side};{value})]",
            ts = ts_str,
            sym = normalize_symbol(symbol),
            tid = trade.id,
            price = trade.price,
            size = trade.size,
            side = side,
            value = value,
        );

        debug!("Publishing equity trade: {} id={}", symbol, trade.id);
        self.send_async_query(&query).await
    }

    /// Publish an equity quote to the Tickerplant
    ///
    /// Publishes to `.u.upd[`equityQuote;data]`
    ///
    /// Schema: (timestamp; exchange; symbol; bid_price; bid_size; ask_price; ask_size; spread)
    pub async fn publish_quote(&mut self, symbol: &str, quote: &Quote) -> Result<()> {
        let ts = parse_alpaca_timestamp(&quote.timestamp)?;
        let ts_str = format_kdb_timestamp(&ts);

        let spread = quote.ask_price - quote.bid_price;

        let query = format!(
            ".u.upd[`equityQuote;enlist(`{ts};`alpaca;`{sym};{bid_price};{bid_size}j;{ask_price};{ask_size}j;{spread})]",
            ts = ts_str,
            sym = normalize_symbol(symbol),
            bid_price = quote.bid_price,
            bid_size = quote.bid_size,
            ask_price = quote.ask_price,
            ask_size = quote.ask_size,
            spread = spread,
        );

        debug!("Publishing equity quote: {}", symbol);
        self.send_async_query(&query).await
    }

    /// Publish an equity bar (OHLCV) to the Tickerplant
    ///
    /// Publishes to `.u.upd[`equityBar;data]`
    ///
    /// Schema: (timestamp; exchange; symbol; open; high; low; close; volume; vwap; trade_count)
    pub async fn publish_bar(&mut self, symbol: &str, bar: &Bar) -> Result<()> {
        let ts = parse_alpaca_timestamp(&bar.timestamp)?;
        let ts_str = format_kdb_timestamp(&ts);

        let query = format!(
            ".u.upd[`equityBar;enlist(`{ts};`alpaca;`{sym};{open};{high};{low};{close};{volume}j;{vwap};{trades}j)]",
            ts = ts_str,
            sym = normalize_symbol(symbol),
            open = bar.open,
            high = bar.high,
            low = bar.low,
            close = bar.close,
            volume = bar.volume,
            vwap = bar.vwap,
            trades = bar.trade_count,
        );

        debug!("Publishing equity bar: {}", symbol);
        self.send_async_query(&query).await
    }

    /// Send a raw async query (fire-and-forget)
    async fn send_async_query(&mut self, query: &str) -> Result<()> {
        let obj = KObject::CharList(query.as_bytes().to_vec());
        self.client
            .send_async(obj)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to publish to TP: {}", e))
    }
}

/// Parse Alpaca RFC3339 timestamp to DateTime<Utc>
fn parse_alpaca_timestamp(timestamp_str: &str) -> Result<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(timestamp_str)
        .map(|dt| dt.with_timezone(&Utc))
        .context(format!("Failed to parse timestamp: {}", timestamp_str))
}

/// Format a DateTime<Utc> as a kdb+ timestamp literal
fn format_kdb_timestamp(dt: &DateTime<Utc>) -> String {
    dt.format("%Y.%m.%dD%H:%M:%S%.9f").to_string()
}

/// Normalize equity symbols to canonical form
///
/// Alpaca symbols are already uppercase (e.g., "AAPL", "TSLA")
fn normalize_symbol(symbol: &str) -> String {
    symbol.to_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Datelike;

    #[test]
    fn test_normalize_symbol() {
        assert_eq!(normalize_symbol("AAPL"), "AAPL");
        assert_eq!(normalize_symbol("aapl"), "AAPL");
        assert_eq!(normalize_symbol("TsLa"), "TSLA");
    }

    #[test]
    fn test_parse_alpaca_timestamp() {
        let ts_str = "2026-01-15T14:30:45.123456789Z";
        let result = parse_alpaca_timestamp(ts_str);
        assert!(result.is_ok());

        let dt = result.unwrap();
        assert_eq!(dt.year(), 2026);
        assert_eq!(dt.month(), 1);
        assert_eq!(dt.day(), 15);
    }

    #[test]
    fn test_format_kdb_timestamp() {
        use chrono::TimeZone;
        let dt = Utc.with_ymd_and_hms(2026, 3, 14, 12, 30, 45).unwrap();
        let ts = format_kdb_timestamp(&dt);
        assert!(ts.starts_with("2026.03.14D12:30:45"));
    }
}
