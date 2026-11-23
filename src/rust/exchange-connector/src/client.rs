//! Exchange client trait and error types

use crate::types::{Balance, Order, OrderBook, OrderType, Side};
use async_trait::async_trait;
use std::time::Duration;
use thiserror::Error;

// Security: validation bounds shared by every venue.
pub(crate) const MAX_PRICE: f64 = 1_000_000_000.0;
pub(crate) const MAX_QUANTITY: f64 = 1_000_000_000.0;
pub(crate) const MIN_POSITIVE: f64 = 1e-18;

/// Total time allowed for one REST request (connect + send + response).
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Build the HTTP client used by every REST venue, with bounded timeouts so a
/// stalled exchange cannot hang a caller (or a held rate-limit slot) forever.
pub(crate) fn build_http_client(request_timeout: Duration) -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(request_timeout)
        .connect_timeout(CONNECT_TIMEOUT.min(request_timeout))
        .build()
        .unwrap_or_default()
}

pub(crate) fn http_client() -> reqwest::Client {
    build_http_client(REQUEST_TIMEOUT)
}

/// Parse a venue's side string (case-insensitive); anything else is an error
/// rather than a guess.
pub(crate) fn parse_side(s: &str) -> Result<Side, ExchangeError> {
    match s.to_ascii_lowercase().as_str() {
        "buy" => Ok(Side::Buy),
        "sell" => Ok(Side::Sell),
        _ => Err(ExchangeError::Other(format!(
            "Unrecognized order side '{s}'"
        ))),
    }
}

/// Parse a venue's order type string (case-insensitive); unsupported types
/// are an error rather than being reported as limit orders.
pub(crate) fn parse_order_type(s: &str) -> Result<OrderType, ExchangeError> {
    match s.to_ascii_lowercase().as_str() {
        "limit" => Ok(OrderType::Limit),
        "market" => Ok(OrderType::Market),
        _ => Err(ExchangeError::Other(format!(
            "Unrecognized order type '{s}'"
        ))),
    }
}

/// A venue order status we do not recognise is an error, never a guess.
pub(crate) fn unknown_status(s: &str) -> ExchangeError {
    ExchangeError::Other(format!("Unrecognized order status '{s}'"))
}

/// Reject orders that must never reach a venue: non-finite, non-positive or
/// absurdly large quantity/price, and limit orders without a price.
///
/// Called first thing in every venue's `place_order` so no venue can forget it.
pub(crate) fn validate_order(order: &Order) -> Result<(), ExchangeError> {
    let bad = |what: &str, v: f64| {
        Err(ExchangeError::InvalidRequest(format!(
            "{what} {v} out of range"
        )))
    };
    let q = order.quantity;
    if !q.is_finite() || !(MIN_POSITIVE..=MAX_QUANTITY).contains(&q) {
        return bad("quantity", q);
    }
    if let Some(id) = &order.client_order_id {
        let ok = (1..=36).contains(&id.len())
            && id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
        if !ok {
            return Err(ExchangeError::InvalidRequest(
                "client_order_id must be 1-36 chars of [A-Za-z0-9_-]".into(),
            ));
        }
    }
    match order.price {
        Some(p) if !p.is_finite() || !(MIN_POSITIVE..=MAX_PRICE).contains(&p) => bad("price", p),
        None if order.order_type == OrderType::Limit => Err(ExchangeError::InvalidRequest(
            "Limit order requires price".into(),
        )),
        _ => Ok(()),
    }
}

/// Exchange-specific errors for fine-grained error handling
#[derive(Debug, Error)]
pub enum ExchangeError {
    /// Network error (retryable)
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    /// Rate limit exceeded (retryable with backoff)
    #[error("Rate limit exceeded: {0}")]
    RateLimit(String),

    /// Invalid request parameters (not retryable)
    #[error("Invalid request: {0}")]
    InvalidRequest(String),

    /// Authentication error (not retryable)
    #[error("Authentication failed: {0}")]
    Authentication(String),

    /// Insufficient balance (not retryable)
    #[error("Insufficient balance: {0}")]
    InsufficientBalance(String),

    /// Order not found (not retryable)
    #[error("Order not found: {0}")]
    OrderNotFound(String),

    /// Exchange unavailable (retryable)
    #[error("Exchange unavailable: {0}")]
    Unavailable(String),

    /// JSON parsing error
    #[error("JSON parsing error: {0}")]
    JsonParse(#[from] serde_json::Error),

    /// Generic error
    #[error("Exchange error: {0}")]
    Other(String),
}

impl ExchangeError {
    /// Returns true if this error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            ExchangeError::Network(_) | ExchangeError::RateLimit(_) | ExchangeError::Unavailable(_)
        )
    }
}

/// Common interface for exchange clients
///
/// # Design Notes
/// - Uses thiserror for library error types (better than anyhow for public APIs)
/// - All methods return Result<T, ExchangeError> for fine-grained error handling
/// - Trait is Send + Sync for use across async tasks
/// - WebSocket subscription methods will be added in Wave 2
#[async_trait]
pub trait ExchangeClient: Send + Sync {
    /// Get orderbook snapshot for a trading pair
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError>;

    /// Get account balance for a specific asset or all assets
    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError>;

    /// Get all open orders for a trading pair or all pairs
    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError>;

    /// Get order status by ID
    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError>;

    /// Place a new order
    ///
    /// Returns the exchange-assigned order ID
    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError>;

    /// Cancel an order by ID
    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError>;

    /// Cancel all open orders for a trading pair or all pairs
    async fn cancel_all_orders(&self, pair: Option<&str>) -> Result<u32, ExchangeError>;

    // WebSocket subscription methods to be added in Wave 2:
    // - subscribe_orderbook
    // - subscribe_trades
    // - subscribe_orders (private channel)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::types::OrderStatus;
    use chrono::Utc;

    #[test]
    fn parse_side_and_type_reject_unknown_values() {
        assert_eq!(parse_side("BUY").unwrap(), Side::Buy);
        assert_eq!(parse_side("sell").unwrap(), Side::Sell);
        assert_eq!(parse_order_type("Limit").unwrap(), OrderType::Limit);
        assert_eq!(parse_order_type("MARKET").unwrap(), OrderType::Market);
        for bad in ["", "short", "0", "BUY ", "stop_limit", "stop"] {
            assert!(parse_side(bad).is_err(), "side {bad:?}");
            assert!(parse_order_type(bad).is_err(), "type {bad:?}");
        }
    }

    pub(crate) fn sample_order() -> Order {
        Order {
            id: None,
            pair: "BTC/USD".to_string(),
            exchange: "test".to_string(),
            side: Side::Buy,
            price: Some(50_000.0),
            quantity: 1.0,
            order_type: OrderType::Limit,
            status: OrderStatus::Pending,
            client_order_id: None,
            filled_quantity: 0.0,
            average_price: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    /// Every venue's `place_order` must reject these before any network I/O.
    pub(crate) async fn assert_place_order_rejects_bad_orders(client: &dyn ExchangeClient) {
        let mut bad = Vec::new();
        for q in [f64::NAN, f64::INFINITY, -1.0, 0.0, MAX_QUANTITY * 2.0] {
            bad.push(Order {
                quantity: q,
                ..sample_order()
            });
        }
        for p in [f64::NAN, f64::INFINITY, -1.0, 0.0, MAX_PRICE * 2.0] {
            bad.push(Order {
                price: Some(p),
                ..sample_order()
            });
        }
        bad.push(Order {
            price: None,
            ..sample_order()
        });
        for order in bad {
            let r = client.place_order(&order).await;
            assert!(
                matches!(r, Err(ExchangeError::InvalidRequest(_))),
                "qty={} price={:?} must be InvalidRequest, got {:?}",
                order.quantity,
                order.price,
                r
            );
        }
    }

    #[test]
    fn validate_order_accepts_sane_orders() {
        assert!(validate_order(&sample_order()).is_ok());
        let market = Order {
            order_type: OrderType::Market,
            price: None,
            ..sample_order()
        };
        assert!(validate_order(&market).is_ok());
    }

    #[test]
    fn validate_order_checks_client_order_id() {
        for ok in ["a", "abc-123_X", &"x".repeat(36)] {
            let o = Order {
                client_order_id: Some(ok.to_string()),
                ..sample_order()
            };
            assert!(validate_order(&o).is_ok(), "{ok}");
        }
        for bad in ["", "has space", "a&b=c", "semi;colon", &"x".repeat(37)] {
            let o = Order {
                client_order_id: Some(bad.to_string()),
                ..sample_order()
            };
            assert!(
                matches!(validate_order(&o), Err(ExchangeError::InvalidRequest(_))),
                "{bad:?}"
            );
        }
    }

    #[test]
    fn validate_order_rejects_bad_values() {
        for q in [f64::NAN, f64::INFINITY, -1.0, 0.0, MAX_QUANTITY * 2.0] {
            let o = Order {
                quantity: q,
                ..sample_order()
            };
            assert!(
                matches!(validate_order(&o), Err(ExchangeError::InvalidRequest(_))),
                "qty {q}"
            );
        }
        for p in [f64::NAN, f64::NEG_INFINITY, -5.0, 0.0, MAX_PRICE * 2.0] {
            let o = Order {
                price: Some(p),
                ..sample_order()
            };
            assert!(
                matches!(validate_order(&o), Err(ExchangeError::InvalidRequest(_))),
                "price {p}"
            );
        }
        let no_price = Order {
            price: None,
            ..sample_order()
        };
        assert!(matches!(
            validate_order(&no_price),
            Err(ExchangeError::InvalidRequest(_))
        ));
    }

    #[tokio::test]
    async fn http_client_enforces_request_timeout() {
        // A server that accepts but never answers must not hang the client.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let _held = listener.accept().await;
            std::future::pending::<()>().await;
        });
        let client = build_http_client(Duration::from_millis(200));
        let err = tokio::time::timeout(
            Duration::from_secs(5),
            client.get(format!("http://{addr}/")).send(),
        )
        .await
        .expect("client hung: no request timeout configured")
        .unwrap_err();
        assert!(err.is_timeout(), "expected timeout, got {err}");
    }

    // ====================================================================
    // ERROR HANDLING TESTS
    // ====================================================================

    #[test]
    fn test_error_is_retryable() {
        // Test retryable errors
        assert!(ExchangeError::RateLimit("Too many requests".to_string()).is_retryable());
        assert!(ExchangeError::Unavailable("Service down".to_string()).is_retryable());

        // Test non-retryable errors
        assert!(!ExchangeError::InvalidRequest("Bad params".to_string()).is_retryable());
        assert!(!ExchangeError::Authentication("Invalid key".to_string()).is_retryable());
        assert!(!ExchangeError::InsufficientBalance("Not enough funds".to_string()).is_retryable());
        assert!(!ExchangeError::OrderNotFound("Order 123".to_string()).is_retryable());
        assert!(!ExchangeError::Other("Unknown".to_string()).is_retryable());
    }

    #[test]
    fn test_error_display() {
        let err = ExchangeError::RateLimit("Exceeded 10/sec".to_string());
        let display = format!("{}", err);
        assert!(display.contains("Rate limit exceeded"));
        assert!(display.contains("10/sec"));
    }

    #[test]
    fn test_error_from_json() {
        let json_err = serde_json::from_str::<serde_json::Value>("invalid json").unwrap_err();
        let exchange_err: ExchangeError = json_err.into();
        assert!(matches!(exchange_err, ExchangeError::JsonParse(_)));
    }

    #[test]
    fn test_error_insufficient_balance() {
        let err = ExchangeError::InsufficientBalance("Need 100 USD, have 50 USD".to_string());
        assert!(!err.is_retryable());
        let display = format!("{}", err);
        assert!(display.contains("Insufficient balance"));
    }

    #[test]
    fn test_error_order_not_found() {
        let err = ExchangeError::OrderNotFound("Order ID abc123 not found".to_string());
        assert!(!err.is_retryable());
    }

    #[test]
    fn test_error_authentication() {
        let err = ExchangeError::Authentication("Invalid API key".to_string());
        assert!(!err.is_retryable());
    }

    #[test]
    fn test_error_invalid_request() {
        let err = ExchangeError::InvalidRequest("Quantity must be positive".to_string());
        assert!(!err.is_retryable());
    }

    #[test]
    fn test_error_other() {
        let err = ExchangeError::Other("Unknown error occurred".to_string());
        assert!(!err.is_retryable());
    }
}
