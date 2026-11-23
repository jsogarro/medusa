//! Core trade subscription logic
//!
//! TradeSubscriber manages WebSocket connection to an exchange, handles
//! reconnection with exponential backoff, deduplicates trades, and publishes
//! to the Tickerplant.

use crate::deduplicator::TradeDeduplicator;
use crate::exchange_adapter::{
    BitstampTradeAdapter, CoinbaseTradeAdapter, KrakenTradeAdapter, NormalizedTrade, TradeAdapter,
};
use anyhow::{Context, Result};
use exchange_connector::types::Trade;
use futures_util::{SinkExt, StreamExt};
use gds_common::{ExchangeConfig, ExponentialBackoff, HealthMonitor, KdbPublisher};
use std::sync::Arc;
use std::time::Duration;
use tokio::time;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};

/// Trade subscriber for a single exchange
pub struct TradeSubscriber {
    config: ExchangeConfig,
    publisher: KdbPublisher,
    health_monitor: HealthMonitor,
    backoff: ExponentialBackoff,
    deduplicator: TradeDeduplicator,
    adapter: Arc<dyn TradeAdapter>,
    backfill_enabled: bool,
    /// Trades sent (or still to be sent) but not yet confirmed by the Tickerplant.
    /// They are resent with the next batch and recorded as seen only once confirmed.
    pending: Vec<Trade>,
}

/// Unconfirmed trades kept for resending; beyond this the oldest are dropped.
const MAX_PENDING: usize = 10_000;

impl TradeSubscriber {
    /// Create a new trade subscriber
    pub fn new(
        config: ExchangeConfig,
        publisher: KdbPublisher,
        health_timeout: Duration,
        backfill_enabled: bool,
    ) -> Result<Self> {
        let adapter: Arc<dyn TradeAdapter> = match config.name.as_str() {
            "bitstamp" => Arc::new(BitstampTradeAdapter::new(config.rest_url.clone())),
            "coinbase" => Arc::new(CoinbaseTradeAdapter::new(config.rest_url.clone())),
            "kraken" => Arc::new(KrakenTradeAdapter::new(config.rest_url.clone())),
            _ => return Err(anyhow::anyhow!("Unknown exchange: {}", config.name)),
        };

        Ok(Self {
            config,
            publisher,
            health_monitor: HealthMonitor::new(health_timeout),
            backoff: ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(60)),
            deduplicator: TradeDeduplicator::default(),
            adapter,
            backfill_enabled,
            pending: Vec::new(),
        })
    }

    /// Returns the exchange name
    pub fn exchange_name(&self) -> &str {
        &self.config.name
    }

    /// Main run loop with reconnection
    pub async fn run(&mut self) -> Result<()> {
        loop {
            info!(
                "[{}] Connecting to WebSocket: {}",
                self.exchange_name(),
                self.config.ws_url
            );

            match self.subscribe_loop().await {
                Ok(()) => {
                    info!("[{}] Subscription ended normally", self.exchange_name());
                    self.backoff.reset();
                }
                Err(e) => {
                    error!("[{}] Subscription error: {}", self.exchange_name(), e);

                    // Publish alert to Tickerplant
                    let _ = self
                        .publisher
                        .publish_alert(
                            "error",
                            "trade_subscriber",
                            &format!("Connection failed: {}", e),
                            &self.config.name,
                            "",
                        )
                        .await;

                    let delay = self.backoff.next_delay();
                    warn!("[{}] Reconnecting in {:?}", self.exchange_name(), delay);
                    time::sleep(delay).await;
                }
            }

            self.health_monitor.mark_unhealthy();
        }
    }

    /// Subscribe to trade streams and process messages
    async fn subscribe_loop(&mut self) -> Result<()> {
        // Connect to WebSocket
        let (ws_stream, _response) = connect_async(&self.config.ws_url)
            .await
            .with_context(|| format!("Failed to connect to {} WebSocket", self.exchange_name()))?;

        let (mut write, mut read) = ws_stream.split();

        info!(
            "[{}] WebSocket connected, subscribing to {} symbols",
            self.exchange_name(),
            self.config.symbols.len()
        );

        // Build and send subscribe message
        let subscribe_msg = self.adapter.build_subscribe_message(&self.config.symbols);

        for line in subscribe_msg.lines() {
            if !line.is_empty() {
                write
                    .send(Message::Text(line.to_string()))
                    .await
                    .with_context(|| {
                        format!(
                            "Failed to send subscribe message to {}",
                            self.exchange_name()
                        )
                    })?;
                debug!("[{}] Sent subscribe: {}", self.exchange_name(), line);
            }
        }

        self.health_monitor.mark_healthy();
        info!("[{}] Subscribed successfully", self.exchange_name());

        // Backfill trades (optional, one-time)
        if self.backfill_enabled {
            self.backfill_trades().await?;
        }

        // Process messages
        loop {
            // Bound the wait by the health deadline: a feed that goes silent
            // never yields a message to check staleness against.
            let Ok(next) = time::timeout(self.health_monitor.remaining(), read.next()).await else {
                warn!(
                    "[{}] Connection stale (no data for {:?}), reconnecting",
                    self.exchange_name(),
                    self.health_monitor.timeout()
                );
                return Err(anyhow::anyhow!("Connection stale"));
            };
            let Some(msg_result) = next else { break };

            match msg_result {
                Ok(Message::Text(text)) => {
                    self.health_monitor.reset_timer();
                    self.process_message(&text).await;
                }
                Ok(Message::Ping(_)) | Ok(Message::Pong(_)) => {
                    self.health_monitor.reset_timer();
                }
                Ok(Message::Close(_)) => {
                    warn!("[{}] WebSocket closed by server", self.exchange_name());
                    return Err(anyhow::anyhow!("WebSocket closed"));
                }
                Err(e) => {
                    error!("[{}] WebSocket error: {}", self.exchange_name(), e);
                    return Err(e.into());
                }
                _ => {}
            }
        }

        Ok(())
    }

    /// Process a WebSocket message
    async fn process_message(&mut self, text: &str) {
        match self.adapter.parse_message(text) {
            Ok(trades) => self.publish_confirmed(trades).await,
            Err(e) => {
                // Not all messages are trades, so this is often expected
                debug!("[{}] Failed to parse message: {}", self.exchange_name(), e);
            }
        }
    }

    /// Queue new trades and publish everything unconfirmed. A trade is recorded as
    /// seen only once the Tickerplant has confirmed the batch; otherwise it stays
    /// queued and goes out again with the next batch.
    async fn publish_confirmed(&mut self, trades: Vec<NormalizedTrade>) {
        for normalized_trade in trades {
            let trade = normalized_trade.into_trade();
            if self.deduplicator.is_duplicate(&trade.id)
                || self.pending.iter().any(|p| p.id == trade.id)
            {
                debug!("[{}] Duplicate trade: {}", self.exchange_name(), trade.id);
                continue;
            }
            self.pending.push(trade);
        }
        if self.pending.is_empty() {
            return;
        }
        match self.publisher.publish_trades_confirmed(&self.pending).await {
            Ok(()) => {
                for trade in self.pending.drain(..) {
                    self.deduplicator.record(&trade.id);
                }
            }
            Err(e) => {
                error!(
                    "[{}] Failed to publish {} trades, will resend: {}",
                    self.exchange_name(),
                    self.pending.len(),
                    e
                );
                if self.pending.len() > MAX_PENDING {
                    let excess = self.pending.len() - MAX_PENDING;
                    warn!(
                        "[{}] Dropping {} oldest unconfirmed trades",
                        self.exchange_name(),
                        excess
                    );
                    self.pending.drain(..excess);
                }
            }
        }
    }

    /// Backfill recent trades via REST (one-time on startup)
    async fn backfill_trades(&mut self) -> Result<()> {
        info!("[{}] Backfilling recent trades", self.exchange_name());

        let symbols = self.config.symbols.clone();
        for symbol in &symbols {
            match self
                .adapter
                .fetch_recent_trades(symbol, 100)
                .await
                .with_context(|| {
                    format!(
                        "Failed to backfill trades for {} {}",
                        self.exchange_name(),
                        symbol
                    )
                }) {
                Ok(trades) => {
                    info!(
                        "[{}] Backfilled {} trades for {}",
                        self.exchange_name(),
                        trades.len(),
                        symbol
                    );

                    self.publish_confirmed(trades).await;
                }
                Err(e) => {
                    warn!("{}", e);
                    // Continue with other symbols
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BITSTAMP_TRADE: &str = r#"{"event":"trade","channel":"live_trades_btcusd","data":{"id":123456,"amount":0.5,"price":50000.0,"type":0,"timestamp":"1640000000"}}"#;

    fn subscriber(tp_port: u16) -> TradeSubscriber {
        let config = ExchangeConfig {
            name: "bitstamp".to_string(),
            ws_url: "ws://127.0.0.1:1".to_string(),
            rest_url: "http://127.0.0.1:1".to_string(),
            symbols: vec![],
            enabled: true,
        };
        let publisher = KdbPublisher::lazy("127.0.0.1", tp_port, "", "");
        TradeSubscriber::new(config, publisher, Duration::from_secs(30), false).unwrap()
    }

    #[tokio::test]
    async fn failed_publish_does_not_mark_trade_as_seen() {
        // Nothing listens on port 1: the publish fails.
        let mut sub = subscriber(1);
        sub.process_message(BITSTAMP_TRADE).await;
        assert!(
            !sub.deduplicator.is_duplicate("123456"),
            "a trade that was not published must stay eligible for redelivery"
        );
    }

    /// Fake Tickerplant: handshake, then counts async messages and answers every
    /// sync one with a boolean atom, as q does.
    async fn serving_tp(port: u16) -> (u16, std::sync::Arc<std::sync::atomic::AtomicUsize>) {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", port))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let asyncs = std::sync::Arc::new(AtomicUsize::new(0));
        let counter = asyncs.clone();
        tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
            }
            sock.write_all(&[3]).await.unwrap();
            loop {
                let mut header = [0u8; 8];
                if sock.read_exact(&mut header).await.is_err() {
                    return;
                }
                let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
                let mut body = vec![0u8; len - 8];
                if sock.read_exact(&mut body).await.is_err() {
                    return;
                }
                if header[1] == 1 {
                    sock.write_all(&[1, 2, 0, 0, 10, 0, 0, 0, 0xff, 1])
                        .await
                        .unwrap();
                } else {
                    counter.fetch_add(1, Ordering::SeqCst);
                }
            }
        });
        (port, asyncs)
    }

    #[tokio::test]
    async fn successful_publish_marks_trade_as_seen() {
        let (port, _asyncs) = serving_tp(0).await;
        let mut sub = subscriber(port);
        sub.process_message(BITSTAMP_TRADE).await;
        assert!(sub.deduplicator.is_duplicate("123456"));
    }

    #[tokio::test]
    async fn trade_written_to_a_dead_tickerplant_is_resent_after_reconnect() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        // Tickerplant that logs the publisher in and then dies: the first async
        // write still "succeeds", so the trade must not be recorded as seen.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let dying = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
            }
            sock.write_all(&[3]).await.unwrap();
        });
        let mut sub = subscriber(port);
        sub.publisher = KdbPublisher::connect("127.0.0.1", port, "", "")
            .await
            .unwrap();
        dying.await.unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;

        sub.process_message(BITSTAMP_TRADE).await;
        assert!(
            !sub.deduplicator.is_duplicate("123456"),
            "a trade the tickerplant never confirmed must not be recorded as seen"
        );

        // The tickerplant comes back: the unconfirmed trade goes out again with the next one.
        let (_, asyncs) = serving_tp(port).await;
        let next = BITSTAMP_TRADE.replace("123456", "123457");
        sub.process_message(&next).await;
        assert_eq!(asyncs.load(std::sync::atomic::Ordering::SeqCst), 2);
        assert!(sub.deduplicator.is_duplicate("123456"));
        assert!(sub.deduplicator.is_duplicate("123457"));
    }

    #[tokio::test]
    async fn reconnects_when_server_goes_silent() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        tokio::spawn(async move {
            // Scripted exchange: complete the handshake, then never send a frame.
            let mut held = Vec::new();
            while let Ok((sock, _)) = listener.accept().await {
                if let Ok(ws) = tokio_tungstenite::accept_async(sock).await {
                    held.push(ws);
                    let _ = tx.send(());
                }
            }
        });

        let config = ExchangeConfig {
            name: "bitstamp".to_string(),
            ws_url: format!("ws://127.0.0.1:{}", port),
            rest_url: "http://127.0.0.1:1".to_string(),
            symbols: vec![],
            enabled: true,
        };
        let publisher = KdbPublisher::lazy("127.0.0.1", 1, "", "");
        let mut sub =
            TradeSubscriber::new(config, publisher, Duration::from_millis(200), false).unwrap();
        let run = tokio::spawn(async move { sub.run().await });

        rx.recv().await.expect("first connection");
        let second = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await;
        run.abort();
        assert!(
            matches!(second, Ok(Some(()))),
            "a feed that goes silent must be treated as a lost connection"
        );
    }
}
