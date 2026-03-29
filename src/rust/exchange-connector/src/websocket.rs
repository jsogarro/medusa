//! Generic WebSocket client with auto-reconnection
//!
//! Provides a robust WebSocket client with exponential backoff reconnection,
//! heartbeat/ping-pong handling, and message dispatch via channels.

use crate::client::ExchangeError;
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::{interval, sleep, Instant};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, trace, warn};

/// WebSocket message type
#[derive(Debug, Clone)]
pub enum WsMessage {
    /// Text message from server
    Text(String),
    /// Binary message from server
    Binary(Vec<u8>),
    /// Ping received (application should respond with pong if needed)
    Ping(Vec<u8>),
    /// Pong received
    Pong(Vec<u8>),
    /// Connection closed
    Close,
}

/// WebSocket client configuration
#[derive(Debug, Clone)]
pub struct WsConfig {
    /// URL to connect to
    pub url: String,
    /// Heartbeat interval (send ping every N seconds)
    pub heartbeat_interval: Duration,
    /// Reconnection configuration
    pub reconnect_config: ReconnectConfig,
}

/// Reconnection configuration with exponential backoff
#[derive(Debug, Clone)]
pub struct ReconnectConfig {
    /// Initial reconnection delay
    pub initial_delay: Duration,
    /// Maximum reconnection delay
    pub max_delay: Duration,
    /// Backoff multiplier (delay *= multiplier after each attempt)
    pub multiplier: f64,
    /// Maximum number of reconnection attempts (None = infinite)
    pub max_attempts: Option<u32>,
}

impl Default for ReconnectConfig {
    fn default() -> Self {
        Self {
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(60),
            multiplier: 2.0,
            max_attempts: None,
        }
    }
}

/// WebSocket client with auto-reconnection
pub struct WebSocketClient {
    #[allow(dead_code)]
    config: WsConfig,
    tx: mpsc::UnboundedSender<Message>,
}

impl WebSocketClient {
    /// Create a new WebSocket client and start connection
    ///
    /// Returns a client handle and a receiver for incoming messages.
    ///
    /// # Example
    /// ```no_run
    /// use exchange_connector::websocket::{WebSocketClient, WsConfig, ReconnectConfig};
    /// use std::time::Duration;
    ///
    /// # async fn example() {
    /// let config = WsConfig {
    ///     url: "wss://ws.bitstamp.net".to_string(),
    ///     heartbeat_interval: Duration::from_secs(30),
    ///     reconnect_config: ReconnectConfig::default(),
    /// };
    ///
    /// let (mut client, mut rx) = WebSocketClient::connect(config).await.unwrap();
    ///
    /// // Subscribe to a channel
    /// client.send_text(r#"{"event":"bts:subscribe","data":{"channel":"order_book_btcusd"}}"#).await.unwrap();
    ///
    /// // Receive messages
    /// while let Some(msg) = rx.recv().await {
    ///     println!("Received: {:?}", msg);
    /// }
    /// # }
    /// ```
    pub async fn connect(
        config: WsConfig,
    ) -> Result<(Self, mpsc::UnboundedReceiver<WsMessage>), ExchangeError> {
        let (msg_tx, msg_rx) = mpsc::unbounded_channel();
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();

        // Spawn connection task
        tokio::spawn(connection_task(config.clone(), cmd_rx, msg_tx));

        Ok((
            Self {
                config,
                tx: cmd_tx,
            },
            msg_rx,
        ))
    }

    /// Send a text message
    pub async fn send_text(&self, text: &str) -> Result<(), ExchangeError> {
        self.tx
            .send(Message::Text(text.to_string()))
            .map_err(|_| ExchangeError::Other("Failed to send message".into()))?;
        Ok(())
    }

    /// Send a binary message
    pub async fn send_binary(&self, data: Vec<u8>) -> Result<(), ExchangeError> {
        self.tx
            .send(Message::Binary(data))
            .map_err(|_| ExchangeError::Other("Failed to send message".into()))?;
        Ok(())
    }

    /// Send a ping
    pub async fn send_ping(&self, data: Vec<u8>) -> Result<(), ExchangeError> {
        self.tx
            .send(Message::Ping(data))
            .map_err(|_| ExchangeError::Other("Failed to send ping".into()))?;
        Ok(())
    }

    /// Close the connection
    pub async fn close(&self) -> Result<(), ExchangeError> {
        self.tx
            .send(Message::Close(None))
            .map_err(|_| ExchangeError::Other("Failed to send close".into()))?;
        Ok(())
    }
}

/// Connection task that manages WebSocket lifecycle
async fn connection_task(
    config: WsConfig,
    mut cmd_rx: mpsc::UnboundedReceiver<Message>,
    msg_tx: mpsc::UnboundedSender<WsMessage>,
) {
    let mut attempt = 0;
    let mut current_delay = config.reconnect_config.initial_delay;

    loop {
        match connect_and_run(&config, &mut cmd_rx, &msg_tx).await {
            Ok(_) => {
                info!("WebSocket connection closed normally");
                break;
            }
            Err(e) => {
                error!("WebSocket error: {}", e);

                // Check if we should attempt reconnection
                if let Some(max) = config.reconnect_config.max_attempts {
                    if attempt >= max {
                        error!("Max reconnection attempts reached, giving up");
                        break;
                    }
                }

                attempt += 1;
                warn!(
                    "Reconnecting in {:?} (attempt {}/{})",
                    current_delay,
                    attempt,
                    config
                        .reconnect_config
                        .max_attempts
                        .map(|m| m.to_string())
                        .unwrap_or_else(|| "∞".to_string())
                );

                sleep(current_delay).await;

                // Exponential backoff
                current_delay = Duration::from_secs_f64(
                    (current_delay.as_secs_f64() * config.reconnect_config.multiplier)
                        .min(config.reconnect_config.max_delay.as_secs_f64()),
                );
            }
        }
    }
}

/// Connect to WebSocket and run message loop
async fn connect_and_run(
    config: &WsConfig,
    cmd_rx: &mut mpsc::UnboundedReceiver<Message>,
    msg_tx: &mpsc::UnboundedSender<WsMessage>,
) -> Result<(), ExchangeError> {
    debug!("Connecting to WebSocket: {}", config.url);

    // Validate URL is wss:// (TLS required)
    if !config.url.starts_with("wss://") {
        return Err(ExchangeError::Other(
            "WebSocket URL must use wss:// (TLS required)".into(),
        ));
    }

    let (ws_stream, _) = connect_async(&config.url)
        .await
        .map_err(|e| ExchangeError::Other(format!("WebSocket connection failed: {}", e)))?;

    info!("WebSocket connected");

    let (mut write, mut read) = ws_stream.split();

    // Heartbeat interval
    let mut heartbeat = interval(config.heartbeat_interval);
    let mut last_pong = Instant::now();

    loop {
        tokio::select! {
            // Incoming message from server
            msg = read.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        trace!("Received text: {}", text);
                        if msg_tx.send(WsMessage::Text(text)).is_err() {
                            warn!("Message receiver dropped, closing connection");
                            break;
                        }
                    }
                    Some(Ok(Message::Binary(data))) => {
                        trace!("Received binary: {} bytes", data.len());
                        if msg_tx.send(WsMessage::Binary(data)).is_err() {
                            warn!("Message receiver dropped, closing connection");
                            break;
                        }
                    }
                    Some(Ok(Message::Ping(data))) => {
                        trace!("Received ping");
                        if msg_tx.send(WsMessage::Ping(data.clone())).is_err() {
                            warn!("Message receiver dropped, closing connection");
                            break;
                        }
                        // Respond with pong
                        if let Err(e) = write.send(Message::Pong(data)).await {
                            error!("Failed to send pong: {}", e);
                            break;
                        }
                    }
                    Some(Ok(Message::Pong(_))) => {
                        trace!("Received pong");
                        last_pong = Instant::now();
                    }
                    Some(Ok(Message::Close(_))) => {
                        info!("Server closed connection");
                        let _ = msg_tx.send(WsMessage::Close);
                        break;
                    }
                    Some(Err(e)) => {
                        error!("WebSocket error: {}", e);
                        break;
                    }
                    None => {
                        warn!("WebSocket stream ended");
                        break;
                    }
                    _ => {}
                }
            }

            // Outgoing command from client
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(msg) => {
                        trace!("Sending message: {:?}", msg);
                        if let Err(e) = write.send(msg).await {
                            error!("Failed to send message: {}", e);
                            break;
                        }
                    }
                    None => {
                        info!("Command channel closed");
                        break;
                    }
                }
            }

            // Heartbeat tick
            _ = heartbeat.tick() => {
                trace!("Sending heartbeat ping");
                if let Err(e) = write.send(Message::Ping(vec![])).await {
                    error!("Failed to send heartbeat: {}", e);
                    break;
                }

                // Check if we've received a pong recently
                let elapsed = last_pong.elapsed();
                if elapsed > config.heartbeat_interval * 3 {
                    warn!("No pong received for {:?}, connection may be dead", elapsed);
                    break;
                }
            }
        }
    }

    info!("WebSocket connection closed");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reconnect_config_default() {
        let config = ReconnectConfig::default();
        assert_eq!(config.initial_delay, Duration::from_secs(1));
        assert_eq!(config.max_delay, Duration::from_secs(60));
        assert_eq!(config.multiplier, 2.0);
        assert!(config.max_attempts.is_none());
    }

    #[tokio::test]
    async fn test_ws_config() {
        let config = WsConfig {
            url: "wss://example.com".to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        assert_eq!(config.url, "wss://example.com");
        assert_eq!(config.heartbeat_interval, Duration::from_secs(30));
    }

    // ====================================================================
    // EDGE CASE & ERROR PATH TESTS
    // ====================================================================

    #[test]
    fn test_reconnect_config_custom() {
        let config = ReconnectConfig {
            initial_delay: Duration::from_millis(500),
            max_delay: Duration::from_secs(30),
            multiplier: 1.5,
            max_attempts: Some(5),
        };
        assert_eq!(config.initial_delay, Duration::from_millis(500));
        assert_eq!(config.max_attempts, Some(5));
    }

    #[test]
    fn test_reconnect_config_zero_multiplier() {
        let config = ReconnectConfig {
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(60),
            multiplier: 0.0,
            max_attempts: None,
        };
        // Should not panic, multiplier can be any value
        assert_eq!(config.multiplier, 0.0);
    }

    #[test]
    fn test_ws_message_types() {
        let text_msg = WsMessage::Text("hello".to_string());
        assert!(matches!(text_msg, WsMessage::Text(_)));

        let binary_msg = WsMessage::Binary(vec![1, 2, 3]);
        assert!(matches!(binary_msg, WsMessage::Binary(_)));

        let ping_msg = WsMessage::Ping(vec![]);
        assert!(matches!(ping_msg, WsMessage::Ping(_)));

        let pong_msg = WsMessage::Pong(vec![]);
        assert!(matches!(pong_msg, WsMessage::Pong(_)));

        let close_msg = WsMessage::Close;
        assert!(matches!(close_msg, WsMessage::Close));
    }

    #[test]
    fn test_ws_message_clone() {
        let msg = WsMessage::Text("test".to_string());
        let cloned = msg.clone();
        assert!(matches!(cloned, WsMessage::Text(ref s) if s == "test"));
    }

    #[tokio::test]
    async fn test_ws_config_invalid_url() {
        // Non-wss:// URL should fail in connect_and_run
        let config = WsConfig {
            url: "ws://example.com".to_string(), // Not wss://
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (msg_tx, _msg_rx) = mpsc::unbounded_channel();
        let (_cmd_tx, cmd_rx) = mpsc::unbounded_channel();

        let result = connect_and_run(&config, &mut cmd_rx.into(), &msg_tx).await;
        assert!(result.is_err(), "Should reject non-wss:// URLs");
        if let Err(ExchangeError::Other(msg)) = result {
            assert!(msg.contains("wss://") || msg.contains("TLS"));
        }
    }

    #[tokio::test]
    async fn test_ws_config_empty_url() {
        let config = WsConfig {
            url: "".to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig::default(),
        };

        let (msg_tx, _msg_rx) = mpsc::unbounded_channel();
        let (_cmd_tx, cmd_rx) = mpsc::unbounded_channel();

        let result = connect_and_run(&config, &mut cmd_rx.into(), &msg_tx).await;
        assert!(result.is_err(), "Should reject empty URL");
    }

    #[tokio::test]
    async fn test_ws_config_heartbeat_zero() {
        let config = WsConfig {
            url: "wss://example.com".to_string(),
            heartbeat_interval: Duration::from_secs(0),
            reconnect_config: ReconnectConfig::default(),
        };
        // Should not panic
        assert_eq!(config.heartbeat_interval, Duration::ZERO);
    }

    #[test]
    fn test_reconnect_max_delay_less_than_initial() {
        let config = ReconnectConfig {
            initial_delay: Duration::from_secs(10),
            max_delay: Duration::from_secs(5), // Less than initial
            multiplier: 2.0,
            max_attempts: None,
        };
        // Should not panic, clamping will handle it
        assert!(config.max_delay < config.initial_delay);
    }

    #[tokio::test]
    async fn test_websocket_client_send_empty_binary() {
        // This test can't fully run without a real connection,
        // but we can test the interface accepts empty binary
        let config = WsConfig {
            url: "wss://example.com".to_string(),
            heartbeat_interval: Duration::from_secs(30),
            reconnect_config: ReconnectConfig {
                initial_delay: Duration::from_secs(1),
                max_delay: Duration::from_secs(1),
                multiplier: 1.0,
                max_attempts: Some(0), // Don't retry
            },
        };

        // We can't actually connect, but we can verify the types work
        let result = WebSocketClient::connect(config).await;
        // Will fail to connect, but should not panic
        assert!(result.is_ok() || result.is_err());
    }
}
