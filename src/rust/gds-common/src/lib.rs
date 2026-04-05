//! GDS Common — Shared infrastructure for Guardian Data System subscribers
//!
//! Provides health monitoring, exponential backoff, and kdb+ Tickerplant
//! publishing utilities shared across all GDS binary crates.

pub mod backoff;
pub mod config;
pub mod health;
pub mod publisher;

pub use backoff::ExponentialBackoff;
pub use config::{ExchangeConfig, GdsConfig};
pub use health::HealthMonitor;
pub use publisher::KdbPublisher;
