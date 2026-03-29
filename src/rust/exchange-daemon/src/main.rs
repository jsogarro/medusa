//! Exchange daemon for Medusa
//!
//! Bridges exchange APIs and kdb+ via IPC.

use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "exchange_daemon=info".into()),
        )
        .init();

    info!("Starting Medusa exchange daemon");

    // TODO: Load configuration
    // TODO: Initialize exchange clients
    // TODO: Connect to kdb+ Tickerplant via IPC
    // TODO: Start event loop

    info!("Exchange daemon initialized — waiting for shutdown signal");

    tokio::signal::ctrl_c().await?;
    info!("Shutting down exchange daemon");

    Ok(())
}
