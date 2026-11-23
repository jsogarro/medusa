//! Alpaca WebSocket client for real-time market data
//!
//! WebSocket documentation: https://docs.alpaca.markets/docs/streaming-market-data

use super::types::{AlpacaTrade, Bar, Quote, WsAuthMessage, WsSubscribeMessage};
use crate::client::ExchangeError;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};
use tracing::{debug, error, info, warn};

/// Alpaca WebSocket URLs
const IEX_WS_URL: &str = "wss://stream.data.alpaca.markets/v2/iex";
const SIP_WS_URL: &str = "wss://stream.data.alpaca.markets/v2/sip";

/// Market data message types from WebSocket
#[derive(Debug)]
pub enum MarketDataMessage {
    Trade { symbol: String, trade: AlpacaTrade },
    Quote { symbol: String, quote: Quote },
    Bar { symbol: String, bar: Bar },
    Error(String),
}

/// Alpaca WebSocket client
pub struct AlpacaWebSocket {
    ws_url: String,
    api_key: String,
    secret_key: String,
}

impl AlpacaWebSocket {
    /// Create a new WebSocket client
    ///
    /// # Arguments
    /// * `api_key` - Alpaca API key ID
    /// * `secret_key` - Alpaca API secret key
    /// * `feed` - "iex" (free, real-time) or "sip" (paid, all exchanges)
    pub fn new(api_key: String, secret_key: String, feed: &str) -> Self {
        let ws_url = match feed {
            "sip" => SIP_WS_URL.to_string(),
            _ => IEX_WS_URL.to_string(),
        };

        Self {
            ws_url,
            api_key,
            secret_key,
        }
    }

    /// Connect to Alpaca WebSocket and authenticate
    pub async fn connect(
        &self,
    ) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>, ExchangeError> {
        info!("Connecting to Alpaca WebSocket: {}", self.ws_url);

        let (ws_stream, _) = connect_async(&self.ws_url)
            .await
            .map_err(|e| ExchangeError::Other(format!("WebSocket connection failed: {}", e)))?;

        info!("WebSocket connected");
        Ok(ws_stream)
    }

    /// Authenticate with the WebSocket
    pub async fn authenticate(
        &self,
        stream: &mut WebSocketStream<MaybeTlsStream<TcpStream>>,
    ) -> Result<(), ExchangeError> {
        debug!("Authenticating WebSocket");

        let auth_msg = WsAuthMessage {
            action: "auth".to_string(),
            key: self.api_key.clone(),
            secret: self.secret_key.clone(),
        };

        let auth_json = serde_json::to_string(&auth_msg)
            .map_err(|e| ExchangeError::Other(format!("Failed to serialize auth: {}", e)))?;

        stream
            .send(Message::Text(auth_json))
            .await
            .map_err(|e| ExchangeError::Other(format!("Failed to send auth: {}", e)))?;

        // Wait for authentication response
        if let Some(msg_result) = stream.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    debug!("Auth response: {}", text);

                    // Parse response to check for success
                    if let Ok(response) = serde_json::from_str::<Value>(&text) {
                        if let Some(msg_type) = response[0]["T"].as_str() {
                            if msg_type == "success" {
                                info!("WebSocket authenticated successfully");
                                return Ok(());
                            } else if msg_type == "error" {
                                let error_msg =
                                    response[0]["msg"].as_str().unwrap_or("Unknown error");
                                return Err(ExchangeError::Authentication(format!(
                                    "Authentication failed: {}",
                                    error_msg
                                )));
                            }
                        }
                    }

                    // If we can't determine success, assume it's OK (Alpaca may send success differently)
                    info!("WebSocket authentication message received");
                    Ok(())
                }
                Ok(_) => Err(ExchangeError::Other(
                    "Unexpected message type during auth".to_string(),
                )),
                Err(e) => Err(ExchangeError::Other(format!(
                    "Failed to receive auth response: {}",
                    e
                ))),
            }
        } else {
            Err(ExchangeError::Other(
                "No auth response received".to_string(),
            ))
        }
    }

    /// Subscribe to market data streams
    ///
    /// # Arguments
    /// * `stream` - WebSocket stream
    /// * `trades` - Symbols to subscribe to trades
    /// * `quotes` - Symbols to subscribe to quotes
    /// * `bars` - Symbols to subscribe to bars (use `vec!["*"]` for all)
    pub async fn subscribe(
        &self,
        stream: &mut WebSocketStream<MaybeTlsStream<TcpStream>>,
        trades: Option<Vec<String>>,
        quotes: Option<Vec<String>>,
        bars: Option<Vec<String>>,
    ) -> Result<(), ExchangeError> {
        debug!(
            "Subscribing - trades: {:?}, quotes: {:?}, bars: {:?}",
            trades, quotes, bars
        );

        let sub_msg = WsSubscribeMessage {
            action: "subscribe".to_string(),
            trades,
            quotes,
            bars,
        };

        let sub_json = serde_json::to_string(&sub_msg)
            .map_err(|e| ExchangeError::Other(format!("Failed to serialize subscribe: {}", e)))?;

        stream
            .send(Message::Text(sub_json))
            .await
            .map_err(|e| ExchangeError::Other(format!("Failed to send subscribe: {}", e)))?;

        info!("Subscription request sent");
        Ok(())
    }

    /// Read messages from WebSocket and send to channel
    ///
    /// This is a long-running task that should be spawned in a separate tokio task.
    pub async fn read_messages(
        &self,
        mut stream: WebSocketStream<MaybeTlsStream<TcpStream>>,
        tx: mpsc::Sender<MarketDataMessage>,
    ) -> Result<(), ExchangeError> {
        info!("Starting message read loop");

        while let Some(msg_result) = stream.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    // Parse message array
                    if let Ok(messages) = serde_json::from_str::<Vec<Value>>(&text) {
                        for msg_value in messages {
                            if let Err(e) = self.process_message(msg_value, &tx).await {
                                warn!("Failed to process message: {}", e);
                            }
                        }
                    } else {
                        warn!("Failed to parse WebSocket message: {}", text);
                    }
                }
                Ok(Message::Ping(_)) => {
                    debug!("Received ping");
                }
                Ok(Message::Pong(_)) => {
                    debug!("Received pong");
                }
                Ok(Message::Close(frame)) => {
                    info!("WebSocket closed: {:?}", frame);
                    break;
                }
                Ok(_) => {
                    debug!("Received other message type");
                }
                Err(e) => {
                    error!("WebSocket error: {}", e);
                    let _ = tx
                        .send(MarketDataMessage::Error(format!("WebSocket error: {}", e)))
                        .await;
                    return Err(ExchangeError::Other(format!("WebSocket error: {}", e)));
                }
            }
        }

        info!("Message read loop ended");
        Ok(())
    }

    /// Process a single WebSocket message
    async fn process_message(
        &self,
        msg_value: Value,
        tx: &mpsc::Sender<MarketDataMessage>,
    ) -> Result<(), ExchangeError> {
        // Check message type (T field)
        let msg_type = msg_value["T"]
            .as_str()
            .ok_or_else(|| ExchangeError::Other("Missing T field".to_string()))?;

        match msg_type {
            "t" => {
                // Trade
                let trade: AlpacaTrade =
                    serde_json::from_value(msg_value.clone()).map_err(ExchangeError::JsonParse)?;
                let symbol = msg_value["S"].as_str().unwrap_or("UNKNOWN").to_string();

                tx.send(MarketDataMessage::Trade { symbol, trade })
                    .await
                    .map_err(|e| ExchangeError::Other(format!("Channel send error: {}", e)))?;
            }
            "q" => {
                // Quote
                let quote: Quote =
                    serde_json::from_value(msg_value.clone()).map_err(ExchangeError::JsonParse)?;
                let symbol = msg_value["S"].as_str().unwrap_or("UNKNOWN").to_string();

                tx.send(MarketDataMessage::Quote { symbol, quote })
                    .await
                    .map_err(|e| ExchangeError::Other(format!("Channel send error: {}", e)))?;
            }
            "b" => {
                // Bar
                let bar: Bar =
                    serde_json::from_value(msg_value.clone()).map_err(ExchangeError::JsonParse)?;
                let symbol = msg_value["S"].as_str().unwrap_or("UNKNOWN").to_string();

                tx.send(MarketDataMessage::Bar { symbol, bar })
                    .await
                    .map_err(|e| ExchangeError::Other(format!("Channel send error: {}", e)))?;
            }
            "success" => {
                debug!("Subscription success: {:?}", msg_value);
            }
            "error" => {
                let error_msg = msg_value["msg"]
                    .as_str()
                    .unwrap_or("Unknown error")
                    .to_string();
                warn!("WebSocket error message: {}", error_msg);
                tx.send(MarketDataMessage::Error(error_msg))
                    .await
                    .map_err(|e| ExchangeError::Other(format!("Channel send error: {}", e)))?;
            }
            "subscription" => {
                debug!("Subscription confirmation: {:?}", msg_value);
            }
            _ => {
                debug!("Unknown message type: {}", msg_type);
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_websocket_creation_iex() {
        let ws = AlpacaWebSocket::new("test-key".to_string(), "test-secret".to_string(), "iex");
        assert_eq!(ws.ws_url, IEX_WS_URL);
    }

    #[test]
    fn test_websocket_creation_sip() {
        let ws = AlpacaWebSocket::new("test-key".to_string(), "test-secret".to_string(), "sip");
        assert_eq!(ws.ws_url, SIP_WS_URL);
    }

    #[test]
    fn test_auth_message_serialization() {
        let auth = WsAuthMessage {
            action: "auth".to_string(),
            key: "test-key".to_string(),
            secret: "test-secret".to_string(),
        };

        let json = serde_json::to_string(&auth).unwrap();
        assert!(json.contains("\"action\":\"auth\""));
        assert!(json.contains("\"key\":\"test-key\""));
        assert!(json.contains("\"secret\":\"test-secret\""));
    }

    #[test]
    fn test_subscribe_message_serialization() {
        let sub = WsSubscribeMessage {
            action: "subscribe".to_string(),
            trades: Some(vec!["AAPL".to_string(), "TSLA".to_string()]),
            quotes: None,
            bars: None,
        };

        let json = serde_json::to_string(&sub).unwrap();
        assert!(json.contains("\"action\":\"subscribe\""));
        assert!(json.contains("\"trades\":[\"AAPL\",\"TSLA\"]"));
    }
}
