//! Alpaca-specific trade subscriber
//!
//! Alpaca diverges from the TradeAdapter pattern because the upstream
//! `exchange_connector::feeds::AlpacaFeed` already emits typed messages
//! (`AlpacaFeedMessage::{Trade, OrderBook, Error}`) rather than raw WebSocket
//! text frames. This subscriber consumes those typed messages directly,
//! deduplicates trades by id, and publishes to the Tickerplant alongside the
//! other exchanges.

use crate::deduplicator::TradeDeduplicator;
use anyhow::{Context, Result};
use exchange_connector::feeds::alpaca::{AlpacaFeed, AlpacaFeedMessage};
use gds_common::{ExchangeConfig, ExponentialBackoff, HealthMonitor, KdbPublisher};
use std::time::Duration;
use tokio::time;
use tracing::{debug, error, info, warn};

pub struct AlpacaTradeSubscriber {
    config: ExchangeConfig,
    publisher: KdbPublisher,
    health_monitor: HealthMonitor,
    backoff: ExponentialBackoff,
    deduplicator: TradeDeduplicator,
}

impl AlpacaTradeSubscriber {
    pub fn new(config: ExchangeConfig, publisher: KdbPublisher, health_timeout: Duration) -> Self {
        Self {
            config,
            publisher,
            health_monitor: HealthMonitor::new(health_timeout),
            backoff: ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(60)),
            deduplicator: TradeDeduplicator::default(),
        }
    }

    pub fn exchange_name(&self) -> &str {
        &self.config.name
    }

    pub async fn run(&mut self) -> Result<()> {
        loop {
            info!(
                "[{}] Starting Alpaca feed ({} symbols)",
                self.exchange_name(),
                self.config.symbols.len()
            );

            match self.subscribe_loop().await {
                Ok(()) => {
                    info!("[{}] Subscription ended normally", self.exchange_name());
                    self.backoff.reset();
                }
                Err(e) => {
                    error!("[{}] Subscription error: {}", self.exchange_name(), e);

                    let _ = self
                        .publisher
                        .publish_alert(
                            "error",
                            "alpaca_subscriber",
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

    async fn subscribe_loop(&mut self) -> Result<()> {
        let (mut feed, mut rx) = AlpacaFeed::new()
            .await
            .with_context(|| "Failed to construct AlpacaFeed (check ALPACA_API_KEY/SECRET_KEY)")?;

        feed.subscribe_trades(self.config.symbols.clone())
            .await
            .with_context(|| "Failed to subscribe to Alpaca trades")?;

        self.health_monitor.mark_healthy();
        info!("[{}] Subscribed successfully", self.exchange_name());

        while let Some(msg) = rx.recv().await {
            if self.health_monitor.is_stale() {
                warn!(
                    "[{}] Feed stale (no data for {:?}), reconnecting",
                    self.exchange_name(),
                    self.health_monitor.timeout()
                );
                return Err(anyhow::anyhow!("Feed stale"));
            }

            self.health_monitor.reset_timer();

            match msg {
                AlpacaFeedMessage::Trade(trade) => {
                    if self.deduplicator.is_duplicate(&trade.id) {
                        debug!("[{}] Duplicate trade: {}", self.exchange_name(), trade.id);
                        continue;
                    }
                    self.deduplicator.record(&trade.id);

                    if let Err(e) = self.publisher.publish_trade(&trade).await {
                        error!(
                            "[{}] Failed to publish trade {}: {}",
                            self.exchange_name(),
                            trade.id,
                            e
                        );
                    } else {
                        debug!(
                            "[{}] Published trade: {} @ {} x {}",
                            self.exchange_name(),
                            trade.id,
                            trade.price,
                            trade.quantity
                        );
                    }
                }
                AlpacaFeedMessage::OrderBook(ob) => {
                    if let Err(e) = self.publisher.publish_orderbook(&ob).await {
                        error!(
                            "[{}] Failed to publish orderbook for {}: {}",
                            self.exchange_name(),
                            ob.pair,
                            e
                        );
                    } else {
                        debug!(
                            "[{}] Published orderbook: {} bid={} ask={}",
                            self.exchange_name(),
                            ob.pair,
                            ob.bids.first().map(|l| l.price).unwrap_or(0.0),
                            ob.asks.first().map(|l| l.price).unwrap_or(0.0),
                        );
                    }
                }
                AlpacaFeedMessage::Error(e) => {
                    warn!("[{}] Feed error: {}", self.exchange_name(), e);
                    return Err(anyhow::anyhow!("Alpaca feed error: {}", e));
                }
            }
        }

        Ok(())
    }
}
