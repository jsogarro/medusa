//! Bitstamp exchange client implementation
//!
//! REST API documentation: https://www.bitstamp.net/api/

use crate::client::{ExchangeClient, ExchangeError};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tracing::{debug, trace};

type HmacSha256 = Hmac<Sha256>;

const BASE_URL: &str = "https://www.bitstamp.net/api/v2";

// Security: Atomic counter for nonce uniqueness
static NONCE_COUNTER: AtomicU64 = AtomicU64::new(0);

// Security: Validation constants for price/quantity bounds
const MAX_PRICE: f64 = 1_000_000_000.0;  // $1B per unit
const MAX_QUANTITY: f64 = 1_000_000_000.0; // 1B units
const MIN_POSITIVE: f64 = 1e-18;  // 18 decimal places

/// Bitstamp REST client
///
/// # Security
/// API credentials are held in memory as String. For production use,
/// consider using secure memory or credential managers.
#[derive(Clone)]
pub struct BitstampClient {
    client: Client,
    api_key: String,
    api_secret: String,
    customer_id: String,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for BitstampClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BitstampClient")
            .field("api_key", &"<redacted>")
            .field("api_secret", &"<redacted>")
            .field("customer_id", &"<redacted>")
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl BitstampClient {
    /// Create a new Bitstamp client
    ///
    /// # Arguments
    /// * `api_key` - Bitstamp API key
    /// * `api_secret` - Bitstamp API secret
    /// * `customer_id` - Bitstamp customer ID
    ///
    /// # Rate Limits
    /// Bitstamp rate limits: 8000 requests per 10 minutes = ~13 req/sec
    pub fn new(api_key: String, api_secret: String, customer_id: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            api_secret,
            customer_id,
            rate_limiter: Arc::new(RateLimiter::new(13, Some(8000 / 10))), // 13/sec, 800/min
        }
    }

    /// Generate HMAC signature for authenticated requests
    ///
    /// HMAC operations are inherently constant-time safe.
    fn generate_signature(&self, nonce: u64, message: &str) -> String {
        let signature_input = format!("{}{}{}", nonce, self.customer_id, self.api_key);
        let mut mac = HmacSha256::new_from_slice(self.api_secret.as_bytes())
            .expect("HMAC can take key of any size");
        mac.update(signature_input.as_bytes());
        mac.update(message.as_bytes());
        hex::encode(mac.finalize().into_bytes()).to_uppercase()
    }

    /// Get current nonce with microsecond precision and uniqueness guarantee
    ///
    /// # Security
    /// Uses microsecond timestamps with atomic counter to prevent nonce collisions
    /// even under high-frequency trading conditions. Guarantees strictly increasing
    /// nonces even if called multiple times within the same microsecond.
    fn get_nonce() -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_micros() as u64;

        // Ensure strictly increasing nonces using compare-exchange
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

    /// Normalize pair format (e.g., "BTC/USD" -> "btcusd")
    fn normalize_pair(pair: &str) -> String {
        pair.replace('/', "").to_lowercase()
    }

    /// Parse Bitstamp error response
    ///
    /// # Security
    /// Error messages are returned as-is from the API. In production,
    /// sanitize error messages before logging to prevent credential leaks.
    fn parse_error(status: u16, body: &str) -> ExchangeError {
        #[derive(Deserialize)]
        struct ErrorResponse {
            #[serde(default)]
            error: Option<String>,
            #[serde(default)]
            reason: Option<serde_json::Value>,
        }

        if let Ok(err_resp) = serde_json::from_str::<ErrorResponse>(body) {
            let message = err_resp
                .error
                .or_else(|| err_resp.reason.as_ref().and_then(|r| r.as_str().map(String::from)))
                .unwrap_or_else(|| body.to_string());

            return match status {
                429 => ExchangeError::RateLimit(message),
                401 | 403 => ExchangeError::Authentication(message),
                400 if message.contains("insufficient") => ExchangeError::InsufficientBalance(message),
                404 => ExchangeError::OrderNotFound(message),
                _ => ExchangeError::Other(format!("Bitstamp error {}: {}", status, message)),
            };
        }

        ExchangeError::Other(format!("Bitstamp error {}: {}", status, body))
    }
}

// Bitstamp API response types
#[derive(Debug, Deserialize)]
struct BitstampOrderBook {
    timestamp: String,
    bids: Vec<Vec<String>>, // [price, amount]
    asks: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct BitstampBalance {
    #[serde(flatten)]
    balances: std::collections::HashMap<String, String>,
}

#[derive(Debug, Serialize)]
struct BitstampOrderRequest {
    amount: String,
    price: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    daily_order: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct BitstampOrderResponse {
    id: String,
    #[serde(default)]
    datetime: Option<String>,
    #[serde(rename = "type")]
    side: String, // "0" = buy, "1" = sell
    price: String,
    amount: String,
}

#[async_trait]
impl ExchangeClient for BitstampClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        let normalized_pair = Self::normalize_pair(pair);
        let url = format!("{}/order_book/{}/", BASE_URL, normalized_pair);

        trace!("Fetching Bitstamp orderbook for {}", pair);
        self.rate_limiter.acquire(Some("/order_book"), 1).await;

        let response = self.client.get(&url).send().await?;
        let status = response.status();

        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BitstampOrderBook = serde_json::from_str(&body)?;

        // Parse timestamp
        let timestamp = data
            .timestamp
            .parse::<i64>()
            .map(|ts| DateTime::from_timestamp(ts, 0).unwrap_or_else(Utc::now))
            .unwrap_or_else(|_| Utc::now());

        // Parse price levels with validation
        let parse_level = |level: &[String]| -> Result<PriceLevel, ExchangeError> {
            if level.len() < 2 {
                return Err(ExchangeError::Other("Invalid price level format".into()));
            }

            let price: f64 = level[0].parse().map_err(|_| {
                ExchangeError::Other(format!("Invalid price: {}", level[0]))
            })?;

            let quantity: f64 = level[1].parse().map_err(|_| {
                ExchangeError::Other(format!("Invalid quantity: {}", level[1]))
            })?;

            // Security: Validate numeric bounds to prevent overflow/manipulation
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
            exchange: "bitstamp".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp,
            sequence: None, // REST API doesn't provide sequence numbers
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        let url = format!("{}/balance/", BASE_URL);
        let nonce = Self::get_nonce();
        let signature = self.generate_signature(nonce, "");

        trace!("Fetching Bitstamp balance");
        self.rate_limiter.acquire(Some("/balance"), 1).await;

        let response = self
            .client
            .post(&url)
            .form(&[
                ("key", self.api_key.as_str()),
                ("signature", &signature),
                ("nonce", &nonce.to_string()),
            ])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BitstampBalance = serde_json::from_str(&body)?;

        // Parse balance data (Bitstamp returns fields like "btc_balance", "btc_available", "btc_reserved")
        let mut balances = Vec::new();
        let mut assets = std::collections::HashSet::new();

        for (key, _value) in data.balances.iter() {
            if let Some(asset_suffix) = key.strip_suffix("_balance") {
                assets.insert(asset_suffix.to_uppercase());
            }
        }

        for asset_name in assets {
            let asset_lower = asset_name.to_lowercase();
            let total = data
                .balances
                .get(&format!("{}_balance", asset_lower))
                .and_then(|v| v.parse::<f64>().ok())
                .unwrap_or(0.0);
            let available = data
                .balances
                .get(&format!("{}_available", asset_lower))
                .and_then(|v| v.parse::<f64>().ok())
                .unwrap_or(0.0);
            let locked = data
                .balances
                .get(&format!("{}_reserved", asset_lower))
                .and_then(|v| v.parse::<f64>().ok())
                .unwrap_or(0.0);

            if let Some(filter_asset) = asset {
                if asset_name != filter_asset.to_uppercase() {
                    continue;
                }
            }

            balances.push(Balance {
                asset: asset_name,
                exchange: "bitstamp".to_string(),
                total,
                available,
                locked,
            });
        }

        Ok(balances)
    }

    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError> {
        let url = if let Some(p) = pair {
            format!("{}/open_orders/{}/", BASE_URL, Self::normalize_pair(p))
        } else {
            format!("{}/open_orders/all/", BASE_URL)
        };

        let nonce = Self::get_nonce();
        let signature = self.generate_signature(nonce, "");

        trace!("Fetching Bitstamp open orders");
        self.rate_limiter.acquire(Some("/open_orders"), 1).await;

        let response = self
            .client
            .post(&url)
            .form(&[
                ("key", self.api_key.as_str()),
                ("signature", &signature),
                ("nonce", &nonce.to_string()),
            ])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: Vec<BitstampOrderResponse> = serde_json::from_str(&body)?;

        let orders = data
            .into_iter()
            .map(|o| {
                let side = if o.side == "0" { Side::Buy } else { Side::Sell };
                let price: f64 = o.price.parse().unwrap_or(0.0);
                let quantity: f64 = o.amount.parse().unwrap_or(0.0);
                let created_at = o
                    .datetime
                    .as_ref()
                    .and_then(|dt| DateTime::parse_from_rfc3339(dt).ok())
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(Utc::now);

                Order {
                    id: Some(o.id),
                    pair: pair.map(String::from).unwrap_or_default(),
                    exchange: "bitstamp".to_string(),
                    side,
                    price: Some(price),
                    quantity,
                    order_type: OrderType::Limit,
                    status: OrderStatus::Open,
                    client_order_id: None,
                    filled_quantity: 0.0,
                    average_price: None,
                    created_at,
                    updated_at: created_at,
                }
            })
            .collect();

        Ok(orders)
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        // Bitstamp doesn't have a direct "get order by ID" endpoint
        // We need to fetch all open orders and filter
        let orders = self.get_open_orders(None).await?;
        orders
            .into_iter()
            .find(|o| o.id.as_ref() == Some(&order_id.to_string()))
            .ok_or_else(|| ExchangeError::OrderNotFound(order_id.to_string()))
    }

    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError> {
        let normalized_pair = Self::normalize_pair(&order.pair);
        let endpoint = match (order.side, order.order_type) {
            (Side::Buy, OrderType::Limit) => format!("/buy/{}/", normalized_pair),
            (Side::Sell, OrderType::Limit) => format!("/sell/{}/", normalized_pair),
            (Side::Buy, OrderType::Market) => format!("/buy/market/{}/", normalized_pair),
            (Side::Sell, OrderType::Market) => format!("/sell/market/{}/", normalized_pair),
            _ => {
                return Err(ExchangeError::InvalidRequest(format!(
                    "Unsupported order type: {:?}",
                    order.order_type
                )))
            }
        };

        let url = format!("{}{}", BASE_URL, endpoint);
        let nonce = Self::get_nonce();
        let signature = self.generate_signature(nonce, "");

        let request_body = BitstampOrderRequest {
            amount: order.quantity.to_string(),
            price: order.price.map(|p| p.to_string()),
            daily_order: None,
        };

        debug!(
            "Placing Bitstamp order: {:?} {} {} @ {:?}",
            order.side, order.quantity, order.pair, order.price
        );
        self.rate_limiter.acquire(Some(&endpoint), 1).await;

        let nonce_str = nonce.to_string();
        let mut form_data = vec![
            ("key", self.api_key.as_str()),
            ("signature", &signature),
            ("nonce", &nonce_str),
            ("amount", &request_body.amount),
        ];

        if let Some(ref price) = request_body.price {
            form_data.push(("price", price));
        }

        let response = self.client.post(&url).form(&form_data).send().await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BitstampOrderResponse = serde_json::from_str(&body)?;

        Ok(data.id)
    }

    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError> {
        let url = format!("{}/cancel_order/", BASE_URL);
        let nonce = Self::get_nonce();
        let signature = self.generate_signature(nonce, "");

        debug!("Cancelling Bitstamp order: {}", order_id);
        self.rate_limiter.acquire(Some("/cancel_order"), 1).await;

        let response = self
            .client
            .post(&url)
            .form(&[
                ("key", self.api_key.as_str()),
                ("signature", &signature),
                ("nonce", &nonce.to_string()),
                ("id", order_id),
            ])
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
        let url = if let Some(p) = pair {
            format!("{}/cancel_all_orders/{}/", BASE_URL, Self::normalize_pair(p))
        } else {
            format!("{}/cancel_all_orders/", BASE_URL)
        };

        let nonce = Self::get_nonce();
        let signature = self.generate_signature(nonce, "");

        debug!("Cancelling all Bitstamp orders for {:?}", pair);
        self.rate_limiter.acquire(Some("/cancel_all_orders"), 1).await;

        let response = self
            .client
            .post(&url)
            .form(&[
                ("key", self.api_key.as_str()),
                ("signature", &signature),
                ("nonce", &nonce.to_string()),
            ])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        // Bitstamp returns {"success": true} or {"canceled": [...]}
        // Count cancelled orders if available
        let body = response.text().await?;
        if let Ok(resp) = serde_json::from_str::<serde_json::Value>(&body) {
            if let Some(canceled) = resp.get("canceled").and_then(|v| v.as_array()) {
                return Ok(canceled.len() as u32);
            }
        }

        // If no count available, return 0 (success but unknown count)
        Ok(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_pair() {
        assert_eq!(BitstampClient::normalize_pair("BTC/USD"), "btcusd");
        assert_eq!(BitstampClient::normalize_pair("ETH/EUR"), "etheur");
        assert_eq!(BitstampClient::normalize_pair("btcusd"), "btcusd");
    }

    #[test]
    fn test_parse_error() {
        let err = BitstampClient::parse_error(
            429,
            r#"{"error": "Rate limit exceeded"}"#,
        );
        assert!(matches!(err, ExchangeError::RateLimit(_)));

        let err = BitstampClient::parse_error(
            401,
            r#"{"error": "Invalid API key"}"#,
        );
        assert!(matches!(err, ExchangeError::Authentication(_)));

        let err = BitstampClient::parse_error(
            400,
            r#"{"error": "insufficient funds"}"#,
        );
        assert!(matches!(err, ExchangeError::InsufficientBalance(_)));
    }

    // Note: Real API tests require credentials and should be run manually or in CI with test credentials
}
