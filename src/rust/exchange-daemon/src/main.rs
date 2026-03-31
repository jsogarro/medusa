//! Exchange daemon for Medusa
//!
//! Bridges exchange APIs and kdb+ via IPC.
//!
//! # Architecture
//! Long-running daemon that:
//! 1. Connects to kdb+ Tickerplant via IPC
//! 2. Initializes orderbook schema
//! 3. Publishes mock orderbook data (Wave 3 - testing only)
//! 4. Handles graceful shutdown on SIGTERM/SIGINT

use anyhow::{Context, Result};
use clap::Parser;
use kdb_ipc::KdbClient;
use std::time::Duration;
use tokio::time;
use tracing::{error, info};

#[derive(Parser, Debug)]
#[command(name = "exchange-daemon")]
#[command(about = "Medusa exchange data daemon")]
struct Args {
    /// kdb+ Tickerplant host
    #[arg(long, default_value = "localhost")]
    kdb_host: String,

    /// kdb+ Tickerplant port
    #[arg(long, default_value = "5001")]
    kdb_port: u16,

    /// kdb+ username (empty for no auth)
    #[arg(long, default_value = "")]
    kdb_user: String,

    /// Mock data publish interval (seconds)
    #[arg(long, default_value = "5")]
    publish_interval: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "exchange_daemon=info,kdb_ipc=info".into()),
        )
        .init();

    let args = Args::parse();

    // Read password from environment variable (not CLI for security)
    let kdb_password = std::env::var("KDB_PASSWORD").unwrap_or_default();

    info!("Starting Medusa exchange daemon");
    info!(
        "Connecting to kdb+ at {}:{}",
        args.kdb_host, args.kdb_port
    );

    // Connect to kdb+ Tickerplant
    let mut client = KdbClient::connect(
        &args.kdb_host,
        args.kdb_port,
        &args.kdb_user,
        &kdb_password,
    )
    .await
    .context("Failed to connect to kdb+")?;

    // Initialize schema
    info!("Initializing orderbook schema");
    initialize_schema(&mut client)
        .await
        .context("Failed to initialize schema")?;

    // Start mock data publisher
    info!("Starting mock orderbook publisher (interval: {}s)", args.publish_interval);
    let publish_handle = tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(args.publish_interval));
        let mut seq = 0u64;

        loop {
            interval.tick().await;

            match publish_mock_orderbook(&mut client, seq).await {
                Ok(_) => {
                    seq += 1;
                    info!("Published mock orderbook (seq: {})", seq);
                }
                Err(e) => {
                    error!("Failed to publish orderbook: {}", e);
                }
            }
        }
    });

    info!("Exchange daemon running — waiting for shutdown signal");

    // Wait for shutdown
    match wait_for_shutdown().await {
        Ok(_) => info!("Received shutdown signal"),
        Err(e) => error!("Error waiting for shutdown: {}", e),
    }

    // Cancel publisher
    publish_handle.abort();

    info!("Exchange daemon stopped");
    Ok(())
}

/// Initialize orderbook schema in kdb+
async fn initialize_schema(client: &mut KdbClient) -> Result<()> {
    // Create orderbook table with columns:
    // sym, exchange, side, price, quantity, timestamp
    let schema_query = r#"
        orderbook:([]
            sym:`symbol$();
            exchange:`symbol$();
            side:`symbol$();
            price:`float$();
            quantity:`float$();
            timestamp:`timestamp$()
        )
    "#;

    client
        .query(schema_query)
        .await
        .context("Failed to create orderbook table")?;

    info!("Schema initialized successfully");
    Ok(())
}

/// Publish mock orderbook data to kdb+
async fn publish_mock_orderbook(client: &mut KdbClient, _seq: u64) -> Result<()> {
    // Mock data: BTC-USD orderbook with 3 levels
    let insert_query = r#"
        `orderbook insert (
            `BTCUSD`BTCUSD`BTCUSD`BTCUSD`BTCUSD`BTCUSD;
            `coinbase`coinbase`coinbase`coinbase`coinbase`coinbase;
            `bid`bid`bid`ask`ask`ask;
            50000.0 49999.5 49999.0 50001.0 50001.5 50002.0;
            1.5 2.3 3.1 1.2 1.8 2.5;
            6#.z.p
        )
    "#;

    client
        .query(insert_query)
        .await
        .context("Failed to insert orderbook data")?;

    Ok(())
}

/// Wait for shutdown signal (SIGTERM or SIGINT)
async fn wait_for_shutdown() -> Result<()> {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};

        let mut sigterm =
            signal(SignalKind::terminate()).context("Failed to install SIGTERM handler")?;
        let mut sigint =
            signal(SignalKind::interrupt()).context("Failed to install SIGINT handler")?;

        tokio::select! {
            _ = sigterm.recv() => {
                info!("Received SIGTERM");
            }
            _ = sigint.recv() => {
                info!("Received SIGINT");
            }
        }
    }

    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c()
            .await
            .context("Failed to install Ctrl-C handler")?;
        info!("Received Ctrl-C");
    }

    Ok(())
}
