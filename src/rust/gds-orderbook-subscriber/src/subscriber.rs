//! Exchange subscriber - manages WebSocket connection, bootstrap, and publishing

use crate::exchange_adapter::{create_adapter, ExchangeAdapter, ExchangeMessage};
use crate::orderbook_state::OrderbookState;
use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use gds_common::{ExchangeConfig, ExponentialBackoff, HealthMonitor, KdbPublisher};
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

/// Exchange subscriber for orderbook data
pub struct ExchangeSubscriber {
    config: ExchangeConfig,
    publisher: KdbPublisher,
    health_timeout: Duration,
}

impl ExchangeSubscriber {
    /// Create a new exchange subscriber
    pub fn new(
        config: ExchangeConfig,
        publisher: KdbPublisher,
        health_timeout: Duration,
    ) -> Self {
        Self {
            config,
            publisher,
            health_timeout,
        }
    }

    /// Run the subscriber (outer reconnect loop)
    pub async fn run(&mut self) -> Result<()> {
        let mut backoff = ExponentialBackoff::new(
            Duration::from_secs(1),
            Duration::from_secs(60),
        );

        loop {
            info!("Connecting to {} WebSocket", self.config.name);

            match self.subscribe_loop().await {
                Ok(_) => {
                    info!("{} subscriber completed normally", self.config.name);
                    break;
                }
                Err(e) => {
                    error!("{} subscriber error: {}", self.config.name, e);
                    let delay = backoff.next_delay();
                    warn!("Reconnecting in {:?}", delay);
                    tokio::time::sleep(delay).await;
                }
            }
        }

        Ok(())
    }

    /// Single WebSocket connection lifecycle
    async fn subscribe_loop(&mut self) -> Result<()> {
        // Create exchange adapter
        let adapter = create_adapter(&self.config.name, &self.config.ws_url, &self.config.rest_url)
            .with_context(|| format!("Failed to create adapter for {}", self.config.name))?;

        // Connect to WebSocket
        let (ws_stream, _) = connect_async(&self.config.ws_url)
            .await
            .with_context(|| format!("Failed to connect to {} WebSocket", self.config.name))?;

        info!("{} WebSocket connected", self.config.name);

        let (mut write, mut read) = ws_stream.split();

        // Bootstrap orderbooks via REST (ONE-TIME snapshot per symbol)
        info!("Bootstrapping orderbooks via REST for {}", self.config.name);
        let mut state = OrderbookState::new();
        self.bootstrap_orderbooks(adapter.as_ref(), &mut state).await?;

        // Subscribe to WebSocket orderbook channels
        for symbol in &self.config.symbols {
            let sub_msg = adapter.build_subscribe_message(std::slice::from_ref(symbol));
            if !sub_msg.is_empty() {
                debug!("Subscribing to {} {}", self.config.name, symbol);
                write.send(Message::Text(sub_msg)).await?;
            } else {
                warn!("{} generated empty subscribe message for {}", self.config.name, symbol);
            }
        }

        // Health monitor
        let mut health = HealthMonitor::new(self.health_timeout);
        health.mark_healthy();

        // Message processing loop
        while let Some(msg_result) = read.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    health.reset_timer();

                    match adapter.parse_message(&text) {
                        Ok(ExchangeMessage::Snapshot { symbol, bids, asks, sequence }) => {
                            debug!("{} snapshot for {}: {} bids, {} asks",
                                self.config.name, symbol, bids.len(), asks.len());
                            state.apply_snapshot(&symbol, bids, asks, sequence);
                            self.publish_orderbook(&state, &symbol).await?;
                        }
                        Ok(ExchangeMessage::Delta { symbol, bids, asks, sequence }) => {
                            debug!("{} delta for {}: {} bids, {} asks, seq={}",
                                self.config.name, symbol, bids.len(), asks.len(), sequence);

                            // Apply delta with sequence validation
                            if let Err(e) = state.apply_delta(&symbol, bids, asks, sequence) {
                                warn!("{} sequence gap for {}: {}", self.config.name, symbol, e);
                                // Rebootstrap this symbol
                                self.rebootstrap_symbol(adapter.as_ref(), &mut state, &symbol).await?;
                            }

                            self.publish_orderbook(&state, &symbol).await?;
                        }
                        Ok(ExchangeMessage::Heartbeat) => {
                            debug!("{} heartbeat", self.config.name);
                        }
                        Ok(ExchangeMessage::Other) => {
                            // Ignore other message types
                        }
                        Err(e) => {
                            warn!("{} failed to parse message: {}", self.config.name, e);
                        }
                    }
                }
                Ok(Message::Ping(data)) => {
                    debug!("{} ping", self.config.name);
                    write.send(Message::Pong(data)).await?;
                }
                Ok(Message::Pong(_)) => {
                    debug!("{} pong", self.config.name);
                }
                Ok(Message::Close(_)) => {
                    info!("{} server closed connection", self.config.name);
                    break;
                }
                Ok(Message::Binary(_)) => {
                    // Ignore binary messages
                }
                Ok(Message::Frame(_)) => {
                    // Ignore frame messages
                }
                Err(e) => {
                    error!("{} WebSocket error: {}", self.config.name, e);
                    break;
                }
            }

            // Health check
            if health.is_stale() {
                warn!("{} connection stale (no messages in {:?})",
                    self.config.name, self.health_timeout);
                break;
            }
        }

        info!("{} WebSocket connection closed", self.config.name);
        Ok(())
    }

    /// Bootstrap all symbols via REST
    async fn bootstrap_orderbooks(
        &mut self,
        adapter: &dyn ExchangeAdapter,
        state: &mut OrderbookState,
    ) -> Result<()> {
        let symbols = self.config.symbols.clone();
        for symbol in &symbols {
            match adapter.fetch_snapshot(symbol).await
                .with_context(|| format!("Failed to bootstrap {} for {}", symbol, self.config.name)) {
                Ok(snapshot) => {
                    info!("{} bootstrapped {}: {} bids, {} asks",
                        self.config.name, snapshot.symbol,
                        snapshot.bids.len(), snapshot.asks.len());
                    state.apply_snapshot(&snapshot.symbol, snapshot.bids, snapshot.asks, snapshot.sequence);
                    self.publish_orderbook(state, &snapshot.symbol).await?;
                }
                Err(e) => {
                    error!("{}", e);
                    // Continue with other symbols
                }
            }
        }
        Ok(())
    }

    /// Rebootstrap a single symbol after sequence gap
    async fn rebootstrap_symbol(
        &mut self,
        adapter: &dyn ExchangeAdapter,
        state: &mut OrderbookState,
        symbol: &str,
    ) -> Result<()> {
        info!("{} rebootstrapping {}", self.config.name, symbol);
        let snapshot = adapter.fetch_snapshot(symbol).await
            .with_context(|| format!("Failed to rebootstrap {} for {}", symbol, self.config.name))?;
        state.apply_snapshot(&snapshot.symbol, snapshot.bids, snapshot.asks, snapshot.sequence);
        self.publish_orderbook(state, &snapshot.symbol).await?;
        Ok(())
    }

    /// Publish orderbook to Tickerplant
    async fn publish_orderbook(&mut self, state: &OrderbookState, symbol: &str) -> Result<()> {
        if let Some(ob) = state.get_snapshot(symbol, &self.config.name, 25) {
            self.publisher.publish_orderbook(&ob).await
                .with_context(|| format!("Failed to publish {} {} orderbook to Tickerplant", self.config.name, symbol))?;
        }
        Ok(())
    }
}
