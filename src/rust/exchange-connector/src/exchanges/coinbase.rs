//! Coinbase exchange client implementation
//!
//! REST API documentation: https://docs.cloud.coinbase.com/exchange/reference

use crate::client::{ExchangeClient, ExchangeError};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use reqwest::{Client, header};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tracing::{debug, trace};

type HmacSha256 = Hmac<Sha256>;

const BASE_URL: &str = "https://api.exchange.coinbase.com";

// Security: Atomic counter for nonce uniqueness
static NONCE_COUNTER: AtomicU64 = AtomicU64::new(0);

// Security: Validation constants for price/quantity bounds
const MAX_PRICE: f64 = 1_000_000_000.0;
const MAX_QUANTITY: f64 = 1_000_000_000.0;
const MIN_POSITIVE: f64 = 1e-18;

/// Coinbase exchange client
///
/// # Security
/// API credentials are held in memory as String. For production use,
/// consider using secure memory or credential managers.
#[derive(Clone)]
pub struct CoinbaseClient {
    client: Client,
    api_key: String,
    api_secret: String,
    passphrase: String,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for CoinbaseClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CoinbaseClient")
            .field("api_key", &"<redacted>")
            .field("api_secret", &"<redacted>")
            .field("passphrase", &"<redacted>")
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl CoinbaseClient {
    /// Create a new Coinbase client
    ///
    /// # Arguments
    /// * `api_key` - Coinbase API key
    /// * `api_secret` - Coinbase API secret (base64 encoded)
    /// * `passphrase` - Coinbase API passphrase
    ///
    /// # Rate Limits
    /// Coinbase: 10 requests/sec for public, 5 requests/sec for private endpoints
    pub fn new(api_key: String, api_secret: String, passphrase: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            api_secret,
            passphrase,
            rate_limiter: Arc::new(RateLimiter::new(5, None)), // Conservative 5/sec limit
        }
    }

    /// Generate authentication headers for Coinbase API
    ///
    /// HMAC operations are inherently constant-time safe.
    fn generate_auth_headers(
        &self,
        timestamp: u64,
        method: &str,
        path: &str,
        body: &str,
    ) -> Result<(String, String, String, String), ExchangeError> {
        // Construct the prehash string
        let what = format!("{}{}{}{}", timestamp, method, path, body);

        // Decode base64 secret
        let secret_bytes = general_purpose::STANDARD
            .decode(&self.api_secret)
            .map_err(|e| ExchangeError::Authentication(format!("Invalid API secret: {}", e)))?;

        // Create HMAC-SHA256 signature
        let mut mac = HmacSha256::new_from_slice(&secret_bytes)
            .map_err(|e| ExchangeError::Authentication(format!("HMAC error: {}", e)))?;
        mac.update(what.as_bytes());
        let signature = general_purpose::STANDARD.encode(mac.finalize().into_bytes());

        Ok((
            self.api_key.clone(),
            signature,
            timestamp.to_string(),
            self.passphrase.clone(),
        ))
    }

    /// Get current timestamp with uniqueness guarantee
    ///
    /// # Security
    /// Ensures strictly increasing timestamps to prevent nonce collisions.
    fn get_timestamp() -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Ensure strictly increasing timestamps
        loop {
            let prev = NONCE_COUNTER.load(Ordering::Acquire);
            let next = now.max(prev + 1);
            if NONCE_COUNTER
                .compare_exchange(prev, next, Ordering::Release, Ordering::Acquire)
                .is_ok()
            {
                return next;
            }
        }
    }

    /// Normalize pair format (e.g., "BTC/USD" -> "BTC-USD")
    fn normalize_pair(pair: &str) -> String {
        pair.replace('/', "-").to_uppercase()
    }

    /// Parse Coinbase error response
    fn parse_error(status: u16, body: &str) -> ExchangeError {
        #[derive(Deserialize)]
        struct ErrorResponse {
            message: String,
        }

        if let Ok(err_resp) = serde_json::from_str::<ErrorResponse>(body) {
            return match status {
                429 => ExchangeError::RateLimit(err_resp.message),
                401 | 403 => ExchangeError::Authentication(err_resp.message),
                400 if err_resp.message.to_lowercase().contains("insufficient") => {
                    ExchangeError::InsufficientBalance(err_resp.message)
                }
                404 => ExchangeError::OrderNotFound(err_resp.message),
                _ => ExchangeError::Other(format!("Coinbase error {}: {}", status, err_resp.message)),
            };
        }

        ExchangeError::Other(format!("Coinbase error {}: {}", status, body))
    }
}

// Coinbase API response types
#[derive(Debug, Deserialize)]
struct CoinbaseOrderBook {
    sequence: u64,
    bids: Vec<Vec<String>>, // [price, size, num_orders]
    asks: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseAccount {
    #[allow(dead_code)]
    id: String,
    currency: String,
    balance: String,
    available: String,
    hold: String,
}

#[derive(Debug, Serialize)]
struct CoinbaseOrderRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    client_oid: Option<String>,
    #[serde(rename = "type")]
    order_type: String, // "limit" or "market"
    side: String,       // "buy" or "sell"
    product_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    price: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CoinbaseOrderResponse {
    id: String,
    price: Option<String>,
    size: String,
    product_id: String,
    side: String,
    #[serde(rename = "type")]
    order_type: String,
    status: String,
    filled_size: String,
    executed_value: Option<String>,
    created_at: String,
}

#[async_trait]
impl ExchangeClient for CoinbaseClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        let product_id = Self::normalize_pair(pair);
        let path = format!("/products/{}/book?level=2", product_id);
        let url = format!("{}{}", BASE_URL, path);

        trace!("Fetching Coinbase orderbook for {}", pair);
        self.rate_limiter.acquire(Some("/products"), 1).await;

        let response = self.client.get(&url).send().await?;
        let status = response.status();

        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: CoinbaseOrderBook = serde_json::from_str(&body)?;

        // Parse price levels with validation
        let parse_level = |level: &[String]| -> Result<PriceLevel, ExchangeError> {
            if level.len() < 2 {
                return Err(ExchangeError::Other("Invalid price level format".into()));
            }

            let price: f64 = level[0]
                .parse()
                .map_err(|_| ExchangeError::Other(format!("Invalid price: {}", level[0])))?;

            let quantity: f64 = level[1]
                .parse()
                .map_err(|_| ExchangeError::Other(format!("Invalid quantity: {}", level[1])))?;

            // Security: Validate numeric bounds
            if !price.is_finite() || !(MIN_POSITIVE..=MAX_PRICE).contains(&price) {
                return Err(ExchangeError::Other(format!("Price out of range: {}", price)));
            }
            if !quantity.is_finite() || !(0.0..=MAX_QUANTITY).contains(&quantity) {
                return Err(ExchangeError::Other(format!("Quantity out of range: {}", quantity)));
            }

            Ok(PriceLevel { price, quantity })
        };

        let bids: Result<Vec<_>, _> = data.bids.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = data.asks.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair: pair.to_string(),
            exchange: "coinbase".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: Some(data.sequence),
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        let path = "/accounts";
        let url = format!("{}{}", BASE_URL, path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", path, "")?;

        trace!("Fetching Coinbase balance");
        self.rate_limiter.acquire(Some("/accounts"), 1).await;

        let response = self
            .client
            .get(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let accounts: Vec<CoinbaseAccount> = serde_json::from_str(&body)?;

        let balances: Vec<Balance> = accounts
            .into_iter()
            .filter(|acc| {
                if let Some(filter_asset) = asset {
                    acc.currency.eq_ignore_ascii_case(filter_asset)
                } else {
                    true
                }
            })
            .map(|acc| Balance {
                asset: acc.currency,
                exchange: "coinbase".to_string(),
                total: acc.balance.parse().unwrap_or(0.0),
                available: acc.available.parse().unwrap_or(0.0),
                locked: acc.hold.parse().unwrap_or(0.0),
            })
            .collect();

        Ok(balances)
    }

    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError> {
        let path = "/orders";
        let url = if let Some(p) = pair {
            format!("{}{}?product_id={}", BASE_URL, path, Self::normalize_pair(p))
        } else {
            format!("{}{}", BASE_URL, path)
        };

        let timestamp = Self::get_timestamp();
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", path, "")?;

        trace!("Fetching Coinbase open orders");
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        let response = self
            .client
            .get(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: Vec<CoinbaseOrderResponse> = serde_json::from_str(&body)?;

        let orders = data
            .into_iter()
            .map(|o| {
                let side = if o.side == "buy" { Side::Buy } else { Side::Sell };
                let order_type = match o.order_type.as_str() {
                    "limit" => OrderType::Limit,
                    "market" => OrderType::Market,
                    _ => OrderType::Limit,
                };
                let status = match o.status.as_str() {
                    "open" => OrderStatus::Open,
                    "pending" => OrderStatus::Pending,
                    "done" => OrderStatus::Filled,
                    "rejected" => OrderStatus::Rejected,
                    _ => OrderStatus::Open,
                };

                Order {
                    id: Some(o.id),
                    pair: o.product_id.replace('-', "/"),
                    exchange: "coinbase".to_string(),
                    side,
                    price: o.price.and_then(|p| p.parse().ok()),
                    quantity: o.size.parse().unwrap_or(0.0),
                    order_type,
                    status,
                    client_order_id: None,
                    filled_quantity: o.filled_size.parse().unwrap_or(0.0),
                    average_price: o
                        .executed_value
                        .and_then(|v| v.parse::<f64>().ok())
                        .and_then(|v| {
                            let filled: f64 = o.filled_size.parse().ok()?;
                            if filled > 0.0 {
                                Some(v / filled)
                            } else {
                                None
                            }
                        }),
                    created_at: DateTime::parse_from_rfc3339(&o.created_at)
                        .ok()
                        .map(|dt| dt.with_timezone(&Utc))
                        .unwrap_or_else(Utc::now),
                    updated_at: Utc::now(),
                }
            })
            .collect();

        Ok(orders)
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        let path = format!("/orders/{}", order_id);
        let url = format!("{}{}", BASE_URL, path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", &path, "")?;

        trace!("Fetching Coinbase order: {}", order_id);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        let response = self
            .client
            .get(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let o: CoinbaseOrderResponse = serde_json::from_str(&body)?;

        let side = if o.side == "buy" { Side::Buy } else { Side::Sell };
        let order_type = match o.order_type.as_str() {
            "limit" => OrderType::Limit,
            "market" => OrderType::Market,
            _ => OrderType::Limit,
        };
        let status = match o.status.as_str() {
            "open" => OrderStatus::Open,
            "pending" => OrderStatus::Pending,
            "done" => OrderStatus::Filled,
            "rejected" => OrderStatus::Rejected,
            _ => OrderStatus::Open,
        };

        Ok(Order {
            id: Some(o.id),
            pair: o.product_id.replace('-', "/"),
            exchange: "coinbase".to_string(),
            side,
            price: o.price.and_then(|p| p.parse().ok()),
            quantity: o.size.parse().unwrap_or(0.0),
            order_type,
            status,
            client_order_id: None,
            filled_quantity: o.filled_size.parse().unwrap_or(0.0),
            average_price: None,
            created_at: DateTime::parse_from_rfc3339(&o.created_at)
                .ok()
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(Utc::now),
            updated_at: Utc::now(),
        })
    }

    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError> {
        let path = "/orders";
        let url = format!("{}{}", BASE_URL, path);
        let timestamp = Self::get_timestamp();

        let order_type = match order.order_type {
            OrderType::Limit => "limit",
            OrderType::Market => "market",
            _ => return Err(ExchangeError::InvalidRequest("Unsupported order type".into())),
        };

        let request_body = CoinbaseOrderRequest {
            client_oid: order.client_order_id.clone(),
            order_type: order_type.to_string(),
            side: match order.side {
                Side::Buy => "buy".to_string(),
                Side::Sell => "sell".to_string(),
            },
            product_id: Self::normalize_pair(&order.pair),
            price: order.price.map(|p| p.to_string()),
            size: Some(order.quantity.to_string()),
        };

        let body_json = serde_json::to_string(&request_body)?;
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "POST", path, &body_json)?;

        debug!(
            "Placing Coinbase order: {:?} {} {} @ {:?}",
            order.side, order.quantity, order.pair, order.price
        );
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .header(header::CONTENT_TYPE, "application/json")
            .body(body_json)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: CoinbaseOrderResponse = serde_json::from_str(&body)?;

        Ok(data.id)
    }

    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError> {
        let path = format!("/orders/{}", order_id);
        let url = format!("{}{}", BASE_URL, path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "DELETE", &path, "")?;

        debug!("Cancelling Coinbase order: {}", order_id);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        let response = self
            .client
            .delete(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        Ok(())
    }

    async fn cancel_all_orders(&self, pair: Option<&str>) -> Result<u32, ExchangeError> {
        let path = "/orders";
        let url = if let Some(p) = pair {
            format!("{}{}?product_id={}", BASE_URL, path, Self::normalize_pair(p))
        } else {
            format!("{}{}", BASE_URL, path)
        };

        let timestamp = Self::get_timestamp();
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "DELETE", path, "")?;

        debug!("Cancelling all Coinbase orders for {:?}", pair);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        let response = self
            .client
            .delete(&url)
            .header("CB-ACCESS-KEY", api_key)
            .header("CB-ACCESS-SIGN", signature)
            .header("CB-ACCESS-TIMESTAMP", ts)
            .header("CB-ACCESS-PASSPHRASE", passphrase)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        // Coinbase returns an array of cancelled order IDs
        let body = response.text().await?;
        if let Ok(canceled_ids) = serde_json::from_str::<Vec<String>>(&body) {
            return Ok(canceled_ids.len() as u32);
        }

        Ok(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_pair() {
        assert_eq!(CoinbaseClient::normalize_pair("BTC/USD"), "BTC-USD");
        assert_eq!(CoinbaseClient::normalize_pair("ETH/EUR"), "ETH-EUR");
        assert_eq!(CoinbaseClient::normalize_pair("btc/usd"), "BTC-USD");
    }

    #[test]
    fn test_parse_error() {
        let err = CoinbaseClient::parse_error(429, r#"{"message": "Rate limit exceeded"}"#);
        assert!(matches!(err, ExchangeError::RateLimit(_)));

        let err = CoinbaseClient::parse_error(401, r#"{"message": "Invalid API key"}"#);
        assert!(matches!(err, ExchangeError::Authentication(_)));

        let err = CoinbaseClient::parse_error(
            400,
            r#"{"message": "Insufficient funds"}"#,
        );
        assert!(matches!(err, ExchangeError::InsufficientBalance(_)));
    }
}
