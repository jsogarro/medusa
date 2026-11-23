//! Binance exchange client implementation
//!
//! REST API documentation: https://binance-docs.github.io/apidocs/spot/en/

use crate::client::{ExchangeClient, ExchangeError};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use reqwest::{header, Client};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::sync::Arc;
use tracing::{debug, trace};

type HmacSha256 = Hmac<Sha256>;

const BASE_URL: &str = "https://api.binance.com";

// Security: Validation constants
const MAX_PRICE: f64 = 1_000_000_000.0;
const MAX_QUANTITY: f64 = 1_000_000_000.0;
const MIN_POSITIVE: f64 = 1e-18;

/// Binance exchange client
///
/// # Security
/// API credentials are held in memory as String. For production use,
/// consider using secure memory or credential managers.
///
/// # Rate Limits
/// Binance uses a request weight system:
/// - 1200 weight per minute for most endpoints
/// - 100 orders per 10 seconds
/// - Uses IP-based + account-based limits
#[derive(Clone)]
pub struct BinanceClient {
    client: Client,
    api_key: String,
    secret_key: String,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for BinanceClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BinanceClient")
            .field("api_key", &"<redacted>")
            .field("secret_key", &"<redacted>")
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl BinanceClient {
    /// Create a new Binance client
    ///
    /// # Arguments
    /// * `api_key` - Binance API key
    /// * `secret_key` - Binance secret key (used for HMAC-SHA256 signing)
    ///
    /// # Rate Limits
    /// Binance: 1200 weight/minute (using conservative 15 req/sec = 900/min)
    pub fn new(api_key: String, secret_key: String) -> Self {
        Self {
            client: Client::new(),
            api_key,
            secret_key,
            rate_limiter: Arc::new(RateLimiter::new(15, None)),
        }
    }

    /// Create a new Binance client from environment variables
    ///
    /// # Environment Variables
    /// - `BINANCE_API_KEY` - API key (optional, trading disabled if not set)
    /// - `BINANCE_SECRET_KEY` - Secret key (optional, trading disabled if not set)
    pub fn from_env() -> Self {
        let api_key = std::env::var("BINANCE_API_KEY").unwrap_or_else(|_| {
            eprintln!("WARNING: BINANCE_API_KEY not set — trading disabled");
            String::new()
        });

        let secret_key = std::env::var("BINANCE_SECRET_KEY").unwrap_or_else(|_| {
            eprintln!("WARNING: BINANCE_SECRET_KEY not set — trading disabled");
            String::new()
        });

        Self::new(api_key, secret_key)
    }

    /// Generate authentication signature for Binance API
    ///
    /// HMAC-SHA256 signature of the query string using the secret key.
    fn generate_signature(&self, query_string: &str) -> String {
        let mut mac = HmacSha256::new_from_slice(self.secret_key.as_bytes())
            .expect("HMAC can take key of any size");
        mac.update(query_string.as_bytes());
        let result = mac.finalize();
        hex::encode(result.into_bytes())
    }

    /// Get current timestamp in milliseconds
    fn get_timestamp_ms() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
    }

    /// Normalize pair format (e.g., "BTC/USD" -> "BTCUSDT", "BTC/USDT" -> "BTCUSDT")
    /// Binance uses no separator and USDT instead of USD
    fn normalize_pair(pair: &str) -> String {
        let normalized = pair.replace('/', "").to_uppercase();

        // Only replace trailing USD with USDT if it doesn't already end with USDT
        if normalized.ends_with("USD") && !normalized.ends_with("USDT") {
            // Replace only the trailing USD, not all occurrences
            format!("{}T", normalized)
        } else {
            normalized
        }
    }

    /// Denormalize pair format (e.g., "BTCUSDT" -> "BTC/USDT")
    fn denormalize_pair(pair: &str) -> String {
        // Simple heuristic: if ends with USDT, split before it
        if let Some(base) = pair.strip_suffix("USDT") {
            format!("{}/USDT", base)
        } else if let Some(base) = pair.strip_suffix("BTC") {
            format!("{}/BTC", base)
        } else if let Some(base) = pair.strip_suffix("ETH") {
            format!("{}/ETH", base)
        } else if let Some(base) = pair.strip_suffix("BNB") {
            format!("{}/BNB", base)
        } else {
            // Fallback: assume first 3 chars are base, rest is quote
            if pair.len() > 3 {
                format!("{}/{}", &pair[..3], &pair[3..])
            } else {
                pair.to_string()
            }
        }
    }

    /// Parse Binance error response
    fn parse_error(status: u16, body: &str) -> ExchangeError {
        #[derive(Deserialize)]
        struct BinanceError {
            #[allow(dead_code)]
            code: Option<i32>,
            msg: String,
        }

        if let Ok(err) = serde_json::from_str::<BinanceError>(body) {
            let msg = err.msg.clone();
            return match status {
                429 => ExchangeError::RateLimit(msg),
                401 | 403 => ExchangeError::Authentication(msg),
                400 if msg.to_lowercase().contains("insufficient") => {
                    ExchangeError::InsufficientBalance(msg)
                }
                400 => ExchangeError::InvalidRequest(msg),
                _ => ExchangeError::Other(format!("Binance error: {}", msg)),
            };
        }

        ExchangeError::Other(format!("Binance error {}: {}", status, body))
    }

    /// Check if credentials are configured
    fn has_credentials(&self) -> bool {
        !self.api_key.is_empty() && !self.secret_key.is_empty()
    }
}

// Binance API response types
#[derive(Debug, Deserialize)]
struct BinanceOrderBook {
    #[serde(rename = "lastUpdateId")]
    #[allow(dead_code)]
    last_update_id: u64,
    bids: Vec<Vec<String>>, // [price, quantity]
    asks: Vec<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct BinanceBalance {
    asset: String,
    free: String,
    locked: String,
}

#[derive(Debug, Deserialize)]
struct BinanceAccountInfo {
    balances: Vec<BinanceBalance>,
}

#[allow(dead_code)]
#[derive(Debug, Serialize)]
struct BinanceOrderRequest {
    symbol: String,
    side: String, // "BUY" or "SELL"
    #[serde(rename = "type")]
    order_type: String, // "LIMIT" or "MARKET"
    #[serde(rename = "timeInForce")]
    #[serde(skip_serializing_if = "Option::is_none")]
    time_in_force: Option<String>, // "GTC" for limit orders
    #[serde(skip_serializing_if = "Option::is_none")]
    quantity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    price: Option<String>,
    timestamp: String,
    signature: String,
}

#[derive(Debug, Deserialize)]
struct BinanceOrderResponse {
    #[serde(rename = "orderId")]
    order_id: u64,
    #[allow(dead_code)]
    symbol: String,
    #[allow(dead_code)]
    status: String,
    #[allow(dead_code)]
    side: String,
    #[allow(dead_code)]
    #[serde(rename = "type")]
    order_type: String,
    #[allow(dead_code)]
    price: String,
    #[allow(dead_code)]
    #[serde(rename = "origQty")]
    orig_qty: String,
    #[allow(dead_code)]
    #[serde(rename = "executedQty")]
    executed_qty: String,
    #[allow(dead_code)]
    #[serde(rename = "transactTime")]
    trans_time: Option<u64>,
    #[allow(dead_code)]
    #[serde(rename = "updateTime")]
    update_time: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct BinanceOrder {
    #[serde(rename = "orderId")]
    order_id: u64,
    symbol: String,
    #[allow(dead_code)]
    status: String,
    side: String,
    #[serde(rename = "type")]
    order_type: String,
    price: String,
    #[serde(rename = "origQty")]
    orig_qty: String,
    #[serde(rename = "executedQty")]
    executed_qty: String,
    time: u64,
    #[serde(rename = "updateTime")]
    update_time: u64,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct BinanceTrade {
    id: u64,
    price: String,
    qty: String,
    time: u64,
    #[serde(rename = "isBuyerMaker")]
    is_buyer_maker: bool,
}

#[async_trait]
impl ExchangeClient for BinanceClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        let normalized_pair = Self::normalize_pair(pair);
        let url = format!("{}/api/v3/depth", BASE_URL);

        trace!("Fetching Binance orderbook for {}", pair);
        self.rate_limiter.acquire(Some("/depth"), 1).await;

        let response = self
            .client
            .get(&url)
            .query(&[("symbol", &normalized_pair), ("limit", &"50".to_string())])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BinanceOrderBook = serde_json::from_str(&body)?;

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
                return Err(ExchangeError::Other(format!(
                    "Price out of range: {}",
                    price
                )));
            }
            if !quantity.is_finite() || !(0.0..=MAX_QUANTITY).contains(&quantity) {
                return Err(ExchangeError::Other(format!(
                    "Quantity out of range: {}",
                    quantity
                )));
            }

            Ok(PriceLevel { price, quantity })
        };

        let bids: Result<Vec<_>, _> = data.bids.iter().map(|b| parse_level(b)).collect();
        let asks: Result<Vec<_>, _> = data.asks.iter().map(|a| parse_level(a)).collect();

        Ok(OrderBook {
            pair: pair.to_string(),
            exchange: "binance".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        let url = format!("{}/api/v3/account", BASE_URL);
        let timestamp = Self::get_timestamp_ms();
        let query_string = format!("timestamp={}", timestamp);
        let signature = self.generate_signature(&query_string);

        trace!("Fetching Binance balance");
        self.rate_limiter.acquire(Some("/account"), 1).await;

        let response = self
            .client
            .get(&url)
            .header("X-MBX-APIKEY", &self.api_key)
            .query(&[
                ("timestamp", timestamp.to_string()),
                ("signature", signature),
            ])
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BinanceAccountInfo = serde_json::from_str(&body)?;

        let mut balances = Vec::new();
        for balance in data.balances {
            if let Some(filter_asset) = asset {
                if !balance.asset.eq_ignore_ascii_case(filter_asset) {
                    continue;
                }
            }

            let free: f64 = balance.free.parse().unwrap_or(0.0);
            let locked: f64 = balance.locked.parse().unwrap_or(0.0);
            let total = free + locked;

            // Only include non-zero balances
            if total > 0.0 {
                balances.push(Balance {
                    asset: balance.asset,
                    exchange: "binance".to_string(),
                    total,
                    available: free,
                    locked,
                });
            }
        }

        Ok(balances)
    }

    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError> {
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        let url = format!("{}/api/v3/openOrders", BASE_URL);
        let timestamp = Self::get_timestamp_ms();

        let mut query_params = vec![("timestamp", timestamp.to_string())];
        if let Some(p) = pair {
            query_params.push(("symbol", Self::normalize_pair(p)));
        }

        let query_string = query_params
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");
        let signature = self.generate_signature(&query_string);
        query_params.push(("signature", signature));

        trace!("Fetching Binance open orders");
        self.rate_limiter.acquire(Some("/openOrders"), 1).await;

        let response = self
            .client
            .get(&url)
            .header("X-MBX-APIKEY", &self.api_key)
            .query(&query_params)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: Vec<BinanceOrder> = serde_json::from_str(&body)?;

        let orders = data
            .into_iter()
            .map(|o| {
                let side = if o.side == "BUY" {
                    Side::Buy
                } else {
                    Side::Sell
                };
                let order_type = match o.order_type.as_str() {
                    "LIMIT" => OrderType::Limit,
                    "MARKET" => OrderType::Market,
                    _ => OrderType::Limit,
                };

                Order {
                    id: Some(o.order_id.to_string()),
                    pair: Self::denormalize_pair(&o.symbol),
                    exchange: "binance".to_string(),
                    side,
                    price: o.price.parse().ok(),
                    quantity: o.orig_qty.parse().unwrap_or(0.0),
                    order_type,
                    status: OrderStatus::Open,
                    client_order_id: None,
                    filled_quantity: o.executed_qty.parse().unwrap_or(0.0),
                    average_price: None,
                    created_at: DateTime::from_timestamp_millis(o.time as i64)
                        .unwrap_or_else(Utc::now),
                    updated_at: DateTime::from_timestamp_millis(o.update_time as i64)
                        .unwrap_or_else(Utc::now),
                }
            })
            .collect();

        Ok(orders)
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        // Binance requires symbol for querying orders, so we search through open orders
        let orders = self.get_open_orders(None).await?;
        orders
            .into_iter()
            .find(|o| o.id.as_ref() == Some(&order_id.to_string()))
            .ok_or_else(|| ExchangeError::OrderNotFound(order_id.to_string()))
    }

    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError> {
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        let url = format!("{}/api/v3/order", BASE_URL);
        let timestamp = Self::get_timestamp_ms();

        let order_type = match order.order_type {
            OrderType::Limit => "LIMIT",
            OrderType::Market => "MARKET",
            _ => {
                return Err(ExchangeError::InvalidRequest(
                    "Unsupported order type".into(),
                ))
            }
        };

        let side = match order.side {
            Side::Buy => "BUY",
            Side::Sell => "SELL",
        };

        let symbol = Self::normalize_pair(&order.pair);
        let mut params = vec![
            ("symbol", symbol.clone()),
            ("side", side.to_string()),
            ("type", order_type.to_string()),
            ("quantity", order.quantity.to_string()),
            ("timestamp", timestamp.to_string()),
        ];

        if order.order_type == OrderType::Limit {
            if let Some(price) = order.price {
                params.push(("price", price.to_string()));
                params.push(("timeInForce", "GTC".to_string()));
            } else {
                return Err(ExchangeError::InvalidRequest(
                    "Limit order requires price".into(),
                ));
            }
        }

        let query_string = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");
        let signature = self.generate_signature(&query_string);
        params.push(("signature", signature));

        debug!(
            "Placing Binance order: {:?} {} {} @ {:?}",
            order.side, order.quantity, order.pair, order.price
        );
        self.rate_limiter.acquire(Some("/order"), 1).await;

        let response = self
            .client
            .post(&url)
            .header("X-MBX-APIKEY", &self.api_key)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
            .query(&params)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await?;
            return Err(Self::parse_error(status.as_u16(), &body));
        }

        let body = response.text().await?;
        let data: BinanceOrderResponse = serde_json::from_str(&body)?;

        Ok(data.order_id.to_string())
    }

    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError> {
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        // First, find the order to get its symbol
        let orders = self.get_open_orders(None).await?;
        let order = orders
            .iter()
            .find(|o| o.id.as_ref() == Some(&order_id.to_string()))
            .ok_or_else(|| ExchangeError::OrderNotFound(order_id.to_string()))?;

        let url = format!("{}/api/v3/order", BASE_URL);
        let timestamp = Self::get_timestamp_ms();
        let symbol = Self::normalize_pair(&order.pair);

        let params = vec![
            ("symbol", symbol),
            ("orderId", order_id.to_string()),
            ("timestamp", timestamp.to_string()),
        ];

        let query_string = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");
        let signature = self.generate_signature(&query_string);

        debug!("Cancelling Binance order: {}", order_id);
        self.rate_limiter.acquire(Some("/order"), 1).await;

        let response = self
            .client
            .delete(&url)
            .header("X-MBX-APIKEY", &self.api_key)
            .query(&params)
            .query(&[("signature", signature)])
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
        if !self.has_credentials() {
            return Err(ExchangeError::Authentication(
                "API credentials not configured".into(),
            ));
        }

        // Binance supports bulk cancel per symbol, but we'll cancel one by one for consistency
        let orders = self.get_open_orders(pair).await?;
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

    // === Pair Normalization Tests ===

    #[test]
    fn test_normalize_pair_btcusd() {
        assert_eq!(BinanceClient::normalize_pair("BTC/USD"), "BTCUSDT");
    }

    #[test]
    fn test_normalize_pair_ethusdt() {
        // Already USDT, should remain unchanged (except case)
        assert_eq!(BinanceClient::normalize_pair("ETH/USDT"), "ETHUSDT");
    }

    #[test]
    fn test_normalize_pair_usdcusd() {
        // Edge case: USDC/USD → USDCUSDT (not USDCUSD)
        assert_eq!(BinanceClient::normalize_pair("USDC/USD"), "USDCUSDT");
    }

    #[test]
    fn test_normalize_pair_case_insensitive() {
        assert_eq!(BinanceClient::normalize_pair("btc/usd"), "BTCUSDT");
        assert_eq!(BinanceClient::normalize_pair("Eth/Usd"), "ETHUSDT");
    }

    #[test]
    fn test_normalize_pair_stablecoins() {
        // USDC/USD should not double-append T
        assert_eq!(BinanceClient::normalize_pair("USDC/USD"), "USDCUSDT");
        // USDT pairs should remain USDT
        assert_eq!(BinanceClient::normalize_pair("BTC/USDT"), "BTCUSDT");
        assert_eq!(BinanceClient::normalize_pair("ETH/USDT"), "ETHUSDT");
        // DAI/USD edge case
        assert_eq!(BinanceClient::normalize_pair("DAI/USD"), "DAIUSDT");
    }

    #[test]
    fn test_normalize_pair_btc_quote() {
        // BTC as quote currency
        assert_eq!(BinanceClient::normalize_pair("ETH/BTC"), "ETHBTC");
        assert_eq!(BinanceClient::normalize_pair("XRP/BTC"), "XRPBTC");
    }

    #[test]
    fn test_normalize_pair_unusual_pairs() {
        // EUR quote
        assert_eq!(BinanceClient::normalize_pair("BTC/EUR"), "BTCEUR");
        // GBP quote
        assert_eq!(BinanceClient::normalize_pair("ETH/GBP"), "ETHGBP");
        // BNB quote
        assert_eq!(BinanceClient::normalize_pair("XRP/BNB"), "XRPBNB");
    }

    #[test]
    fn test_denormalize_pair() {
        assert_eq!(BinanceClient::denormalize_pair("BTCUSDT"), "BTC/USDT");
        assert_eq!(BinanceClient::denormalize_pair("ETHUSDT"), "ETH/USDT");
        assert_eq!(BinanceClient::denormalize_pair("SOLUSDT"), "SOL/USDT");
    }

    #[test]
    fn test_denormalize_pair_btc_quote() {
        assert_eq!(BinanceClient::denormalize_pair("ETHBTC"), "ETH/BTC");
    }

    // === HMAC Signature Tests ===

    #[test]
    fn test_hmac_signature_known_vector() {
        // Test HMAC-SHA256 with known input/output (verified against independent implementation)
        let client = BinanceClient::new("test_key".to_string(), "test_secret".to_string());
        let query = "symbol=BTCUSDT&timestamp=1234567890";
        let signature = client.generate_signature(query);

        // Signature should be 64-character hex string (SHA256 = 32 bytes = 64 hex chars)
        assert_eq!(signature.len(), 64);
        assert!(signature.chars().all(|c| c.is_ascii_hexdigit()));

        // Verify exact signature value (computed with HMAC-SHA256("test_secret", query))
        // This is a known cryptographic test vector
        assert_eq!(
            signature, "0c87db1e95fcf098ba03f5db382607bf937bcc8c1da02cf29875d67f6229d76e",
            "HMAC signature mismatch - expected consistent cryptographic output"
        );
    }

    #[test]
    fn test_hmac_signature_deterministic() {
        let client = BinanceClient::new("test_key".to_string(), "test_secret".to_string());
        let query = "symbol=BTCUSDT&timestamp=1234567890";

        let sig1 = client.generate_signature(query);
        let sig2 = client.generate_signature(query);

        // Same input should produce same signature
        assert_eq!(sig1, sig2);
    }

    // === Response Parsing Tests ===

    #[test]
    fn test_parse_account_response() {
        let json = r#"{
            "balances": [
                {"asset": "BTC", "free": "1.5", "locked": "0.5"},
                {"asset": "ETH", "free": "10.0", "locked": "0.0"},
                {"asset": "USDT", "free": "0.0", "locked": "0.0"}
            ]
        }"#;

        let account: BinanceAccountInfo =
            serde_json::from_str(json).expect("Valid account JSON should parse successfully");

        assert_eq!(account.balances.len(), 3);
        assert_eq!(account.balances[0].asset, "BTC");
        assert_eq!(account.balances[0].free, "1.5");
        assert_eq!(account.balances[0].locked, "0.5");
    }

    #[test]
    fn test_parse_account_response_missing_balances() {
        let json = r#"{"other_field": "value"}"#;

        let result: Result<BinanceAccountInfo, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Account response without balances field should fail to parse"
        );
    }

    #[test]
    fn test_parse_account_response_invalid_balance_structure() {
        let json = r#"{
            "balances": [
                {"asset": "BTC"}
            ]
        }"#;

        let result: Result<BinanceAccountInfo, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Balance without free/locked fields should fail to parse"
        );
    }

    #[test]
    fn test_parse_order_response() {
        let json = r#"{
            "orderId": 12345,
            "symbol": "BTCUSDT",
            "status": "NEW",
            "side": "BUY",
            "type": "LIMIT",
            "price": "67000.00",
            "origQty": "0.1",
            "executedQty": "0.0",
            "transactTime": 1640000000000,
            "updateTime": 1640000000000
        }"#;

        let order: BinanceOrderResponse = serde_json::from_str(json)
            .expect("Valid order response JSON should parse successfully");

        assert_eq!(order.order_id, 12345);
        assert_eq!(order.symbol, "BTCUSDT");
        assert_eq!(order.status, "NEW");
        assert_eq!(order.side, "BUY");
        assert_eq!(order.order_type, "LIMIT");
        assert_eq!(order.price, "67000.00");
    }

    #[test]
    fn test_parse_order_response_missing_order_id() {
        let json = r#"{
            "symbol": "BTCUSDT",
            "status": "NEW",
            "side": "BUY",
            "type": "LIMIT",
            "price": "67000.00",
            "origQty": "0.1",
            "executedQty": "0.0"
        }"#;

        let result: Result<BinanceOrderResponse, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Order response without orderId should fail to parse"
        );
    }

    #[test]
    fn test_parse_order_response_invalid_side() {
        let json = r#"{
            "orderId": 12345,
            "symbol": "BTCUSDT",
            "status": "NEW",
            "side": 123,
            "type": "LIMIT",
            "price": "67000.00",
            "origQty": "0.1",
            "executedQty": "0.0"
        }"#;

        let result: Result<BinanceOrderResponse, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Order response with invalid side type should fail to parse"
        );
    }

    #[test]
    fn test_parse_orderbook_response() {
        let json = r#"{
            "lastUpdateId": 1234567890,
            "bids": [
                ["67000.00", "0.5"],
                ["66999.00", "1.0"]
            ],
            "asks": [
                ["67001.00", "0.3"],
                ["67002.00", "0.7"]
            ]
        }"#;

        let orderbook: BinanceOrderBook =
            serde_json::from_str(json).expect("Valid orderbook JSON should parse successfully");

        assert_eq!(orderbook.last_update_id, 1234567890);
        assert_eq!(orderbook.bids.len(), 2);
        assert_eq!(orderbook.asks.len(), 2);
        assert_eq!(orderbook.bids[0][0], "67000.00");
        assert_eq!(orderbook.bids[0][1], "0.5");
    }

    #[test]
    fn test_parse_orderbook_response_missing_field() {
        // Missing lastUpdateId
        let json = r#"{
            "bids": [["67000.00", "0.5"]],
            "asks": [["67001.00", "0.3"]]
        }"#;

        let result: Result<BinanceOrderBook, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Orderbook with missing lastUpdateId should fail to parse"
        );
    }

    #[test]
    fn test_parse_orderbook_response_invalid_bid_format() {
        // Bid with wrong type (number instead of string array)
        let json = r#"{
            "lastUpdateId": 1234567890,
            "bids": [67000.00],
            "asks": [["67001.00", "0.3"]]
        }"#;

        let result: Result<BinanceOrderBook, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "Orderbook with invalid bid format should fail to parse"
        );
    }

    // === Error Handling Tests ===

    #[test]
    fn test_error_rate_limit() {
        let err = BinanceClient::parse_error(429, r#"{"code": -1003, "msg": "Too many requests"}"#);
        assert!(matches!(err, ExchangeError::RateLimit(_)));
    }

    #[test]
    fn test_error_authentication() {
        let err = BinanceClient::parse_error(
            401,
            r#"{"code": -2015, "msg": "Invalid API-key, IP, or permissions"}"#,
        );
        assert!(matches!(err, ExchangeError::Authentication(_)));
    }

    #[test]
    fn test_error_insufficient_balance() {
        let err = BinanceClient::parse_error(
            400,
            r#"{"code": -2010, "msg": "Account has insufficient balance for requested action"}"#,
        );
        assert!(matches!(err, ExchangeError::InsufficientBalance(_)));
    }

    #[test]
    fn test_error_invalid_request() {
        let err = BinanceClient::parse_error(
            400,
            r#"{"code": -1102, "msg": "Mandatory parameter 'symbol' was not sent"}"#,
        );
        assert!(matches!(err, ExchangeError::InvalidRequest(_)));
    }

    #[test]
    fn test_error_malformed_json() {
        let err = BinanceClient::parse_error(500, r#"Not JSON response"#);
        assert!(matches!(err, ExchangeError::Other(_)));
    }

    // === Credential Validation Tests ===

    #[test]
    fn test_has_credentials_true() {
        let client = BinanceClient::new("valid_key".to_string(), "valid_secret".to_string());
        assert!(client.has_credentials());
    }

    #[test]
    fn test_has_credentials_false_empty_key() {
        let client = BinanceClient::new("".to_string(), "valid_secret".to_string());
        assert!(!client.has_credentials());
    }

    #[test]
    fn test_has_credentials_false_empty_secret() {
        let client = BinanceClient::new("valid_key".to_string(), "".to_string());
        assert!(!client.has_credentials());
    }

    // === Debug Implementation Test ===

    #[test]
    fn test_debug_redacts_credentials() {
        let client = BinanceClient::new(
            "super_secret_key".to_string(),
            "super_secret_secret".to_string(),
        );
        let debug_str = format!("{:?}", client);

        assert!(!debug_str.contains("super_secret_key"));
        assert!(!debug_str.contains("super_secret_secret"));
        assert!(debug_str.contains("<redacted>"));
    }
}
