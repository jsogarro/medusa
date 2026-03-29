//! Kraken exchange client implementation
//!
//! REST API documentation: https://docs.kraken.com/rest/

use crate::client::{ExchangeClient, ExchangeError};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use reqwest::{Client, header};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256, Sha512};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tracing::{debug, trace};

type HmacSha512 = Hmac<Sha512>;

const BASE_URL: &str = "https://api.kraken.com";

// Security: Atomic counter for nonce uniqueness
static NONCE_COUNTER: AtomicU64 = AtomicU64::new(0);

// Security: Validation constants
const MAX_PRICE: f64 = 1_000_000_000.0;
const MAX_QUANTITY: f64 = 1_000_000_000.0;
const MIN_POSITIVE: f64 = 1e-18;

/// Kraken exchange client
///
/// # Security
/// API credentials are held in memory as String. For production use,
/// consider using secure memory or credential managers.
#[derive(Clone)]
pub struct KrakenClient {
    client: Client,
    api_key: String,
    api_secret: String,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for KrakenClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("KrakenClient")
            .field("api_key", &"<redacted>")
            .field("api_secret", &"<redacted>")
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl KrakenClient {
    /// Create a new Kraken client
    ///
    /// # Arguments
    /// * `api_key` - Kraken API key
    /// * `api_secret` - Kraken API secret (base64 encoded)
    ///
    /// # Rate Limits
    /// Kraken: 15 requests/sec for Tier 2, 20 for Tier 3 (using conservative 10/sec)
    pub fn new(api_key: String, api_secret: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            api_secret,
            rate_limiter: Arc::new(RateLimiter::new(10, None)),
        }
    }

    /// Generate authentication signature for Kraken API
    ///
    /// HMAC operations are inherently constant-time safe.
    fn generate_signature(
        &self,
        path: &str,
        nonce: u64,
        postdata: &str,
    ) -> Result<String, ExchangeError> {
        // Decode base64 secret
        let secret_bytes = general_purpose::STANDARD
            .decode(&self.api_secret)
            .map_err(|e| ExchangeError::Authentication(format!("Invalid API secret: {}", e)))?;

        // Compute SHA256 hash of (nonce + postdata)
        let mut hasher = Sha256::new();
        hasher.update(format!("{}{}", nonce, postdata));
        let hash = hasher.finalize();

        // Compute HMAC-SHA512 of (path + hash)
        let mut message = path.as_bytes().to_vec();
        message.extend_from_slice(&hash);

        let mut mac = HmacSha512::new_from_slice(&secret_bytes)
            .map_err(|e| ExchangeError::Authentication(format!("HMAC error: {}", e)))?;
        mac.update(&message);
        let signature = general_purpose::STANDARD.encode(mac.finalize().into_bytes());

        Ok(signature)
    }

    /// Get current nonce with microsecond precision and uniqueness guarantee
    ///
    /// # Security
    /// Uses microsecond timestamps with atomic counter for collision prevention.
    fn get_nonce() -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_micros() as u64;

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

    /// Normalize pair format (e.g., "BTC/USD" -> "XBTUSDT")
    /// Kraken uses special codes: BTC -> XBT, some pairs have Z/X prefixes
    fn normalize_pair(pair: &str) -> String {
        pair.replace('/', "")
            .replace("BTC", "XBT")
            .to_uppercase()
    }

    /// Parse Kraken error response
    fn parse_error(status: u16, body: &str) -> ExchangeError {
        #[derive(Deserialize)]
        struct KrakenResponse {
            error: Vec<String>,
        }

        if let Ok(resp) = serde_json::from_str::<KrakenResponse>(body) {
            if let Some(err_msg) = resp.error.first() {
                return match status {
                    429 => ExchangeError::RateLimit(err_msg.clone()),
                    401 | 403 => ExchangeError::Authentication(err_msg.clone()),
                    400 if err_msg.to_lowercase().contains("insufficient") => {
                        ExchangeError::InsufficientBalance(err_msg.clone())
                    }
                    _ => ExchangeError::Other(format!("Kraken error: {}", err_msg)),
                };
            }
        }

        ExchangeError::Other(format!("Kraken error {}: {}", status, body))
    }
}

// Kraken API response types
#[derive(Debug, Deserialize)]
struct KrakenResponse<T> {
    error: Vec<String>,
    result: Option<T>,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderBook {
    #[serde(flatten)]
    pairs: HashMap<String, KrakenOrderBookData>,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderBookData {
    asks: Vec<Vec<String>>, // [price, volume, timestamp]
    bids: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct KrakenBalance {
    #[serde(flatten)]
    balances: HashMap<String, String>,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
struct KrakenOrderRequest {
    nonce: String,
    ordertype: String, // "limit" or "market"
    #[serde(rename = "type")]
    side: String, // "buy" or "sell"
    pair: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    price: Option<String>,
    volume: String,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderResult {
    #[allow(dead_code)]
    descr: KrakenOrderDescription,
    txid: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderDescription {
    #[allow(dead_code)]
    order: String,
}

#[derive(Debug, Deserialize)]
struct KrakenOpenOrders {
    open: HashMap<String, KrakenOrderInfo>,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderInfo {
    descr: KrakenOrderDescr,
    vol: String,
    vol_exec: String,
    #[allow(dead_code)]
    status: String,
    opentm: f64,
}

#[derive(Debug, Deserialize)]
struct KrakenOrderDescr {
    pair: String,
    #[serde(rename = "type")]
    side: String,
    ordertype: String,
    price: String,
}

#[async_trait]
impl ExchangeClient for KrakenClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        let normalized_pair = Self::normalize_pair(pair);
        let url = format!("{}/0/public/Depth", BASE_URL);

        trace!("Fetching Kraken orderbook for {}", pair);
        self.rate_limiter.acquire(Some("/Depth"), 1).await;

        let response = self
            .client
            .get(&url)
            .query(&[("pair", &normalized_pair)])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: KrakenResponse<KrakenOrderBook> = serde_json::from_str(&body)?;

        if !data.error.is_empty() {
            return Err(ExchangeError::Other(format!(
                "Kraken API error: {}",
                data.error.join(", ")
            )));
        }

        let result = data
            .result
            .ok_or_else(|| ExchangeError::Other("Missing result in Kraken response".into()))?;

        // Kraken returns the orderbook under the pair name key
        let book_data = result
            .pairs
            .values()
            .next()
            .ok_or_else(|| ExchangeError::Other("Empty orderbook response".into()))?;

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

        let bids: Result<Vec<_>, _> = book_data.bids.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = book_data.asks.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair: pair.to_string(),
            exchange: "kraken".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        let path = "/0/private/Balance";
        let url = format!("{}{}", BASE_URL, path);
        let nonce = Self::get_nonce();
        let postdata = format!("nonce={}", nonce);

        let signature = self.generate_signature(path, nonce, &postdata)?;

        trace!("Fetching Kraken balance");
        self.rate_limiter.acquire(Some("/Balance"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("API-Key", &self.api_key)
            .header("API-Sign", signature)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(postdata)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: KrakenResponse<KrakenBalance> = serde_json::from_str(&body)?;

        if !data.error.is_empty() {
            return Err(ExchangeError::Other(format!(
                "Kraken API error: {}",
                data.error.join(", ")
            )));
        }

        let result = data
            .result
            .ok_or_else(|| ExchangeError::Other("Missing result in Kraken response".into()))?;

        let mut balances = Vec::new();
        for (asset_name, amount) in result.balances {
            // Kraken prefixes assets with Z (fiat) or X (crypto)
            let normalized_asset = asset_name.trim_start_matches(['Z', 'X']);

            if let Some(filter_asset) = asset {
                if !normalized_asset.eq_ignore_ascii_case(filter_asset) {
                    continue;
                }
            }

            let total: f64 = amount.parse().unwrap_or(0.0);
            balances.push(Balance {
                asset: normalized_asset.to_uppercase(),
                exchange: "kraken".to_string(),
                total,
                available: total, // Kraken doesn't separate available/locked in Balance endpoint
                locked: 0.0,
            });
        }

        Ok(balances)
    }

    async fn get_open_orders(&self, _pair: Option<&str>) -> Result<Vec<Order>, ExchangeError> {
        let path = "/0/private/OpenOrders";
        let url = format!("{}{}", BASE_URL, path);
        let nonce = Self::get_nonce();
        let postdata = format!("nonce={}", nonce);

        let signature = self.generate_signature(path, nonce, &postdata)?;

        trace!("Fetching Kraken open orders");
        self.rate_limiter.acquire(Some("/OpenOrders"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("API-Key", &self.api_key)
            .header("API-Sign", signature)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(postdata)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: KrakenResponse<KrakenOpenOrders> = serde_json::from_str(&body)?;

        if !data.error.is_empty() {
            return Err(ExchangeError::Other(format!(
                "Kraken API error: {}",
                data.error.join(", ")
            )));
        }

        let result = data
            .result
            .ok_or_else(|| ExchangeError::Other("Missing result in Kraken response".into()))?;

        let orders = result
            .open
            .into_iter()
            .map(|(order_id, info)| {
                let side = if info.descr.side == "buy" {
                    Side::Buy
                } else {
                    Side::Sell
                };
                let order_type = match info.descr.ordertype.as_str() {
                    "limit" => OrderType::Limit,
                    "market" => OrderType::Market,
                    _ => OrderType::Limit,
                };

                Order {
                    id: Some(order_id),
                    pair: info.descr.pair.clone(),
                    exchange: "kraken".to_string(),
                    side,
                    price: info.descr.price.parse().ok(),
                    quantity: info.vol.parse().unwrap_or(0.0),
                    order_type,
                    status: OrderStatus::Open,
                    client_order_id: None,
                    filled_quantity: info.vol_exec.parse().unwrap_or(0.0),
                    average_price: None,
                    created_at: DateTime::from_timestamp(info.opentm as i64, 0)
                        .unwrap_or_else(Utc::now),
                    updated_at: Utc::now(),
                }
            })
            .collect();

        Ok(orders)
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        // Kraken's QueryOrders endpoint requires txid
        let orders = self.get_open_orders(None).await?;
        orders
            .into_iter()
            .find(|o| o.id.as_ref() == Some(&order_id.to_string()))
            .ok_or_else(|| ExchangeError::OrderNotFound(order_id.to_string()))
    }

    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError> {
        let path = "/0/private/AddOrder";
        let url = format!("{}{}", BASE_URL, path);
        let nonce = Self::get_nonce();

        let order_type = match order.order_type {
            OrderType::Limit => "limit",
            OrderType::Market => "market",
            _ => return Err(ExchangeError::InvalidRequest("Unsupported order type".into())),
        };

        let side = match order.side {
            Side::Buy => "buy",
            Side::Sell => "sell",
        };

        let mut form_data = vec![
            ("nonce", nonce.to_string()),
            ("ordertype", order_type.to_string()),
            ("type", side.to_string()),
            ("pair", Self::normalize_pair(&order.pair)),
            ("volume", order.quantity.to_string()),
        ];

        if let Some(price) = order.price {
            form_data.push(("price", price.to_string()));
        }

        let postdata = form_data
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");

        let signature = self.generate_signature(path, nonce, &postdata)?;

        debug!(
            "Placing Kraken order: {:?} {} {} @ {:?}",
            order.side, order.quantity, order.pair, order.price
        );
        self.rate_limiter.acquire(Some("/AddOrder"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("API-Key", &self.api_key)
            .header("API-Sign", signature)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(postdata)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: KrakenResponse<KrakenOrderResult> = serde_json::from_str(&body)?;

        if !data.error.is_empty() {
            return Err(ExchangeError::Other(format!(
                "Kraken API error: {}",
                data.error.join(", ")
            )));
        }

        let result = data
            .result
            .ok_or_else(|| ExchangeError::Other("Missing result in Kraken response".into()))?;

        result
            .txid
            .first()
            .cloned()
            .ok_or_else(|| ExchangeError::Other("No transaction ID in response".into()))
    }

    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError> {
        let path = "/0/private/CancelOrder";
        let url = format!("{}{}", BASE_URL, path);
        let nonce = Self::get_nonce();
        let postdata = format!("nonce={}&txid={}", nonce, order_id);

        let signature = self.generate_signature(path, nonce, &postdata)?;

        debug!("Cancelling Kraken order: {}", order_id);
        self.rate_limiter.acquire(Some("/CancelOrder"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("API-Key", &self.api_key)
            .header("API-Sign", signature)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(postdata)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: KrakenResponse<serde_json::Value> = serde_json::from_str(&body)?;

        if !data.error.is_empty() {
            return Err(ExchangeError::Other(format!(
                "Kraken API error: {}",
                data.error.join(", ")
            )));
        }

        Ok(())
    }

    async fn cancel_all_orders(&self, _pair: Option<&str>) -> Result<u32, ExchangeError> {
        // Kraken doesn't have a bulk cancel endpoint, so we cancel orders one by one
        let orders = self.get_open_orders(None).await?;
        let mut count = 0;

        for order in orders {
            if let Some(order_id) = order.id {
                if self.cancel_order(&order_id).await.is_ok() {
                    count += 1;
                }
            }
        }

        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_pair() {
        assert_eq!(KrakenClient::normalize_pair("BTC/USD"), "XBTUSD");
        assert_eq!(KrakenClient::normalize_pair("ETH/EUR"), "ETHEUR");
    }

    #[test]
    fn test_parse_error() {
        let err = KrakenClient::parse_error(
            400,
            r#"{"error": ["EGeneral:Invalid arguments"]}"#,
        );
        assert!(matches!(err, ExchangeError::Other(_)));

        let err = KrakenClient::parse_error(
            400,
            r#"{"error": ["EFunding:Insufficient funds"]}"#,
        );
        assert!(matches!(err, ExchangeError::InsufficientBalance(_)));
    }
}
