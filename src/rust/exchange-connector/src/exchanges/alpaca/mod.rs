//! Alpaca exchange client implementation
//!
//! REST API documentation: https://docs.alpaca.markets/
//!
//! # Environment Variables
//! - `ALPACA_API_KEY` - API key ID (required)
//! - `ALPACA_SECRET_KEY` - API secret key (required)
//! - `ALPACA_PAPER` - "true" for paper trading, "false" for live (default: "true")

pub mod bridge;
pub mod types;
pub mod ws;

use crate::client::{ExchangeClient, ExchangeError};
use crate::rate_limiter::RateLimiter;
use crate::types::{Balance, Order, OrderBook, OrderStatus, OrderType, PriceLevel, Side};
use async_trait::async_trait;
use chrono::Utc;
use reqwest::Client;
use serde_json::Value;
use std::sync::Arc;
use tracing::{debug, trace, warn};

use types::*;

/// Alpaca base URLs
const PAPER_BASE_URL: &str = "https://paper-api.alpaca.markets";
const LIVE_BASE_URL: &str = "https://api.alpaca.markets";
const MARKET_DATA_URL: &str = "https://data.alpaca.markets";

/// Alpaca REST client
///
/// # Security
/// API credentials are held in memory. For production, consider using
/// secure credential managers or environment-based key rotation.
#[derive(Clone)]
pub struct AlpacaClient {
    client: Client,
    base_url: String,
    data_url: String,
    api_key: String,
    secret_key: String,
    rate_limiter: Arc<RateLimiter>,
}

// Prevent debug output from leaking credentials
impl std::fmt::Debug for AlpacaClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AlpacaClient")
            .field("base_url", &self.base_url)
            .field("data_url", &self.data_url)
            .field("api_key", &"<redacted>")
            .field("secret_key", &"<redacted>")
            .field("rate_limiter", &self.rate_limiter)
            .finish()
    }
}

impl AlpacaClient {
    /// Create a new Alpaca client from environment variables
    ///
    /// # Environment Variables
    /// - `ALPACA_API_KEY` - API key ID (required)
    /// - `ALPACA_SECRET_KEY` - API secret key (required)
    /// - `ALPACA_PAPER` - "true" for paper trading, "false" for live (default: "true")
    ///
    /// # Rate Limits
    /// Alpaca rate limits: 200 requests per minute = ~3.3 req/sec
    pub fn from_env() -> Result<Self, ExchangeError> {
        let api_key = std::env::var("ALPACA_API_KEY").map_err(|_| {
            ExchangeError::Authentication(
                "ALPACA_API_KEY environment variable must be set".to_string(),
            )
        })?;

        let secret_key = std::env::var("ALPACA_SECRET_KEY").map_err(|_| {
            ExchangeError::Authentication(
                "ALPACA_SECRET_KEY environment variable must be set".to_string(),
            )
        })?;

        let paper_mode = std::env::var("ALPACA_PAPER")
            .unwrap_or_else(|_| "true".to_string())
            .eq_ignore_ascii_case("true");

        Ok(Self::new(api_key, secret_key, paper_mode))
    }

    /// Create a new Alpaca client
    ///
    /// # Arguments
    /// * `api_key` - Alpaca API key ID
    /// * `secret_key` - Alpaca API secret key
    /// * `paper_mode` - If true, use paper trading; if false, use live trading
    pub fn new(api_key: String, secret_key: String, paper_mode: bool) -> Self {
        let base_url = if paper_mode {
            PAPER_BASE_URL.to_string()
        } else {
            LIVE_BASE_URL.to_string()
        };

        Self {
            client: Client::new(),
            base_url,
            data_url: MARKET_DATA_URL.to_string(),
            api_key,
            secret_key,
            // Alpaca: 200 req/min = ~3 req/sec
            rate_limiter: Arc::new(RateLimiter::new(3, Some(200))),
        }
    }

    /// Make an authenticated GET request to trading API
    async fn get(&self, path: &str) -> Result<Value, ExchangeError> {
        self.rate_limiter.acquire(None, 1).await;

        let url = format!("{}{}", self.base_url, path);
        trace!("GET {}", url);

        let response = self
            .client
            .get(&url)
            .header("APCA-API-KEY-ID", &self.api_key)
            .header("APCA-API-SECRET-KEY", &self.secret_key)
            .send()
            .await?;

        self.handle_response(response).await
    }

    /// Make an authenticated POST request to trading API
    async fn post(&self, path: &str, body: &Value) -> Result<Value, ExchangeError> {
        self.rate_limiter.acquire(None, 1).await;

        let url = format!("{}{}", self.base_url, path);
        trace!("POST {} body={}", url, body);

        let response = self
            .client
            .post(&url)
            .header("APCA-API-KEY-ID", &self.api_key)
            .header("APCA-API-SECRET-KEY", &self.secret_key)
            .json(body)
            .send()
            .await?;

        self.handle_response(response).await
    }

    /// Make an authenticated DELETE request to trading API
    async fn delete(&self, path: &str) -> Result<Value, ExchangeError> {
        self.rate_limiter.acquire(None, 1).await;

        let url = format!("{}{}", self.base_url, path);
        trace!("DELETE {}", url);

        let response = self
            .client
            .delete(&url)
            .header("APCA-API-KEY-ID", &self.api_key)
            .header("APCA-API-SECRET-KEY", &self.secret_key)
            .send()
            .await?;

        self.handle_response(response).await
    }

    /// Make an authenticated GET request to market data API
    async fn get_market_data(&self, path: &str) -> Result<Value, ExchangeError> {
        self.rate_limiter.acquire(None, 1).await;

        let url = format!("{}{}", self.data_url, path);
        trace!("GET {}", url);

        let response = self
            .client
            .get(&url)
            .header("APCA-API-KEY-ID", &self.api_key)
            .header("APCA-API-SECRET-KEY", &self.secret_key)
            .send()
            .await?;

        self.handle_response(response).await
    }

    /// Handle HTTP response and convert to Result<Value>
    async fn handle_response(&self, response: reqwest::Response) -> Result<Value, ExchangeError> {
        let status = response.status();

        if status.is_success() {
            let json = response.json::<Value>().await?;
            Ok(json)
        } else {
            // Parse error response
            let error_text = response.text().await.unwrap_or_default();
            debug!("HTTP {} error: {}", status.as_u16(), error_text);

            // Map HTTP status codes to ExchangeError variants
            match status.as_u16() {
                401 | 403 => Err(ExchangeError::Authentication(format!(
                    "Authentication failed: {}",
                    error_text
                ))),
                429 => {
                    // Extract retry-after header if present
                    let retry_after = "60"; // Default to 60 seconds
                    Err(ExchangeError::RateLimit(format!(
                        "Rate limit exceeded, retry after {} seconds",
                        retry_after
                    )))
                }
                400 | 422 => Err(ExchangeError::InvalidRequest(error_text)),
                404 => Err(ExchangeError::OrderNotFound(error_text)),
                503 => Err(ExchangeError::Unavailable(format!(
                    "Service unavailable: {}",
                    error_text
                ))),
                _ => Err(ExchangeError::Other(format!(
                    "HTTP {}: {}",
                    status.as_u16(),
                    error_text
                ))),
            }
        }
    }

    // ====================================================================
    // ACCOUNT ENDPOINTS
    // ====================================================================

    /// Get account information
    ///
    /// GET /v2/account
    pub async fn get_account(&self) -> Result<Account, ExchangeError> {
        let json = self.get("/v2/account").await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    // ====================================================================
    // ORDER ENDPOINTS
    // ====================================================================

    /// Submit a new order
    ///
    /// POST /v2/orders
    pub async fn submit_order(&self, req: OrderRequest) -> Result<types::Order, ExchangeError> {
        let body = serde_json::to_value(&req)?;
        let json = self.post("/v2/orders", &body).await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    /// Get order by ID
    ///
    /// GET /v2/orders/{order_id}
    pub async fn get_order_by_id(&self, order_id: &str) -> Result<types::Order, ExchangeError> {
        let path = format!("/v2/orders/{}", order_id);
        let json = self.get(&path).await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    /// Cancel order by ID
    ///
    /// DELETE /v2/orders/{order_id}
    pub async fn cancel_order_by_id(&self, order_id: &str) -> Result<(), ExchangeError> {
        let path = format!("/v2/orders/{}", order_id);
        self.delete(&path).await?;
        Ok(())
    }

    /// List orders with optional status filter
    ///
    /// GET /v2/orders?status={status}
    /// Status: "open", "closed", "all"
    pub async fn list_orders(&self, status: &str) -> Result<Vec<types::Order>, ExchangeError> {
        let path = format!("/v2/orders?status={}", status);
        let json = self.get(&path).await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    // ====================================================================
    // POSITION ENDPOINTS
    // ====================================================================

    /// List all positions
    ///
    /// GET /v2/positions
    pub async fn list_positions(&self) -> Result<Vec<Position>, ExchangeError> {
        let json = self.get("/v2/positions").await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    /// Get position for specific symbol
    ///
    /// GET /v2/positions/{symbol}
    pub async fn get_position(&self, symbol: &str) -> Result<Position, ExchangeError> {
        let path = format!("/v2/positions/{}", symbol);
        let json = self.get(&path).await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }

    // ====================================================================
    // MARKET DATA ENDPOINTS (Historical)
    // ====================================================================

    /// Get historical bars (OHLCV candles)
    ///
    /// GET /v2/stocks/{symbol}/bars?timeframe={}&start={}&end={}
    ///
    /// # Arguments
    /// * `symbol` - Stock symbol (e.g., "AAPL")
    /// * `timeframe` - "1Min", "5Min", "1Hour", "1Day", etc.
    /// * `start` - Start time (RFC3339 format)
    /// * `end` - End time (RFC3339 format)
    pub async fn get_bars(
        &self,
        symbol: &str,
        timeframe: &str,
        start: &str,
        end: &str,
    ) -> Result<Vec<Bar>, ExchangeError> {
        let path = format!(
            "/v2/stocks/{}/bars?timeframe={}&start={}&end={}",
            symbol, timeframe, start, end
        );
        let json = self.get_market_data(&path).await?;

        // Parse bars array from response
        let response: BarsResponse = serde_json::from_value(json)?;
        Ok(response.bars)
    }

    /// Get historical trades
    ///
    /// GET /v2/stocks/{symbol}/trades?start={}&end={}
    pub async fn get_trades(
        &self,
        symbol: &str,
        start: &str,
        end: &str,
    ) -> Result<Vec<AlpacaTrade>, ExchangeError> {
        let path = format!("/v2/stocks/{}/trades?start={}&end={}", symbol, start, end);
        let json = self.get_market_data(&path).await?;

        let response: TradesResponse = serde_json::from_value(json)?;
        Ok(response.trades)
    }

    /// Get historical quotes
    ///
    /// GET /v2/stocks/{symbol}/quotes?start={}&end={}
    pub async fn get_quotes(
        &self,
        symbol: &str,
        start: &str,
        end: &str,
    ) -> Result<Vec<Quote>, ExchangeError> {
        let path = format!("/v2/stocks/{}/quotes?start={}&end={}", symbol, start, end);
        let json = self.get_market_data(&path).await?;

        let response: QuotesResponse = serde_json::from_value(json)?;
        Ok(response.quotes)
    }

    /// Get latest snapshot (combines latest trade, quote, bars)
    ///
    /// GET /v2/stocks/{symbol}/snapshot
    pub async fn get_snapshot(&self, symbol: &str) -> Result<SnapshotResponse, ExchangeError> {
        let path = format!("/v2/stocks/{}/snapshot", symbol);
        let json = self.get_market_data(&path).await?;
        serde_json::from_value(json).map_err(ExchangeError::from)
    }
}

// ====================================================================
// EXCHANGE CLIENT TRAIT IMPLEMENTATION
// ====================================================================

#[async_trait]
impl ExchangeClient for AlpacaClient {
    async fn get_orderbook(&self, pair: &str) -> Result<OrderBook, ExchangeError> {
        // Alpaca doesn't provide orderbook data via REST API
        // Use snapshot to get best bid/ask only
        let snapshot = self.get_snapshot(pair).await?;

        let mut bids = Vec::new();
        let mut asks = Vec::new();

        if let Some(quote) = &snapshot.latest_quote {
            bids.push(PriceLevel {
                price: quote.bid_price,
                quantity: quote.bid_size as f64,
            });
            asks.push(PriceLevel {
                price: quote.ask_price,
                quantity: quote.ask_size as f64,
            });
        }

        Ok(OrderBook {
            pair: pair.to_string(),
            exchange: "alpaca".to_string(),
            bids,
            asks,
            timestamp: Utc::now(),
            sequence: None,
        })
    }

    async fn get_balance(&self, asset: Option<&str>) -> Result<Vec<Balance>, ExchangeError> {
        let account = self.get_account().await?;

        // Parse cash balance
        let cash_value: f64 = account.cash.parse().unwrap_or_else(|_| {
            warn!("Failed to parse cash value: {}", account.cash);
            0.0
        });

        let buying_power_value: f64 = account.buying_power.parse().unwrap_or_else(|_| {
            warn!("Failed to parse buying power: {}", account.buying_power);
            0.0
        });

        // If specific asset requested, filter
        if let Some(asset_filter) = asset {
            if asset_filter.eq_ignore_ascii_case("USD") {
                return Ok(vec![Balance {
                    asset: "USD".to_string(),
                    exchange: "alpaca".to_string(),
                    total: cash_value,
                    available: buying_power_value,
                    locked: 0.0, // Alpaca doesn't expose locked cash separately
                }]);
            }

            // For equity positions, get the specific position
            let position = self.get_position(asset_filter).await?;
            let market_value: f64 = position.market_value.parse().unwrap_or(0.0);

            return Ok(vec![Balance {
                asset: asset_filter.to_string(),
                exchange: "alpaca".to_string(),
                total: market_value,
                available: market_value,
                locked: 0.0,
            }]);
        }

        // Return all balances (cash + all positions)
        let mut balances = vec![Balance {
            asset: "USD".to_string(),
            exchange: "alpaca".to_string(),
            total: cash_value,
            available: buying_power_value,
            locked: 0.0,
        }];

        // Add all equity positions
        let positions = self.list_positions().await?;
        for position in positions {
            let market_value: f64 = position.market_value.parse().unwrap_or(0.0);
            balances.push(Balance {
                asset: position.symbol,
                exchange: "alpaca".to_string(),
                total: market_value,
                available: market_value,
                locked: 0.0,
            });
        }

        Ok(balances)
    }

    async fn get_open_orders(&self, pair: Option<&str>) -> Result<Vec<Order>, ExchangeError> {
        let alpaca_orders = self.list_orders("open").await?;

        // Filter by pair if specified
        let filtered_orders: Vec<_> = if let Some(symbol) = pair {
            alpaca_orders
                .into_iter()
                .filter(|o| o.symbol.eq_ignore_ascii_case(symbol))
                .collect()
        } else {
            alpaca_orders
        };

        // Convert to common Order type
        Ok(filtered_orders
            .into_iter()
            .map(|o| self.convert_order(o))
            .collect())
    }

    async fn get_order(&self, order_id: &str) -> Result<Order, ExchangeError> {
        let alpaca_order = self.get_order_by_id(order_id).await?;
        Ok(self.convert_order(alpaca_order))
    }

    async fn place_order(&self, order: &Order) -> Result<String, ExchangeError> {
        let req = OrderRequest {
            symbol: order.pair.clone(),
            qty: Some(order.quantity.to_string()),
            notional: None,
            side: match order.side {
                Side::Buy => "buy".to_string(),
                Side::Sell => "sell".to_string(),
            },
            order_type: match order.order_type {
                OrderType::Market => "market".to_string(),
                OrderType::Limit => "limit".to_string(),
                _ => {
                    return Err(ExchangeError::InvalidRequest(
                        "Unsupported order type for Alpaca".to_string(),
                    ))
                }
            },
            time_in_force: "day".to_string(),
            limit_price: order.price.map(|p| p.to_string()),
            stop_price: None,
            extended_hours: Some(false),
            client_order_id: order.client_order_id.clone(),
        };

        let alpaca_order = self.submit_order(req).await?;
        Ok(alpaca_order.id)
    }

    async fn cancel_order(&self, order_id: &str) -> Result<(), ExchangeError> {
        self.cancel_order_by_id(order_id).await
    }

    async fn cancel_all_orders(&self, pair: Option<&str>) -> Result<u32, ExchangeError> {
        let open_orders = self.get_open_orders(pair).await?;
        let mut cancelled_count = 0u32;

        for order in open_orders {
            if let Some(id) = order.id {
                if self.cancel_order(&id).await.is_ok() {
                    cancelled_count += 1;
                }
            }
        }

        Ok(cancelled_count)
    }
}

impl AlpacaClient {
    /// Convert Alpaca Order to common Order type
    fn convert_order(&self, alpaca_order: types::Order) -> Order {
        let status = match alpaca_order.status.as_str() {
            "accepted" | "new" => OrderStatus::Open,
            "pending_new" => OrderStatus::Pending,
            "partially_filled" => OrderStatus::PartiallyFilled,
            "filled" => OrderStatus::Filled,
            "canceled" => OrderStatus::Cancelled,
            "rejected" => OrderStatus::Rejected,
            "expired" => OrderStatus::Expired,
            _ => OrderStatus::Pending,
        };

        let order_type = match alpaca_order.order_type.as_str() {
            "market" => OrderType::Market,
            "limit" => OrderType::Limit,
            _ => OrderType::Market,
        };

        let side = match alpaca_order.side.as_str() {
            "buy" => Side::Buy,
            "sell" => Side::Sell,
            _ => Side::Buy,
        };

        let filled_qty: f64 = alpaca_order.filled_qty.parse().unwrap_or(0.0);
        let avg_price: Option<f64> = alpaca_order
            .filled_avg_price
            .and_then(|p: String| p.parse::<f64>().ok());

        Order {
            id: Some(alpaca_order.id),
            pair: alpaca_order.symbol,
            exchange: "alpaca".to_string(),
            side,
            price: alpaca_order
                .limit_price
                .and_then(|p: String| p.parse::<f64>().ok()),
            quantity: alpaca_order
                .qty
                .and_then(|q: String| q.parse::<f64>().ok())
                .unwrap_or(0.0),
            order_type,
            status,
            client_order_id: Some(alpaca_order.client_order_id),
            filled_quantity: filled_qty,
            average_price: avg_price,
            created_at: Utc::now(), // TODO: Parse alpaca_order.created_at
            updated_at: Utc::now(), // TODO: Parse alpaca_order.updated_at
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = AlpacaClient::new("test-key".to_string(), "test-secret".to_string(), true);
        assert_eq!(client.base_url, PAPER_BASE_URL);
        assert_eq!(client.data_url, MARKET_DATA_URL);
    }

    #[test]
    fn test_paper_mode_selection() {
        let paper_client = AlpacaClient::new("key".to_string(), "secret".to_string(), true);
        assert_eq!(paper_client.base_url, PAPER_BASE_URL);

        let live_client = AlpacaClient::new("key".to_string(), "secret".to_string(), false);
        assert_eq!(live_client.base_url, LIVE_BASE_URL);
    }

    #[test]
    fn test_from_env_missing_keys() {
        // Clear env vars
        std::env::remove_var("ALPACA_API_KEY");
        std::env::remove_var("ALPACA_SECRET_KEY");

        let result = AlpacaClient::from_env();
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            ExchangeError::Authentication(_)
        ));
    }
}
