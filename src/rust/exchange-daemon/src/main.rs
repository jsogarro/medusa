//! Exchange daemon for Medusa
//!
//! Bridges exchange APIs and kdb+ via IPC.
//!
//! # Architecture
//! Long-running daemon that:
//! 1. Connects to kdb+ Tickerplant via IPC
//! 2. Handles graceful shutdown on SIGTERM/SIGINT
//!
//! It defines no tables and publishes no data; the GDS subscribers publish.

use anyhow::{Context, Result};
use clap::Parser;
use kdb_ipc::KdbClient;
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
    info!("Connecting to kdb+ at {}:{}", args.kdb_host, args.kdb_port);

    // Connect to kdb+ Tickerplant
    let client = KdbClient::connect(&args.kdb_host, args.kdb_port, &args.kdb_user, &kdb_password)
        .await
        .context("Failed to connect to kdb+")?;
    run(client, wait_for_shutdown()).await
}

/// Hold the Tickerplant connection until `shutdown` resolves.
///
/// The daemon publishes nothing itself: market data reaches the Tickerplant
/// through the GDS subscribers, and the schema is owned by the q side.
async fn run(
    _client: KdbClient,
    shutdown: impl std::future::Future<Output = Result<()>>,
) -> Result<()> {
    info!("Exchange daemon running — waiting for shutdown signal");

    match shutdown.await {
        Ok(_) => info!("Received shutdown signal"),
        Err(e) => error!("Error waiting for shutdown: {}", e),
    }

    info!("Exchange daemon stopped");
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::time;

    /// A Tickerplant stand-in that completes the handshake and returns how many
    /// bytes the daemon sent it afterwards.
    #[tokio::test]
    async fn daemon_sends_nothing_to_the_tickerplant() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let tp = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
            }
            sock.write_all(&[3]).await.unwrap();
            let mut received = Vec::new();
            let _ = sock.read_to_end(&mut received).await;
            received.len()
        });

        let client = KdbClient::connect("127.0.0.1", port, "", "").await.unwrap();
        run(client, async {
            time::sleep(Duration::from_millis(300)).await;
            Ok(())
        })
        .await
        .unwrap();

        assert_eq!(
            tp.await.unwrap(),
            0,
            "the daemon must not define tables or publish quotes of its own"
        );
    }
}
