//! kdb+ Tickerplant publisher
//!
//! Wraps KdbClient for publishing market data to the Tickerplant
//! via `.u.upd` IPC calls. Uses async fire-and-forget for throughput.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use exchange_connector::types::{OrderBook, PriceLevel, Side, Trade};
use kdb_ipc::types::KObject;
use kdb_ipc::KdbClient;
use tracing::{debug, info};

/// Publisher that sends market data to kdb+ Tickerplant via `.u.upd`.
///
/// Uses string-based q expressions sent as async IPC messages.
/// Binary-encoded table rows would be faster but string-based is
/// simpler and sufficient for current throughput requirements.
pub struct KdbPublisher {
    client: KdbClient,
}

impl KdbPublisher {
    /// Connect to the Tickerplant.
    pub async fn connect(host: &str, port: u16, user: &str, password: &str) -> Result<Self> {
        let client = KdbClient::connect(host, port, user, password)
            .await
            .context("Failed to connect to Tickerplant")?;

        info!("Connected to Tickerplant at {}:{}", host, port);
        Ok(Self { client })
    }

    /// Publish an orderbook snapshot to the Tickerplant.
    ///
    /// Sends `.u.upd[`orderbook;data]` as an async IPC message.
    pub async fn publish_orderbook(&mut self, ob: &OrderBook) -> Result<()> {
        let ts = format_timestamp(&ob.timestamp);
        let exchange = &ob.exchange;
        let sym = normalize_symbol(&ob.pair);
        let sequence = ob.sequence.unwrap_or(0);

        // Debug assertions to catch q metacharacters in exchange/symbol names
        debug_assert!(
            !exchange.contains(['`', ';', '\n']),
            "exchange name contains q metacharacters"
        );
        debug_assert!(
            !sym.contains(['`', ';', '\n']),
            "symbol contains q metacharacters"
        );

        // Compute mid price
        let mid = match (ob.bids.first(), ob.asks.first()) {
            (Some(bid), Some(ask)) => (bid.price + ask.price) / 2.0,
            _ => 0.0f64,
        };

        // Serialize bid/ask levels as nested lists: (price1 price2;size1 size2)
        let bids_str = serialize_levels(&ob.bids);
        let asks_str = serialize_levels(&ob.asks);

        let query = format!(
            ".u.upd[`orderbook;enlist(`{ts};`{exchange};`{sym};{bids};{asks};{seq}j;{mid})]",
            ts = ts,
            exchange = exchange,
            sym = sym,
            bids = bids_str,
            asks = asks_str,
            seq = sequence,
            mid = mid,
        );

        debug!("Publishing orderbook: {} {} seq={}", exchange, sym, sequence);
        self.send_async_query(&query).await
    }

    /// Publish a trade to the Tickerplant.
    ///
    /// Sends `.u.upd[`trade;data]` as an async IPC message.
    pub async fn publish_trade(&mut self, trade: &Trade) -> Result<()> {
        let ts = format_timestamp(&trade.timestamp);
        let exchange = &trade.exchange;
        let sym = normalize_symbol(&trade.pair);
        let trade_id = &trade.id;

        // Debug assertions to catch q metacharacters in exchange/symbol names
        debug_assert!(
            !exchange.contains(['`', ';', '\n']),
            "exchange name contains q metacharacters"
        );
        debug_assert!(
            !sym.contains(['`', ';', '\n']),
            "symbol contains q metacharacters"
        );
        let side_str = match trade.side {
            Side::Buy => "buy",
            Side::Sell => "sell",
        };
        let value = trade.price * trade.quantity;

        let query = format!(
            ".u.upd[`trade;enlist(`{ts};`{exchange};`{sym};`{tid};{price};{size};`{side};{value})]",
            ts = ts,
            exchange = exchange,
            sym = sym,
            tid = trade_id,
            price = trade.price,
            size = trade.quantity,
            side = side_str,
            value = value,
        );

        debug!("Publishing trade: {} {} id={}", exchange, sym, trade_id);
        self.send_async_query(&query).await
    }

    /// Publish a GDS alert to the Tickerplant.
    pub async fn publish_alert(
        &mut self,
        severity: &str,
        source: &str,
        message: &str,
        exchange: &str,
        symbol: &str,
    ) -> Result<()> {
        // Escape q metacharacters to prevent q injection
        let safe_msg = message
            .replace(['`', '"'], "'")
            .replace([';', '\n', '\r'], " ")
            .replace('\\', "/");

        let query = format!(
            ".u.upd[`gds_alert;enlist(.z.p;`{sev};`{src};`$\"{msg}\";`{exch};`{sym})]",
            sev = severity,
            src = source,
            msg = safe_msg,
            exch = exchange,
            sym = symbol,
        );

        self.send_async_query(&query).await
    }

    /// Send a raw async query (fire-and-forget).
    async fn send_async_query(&mut self, query: &str) -> Result<()> {
        let obj = KObject::CharList(query.as_bytes().to_vec());
        self.client
            .send_async(obj)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to publish to TP: {}", e))
    }
}

/// Format a DateTime<Utc> as a kdb+ timestamp literal.
fn format_timestamp(dt: &DateTime<Utc>) -> String {
    dt.format("%Y.%m.%dD%H:%M:%S%.9f").to_string()
}

/// Normalize exchange-specific symbols to a canonical form.
/// e.g., "BTC-USD" -> "BTCUSD", "XBT/USD" -> "XBTUSD", "btcusd" -> "BTCUSD"
fn normalize_symbol(pair: &str) -> String {
    pair.replace(['-', '/', '_'], "").to_uppercase()
}

/// Serialize price levels as a q expression: `(price1 price2;size1 size2)`.
fn serialize_levels(levels: &[PriceLevel]) -> String {
    if levels.is_empty() {
        return "(`float$();`float$())".to_string();
    }

    let prices: Vec<String> = levels.iter().map(|l| format!("{}", l.price)).collect();
    let sizes: Vec<String> = levels.iter().map(|l| format!("{}", l.quantity)).collect();

    format!("({};{})", prices.join(" "), sizes.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_symbol() {
        assert_eq!(normalize_symbol("BTC-USD"), "BTCUSD");
        assert_eq!(normalize_symbol("XBT/USD"), "XBTUSD");
        assert_eq!(normalize_symbol("btcusd"), "BTCUSD");
        assert_eq!(normalize_symbol("ETH_USD"), "ETHUSD");
    }

    #[test]
    fn test_format_timestamp() {
        use chrono::TimeZone;
        let dt = Utc.with_ymd_and_hms(2026, 3, 14, 12, 30, 45).unwrap();
        let ts = format_timestamp(&dt);
        assert!(ts.starts_with("2026.03.14D12:30:45"));
    }

    #[test]
    fn test_serialize_levels_empty() {
        let levels: Vec<PriceLevel> = vec![];
        assert_eq!(serialize_levels(&levels), "(`float$();`float$())");
    }

    #[test]
    fn test_serialize_levels() {
        let levels = vec![
            PriceLevel {
                price: 50000.0,
                quantity: 1.5,
            },
            PriceLevel {
                price: 49999.5,
                quantity: 2.3,
            },
        ];
        let result = serialize_levels(&levels);
        assert_eq!(result, "(50000 49999.5;1.5 2.3)");
    }
}
