//! GDS Trade Subscriber — Subscribe to real-time trade data from exchanges
//!
//! Subscribes to WebSocket trade streams from multiple cryptocurrency exchanges
//! and publishes to the kdb+ Tickerplant for downstream strategy consumption.
//!
//! Architecture:
//! ```text
//! Exchange WebSocket → Rust Subscriber → Tickerplant (port 5010) → RDB → Strategies
//! ```
//!
//! # Usage
//! ```bash
//! export KDB_PASSWORD="secret"
//! export BACKFILL_TRADES="true"  # optional
//! gds-trade-subscriber \
//!   --tp-host localhost \
//!   --tp-port 5010 \
//!   --tp-user "" \
//!   --health-timeout 30
//! ```

mod deduplicator;
mod exchange_adapter;
mod subscriber;

#[cfg(test)]
mod tests;

use anyhow::{Context, Result};
use clap::Parser;
use gds_common::{ExchangeConfig, GdsConfig, KdbPublisher};
use std::env;
use tokio::signal;
use tracing::{error, info};

#[derive(Parser, Debug)]
#[command(name = "gds-trade-subscriber")]
#[command(about = "Subscribe to cryptocurrency trade data and publish to kdb+ Tickerplant")]
struct Args {
    /// Tickerplant host
    #[arg(long, default_value = "localhost")]
    tp_host: String,

    /// Tickerplant port
    #[arg(long, default_value_t = 5010)]
    tp_port: u16,

    /// Tickerplant username (empty for no auth)
    #[arg(long, default_value = "")]
    tp_user: String,

    /// Health timeout in seconds
    #[arg(long, default_value_t = 30)]
    health_timeout: u64,

    /// Enable backfill (one-time on startup)
    #[arg(long)]
    backfill: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .with_level(true)
        .init();

    let args = Args::parse();

    // Read password from env
    let tp_password = env::var("KDB_PASSWORD").unwrap_or_default();

    // Backfill setting from env or CLI
    let backfill_enabled = args.backfill
        || env::var("BACKFILL_TRADES")
            .unwrap_or_default()
            .to_lowercase() == "true";

    info!("GDS Trade Subscriber starting");
    info!("Tickerplant: {}:{}", args.tp_host, args.tp_port);
    info!("Health timeout: {}s", args.health_timeout);
    info!("Backfill enabled: {}", backfill_enabled);

    // Build configuration
    let config = GdsConfig {
        tp_host: args.tp_host.clone(),
        tp_port: args.tp_port,
        tp_user: args.tp_user.clone(),
        tp_password: tp_password.clone(),
        exchanges: vec![
            ExchangeConfig::bitstamp(),
            ExchangeConfig::coinbase(),
            ExchangeConfig::kraken(),
        ],
        health_timeout_secs: args.health_timeout,
    };

    // Connect to Tickerplant (verify connection)
    let _initial_publisher = KdbPublisher::connect(
        &config.tp_host,
        config.tp_port,
        &config.tp_user,
        &tp_password,
    )
    .await
    .with_context(|| format!("Failed to connect to Tickerplant at {}:{}", config.tp_host, config.tp_port))?;

    info!("Connected to Tickerplant successfully");

    // Spawn subscriber task for each enabled exchange
    let mut tasks = vec![];

    for exchange_config in config.exchanges.iter().filter(|e| e.enabled) {
        info!(
            "Starting subscriber for {} ({} symbols)",
            exchange_config.name,
            exchange_config.symbols.len()
        );

        // Clone publisher for this task (each task gets its own connection)
        let exchange_publisher = KdbPublisher::connect(
            &config.tp_host,
            config.tp_port,
            &config.tp_user,
            &tp_password,
        )
        .await
        .with_context(|| {
            format!("Failed to create publisher for {}", exchange_config.name)
        })?;

        let exchange_cfg = exchange_config.clone();
        let health_timeout = config.health_timeout();

        let task = tokio::spawn(async move {
            let mut subscriber = match subscriber::TradeSubscriber::new(
                exchange_cfg,
                exchange_publisher,
                health_timeout,
                backfill_enabled,
            ) {
                Ok(sub) => sub,
                Err(e) => {
                    error!("Failed to create trade subscriber: {}", e);
                    return;
                }
            };

            if let Err(e) = subscriber.run().await {
                error!("Subscriber failed for {}: {}", subscriber.exchange_name(), e);
            }
        });

        tasks.push(task);
    }

    // Wait for shutdown signal
    info!("All subscribers started. Press Ctrl+C to shutdown.");

    match signal::ctrl_c().await {
        Ok(()) => {
            info!("Shutdown signal received");
        }
        Err(err) => {
            error!("Unable to listen for shutdown signal: {}", err);
        }
    }

    // Abort all tasks
    for task in tasks {
        task.abort();
    }

    info!("GDS Trade Subscriber shutdown complete");
    Ok(())
}
