//! Exchange daemon for Medusa
//!
//! Bridges exchange APIs and kdb+ via IPC.
//!
//! # Architecture
//! Long-running daemon that:
//! 1. Polls REST APIs for orderbook snapshots (Wave 1)
//! 2. Subscribes to WebSocket feeds for real-time updates (Wave 2)
//! 3. Publishes data to kdb+ Tickerplant via `.u.upd` (Wave 1)
//! 4. Handles graceful shutdown on SIGTERM/SIGINT
//!
//! # Shutdown Pattern
//! Uses tokio::select! to wait for either:
//! - SIGTERM (systemd, Docker)
//! - SIGINT (Ctrl-C)
//!
//! Then performs graceful cleanup:
//! - Cancel all subscriptions
//! - Disconnect from kdb+
//! - Flush pending messages

use anyhow::Context;
use tracing::{error, info};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging with env filter support
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "exchange_daemon=info,exchange_connector=info,kdb_ipc=info".into()),
        )
        .init();

    info!("Starting Medusa exchange daemon");

    // TODO: Load configuration from env vars or config file
    // - Exchange API keys
    // - kdb+ Tickerplant host/port
    // - Poll intervals
    // - Trading pairs to monitor

    // TODO: Initialize exchange clients
    // - Create clients for each exchange (Coinbase, Binance, etc.)
    // - Validate API keys

    // TODO: Connect to kdb+ Tickerplant via IPC
    // - Create KdbClient
    // - Connect and authenticate
    // - Verify `.u.upd` function exists

    // TODO: Start event loop
    // - Spawn tasks for each trading pair
    // - Each task polls REST API at configured interval
    // - Serialize data and publish to kdb+ via `.u.upd`

    info!("Exchange daemon initialized — waiting for shutdown signal");

    // Graceful shutdown on SIGTERM or SIGINT
    match wait_for_shutdown().await {
        Ok(_) => info!("Received shutdown signal"),
        Err(e) => error!("Error waiting for shutdown signal: {}", e),
    }

    info!("Shutting down exchange daemon");

    // TODO: Graceful cleanup
    // - Cancel all polling tasks
    // - Disconnect from kdb+
    // - Flush any pending messages

    info!("Exchange daemon stopped");

    Ok(())
}

/// Wait for shutdown signal (SIGTERM or SIGINT)
async fn wait_for_shutdown() -> anyhow::Result<()> {
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
