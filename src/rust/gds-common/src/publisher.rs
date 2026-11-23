//! kdb+ Tickerplant publisher
//!
//! Wraps KdbClient for publishing market data to the Tickerplant
//! via `.u.upd` IPC calls. Messages are typed kdb+ objects
//! (`(`.u.upd;`table;data)`), never q source text, so feed-supplied strings
//! cannot be evaluated by the Tickerplant. Uses async fire-and-forget for
//! throughput and re-dials the Tickerplant with backoff after a failure.

use crate::backoff::ExponentialBackoff;
use anyhow::{bail, Context, Result};
use chrono::{DateTime, Utc};
use exchange_connector::types::{OrderBook, PriceLevel, Side, Trade};
use kdb_ipc::types::KObject;
use kdb_ipc::KdbClient;
use std::time::{Duration, Instant};
use tracing::{debug, info, warn};

/// Upper bound on a single (re)connect attempt.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

/// Publisher that sends market data to kdb+ Tickerplant via `.u.upd`.
pub struct KdbPublisher {
    host: String,
    port: u16,
    user: String,
    password: String,
    client: Option<KdbClient>,
    backoff: ExponentialBackoff,
    /// Earliest time the next reconnect may be attempted (None = now).
    retry_at: Option<Instant>,
}

impl KdbPublisher {
    /// Connect to the Tickerplant.
    pub async fn connect(host: &str, port: u16, user: &str, password: &str) -> Result<Self> {
        let client = KdbClient::connect(host, port, user, password)
            .await
            .context("Failed to connect to Tickerplant")?;

        info!("Connected to Tickerplant at {}:{}", host, port);
        let mut publisher = Self::lazy(host, port, user, password);
        publisher.client = Some(client);
        Ok(publisher)
    }

    /// Create a publisher that dials the Tickerplant on first publish.
    pub fn lazy(host: &str, port: u16, user: &str, password: &str) -> Self {
        Self {
            host: host.to_string(),
            port,
            user: user.to_string(),
            password: password.to_string(),
            client: None,
            backoff: ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(30)),
            retry_at: None,
        }
    }

    /// Publish an orderbook snapshot to the Tickerplant.
    pub async fn publish_orderbook(&mut self, ob: &OrderBook) -> Result<()> {
        let sym = normalize_symbol(&ob.pair);
        let sequence = ob.sequence.unwrap_or(0);

        // Compute mid price
        let mid = match (ob.bids.first(), ob.asks.first()) {
            (Some(bid), Some(ask)) => (bid.price + ask.price) / 2.0,
            _ => 0.0f64,
        };
        let msg = upd(
            "orderbook",
            &["time", "exchange", "sym", "bids", "asks", "sequence", "mid"],
            vec![
                KObject::TimestampList(vec![timestamp_nanos(&ob.timestamp)]),
                KObject::SymbolList(vec![ob.exchange.clone()]),
                KObject::SymbolList(vec![sym.clone()]),
                KObject::MixedList(vec![levels(&ob.bids)?]),
                KObject::MixedList(vec![levels(&ob.asks)?]),
                KObject::LongList(vec![i64::try_from(sequence).unwrap_or(i64::MAX)]),
                KObject::FloatList(vec![finite(mid)?]),
            ],
        );

        debug!(
            "Publishing orderbook: {} {} seq={}",
            ob.exchange, sym, sequence
        );
        self.send(msg).await
    }

    /// Publish a trade to the Tickerplant.
    pub async fn publish_trade(&mut self, trade: &Trade) -> Result<()> {
        let sym = normalize_symbol(&trade.pair);
        let side = match trade.side {
            Side::Buy => "buy",
            Side::Sell => "sell",
        };
        let msg = upd(
            "trade",
            &[
                "time", "exchange", "sym", "tradeId", "price", "size", "side", "notional",
            ],
            vec![
                KObject::TimestampList(vec![timestamp_nanos(&trade.timestamp)]),
                KObject::SymbolList(vec![trade.exchange.clone()]),
                KObject::SymbolList(vec![sym.clone()]),
                KObject::SymbolList(vec![trade.id.clone()]),
                KObject::FloatList(vec![finite(trade.price)?]),
                KObject::FloatList(vec![finite(trade.quantity)?]),
                KObject::SymbolList(vec![side.to_string()]),
                KObject::FloatList(vec![finite(trade.price * trade.quantity)?]),
            ],
        );

        debug!(
            "Publishing trade: {} {} id={}",
            trade.exchange, sym, trade.id
        );
        self.send(msg).await
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
        let msg = upd(
            "gds_alert",
            &["time", "severity", "source", "message", "exchange", "sym"],
            vec![
                KObject::TimestampList(vec![timestamp_nanos(&Utc::now())]),
                KObject::SymbolList(vec![severity.to_string()]),
                KObject::SymbolList(vec![source.to_string()]),
                KObject::SymbolList(vec![message.to_string()]),
                KObject::SymbolList(vec![exchange.to_string()]),
                KObject::SymbolList(vec![symbol.to_string()]),
            ],
        );

        self.send(msg).await
    }

    /// Send an async message (fire-and-forget), re-dialing the Tickerplant first
    /// if the previous connection failed. A failed send drops the connection so
    /// the next publish starts from a fresh one.
    async fn send(&mut self, msg: KObject) -> Result<()> {
        if self.client.is_none() {
            self.reconnect().await?;
        }
        let Some(client) = self.client.as_mut() else {
            bail!("Not connected to Tickerplant");
        };
        if let Err(e) = client.send_async(msg).await {
            self.client = None;
            return Err(anyhow::anyhow!("Failed to publish to TP: {}", e));
        }
        Ok(())
    }

    async fn reconnect(&mut self) -> Result<()> {
        if let Some(at) = self.retry_at {
            if Instant::now() < at {
                bail!("Tickerplant unavailable, waiting to reconnect");
            }
        }
        let attempt = tokio::time::timeout(
            CONNECT_TIMEOUT,
            KdbClient::connect(&self.host, self.port, &self.user, &self.password),
        )
        .await;
        match attempt {
            Ok(Ok(client)) => {
                info!("Reconnected to Tickerplant at {}:{}", self.host, self.port);
                self.client = Some(client);
                self.retry_at = None;
                self.backoff.reset();
                Ok(())
            }
            other => {
                let delay = self.backoff.next_delay();
                self.retry_at = Some(Instant::now() + delay);
                let reason = match other {
                    Ok(Err(e)) => e.to_string(),
                    _ => "connect timed out".to_string(),
                };
                warn!(
                    "Tickerplant reconnect failed ({}), retrying in {:?}",
                    reason, delay
                );
                bail!("Failed to reconnect to Tickerplant: {}", reason)
            }
        }
    }
}

/// `(`.u.upd;`table;data)` with `data` a one-row table of typed columns.
fn upd(table: &str, columns: &[&str], data: Vec<KObject>) -> KObject {
    KObject::MixedList(vec![
        KObject::Symbol(".u.upd".to_string()),
        KObject::Symbol(table.to_string()),
        KObject::Table(columns.iter().map(|c| c.to_string()).collect(), data),
    ])
}

/// kdb+ timestamp (ns since 2000-01-01) for a UTC time.
fn timestamp_nanos(dt: &DateTime<Utc>) -> i64 {
    match KObject::from_datetime(*dt) {
        KObject::Timestamp(n) => n,
        _ => unreachable!("from_datetime returns a Timestamp"),
    }
}

/// Reject NaN and infinities: q has no safe stand-in for them in price columns.
fn finite(v: f64) -> Result<f64> {
    if v.is_finite() {
        Ok(v)
    } else {
        bail!("Refusing to publish non-finite value {}", v)
    }
}

/// Normalize exchange-specific symbols to a canonical form.
/// e.g., "BTC-USD" -> "BTCUSD", "XBT/USD" -> "XBTUSD", "btcusd" -> "BTCUSD"
fn normalize_symbol(pair: &str) -> String {
    pair.replace(['-', '/', '_'], "").to_uppercase()
}

/// One side of the book as `(prices;sizes)`, both float lists.
fn levels(levels: &[PriceLevel]) -> Result<KObject> {
    let prices = levels
        .iter()
        .map(|l| finite(l.price))
        .collect::<Result<_>>()?;
    let sizes = levels
        .iter()
        .map(|l| finite(l.quantity))
        .collect::<Result<_>>()?;
    Ok(KObject::MixedList(vec![
        KObject::FloatList(prices),
        KObject::FloatList(sizes),
    ]))
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

    /// Fake Tickerplant: completes the kdb+ handshake, then returns the payload
    /// (message bytes after the 8-byte header) of the first IPC message it receives.
    async fn fake_tp() -> (u16, tokio::task::JoinHandle<String>) {
        fake_tp_on(0).await
    }

    async fn fake_tp_on(port: u16) -> (u16, tokio::task::JoinHandle<String>) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", port))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
            }
            sock.write_all(&[3]).await.unwrap();
            let mut header = [0u8; 8];
            sock.read_exact(&mut header).await.unwrap();
            let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
            let mut body = vec![0u8; len - 8];
            sock.read_exact(&mut body).await.unwrap();
            body.iter().map(|b| format!("{:02x}", b)).collect()
        });
        (port, task)
    }

    fn sample_trade(id: &str, price: f64) -> Trade {
        use chrono::TimeZone;
        Trade {
            id: id.to_string(),
            pair: "BTC-USD".to_string(),
            exchange: "kraken".to_string(),
            price,
            quantity: 0.5,
            side: Side::Buy,
            timestamp: Utc.with_ymd_and_hms(2026, 3, 14, 12, 30, 45).unwrap(),
            is_maker: None,
        }
    }

    // Expected payloads are the bodies of `-8!(`.u.upd;`trade;tbl)` from a real q 4.1.
    // The hostile id stays a symbol atom inside a typed table; it is never evaluated.
    #[tokio::test]
    async fn publish_trade_sends_typed_upd_message() {
        let (port, tp) = fake_tp().await;
        let mut p = KdbPublisher::connect("127.0.0.1", port, "", "")
            .await
            .unwrap();
        p.publish_trade(&sample_trade("1;hostile`x", 100.0))
            .await
            .unwrap();
        assert_eq!(tp.await.unwrap(), "000003000000f52e752e75706400f57472616465006200630b000800000074696d650065786368616e67650073796d00747261646549640070726963650073697a650073696465006e6f74696f6e616c000000080000000c0001000000005228554368790b0b00010000006b72616b656e000b0001000000425443555344000b0001000000313b686f7374696c656078000900010000000000000000005940090001000000000000000000e03f0b0001000000627579000900010000000000000000004940");
    }

    #[tokio::test]
    async fn publish_orderbook_sends_typed_upd_message() {
        use chrono::TimeZone;
        let (port, tp) = fake_tp().await;
        let mut p = KdbPublisher::connect("127.0.0.1", port, "", "")
            .await
            .unwrap();
        let ob = OrderBook {
            pair: "BTC-USD".to_string(),
            exchange: "kraken".to_string(),
            bids: vec![
                PriceLevel {
                    price: 100.0,
                    quantity: 1.5,
                },
                PriceLevel {
                    price: 99.5,
                    quantity: 2.0,
                },
            ],
            asks: vec![PriceLevel {
                price: 101.0,
                quantity: 3.0,
            }],
            timestamp: Utc.with_ymd_and_hms(2026, 3, 14, 12, 30, 45).unwrap(),
            sequence: Some(7),
        };
        p.publish_orderbook(&ob).await.unwrap();
        assert_eq!(tp.await.unwrap(), "000003000000f52e752e75706400f56f72646572626f6f6b006200630b000700000074696d650065786368616e67650073796d00626964730061736b730073657175656e6365006d6964000000070000000c0001000000005228554368790b0b00010000006b72616b656e000b00010000004254435553440000000100000000000200000009000200000000000000000059400000000000e05840090002000000000000000000f83f00000000000000400000010000000000020000000900010000000000000000405940090001000000000000000000084007000100000007000000000000000900010000000000000000205940");
    }

    #[tokio::test]
    async fn publish_rejects_non_finite_numbers() {
        let (port, _tp) = fake_tp().await;
        let mut p = KdbPublisher::connect("127.0.0.1", port, "", "")
            .await
            .unwrap();
        assert!(p.publish_trade(&sample_trade("1", f64::NAN)).await.is_err());
        assert!(p
            .publish_trade(&sample_trade("1", f64::INFINITY))
            .await
            .is_err());
    }

    #[tokio::test]
    async fn publisher_reconnects_after_tickerplant_outage() {
        // Nothing listening: publish fails but the publisher stays usable.
        let probe = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let mut p = KdbPublisher::lazy("127.0.0.1", port, "", "");
        assert!(p.publish_trade(&sample_trade("1", 100.0)).await.is_err());

        // Tickerplant comes back on the same port; skip the backoff wait.
        let (_, tp) = fake_tp_on(port).await;
        p.retry_at = None;
        p.publish_trade(&sample_trade("1", 100.0)).await.unwrap();
        assert!(!tp.await.unwrap().is_empty());
    }
}
