//! Alpaca WebSocket feed implementation
//!
//! Bridges Alpaca's real-time stock market data into the common feed interface.
//! Supports both IEX (free, real-time) and SIP (paid, all exchanges) feeds.

use crate::client::ExchangeError;
use crate::exchanges::alpaca::types::{AlpacaTrade, Quote};
use crate::exchanges::alpaca::ws::{AlpacaWebSocket, MarketDataMessage};
use crate::types::{OrderBook, PriceLevel, Side, Trade};
use chrono::{DateTime, Utc};
use std::env;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};
use tracing::{debug, warn};

/// Alpaca WebSocket feed
pub struct AlpacaFeed {
    ws_client: AlpacaWebSocket,
    tx: Option<mpsc::UnboundedSender<AlpacaFeedMessage>>,
}

/// Alpaca feed message type
///
/// Unlike other feeds which return raw `WsMessage`, AlpacaFeed returns typed messages
/// because the underlying `AlpacaWebSocket` already performs parsing.
#[derive(Debug, Clone)]
pub enum AlpacaFeedMessage {
    /// Trade update
    Trade(Trade),
    /// OrderBook update (from quote)
    OrderBook(OrderBook),
    /// Error message
    Error(String),
}

impl AlpacaFeed {
    /// Create a new Alpaca WebSocket feed
    ///
    /// # Environment Variables
    /// * `ALPACA_API_KEY` - Alpaca API key ID (required)
    /// * `ALPACA_SECRET_KEY` - Alpaca API secret key (required)
    /// * `ALPACA_FEED` - Feed type: "iex" (default, free) or "sip" (paid)
    pub async fn new() -> Result<(Self, mpsc::UnboundedReceiver<AlpacaFeedMessage>), ExchangeError>
    {
        let api_key = env::var("ALPACA_API_KEY")
            .map_err(|_| ExchangeError::Authentication("ALPACA_API_KEY not set".into()))?;
        let secret_key = env::var("ALPACA_SECRET_KEY")
            .map_err(|_| ExchangeError::Authentication("ALPACA_SECRET_KEY not set".into()))?;
        let feed = env::var("ALPACA_FEED").unwrap_or_else(|_| "iex".to_string());

        let ws_client = AlpacaWebSocket::new(api_key, secret_key, &feed);
        let (tx, rx) = mpsc::unbounded_channel();

        Ok((
            Self {
                ws_client,
                tx: Some(tx),
            },
            rx,
        ))
    }

    /// Subscribe to trades for given symbols
    ///
    /// # Security
    /// Validates symbols contain only alphanumeric characters.
    pub async fn subscribe_trades(&mut self, symbols: Vec<String>) -> Result<(), ExchangeError> {
        for symbol in &symbols {
            if !symbol.chars().all(|c| c.is_alphanumeric()) {
                return Err(ExchangeError::InvalidRequest(
                    "Symbol must contain only alphanumeric characters".into(),
                ));
            }
        }

        let mut stream = self.ws_client.connect().await?;
        self.ws_client.authenticate(&mut stream).await?;
        self.ws_client
            .subscribe(&mut stream, Some(symbols), None, None)
            .await?;

        self.spawn_message_loop(stream);
        Ok(())
    }

    /// Subscribe to quotes for given symbols
    pub async fn subscribe_quotes(&mut self, symbols: Vec<String>) -> Result<(), ExchangeError> {
        for symbol in &symbols {
            if !symbol.chars().all(|c| c.is_alphanumeric()) {
                return Err(ExchangeError::InvalidRequest(
                    "Symbol must contain only alphanumeric characters".into(),
                ));
            }
        }

        let mut stream = self.ws_client.connect().await?;
        self.ws_client.authenticate(&mut stream).await?;
        self.ws_client
            .subscribe(&mut stream, None, Some(symbols), None)
            .await?;

        self.spawn_message_loop(stream);
        Ok(())
    }

    /// Spawn background task to read messages from WebSocket and translate to AlpacaFeedMessage
    fn spawn_message_loop(&mut self, stream: WebSocketStream<MaybeTlsStream<TcpStream>>) {
        let tx = self.tx.take().expect("spawn_message_loop called twice");
        let (sender_for_task, mut rx_from_alpaca) = mpsc::channel(100);

        tokio::spawn({
            let ws_client = AlpacaWebSocket::new(
                env::var("ALPACA_API_KEY").unwrap_or_default(),
                env::var("ALPACA_SECRET_KEY").unwrap_or_default(),
                &env::var("ALPACA_FEED").unwrap_or_else(|_| "iex".to_string()),
            );
            async move {
                let _ = ws_client.read_messages(stream, sender_for_task).await;
            }
        });

        tokio::spawn(async move {
            while let Some(msg) = rx_from_alpaca.recv().await {
                match msg {
                    MarketDataMessage::Trade { symbol, trade } => {
                        match translate_trade(&symbol, trade) {
                            Ok(t) => {
                                if tx.send(AlpacaFeedMessage::Trade(t)).is_err() {
                                    break;
                                }
                            }
                            Err(e) => {
                                warn!("Failed to translate trade: {}", e);
                            }
                        }
                    }
                    MarketDataMessage::Quote { symbol, quote } => {
                        match translate_quote(&symbol, quote) {
                            Ok(ob) => {
                                if tx.send(AlpacaFeedMessage::OrderBook(ob)).is_err() {
                                    break;
                                }
                            }
                            Err(e) => {
                                warn!("Failed to translate quote: {}", e);
                            }
                        }
                    }
                    MarketDataMessage::Bar { symbol: _, bar: _ } => {
                        debug!("Received bar message (discarded - out of scope)");
                    }
                    MarketDataMessage::Error(e) => {
                        warn!("Alpaca WebSocket error: {}", e);
                        let _ = tx.send(AlpacaFeedMessage::Error(e));
                    }
                }
            }
        });
    }
}

/// Translate AlpacaTrade to common Trade type
fn translate_trade(symbol: &str, alpaca_trade: AlpacaTrade) -> Result<Trade, ExchangeError> {
    let timestamp = DateTime::parse_from_rfc3339(&alpaca_trade.timestamp)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(Utc::now);

    Ok(Trade {
        id: alpaca_trade.id.to_string(),
        pair: symbol.to_uppercase(),
        exchange: "alpaca".to_string(),
        price: alpaca_trade.price,
        quantity: alpaca_trade.size as f64,
        side: Side::Buy,
        timestamp,
        is_maker: None,
    })
}

/// Translate Quote to OrderBook (1-level book with bid + ask)
fn translate_quote(symbol: &str, quote: Quote) -> Result<OrderBook, ExchangeError> {
    let timestamp = DateTime::parse_from_rfc3339(&quote.timestamp)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(Utc::now);

    Ok(OrderBook {
        pair: symbol.to_uppercase(),
        exchange: "alpaca".to_string(),
        bids: vec![PriceLevel {
            price: quote.bid_price,
            quantity: quote.bid_size as f64,
        }],
        asks: vec![PriceLevel {
            price: quote.ask_price,
            quantity: quote.ask_size as f64,
        }],
        timestamp,
        sequence: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_translate_trade_to_wsmessage() {
        let alpaca_trade = AlpacaTrade {
            timestamp: "2024-01-15T14:30:00.000000Z".to_string(),
            price: 159.42,
            size: 100,
            exchange: "Q".to_string(),
            id: 12345,
            conditions: vec!["@".to_string()],
            tape: "C".to_string(),
        };

        let trade = translate_trade("AAPL", alpaca_trade).unwrap();

        assert_eq!(trade.pair, "AAPL");
        assert_eq!(trade.exchange, "alpaca");
        assert!((trade.price - 159.42).abs() < 1e-6);
        assert!((trade.quantity - 100.0).abs() < 1e-6);
        assert_eq!(trade.id, "12345");
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_translate_quote_to_orderbook() {
        let quote = Quote {
            timestamp: "2024-01-15T14:30:00.000000Z".to_string(),
            bid_exchange: "Q".to_string(),
            bid_price: 159.40,
            bid_size: 100,
            ask_exchange: "Q".to_string(),
            ask_price: 159.45,
            ask_size: 200,
            conditions: vec![],
            tape: "C".to_string(),
        };

        let orderbook = translate_quote("AAPL", quote).unwrap();

        assert_eq!(orderbook.pair, "AAPL");
        assert_eq!(orderbook.exchange, "alpaca");
        assert_eq!(orderbook.bids.len(), 1);
        assert_eq!(orderbook.asks.len(), 1);
        assert!((orderbook.bids[0].price - 159.40).abs() < 1e-6);
        assert!((orderbook.bids[0].quantity - 100.0).abs() < 1e-6);
        assert!((orderbook.asks[0].price - 159.45).abs() < 1e-6);
        assert!((orderbook.asks[0].quantity - 200.0).abs() < 1e-6);
    }

    #[test]
    fn test_new_requires_env_vars() {
        std::env::remove_var("ALPACA_API_KEY");
        std::env::remove_var("ALPACA_SECRET_KEY");

        let rt = tokio::runtime::Runtime::new().unwrap();
        let result = rt.block_on(AlpacaFeed::new());

        assert!(result.is_err());
        if let Err(ExchangeError::Authentication(msg)) = result {
            assert!(msg.contains("ALPACA_API_KEY"));
        } else {
            panic!("Expected Authentication error");
        }
    }

    #[test]
    fn test_price_passthrough() {
        let alpaca_trade = AlpacaTrade {
            timestamp: "2024-01-15T14:30:00.000000Z".to_string(),
            price: 1234.567890,
            size: 50,
            exchange: "Q".to_string(),
            id: 999,
            conditions: vec![],
            tape: "C".to_string(),
        };

        let trade = translate_trade("TSLA", alpaca_trade).unwrap();

        assert!((trade.price - 1234.567890).abs() < 1e-6);
        assert!((trade.quantity - 50.0).abs() < 1e-6);
    }
}
