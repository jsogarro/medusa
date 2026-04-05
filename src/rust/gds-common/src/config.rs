//! Configuration types for GDS subscribers
//!
//! Defines shared configuration for exchange connections and TP publishing.

use serde::Deserialize;
use std::time::Duration;

/// Top-level GDS subscriber configuration.
#[derive(Debug, Clone, Deserialize)]
pub struct GdsConfig {
    /// Tickerplant host
    pub tp_host: String,
    /// Tickerplant port
    pub tp_port: u16,
    /// kdb+ username (empty for no auth)
    pub tp_user: String,
    /// kdb+ password (from env var, not config file)
    pub tp_password: String,
    /// Exchange configurations
    pub exchanges: Vec<ExchangeConfig>,
    /// Health check timeout in seconds
    pub health_timeout_secs: u64,
}

impl GdsConfig {
    /// Returns the health timeout as a Duration.
    pub fn health_timeout(&self) -> Duration {
        Duration::from_secs(self.health_timeout_secs)
    }
}

impl Default for GdsConfig {
    fn default() -> Self {
        Self {
            tp_host: "localhost".to_string(),
            tp_port: 5010,
            tp_user: String::new(),
            tp_password: String::new(),
            exchanges: vec![
                ExchangeConfig::bitstamp(),
                ExchangeConfig::coinbase(),
                ExchangeConfig::kraken(),
            ],
            health_timeout_secs: 30,
        }
    }
}

/// Configuration for a single exchange connection.
#[derive(Debug, Clone, Deserialize)]
pub struct ExchangeConfig {
    /// Exchange name (bitstamp, coinbase, kraken)
    pub name: String,
    /// WebSocket URL
    pub ws_url: String,
    /// REST API base URL (for bootstrap/backfill only)
    pub rest_url: String,
    /// Trading pairs to subscribe to
    pub symbols: Vec<String>,
    /// Whether this exchange is enabled
    pub enabled: bool,
}

impl ExchangeConfig {
    pub fn bitstamp() -> Self {
        Self {
            name: "bitstamp".to_string(),
            ws_url: "wss://ws.bitstamp.net".to_string(),
            rest_url: "https://www.bitstamp.net/api/v2".to_string(),
            symbols: vec!["btcusd".to_string(), "ethusd".to_string()],
            enabled: true,
        }
    }

    pub fn coinbase() -> Self {
        Self {
            name: "coinbase".to_string(),
            ws_url: "wss://ws-feed.exchange.coinbase.com".to_string(),
            rest_url: "https://api.exchange.coinbase.com".to_string(),
            symbols: vec!["BTC-USD".to_string(), "ETH-USD".to_string()],
            enabled: true,
        }
    }

    pub fn kraken() -> Self {
        Self {
            name: "kraken".to_string(),
            ws_url: "wss://ws.kraken.com".to_string(),
            rest_url: "https://api.kraken.com/0/public".to_string(),
            symbols: vec!["XBT/USD".to_string(), "ETH/USD".to_string()],
            enabled: true,
        }
    }
}
