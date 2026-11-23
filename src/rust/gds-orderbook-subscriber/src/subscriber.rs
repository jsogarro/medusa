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
    pub fn new(config: ExchangeConfig, publisher: KdbPublisher, health_timeout: Duration) -> Self {
        Self {
            config,
            publisher,
            health_timeout,
        }
    }

    /// Run the subscriber (outer reconnect loop)
    pub async fn run(&mut self) -> Result<()> {
        let mut backoff = ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(60));

        loop {
            info!("Connecting to {} WebSocket", self.config.name);

            // The loop returns Ok when the server closes, the stream ends or the
            // connection goes stale; every exit means the book has stopped updating.
            match self.subscribe_loop().await {
                Ok(()) => warn!("{} connection ended, reconnecting", self.config.name),
                Err(e) => error!("{} subscriber error: {}", self.config.name, e),
            }
            let delay = backoff.next_delay();
            warn!("Reconnecting in {:?}", delay);
            tokio::time::sleep(delay).await;
        }
    }

    /// Single WebSocket connection lifecycle
    async fn subscribe_loop(&mut self) -> Result<()> {
        // Create exchange adapter
        let adapter = create_adapter(
            &self.config.name,
            &self.config.ws_url,
            &self.config.rest_url,
        )
        .with_context(|| format!("Failed to create adapter for {}", self.config.name))?;

        // Connect to WebSocket
        let (ws_stream, _) = connect_async(&self.config.ws_url)
            .await
            .with_context(|| format!("Failed to connect to {} WebSocket", self.config.name))?;

        info!("{} WebSocket connected", self.config.name);

        let (mut write, mut read) = ws_stream.split();

        // Subscribe to WebSocket orderbook channels
        for symbol in &self.config.symbols {
            let sub_msg = adapter.build_subscribe_message(std::slice::from_ref(symbol));
            if !sub_msg.is_empty() {
                debug!("Subscribing to {} {}", self.config.name, symbol);
                write.send(Message::Text(sub_msg)).await?;
            } else {
                warn!(
                    "{} generated empty subscribe message for {}",
                    self.config.name, symbol
                );
            }
        }

        // Bootstrap orderbooks via REST (ONE-TIME snapshot per symbol). This runs after
        // subscribing: diffs that arrive meanwhile queue on the socket and are applied
        // below with the venue's ordering rule, so none is lost between snapshot and
        // subscription (Bitstamp sends no snapshot on subscribe).
        info!("Bootstrapping orderbooks via REST for {}", self.config.name);
        let mut state = OrderbookState::new();
        self.bootstrap_orderbooks(adapter.as_ref(), &mut state)
            .await?;

        // Health monitor
        let mut health = HealthMonitor::new(self.health_timeout);
        health.mark_healthy();

        // Message processing loop
        loop {
            // Bound the wait by the health deadline: a feed that goes silent
            // never yields a message to check staleness against.
            let Ok(next) = tokio::time::timeout(health.remaining(), read.next()).await else {
                warn!(
                    "{} connection stale (no messages in {:?})",
                    self.config.name, self.health_timeout
                );
                break;
            };
            let Some(msg_result) = next else { break };
            health.reset_timer();
            match msg_result {
                Ok(Message::Text(text)) => {
                    match adapter.parse_message(&text) {
                        Ok(ExchangeMessage::Snapshot {
                            symbol,
                            bids,
                            asks,
                            sequence,
                        }) => {
                            debug!(
                                "{} snapshot for {}: {} bids, {} asks",
                                self.config.name,
                                symbol,
                                bids.len(),
                                asks.len()
                            );
                            state.apply_snapshot(&symbol, bids, asks, sequence);
                            self.publish_orderbook(&state, &symbol).await?;
                        }
                        Ok(ExchangeMessage::Delta {
                            symbol,
                            bids,
                            asks,
                            first_sequence,
                            sequence,
                        }) => {
                            debug!(
                                "{} delta for {}: {} bids, {} asks, seq={}",
                                self.config.name,
                                symbol,
                                bids.len(),
                                asks.len(),
                                sequence
                            );

                            // Apply delta with sequence validation
                            if let Err(e) =
                                state.apply_update(&symbol, bids, asks, first_sequence, sequence)
                            {
                                warn!("{} sequence gap for {}: {}", self.config.name, symbol, e);
                                // Rebootstrap this symbol
                                self.rebootstrap_symbol(adapter.as_ref(), &mut state, &symbol)
                                    .await?;
                            }

                            self.publish_orderbook(&state, &symbol).await?;
                        }
                        Ok(ExchangeMessage::Gap) => {
                            warn!(
                                "{} message sequence gap, reconnecting to resync",
                                self.config.name
                            );
                            break;
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
            match adapter
                .fetch_snapshot(symbol)
                .await
                .with_context(|| format!("Failed to bootstrap {} for {}", symbol, self.config.name))
            {
                Ok(snapshot) => {
                    info!(
                        "{} bootstrapped {}: {} bids, {} asks",
                        self.config.name,
                        snapshot.symbol,
                        snapshot.bids.len(),
                        snapshot.asks.len()
                    );
                    state.apply_snapshot(
                        &snapshot.symbol,
                        snapshot.bids,
                        snapshot.asks,
                        snapshot.sequence,
                    );
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
        let snapshot = adapter.fetch_snapshot(symbol).await.with_context(|| {
            format!("Failed to rebootstrap {} for {}", symbol, self.config.name)
        })?;
        state.apply_snapshot(
            &snapshot.symbol,
            snapshot.bids,
            snapshot.asks,
            snapshot.sequence,
        );
        self.publish_orderbook(state, &snapshot.symbol).await?;
        Ok(())
    }

    /// Publish orderbook to Tickerplant
    async fn publish_orderbook(&mut self, state: &OrderbookState, symbol: &str) -> Result<()> {
        if let Some(ob) = state.get_snapshot(symbol, &self.config.name, 25) {
            self.publisher
                .publish_orderbook(&ob)
                .await
                .with_context(|| {
                    format!(
                        "Failed to publish {} {} orderbook to Tickerplant",
                        self.config.name, symbol
                    )
                })?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn reconnects_after_server_close_frame() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        tokio::spawn(async move {
            // Scripted exchange: accept, complete the handshake, close immediately.
            while let Ok((sock, _)) = listener.accept().await {
                if let Ok(mut ws) = tokio_tungstenite::accept_async(sock).await {
                    let _ = ws.close(None).await;
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
        let mut sub = ExchangeSubscriber::new(config, publisher, Duration::from_secs(30));
        let run = tokio::spawn(async move { sub.run().await });

        rx.recv().await.expect("first connection");
        let second = tokio::time::timeout(Duration::from_secs(10), rx.recv()).await;
        run.abort();
        assert!(
            matches!(second, Ok(Some(()))),
            "subscriber must reconnect after a Close frame"
        );
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
        let mut sub = ExchangeSubscriber::new(config, publisher, Duration::from_millis(200));
        let run = tokio::spawn(async move { sub.run().await });

        rx.recv().await.expect("first connection");
        let second = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await;
        run.abort();
        assert!(
            matches!(second, Ok(Some(()))),
            "a feed that goes silent must be treated as a lost connection"
        );
    }

    #[tokio::test]
    async fn subscribes_before_fetching_the_rest_snapshot() {
        use futures_util::StreamExt;
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        let ws = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let ws_port = ws.local_addr().unwrap().port();
        let ws_tx = tx.clone();
        tokio::spawn(async move {
            while let Ok((sock, _)) = ws.accept().await {
                if let Ok(mut s) = tokio_tungstenite::accept_async(sock).await {
                    if let Some(Ok(Message::Text(_))) = s.next().await {
                        let _ = ws_tx.send("subscribe");
                    }
                    std::future::pending::<()>().await;
                }
            }
        });
        let rest = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let rest_port = rest.local_addr().unwrap().port();
        tokio::spawn(async move {
            while let Ok((mut sock, _)) = rest.accept().await {
                let mut buf = [0u8; 1024];
                let _ = sock.read(&mut buf).await;
                let _ = tx.send("snapshot");
                let body =
                    r#"{"timestamp":1,"microtimestamp":"1","bids":[["1","1"]],"asks":[["2","1"]]}"#;
                let _ = sock
                    .write_all(
                        format!(
                            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
                            body.len(),
                            body
                        )
                        .as_bytes(),
                    )
                    .await;
            }
        });

        let config = ExchangeConfig {
            name: "bitstamp".to_string(),
            ws_url: format!("ws://127.0.0.1:{}", ws_port),
            rest_url: format!("http://127.0.0.1:{}", rest_port),
            symbols: vec!["btcusd".to_string()],
            enabled: true,
        };
        let publisher = KdbPublisher::lazy("127.0.0.1", 1, "", "");
        let mut sub = ExchangeSubscriber::new(config, publisher, Duration::from_secs(30));
        let run = tokio::spawn(async move { sub.run().await });

        let first = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await;
        run.abort();
        assert!(
            matches!(first, Ok(Some("subscribe"))),
            "diffs sent between the snapshot and the subscription are lost unless the \
             subscription comes first, got {first:?}"
        );
    }
}
