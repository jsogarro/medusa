//! GDS Orderbook Subscriber
//!
//! Subscribes to real-time orderbook data from multiple cryptocurrency exchanges
//! via WebSocket and publishes to a kdb+ Tickerplant.
//!
//! # Architecture
//!
//! - WebSocket subscription per exchange (Bitstamp, Coinbase, Kraken)
//! - Initial bootstrap via REST (ONE-TIME snapshot per symbol)
//! - Sequence validation and gap recovery
//! - Health monitoring with configurable staleness timeout
//! - Exponential backoff for reconnections
//! - Publish to Tickerplant via `.u.upd[`orderbook;data]`
//!
//! # Usage
//!
//! ```bash
//! export KDB_PASSWORD=mypassword
//! gds-orderbook-subscriber \
//!   --tp-host localhost \
//!   --tp-port 5010 \
//!   --tp-user myuser \
//!   --health-timeout 30
//! ```

use anyhow::{Context, Result};
use clap::Parser;
use gds_common::{GdsConfig, KdbPublisher};
use tokio::signal;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

mod exchange_adapter;
mod orderbook_state;
mod subscriber;

use subscriber::ExchangeSubscriber;

#[derive(Parser, Debug)]
#[command(name = "gds-orderbook-subscriber")]
#[command(about = "GDS Orderbook Subscriber — WebSocket to kdb+ Tickerplant")]
struct Args {
    /// Tickerplant host
    #[arg(long, default_value = "localhost")]
    tp_host: String,

    /// Tickerplant port
    #[arg(long, default_value_t = 5010)]
    tp_port: u16,

    /// kdb+ username
    #[arg(long, default_value = "")]
    tp_user: String,

    /// Health check timeout in seconds
    #[arg(long, default_value_t = 30)]
    health_timeout: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();

    // Read kdb+ password from environment variable
    let tp_password = std::env::var("KDB_PASSWORD").unwrap_or_default();

    info!("Starting GDS Orderbook Subscriber");
    info!("Tickerplant: {}:{}", args.tp_host, args.tp_port);
    info!("Health timeout: {}s", args.health_timeout);

    // Build configuration
    let config = GdsConfig {
        tp_host: args.tp_host.clone(),
        tp_port: args.tp_port,
        tp_user: args.tp_user.clone(),
        tp_password: tp_password.clone(),
        health_timeout_secs: args.health_timeout,
        ..Default::default()
    };

    // Verify initial connection to Tickerplant
    let _initial_publisher =
        KdbPublisher::connect(&args.tp_host, args.tp_port, &args.tp_user, &tp_password)
            .await
            .with_context(|| format!("Failed to connect to Tickerplant at {}:{}", args.tp_host, args.tp_port))?;

    info!("Connected to Tickerplant successfully");

    // Spawn subscriber task for each enabled exchange
    let mut handles = Vec::new();

    for exchange_config in config.exchanges.iter().filter(|e| e.enabled) {
        info!("Starting subscriber for {}", exchange_config.name);

        // Create a separate KdbPublisher connection for this exchange
        let exchange_publisher = KdbPublisher::connect(
            &args.tp_host,
            args.tp_port,
            &args.tp_user,
            &tp_password,
        )
        .await
        .with_context(|| format!("Failed to create publisher for {}", exchange_config.name))?;

        let exchange_config = exchange_config.clone();
        let health_timeout = config.health_timeout();

        let handle = tokio::spawn(async move {
            let mut subscriber = ExchangeSubscriber::new(
                exchange_config,
                exchange_publisher,
                health_timeout,
            );
            if let Err(e) = subscriber.run().await {
                error!("Exchange subscriber failed: {}", e);
            }
        });

        handles.push(handle);
    }

    // Wait for shutdown signal
    info!("GDS Orderbook Subscriber running. Press Ctrl+C to stop.");
    signal::ctrl_c().await.context("Failed to listen for Ctrl+C")?;

    info!("Shutdown signal received, stopping...");

    // Wait for all tasks to complete (they may still be running)
    for handle in handles {
        if let Err(e) = handle.await {
            error!("Task error: {:?}", e);
        }
    }

    info!("GDS Orderbook Subscriber stopped");
    Ok(())
}
