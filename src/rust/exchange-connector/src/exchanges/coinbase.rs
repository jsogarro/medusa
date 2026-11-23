//! Coinbase exchange client implementation
//!
//! Supports both Exchange API (legacy) and Advanced Trade API v3.
//! REST API documentation:
//! - Exchange: https://docs.cloud.coinbase.com/exchange/reference
//! - Advanced Trade: https://docs.cdp.coinbase.com/advanced-trade/docs

use crate::client::{
    http_client, parse_order_type, parse_side, unknown_status, ExchangeClient, ExchangeError,
    MAX_PRICE, MAX_QUANTITY, MIN_POSITIVE,
};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use jsonwebtoken::{crypto, Algorithm, EncodingKey};
use rand::Rng;
use reqwest::{header, Client};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::sync::Arc;
use tracing::{debug, trace, warn};

type HmacSha256 = Hmac<Sha256>;

// API URLs - Toggle with COINBASE_USE_ADVANCED_TRADE env var
const LEGACY_BASE_URL: &str = "https://api.exchange.coinbase.com";
const ADVANCED_BASE_URL: &str = "https://api.coinbase.com";
const ADVANCED_HOST: &str = "api.coinbase.com";

/// Coinbase exchange client
///
/// # Security
/// API credentials are held in memory as String. For production use,
/// consider using secure memory or credential managers.
///
/// # API Versions
/// Supports both Exchange API (legacy, HMAC auth) and Advanced Trade API v3 (JWT auth).
/// Toggle via COINBASE_USE_ADVANCED_TRADE env var (default: true).
#[derive(Clone)]
pub struct CoinbaseClient {
    client: Client,
    api_key: String,
    api_secret: String,
    passphrase: Option<String>, // Only for Exchange API (legacy)
    use_advanced: bool,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for CoinbaseClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CoinbaseClient")
            .field("api_key", &"<redacted>")
            .field("api_secret", &"<redacted>")
            .field("passphrase", &"<redacted>")
            .field("use_advanced", &self.use_advanced)
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl CoinbaseClient {
    /// Create a new Coinbase client
    ///
    /// # Arguments
    /// * `api_key` - Coinbase API key
    /// * `api_secret` - For Exchange API: base64 encoded secret. For Advanced Trade: PEM private key
    /// * `passphrase` - Coinbase API passphrase (Exchange API only, ignored for Advanced Trade)
    ///
    /// # Rate Limits
    /// Coinbase: 10 requests/sec for public, 5 requests/sec for private endpoints
    ///
    /// # Environment Variables
    /// * `COINBASE_USE_ADVANCED_TRADE` - Set to "true" for Advanced Trade API v3 (default: true)
    /// * `COINBASE_KEY_NAME` - API key name for Advanced Trade (required if use_advanced=true)
    /// * `COINBASE_PRIVATE_KEY` - PEM private key for Advanced Trade (required if use_advanced=true)
    pub fn new(api_key: String, api_secret: String, passphrase: String) -> Self {
        let use_advanced = std::env::var("COINBASE_USE_ADVANCED_TRADE")
            .unwrap_or_else(|_| "true".to_string())
            == "true";

        if use_advanced {
            warn!("Advanced Trade API enabled. Ensure COINBASE_KEY_NAME and COINBASE_PRIVATE_KEY env vars are set.");
        }

        Self {
            client: http_client(),
            api_key,
            api_secret,
            passphrase: if use_advanced { None } else { Some(passphrase) },
            use_advanced,
            rate_limiter: Arc::new(RateLimiter::new(5, None)), // Conservative 5/sec limit
        }
    }

    /// Get the base URL for the current API version
    fn base_url(&self) -> &'static str {
        if self.use_advanced {
            ADVANCED_BASE_URL
        } else {
            LEGACY_BASE_URL
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
            self.passphrase.clone().unwrap_or_default(),
        ))
    }

    /// Current Unix time in seconds. Coinbase validates this against its own
    /// clock (about 30s), so it must track the wall clock; it is not a nonce.
    fn get_timestamp() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
    }

    /// Build the Advanced Trade create-order body. Coinbase deduplicates on
    /// `client_order_id`, so the caller must supply a stable one: minting a
    /// fresh id here would turn every retry of a timed-out request into a
    /// second order.
    fn build_advanced_order_request(
        order: &Order,
    ) -> Result<AdvancedTradeOrderRequest, ExchangeError> {
        let client_order_id = order.client_order_id.clone().ok_or_else(|| {
            ExchangeError::InvalidRequest(
                "client_order_id is required so retries cannot duplicate the order".into(),
            )
        })?;

        let order_configuration = match order.order_type {
            OrderType::Limit => {
                let price = order.price.ok_or_else(|| {
                    ExchangeError::InvalidRequest("Limit order requires price".into())
                })?;
                AdvancedTradeOrderConfig::Limit {
                    limit_limit_gtc: AdvancedTradeLimitGTC {
                        base_size: order.quantity.to_string(),
                        limit_price: price.to_string(),
                        post_only: false,
                    },
                }
            }
            OrderType::Market => AdvancedTradeOrderConfig::Market {
                market_market_ioc: AdvancedTradeMarketIOC {
                    base_size: Some(order.quantity.to_string()),
                    quote_size: None,
                },
            },
            _ => {
                return Err(ExchangeError::InvalidRequest(
                    "Unsupported order type".into(),
                ))
            }
        };

        Ok(AdvancedTradeOrderRequest {
            client_order_id,
            product_id: Self::normalize_pair(&order.pair),
            side: match order.side {
                Side::Buy => "BUY".to_string(),
                Side::Sell => "SELL".to_string(),
            },
            order_configuration,
        })
    }

    /// Build the legacy Exchange API create-order body.
    fn build_legacy_order_request(order: &Order) -> Result<CoinbaseOrderRequest, ExchangeError> {
        let order_type = match order.order_type {
            OrderType::Limit => "limit",
            OrderType::Market => "market",
            _ => {
                return Err(ExchangeError::InvalidRequest(
                    "Unsupported order type".into(),
                ))
            }
        };
        Ok(CoinbaseOrderRequest {
            client_oid: order.client_order_id.clone(),
            order_type: order_type.to_string(),
            side: match order.side {
                Side::Buy => "buy".to_string(),
                Side::Sell => "sell".to_string(),
            },
            product_id: Self::normalize_pair(&order.pair),
            price: order.price.map(|p| p.to_string()),
            size: Some(order.quantity.to_string()),
        })
    }

    fn advanced_status(s: &str) -> Result<OrderStatus, ExchangeError> {
        Ok(match s.to_uppercase().as_str() {
            "OPEN" => OrderStatus::Open,
            "PENDING" => OrderStatus::Pending,
            "FILLED" => OrderStatus::Filled,
            "CANCELLED" => OrderStatus::Cancelled,
            "EXPIRED" => OrderStatus::Expired,
            "FAILED" | "REJECTED" => OrderStatus::Rejected,
            other => return Err(unknown_status(other)),
        })
    }

    /// Legacy `done` only means the order left the book; `done_reason` says
    /// whether it filled or was cancelled.
    fn legacy_status(s: &str, done_reason: Option<&str>) -> Result<OrderStatus, ExchangeError> {
        Ok(match (s, done_reason) {
            ("open" | "active", _) => OrderStatus::Open,
            ("pending" | "received", _) => OrderStatus::Pending,
            ("rejected", _) => OrderStatus::Rejected,
            ("done", Some("filled")) => OrderStatus::Filled,
            ("done", Some("canceled")) => OrderStatus::Cancelled,
            _ => return Err(unknown_status(&format!("{s}/{done_reason:?}"))),
        })
    }

    fn advanced_key_name(&self) -> Result<String, ExchangeError> {
        let key_name = std::env::var("COINBASE_KEY_NAME")
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| self.api_key.clone());

        if key_name.is_empty() {
            return Err(ExchangeError::Authentication(
                "COINBASE_KEY_NAME env var or api_key must be set".to_string(),
            ));
        }

        Ok(key_name)
    }

    fn advanced_private_key_pem(&self) -> Result<String, ExchangeError> {
        let private_key = std::env::var("COINBASE_PRIVATE_KEY")
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| self.api_secret.clone());

        if private_key.is_empty() {
            return Err(ExchangeError::Authentication(
                "COINBASE_PRIVATE_KEY env var or api_secret must be set".to_string(),
            ));
        }

        Ok(private_key)
    }

    fn build_advanced_rest_uri(method: &str, path: &str) -> String {
        format!("{} {}{}", method.to_uppercase(), ADVANCED_HOST, path)
    }

    /// Generate JWT authentication headers for Advanced Trade API
    ///
    /// # Environment Variables
    /// * `COINBASE_KEY_NAME` - API key name (e.g., "organizations/{org_id}/apiKeys/{key_id}")
    /// * `COINBASE_PRIVATE_KEY` - PEM-formatted ES256 private key
    ///
    /// # Arguments
    /// * `request_method` - HTTP method for REST JWTs, or None for WebSocket/public JWTs
    /// * `request_path` - Full request path (including query string) for REST JWTs, or None
    fn generate_jwt(
        &self,
        request_method: Option<&str>,
        request_path: Option<&str>,
    ) -> Result<String, ExchangeError> {
        let key_name = self.advanced_key_name()?;
        let private_key_pem = self.advanced_private_key_pem()?;

        let encoding_key = EncodingKey::from_ec_pem(private_key_pem.as_bytes())
            .map_err(|e| ExchangeError::Authentication(format!("Invalid EC private key: {}", e)))?;

        #[derive(Serialize)]
        struct Claims {
            sub: String,
            iss: String,
            nbf: u64,
            exp: u64,
            #[serde(skip_serializing_if = "Option::is_none")]
            uri: Option<String>,
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // CDP JWTs include a nonce in the header to prevent replay.
        let nonce_hex = format!("{:032x}", rand::thread_rng().gen::<u128>());

        let claims = Claims {
            sub: key_name.clone(),
            iss: "cdp".to_string(),
            nbf: now,
            exp: now + 120, // 2 minute expiry
            uri: request_method
                .zip(request_path)
                .map(|(method, path)| Self::build_advanced_rest_uri(method, path)),
        };

        #[derive(Serialize)]
        struct CoinbaseJwtHeader<'a> {
            alg: &'static str,
            kid: &'a str,
            nonce: &'a str,
            typ: &'static str,
        }

        let header = CoinbaseJwtHeader {
            alg: "ES256",
            kid: &key_name,
            nonce: &nonce_hex,
            typ: "JWT",
        };

        let encoded_header =
            general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(&header).map_err(|e| {
                ExchangeError::Authentication(format!("JWT header encoding failed: {}", e))
            })?);
        let encoded_claims =
            general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).map_err(|e| {
                ExchangeError::Authentication(format!("JWT claims encoding failed: {}", e))
            })?);

        let message = format!("{}.{}", encoded_header, encoded_claims);
        let signature = crypto::sign(message.as_bytes(), &encoding_key, Algorithm::ES256)
            .map_err(|e| ExchangeError::Authentication(format!("JWT signing failed: {}", e)))?;

        Ok(format!("{}.{}", message, signature))
    }

    /// Generate authentication headers for Advanced Trade API
    fn generate_advanced_auth_headers(
        &self,
        method: &str,
        path: &str,
    ) -> Result<header::HeaderMap, ExchangeError> {
        let jwt = self.generate_jwt(Some(method), Some(path))?;
        let mut headers = header::HeaderMap::new();
        headers.insert(
            header::AUTHORIZATION,
            format!("Bearer {}", jwt).parse().map_err(|e| {
                ExchangeError::Authentication(format!("Invalid auth header: {}", e))
            })?,
        );

        Ok(headers)
    }

    fn extract_order_base_size(order_configuration: &serde_json::Value) -> Option<f64> {
        order_configuration.as_object().and_then(|configs| {
            configs.values().find_map(|config| {
                config
                    .get("base_size")
                    .and_then(|value| value.as_str())
                    .and_then(|value| value.parse::<f64>().ok())
            })
        })
    }

    fn extract_order_limit_price(order_configuration: &serde_json::Value) -> Option<f64> {
        order_configuration.as_object().and_then(|configs| {
            configs.values().find_map(|config| {
                config
                    .get("limit_price")
                    .and_then(|value| value.as_str())
                    .and_then(|value| value.parse::<f64>().ok())
            })
        })
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
                _ => {
                    ExchangeError::Other(format!("Coinbase error {}: {}", status, err_resp.message))
                }
            };
        }

        ExchangeError::Other(format!("Coinbase error {}: {}", status, body))
    }
}

// Coinbase Exchange API response types (Legacy)
#[derive(Debug, Deserialize)]
struct CoinbaseOrderBook {
    sequence: u64,
    bids: Vec<Vec<String>>, // [price, size, num_orders]
    asks: Vec<Vec<String>>,
}

// Coinbase Advanced Trade API v3 response types
#[derive(Debug, Deserialize)]
struct AdvancedTradeOrderBook {
    pricebook: AdvancedTradePriceBook,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradePriceBook {
    #[allow(dead_code)]
    product_id: String,
    bids: Vec<AdvancedTradeLevel>,
    asks: Vec<AdvancedTradeLevel>,
    #[allow(dead_code)]
    time: String,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeLevel {
    price: String,
    size: String,
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

// Advanced Trade accounts response
#[derive(Debug, Deserialize)]
struct AdvancedTradeAccountsResponse {
    accounts: Vec<AdvancedTradeAccount>,
    #[allow(dead_code)]
    has_next: bool,
    #[allow(dead_code)]
    cursor: String,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeAccount {
    #[allow(dead_code)]
    uuid: String,
    currency: String,
    available_balance: AdvancedTradeBalance,
    #[serde(default)]
    hold: Option<AdvancedTradeBalance>,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeBalance {
    value: String,
    #[allow(dead_code)]
    currency: String,
}

// Advanced Trade orders response
#[derive(Debug, Deserialize)]
struct AdvancedTradeOrdersResponse {
    orders: Vec<AdvancedTradeOrder>,
    #[allow(dead_code)]
    has_next: bool,
    #[allow(dead_code)]
    cursor: String,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeOrderResponse {
    order: AdvancedTradeOrder,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeCreateOrderResponse {
    success: bool,
    success_response: Option<AdvancedTradeCreateOrderSuccess>,
    error_response: Option<AdvancedTradeCreateOrderError>,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeCreateOrderSuccess {
    order_id: String,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeCreateOrderError {
    message: Option<String>,
    error_details: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AdvancedTradeOrder {
    order_id: String,
    product_id: String,
    side: String, // "BUY" or "SELL"
    #[serde(rename = "type")]
    order_type: String, // "LIMIT", "MARKET"
    status: String,
    #[serde(default)]
    average_filled_price: Option<String>,
    created_time: String,
    filled_size: String,
    order_configuration: serde_json::Value,
}

// Advanced Trade order request
#[derive(Debug, Serialize)]
struct AdvancedTradeOrderRequest {
    client_order_id: String,
    product_id: String,
    side: String, // "BUY" or "SELL" (uppercase)
    order_configuration: AdvancedTradeOrderConfig,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum AdvancedTradeOrderConfig {
    Limit {
        limit_limit_gtc: AdvancedTradeLimitGTC,
    },
    Market {
        market_market_ioc: AdvancedTradeMarketIOC,
    },
}

#[derive(Debug, Serialize)]
struct AdvancedTradeLimitGTC {
    base_size: String,
    limit_price: String,
    post_only: bool,
}

#[derive(Debug, Serialize)]
struct AdvancedTradeMarketIOC {
    #[serde(skip_serializing_if = "Option::is_none")]
    base_size: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    quote_size: Option<String>,
}

// Advanced Trade cancel request
#[derive(Debug, Serialize)]
struct AdvancedTradeCancelRequest {
    order_ids: Vec<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct AdvancedTradeCancelResponse {
    results: Vec<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct CoinbaseOrderRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    client_oid: Option<String>,
    #[serde(rename = "type")]
    order_type: String, // "limit" or "market"
    side: String, // "buy" or "sell"
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
    #[serde(default)]
    done_reason: Option<String>,
    created_at: String,
}

#[async_trait]
impl ExchangeClient for CoinbaseClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        let product_id = Self::normalize_pair(pair);

        if self.use_advanced {
            // Advanced Trade API v3
            let path = format!(
                "/api/v3/brokerage/product_book?product_id={}&limit=50",
                product_id
            );
            let url = format!("{}{}", self.base_url(), path);

            trace!("Fetching Coinbase Advanced Trade orderbook for {}", pair);
            self.rate_limiter.acquire(Some("/products"), 1).await;

            let response = self.client.get(&url).send().await?;
            let status = response.status();

            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            let body = response.text().await?;
            let data: AdvancedTradeOrderBook = serde_json::from_str(&body)?;

            // Parse Advanced Trade format
            let parse_level =
                |level: &AdvancedTradeLevel| -> Result<PriceLevel, ExchangeError> {
                    let price: f64 = level.price.parse().map_err(|_| {
                        ExchangeError::Other(format!("Invalid price: {}", level.price))
                    })?;
                    let quantity: f64 = level.size.parse().map_err(|_| {
                        ExchangeError::Other(format!("Invalid size: {}", level.size))
                    })?;

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

            let bids: Result<Vec<_>, _> = data.pricebook.bids.iter().map(parse_level).collect();
            let asks: Result<Vec<_>, _> = data.pricebook.asks.iter().map(parse_level).collect();

            return Ok(OrderBook {
                pair: pair.to_string(),
                exchange: "coinbase".to_string(),
                bids: bids?,
                asks: asks?,
                timestamp: Utc::now(),
                sequence: None,
            });
        }

        // Legacy Exchange API
        let path = format!("/products/{}/book?level=2", product_id);
        let url = format!("{}{}", self.base_url(), path);

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
            exchange: "coinbase".to_string(),
            bids: bids?,
            asks: asks?,
            timestamp: Utc::now(),
            sequence: Some(data.sequence),
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        trace!("Fetching Coinbase balance");
        self.rate_limiter.acquire(Some("/accounts"), 1).await;

        if self.use_advanced {
            // Advanced Trade API
            let path = "/api/v3/brokerage/accounts";
            let url = format!("{}{}", self.base_url(), path);
            let headers = self.generate_advanced_auth_headers("GET", path)?;

            let response = self.client.get(&url).headers(headers).send().await?;

            let status = response.status();
            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            let body = response.text().await?;
            let data: AdvancedTradeAccountsResponse = serde_json::from_str(&body)?;

            let balances: Vec<Balance> = data
                .accounts
                .into_iter()
                .filter(|acc| {
                    if let Some(filter_asset) = asset {
                        acc.currency.eq_ignore_ascii_case(filter_asset)
                    } else {
                        true
                    }
                })
                .map(|acc| {
                    let available = acc.available_balance.value.parse().unwrap_or(0.0);
                    let locked = acc
                        .hold
                        .as_ref()
                        .and_then(|h| h.value.parse().ok())
                        .unwrap_or(0.0);
                    Balance {
                        asset: acc.currency,
                        exchange: "coinbase".to_string(),
                        total: available + locked,
                        available,
                        locked,
                    }
                })
                .collect();

            return Ok(balances);
        }

        // Legacy Exchange API
        let path = "/accounts";
        let url = format!("{}{}", self.base_url(), path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", path, "")?;

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
        trace!("Fetching Coinbase open orders");
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        if self.use_advanced {
            // Advanced Trade API
            let mut path =
                "/api/v3/brokerage/orders/historical/batch?order_status=OPEN".to_string();
            if let Some(p) = pair {
                path.push_str(&format!("&product_ids={}", Self::normalize_pair(p)));
            }
            let url = format!("{}{}", self.base_url(), path);
            let headers = self.generate_advanced_auth_headers("GET", &path)?;

            let response = self.client.get(&url).headers(headers).send().await?;

            let status = response.status();
            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            let body = response.text().await?;
            let data: AdvancedTradeOrdersResponse = serde_json::from_str(&body)?;

            let orders = data
                .orders
                .into_iter()
                .map(|o| {
                    let side = parse_side(&o.side)?;
                    let order_type = parse_order_type(&o.order_type)?;
                    let status = Self::advanced_status(&o.status)?;

                    // Extract price from order_configuration
                    let price = Self::extract_order_limit_price(&o.order_configuration);
                    let quantity = Self::extract_order_base_size(&o.order_configuration)
                        .unwrap_or_else(|| o.filled_size.parse().unwrap_or(0.0));

                    Ok(Order {
                        id: Some(o.order_id),
                        pair: o.product_id.replace('-', "/"),
                        exchange: "coinbase".to_string(),
                        side,
                        price,
                        quantity,
                        order_type,
                        status,
                        client_order_id: None,
                        filled_quantity: o.filled_size.parse().unwrap_or(0.0),
                        average_price: o.average_filled_price.and_then(|p| p.parse().ok()),
                        created_at: DateTime::parse_from_rfc3339(&o.created_time)
                            .ok()
                            .map(|dt| dt.with_timezone(&Utc))
                            .unwrap_or_else(Utc::now),
                        updated_at: Utc::now(),
                    })
                })
                .collect::<Result<Vec<_>, ExchangeError>>()?;

            return Ok(orders);
        }

        // Legacy Exchange API
        let path = "/orders";
        let url = if let Some(p) = pair {
            format!(
                "{}{}?product_id={}",
                self.base_url(),
                path,
                Self::normalize_pair(p)
            )
        } else {
            format!("{}{}", self.base_url(), path)
        };

        let timestamp = Self::get_timestamp();
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", path, "")?;

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
                let side = parse_side(&o.side)?;
                let order_type = parse_order_type(&o.order_type)?;
                let status = Self::legacy_status(&o.status, o.done_reason.as_deref())?;

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
                })
            })
            .collect::<Result<Vec<_>, ExchangeError>>()?;

        Ok(orders)
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        trace!("Fetching Coinbase order: {}", order_id);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        if self.use_advanced {
            // Advanced Trade API
            let path = format!("/api/v3/brokerage/orders/historical/{}", order_id);
            let url = format!("{}{}", self.base_url(), path);
            let headers = self.generate_advanced_auth_headers("GET", &path)?;

            let response = self.client.get(&url).headers(headers).send().await?;

            let status = response.status();
            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            let body = response.text().await?;
            let data: AdvancedTradeOrderResponse = serde_json::from_str(&body)?;
            let o = data.order;

            let side = parse_side(&o.side)?;
            let order_type = parse_order_type(&o.order_type)?;
            let status = Self::advanced_status(&o.status)?;

            // Extract price from order_configuration
            let price = Self::extract_order_limit_price(&o.order_configuration);
            let quantity = Self::extract_order_base_size(&o.order_configuration)
                .unwrap_or_else(|| o.filled_size.parse().unwrap_or(0.0));

            return Ok(Order {
                id: Some(o.order_id),
                pair: o.product_id.replace('-', "/"),
                exchange: "coinbase".to_string(),
                side,
                price,
                quantity,
                order_type,
                status,
                client_order_id: None,
                filled_quantity: o.filled_size.parse().unwrap_or(0.0),
                average_price: o.average_filled_price.and_then(|p| p.parse().ok()),
                created_at: DateTime::parse_from_rfc3339(&o.created_time)
                    .ok()
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(Utc::now),
                updated_at: Utc::now(),
            });
        }

        // Legacy Exchange API
        let path = format!("/orders/{}", order_id);
        let url = format!("{}{}", self.base_url(), path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "GET", &path, "")?;

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

        let side = parse_side(&o.side)?;
        let order_type = parse_order_type(&o.order_type)?;
        let status = Self::legacy_status(&o.status, o.done_reason.as_deref())?;

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
        crate::client::validate_order(order)?;
        debug!(
            "Placing Coinbase order: {:?} {} {} @ {:?}",
            order.side, order.quantity, order.pair, order.price
        );
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        if self.use_advanced {
            // Advanced Trade API
            let path = "/api/v3/brokerage/orders";
            let url = format!("{}{}", self.base_url(), path);

            let request_body = Self::build_advanced_order_request(order)?;

            let body_json = serde_json::to_string(&request_body)?;
            let headers = self.generate_advanced_auth_headers("POST", path)?;

            let response = self
                .client
                .post(&url)
                .headers(headers)
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
            let data: AdvancedTradeCreateOrderResponse = serde_json::from_str(&body)?;

            if !data.success {
                let message = data
                    .error_response
                    .and_then(|error| error.error_details.or(error.message))
                    .unwrap_or_else(|| "Advanced Trade order creation failed".to_string());
                return Err(ExchangeError::Other(message));
            }

            let success = data.success_response.ok_or_else(|| {
                ExchangeError::Other("Missing success_response in Advanced Trade response".into())
            })?;

            return Ok(success.order_id);
        }

        // Legacy Exchange API
        let path = "/orders";
        let url = format!("{}{}", self.base_url(), path);
        let timestamp = Self::get_timestamp();

        let request_body = Self::build_legacy_order_request(order)?;

        let body_json = serde_json::to_string(&request_body)?;
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "POST", path, &body_json)?;

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
        debug!("Cancelling Coinbase order: {}", order_id);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        if self.use_advanced {
            // Advanced Trade API - uses POST with batch_cancel
            let path = "/api/v3/brokerage/orders/batch_cancel";
            let url = format!("{}{}", self.base_url(), path);

            let request_body = AdvancedTradeCancelRequest {
                order_ids: vec![order_id.to_string()],
            };

            let body_json = serde_json::to_string(&request_body)?;
            let headers = self.generate_advanced_auth_headers("POST", path)?;

            let response = self
                .client
                .post(&url)
                .headers(headers)
                .header(header::CONTENT_TYPE, "application/json")
                .body(body_json)
                .send()
                .await?;

            let status = response.status();
            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            return Ok(());
        }

        // Legacy Exchange API - uses DELETE
        let path = format!("/orders/{}", order_id);
        let url = format!("{}{}", self.base_url(), path);
        let timestamp = Self::get_timestamp();

        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "DELETE", &path, "")?;

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
        debug!("Cancelling all Coinbase orders for {:?}", pair);
        self.rate_limiter.acquire(Some("/orders"), 1).await;

        if self.use_advanced {
            // Advanced Trade API - get all open orders then batch cancel
            let open_orders = self.get_open_orders(pair).await?;
            if open_orders.is_empty() {
                return Ok(0);
            }

            let order_ids: Vec<String> = open_orders.into_iter().filter_map(|o| o.id).collect();

            let count = order_ids.len() as u32;

            let path = "/api/v3/brokerage/orders/batch_cancel";
            let url = format!("{}{}", self.base_url(), path);

            let request_body = AdvancedTradeCancelRequest { order_ids };
            let body_json = serde_json::to_string(&request_body)?;
            let headers = self.generate_advanced_auth_headers("POST", path)?;

            let response = self
                .client
                .post(&url)
                .headers(headers)
                .header(header::CONTENT_TYPE, "application/json")
                .body(body_json)
                .send()
                .await?;

            let status = response.status();
            if !status.is_success() {
                let body = response.text().await?;
                return Err(Self::parse_error(status.as_u16(), &body));
            }

            return Ok(count);
        }

        // Legacy Exchange API
        let path = "/orders";
        let url = if let Some(p) = pair {
            format!(
                "{}{}?product_id={}",
                self.base_url(),
                path,
                Self::normalize_pair(p)
            )
        } else {
            format!("{}{}", self.base_url(), path)
        };

        let timestamp = Self::get_timestamp();
        let (api_key, signature, ts, passphrase) =
            self.generate_auth_headers(timestamp, "DELETE", path, "")?;

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
    use std::sync::{Mutex, OnceLock};

    fn coinbase_env_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    // Non-secret throwaway fixture used only for JWT signing unit tests.
    // Never replace this with a real Coinbase credential.
    fn test_private_key() -> String {
        [
            "-----BEGIN ",
            "PRIVATE KEY-----\n",
            "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgG6CXOcV2xWwNwLBE\n",
            "JoS59byIoBYpIGW89xpC3CM5Hf+hRANCAASjX+UOrgVzFKBCaLmN0fwQIQQYgPyj\n",
            "8v+nYe+0GqhfVZdUhZRkB096Ck3iP7vV6OWQRhqejDR3APS62Sk8mRDn\n",
            "-----END ",
            "PRIVATE KEY-----",
        ]
        .concat()
    }

    fn decode_jwt_part(part: &str) -> serde_json::Value {
        let bytes = general_purpose::URL_SAFE_NO_PAD.decode(part).unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    // === Pair Normalization Tests ===

    #[test]
    fn test_normalize_pair() {
        assert_eq!(CoinbaseClient::normalize_pair("BTC/USD"), "BTC-USD");
        assert_eq!(CoinbaseClient::normalize_pair("ETH/EUR"), "ETH-EUR");
        assert_eq!(CoinbaseClient::normalize_pair("btc/usd"), "BTC-USD");
    }

    #[test]
    fn test_normalize_pair_case_insensitive() {
        assert_eq!(CoinbaseClient::normalize_pair("Btc/Usd"), "BTC-USD");
        assert_eq!(CoinbaseClient::normalize_pair("eTh/eUr"), "ETH-EUR");
    }

    // === Error Parsing Tests ===

    #[test]
    fn test_parse_error() {
        let err = CoinbaseClient::parse_error(429, r#"{"message": "Rate limit exceeded"}"#);
        assert!(matches!(err, ExchangeError::RateLimit(_)));

        let err = CoinbaseClient::parse_error(401, r#"{"message": "Invalid API key"}"#);
        assert!(matches!(err, ExchangeError::Authentication(_)));

        let err = CoinbaseClient::parse_error(400, r#"{"message": "Insufficient funds"}"#);
        assert!(matches!(err, ExchangeError::InsufficientBalance(_)));
    }

    #[test]
    fn test_parse_error_not_found() {
        let err = CoinbaseClient::parse_error(404, r#"{"message": "Order not found"}"#);
        assert!(matches!(err, ExchangeError::OrderNotFound(_)));
    }

    // === JWT Generation Tests ===

    #[test]
    fn test_jwt_generation() {
        let _guard = coinbase_env_lock();
        std::env::set_var("COINBASE_KEY_NAME", "test-key");
        std::env::set_var("COINBASE_PRIVATE_KEY", test_private_key());

        let client = CoinbaseClient::new(
            "test-key".to_string(),
            "test-secret".to_string(),
            "".to_string(),
        );

        let jwt = client
            .generate_jwt(Some("GET"), Some("/api/v3/brokerage/accounts"))
            .unwrap();
        let parts: Vec<&str> = jwt.split('.').collect();
        assert_eq!(parts.len(), 3, "JWT should have header.payload.signature");

        let payload = decode_jwt_part(parts[1]);
        assert_eq!(payload["sub"], "test-key");
        assert_eq!(payload["iss"], "cdp");
        assert_eq!(
            payload["uri"],
            "GET api.coinbase.com/api/v3/brokerage/accounts"
        );

        std::env::remove_var("COINBASE_KEY_NAME");
        std::env::remove_var("COINBASE_PRIVATE_KEY");
    }

    #[test]
    fn test_jwt_has_correct_header() {
        let _guard = coinbase_env_lock();
        std::env::set_var("COINBASE_KEY_NAME", "organizations/123/apiKeys/456");
        std::env::set_var("COINBASE_PRIVATE_KEY", test_private_key());

        let client = CoinbaseClient::new(
            "test-key".to_string(),
            "test-secret".to_string(),
            "".to_string(),
        );

        let jwt = client
            .generate_jwt(Some("POST"), Some("/api/v3/brokerage/orders"))
            .unwrap();
        let parts: Vec<&str> = jwt.split('.').collect();
        assert_eq!(parts.len(), 3, "JWT should have header.payload.signature");

        let header = decode_jwt_part(parts[0]);
        assert_eq!(header["alg"], "ES256");
        assert_eq!(header["typ"], "JWT");
        assert_eq!(header["kid"], "organizations/123/apiKeys/456");
        assert!(header["nonce"]
            .as_str()
            .is_some_and(|value| !value.is_empty()));

        let headers = client
            .generate_advanced_auth_headers("POST", "/api/v3/brokerage/orders")
            .unwrap();
        let auth_header = headers
            .get(header::AUTHORIZATION)
            .unwrap()
            .to_str()
            .unwrap();
        assert!(auth_header.starts_with("Bearer "));

        std::env::remove_var("COINBASE_KEY_NAME");
        std::env::remove_var("COINBASE_PRIVATE_KEY");
    }

    // === Advanced Trade Orderbook Parsing Tests ===

    #[test]
    fn test_parse_advanced_orderbook() {
        let json = r#"{
            "pricebook": {
                "product_id": "BTC-USD",
                "bids": [
                    {"price": "67000.00", "size": "0.5"},
                    {"price": "66999.00", "size": "1.0"}
                ],
                "asks": [
                    {"price": "67001.00", "size": "0.3"},
                    {"price": "67002.00", "size": "0.7"}
                ],
                "time": "2024-01-01T12:00:00Z"
            }
        }"#;

        let orderbook: AdvancedTradeOrderBook = serde_json::from_str(json).unwrap();

        assert_eq!(orderbook.pricebook.product_id, "BTC-USD");
        assert_eq!(orderbook.pricebook.bids.len(), 2);
        assert_eq!(orderbook.pricebook.asks.len(), 2);
        assert_eq!(orderbook.pricebook.bids[0].price, "67000.00");
        assert_eq!(orderbook.pricebook.bids[0].size, "0.5");
    }

    // === Advanced Trade Order Parsing Tests ===

    #[test]
    fn test_parse_advanced_order() {
        let json = r#"{
            "order": {
                "order_id": "abc123",
                "product_id": "BTC-USD",
                "side": "BUY",
                "type": "LIMIT",
                "status": "OPEN",
                "average_filled_price": "67000.00",
                "created_time": "2024-01-01T12:00:00Z",
                "filled_size": "0.0",
                "order_configuration": {}
            }
        }"#;

        let response: AdvancedTradeOrderResponse = serde_json::from_str(json).unwrap();

        assert_eq!(response.order.order_id, "abc123");
        assert_eq!(response.order.product_id, "BTC-USD");
        assert_eq!(response.order.side, "BUY");
        assert_eq!(response.order.order_type, "LIMIT");
        assert_eq!(response.order.status, "OPEN");
    }

    #[test]
    fn test_parse_advanced_create_order_response() {
        let json = r#"{
            "success": true,
            "success_response": {
                "order_id": "order-123"
            }
        }"#;

        let response: AdvancedTradeCreateOrderResponse = serde_json::from_str(json).unwrap();
        assert!(response.success);
        assert_eq!(response.success_response.unwrap().order_id, "order-123");
    }

    #[test]
    fn test_extract_order_configuration_fields() {
        let order_configuration = serde_json::json!({
            "limit_limit_gtc": {
                "base_size": "0.25",
                "limit_price": "67000.00"
            }
        });

        assert_eq!(
            CoinbaseClient::extract_order_base_size(&order_configuration),
            Some(0.25)
        );
        assert_eq!(
            CoinbaseClient::extract_order_limit_price(&order_configuration),
            Some(67000.0)
        );
    }

    // === Advanced Trade Balance Parsing Tests ===

    #[test]
    fn test_parse_advanced_balance() {
        let json = r#"{
            "accounts": [
                {
                    "uuid": "account-1",
                    "currency": "BTC",
                    "available_balance": {
                        "value": "1.5",
                        "currency": "BTC"
                    },
                    "hold": {
                        "value": "0.5",
                        "currency": "BTC"
                    }
                }
            ],
            "has_next": false,
            "cursor": ""
        }"#;

        let response: AdvancedTradeAccountsResponse = serde_json::from_str(json).unwrap();

        assert_eq!(response.accounts.len(), 1);
        assert_eq!(response.accounts[0].currency, "BTC");
        assert_eq!(response.accounts[0].available_balance.value, "1.5");
    }

    // === Advanced Trade Order Request Serialization Tests ===

    #[test]
    fn test_advanced_trade_limit_order_serialization() {
        let order_req = AdvancedTradeOrderRequest {
            client_order_id: "client-123".to_string(),
            product_id: "BTC-USD".to_string(),
            side: "BUY".to_string(),
            order_configuration: AdvancedTradeOrderConfig::Limit {
                limit_limit_gtc: AdvancedTradeLimitGTC {
                    base_size: "0.1".to_string(),
                    limit_price: "67000.00".to_string(),
                    post_only: false,
                },
            },
        };

        let json = serde_json::to_string(&order_req).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["client_order_id"], "client-123");
        assert_eq!(parsed["product_id"], "BTC-USD");
        assert_eq!(parsed["side"], "BUY");
        assert!(parsed["order_configuration"]["limit_limit_gtc"].is_object());
    }

    #[test]
    fn test_advanced_trade_market_order_serialization() {
        let order_req = AdvancedTradeOrderRequest {
            client_order_id: "client-456".to_string(),
            product_id: "ETH-USD".to_string(),
            side: "SELL".to_string(),
            order_configuration: AdvancedTradeOrderConfig::Market {
                market_market_ioc: AdvancedTradeMarketIOC {
                    base_size: Some("1.0".to_string()),
                    quote_size: None,
                },
            },
        };

        let json = serde_json::to_string(&order_req).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["side"], "SELL");
        assert!(parsed["order_configuration"]["market_market_ioc"].is_object());
    }

    // === Cancel Request Serialization Tests ===

    #[test]
    fn test_cancel_as_post() {
        // Advanced Trade API uses POST for cancel (not DELETE)
        let cancel_req = AdvancedTradeCancelRequest {
            order_ids: vec!["order-1".to_string(), "order-2".to_string()],
        };

        let json = serde_json::to_string(&cancel_req).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["order_ids"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["order_ids"][0], "order-1");
    }

    #[tokio::test]
    async fn place_order_rejects_invalid_orders_coinbase() {
        let client = CoinbaseClient::new("k".into(), "c2VjcmV0".into(), "p".into());
        crate::client::tests::assert_place_order_rejects_bad_orders(&client).await;
    }

    #[test]
    fn advanced_order_requires_and_forwards_client_order_id() {
        let none = crate::client::tests::sample_order();
        assert!(matches!(
            CoinbaseClient::build_advanced_order_request(&none),
            Err(ExchangeError::InvalidRequest(_))
        ));

        let order = Order {
            client_order_id: Some("my-id-1".into()),
            ..none
        };
        let req = CoinbaseClient::build_advanced_order_request(&order).unwrap();
        assert_eq!(req.client_order_id, "my-id-1");
        // Same order built twice yields the same id (retry-safe).
        let again = CoinbaseClient::build_advanced_order_request(&order).unwrap();
        assert_eq!(req.client_order_id, again.client_order_id);
    }

    #[test]
    fn legacy_order_forwards_client_oid() {
        let order = Order {
            client_order_id: Some("my-id-1".into()),
            ..crate::client::tests::sample_order()
        };
        let req = CoinbaseClient::build_legacy_order_request(&order).unwrap();
        assert_eq!(req.client_oid.as_deref(), Some("my-id-1"));
        assert_eq!(req.order_type, "limit");
    }

    #[test]
    fn advanced_status_unknown_is_not_open() {
        assert_eq!(
            CoinbaseClient::advanced_status("OPEN").unwrap(),
            OrderStatus::Open
        );
        assert_eq!(
            CoinbaseClient::advanced_status("filled").unwrap(),
            OrderStatus::Filled
        );
        assert!(CoinbaseClient::advanced_status("CANCEL_QUEUED").is_err());
        assert!(CoinbaseClient::advanced_status("").is_err());
    }

    #[test]
    fn legacy_done_status_depends_on_done_reason() {
        let f = |s, r| CoinbaseClient::legacy_status(s, r);
        assert_eq!(f("done", Some("filled")).unwrap(), OrderStatus::Filled);
        assert_eq!(f("done", Some("canceled")).unwrap(), OrderStatus::Cancelled);
        assert!(f("done", None).is_err());
        assert!(f("done", Some("mystery")).is_err());
        assert_eq!(f("active", None).unwrap(), OrderStatus::Open);
        assert_eq!(f("open", None).unwrap(), OrderStatus::Open);
        assert_eq!(f("received", None).unwrap(), OrderStatus::Pending);
        assert_eq!(f("rejected", None).unwrap(), OrderStatus::Rejected);
        assert!(f("mystery", None).is_err());
    }

    #[test]
    fn timestamp_tracks_wall_clock_under_burst() {
        let wall = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let last = (0..500)
            .map(|_| CoinbaseClient::get_timestamp())
            .last()
            .unwrap();
        assert!(
            last <= wall + 2,
            "timestamp ran {}s ahead of the clock",
            last - wall
        );
    }
}
