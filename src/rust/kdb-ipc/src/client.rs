//! kdb+ IPC client
//!
//! Async client for communicating with kdb+ processes via IPC protocol.

use crate::decode::Decoder;
use crate::encode::Encoder;
use crate::error::{KdbError, Result};
use crate::types::KObject;
use byteorder::LittleEndian;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{timeout, Duration};

/// Maximum message size (100 MB)
const MAX_MESSAGE_SIZE: u32 = 100 * 1024 * 1024;

/// Timeout for network operations (30 seconds)
const NETWORK_TIMEOUT: Duration = Duration::from_secs(30);

/// Async client for kdb+ IPC
///
/// # Lifecycle
/// 1. Create with `connect()`
/// 2. Execute queries with `query()`, `send_sync()`, or `send_async()`
/// 3. Subscribe to updates with `subscribe()`
/// 4. Disconnect with `disconnect()` or drop
#[derive(Debug)]
pub struct KdbClient {
    stream: TcpStream,
}

impl KdbClient {
    /// Connect to kdb+ process with authentication
    ///
    /// # Arguments
    /// * `host` - Host address
    /// * `port` - Port number
    /// * `username` - Username for authentication (empty string for no auth)
    /// * `password` - Password for authentication (empty string for no auth)
    ///
    /// # Returns
    /// Connected client or error
    pub async fn connect(
        host: &str,
        port: u16,
        username: &str,
        password: &str,
    ) -> Result<Self> {
        tracing::info!("Connecting to kdb+ at {}:{}", host, port);

        let mut stream = TcpStream::connect(format!("{}:{}", host, port))
            .await
            .map_err(|e| KdbError::ConnectionError(e.to_string()))?;

        // Send authentication credentials
        // Format: "username:password\x03\x00"
        let auth_msg = if username.is_empty() && password.is_empty() {
            ":\x03\x00".to_string()
        } else {
            format!("{}:{}\x03\x00", username, password)
        };

        stream
            .write_all(auth_msg.as_bytes())
            .await
            .map_err(|e| KdbError::ConnectionError(e.to_string()))?;

        // Wait for authentication response (1 byte: 0x01 = success, 0x00 = failure)
        let mut response = [0u8; 1];
        timeout(NETWORK_TIMEOUT, stream.read_exact(&mut response))
            .await
            .map_err(|_| KdbError::ConnectionError("Authentication timeout".to_string()))?
            .map_err(|e| KdbError::ConnectionError(e.to_string()))?;

        if response[0] != 1 {
            return Err(KdbError::AuthenticationFailed);
        }

        tracing::info!("Successfully connected and authenticated");

        Ok(Self { stream })
    }

    /// Send an async message (fire-and-forget)
    ///
    /// # Arguments
    /// * `obj` - K object to send
    ///
    /// # Returns
    /// Success or error
    pub async fn send_async(&mut self, obj: KObject) -> Result<()> {
        let mut encoder = Encoder::new();
        let msg = encoder.encode_async(&obj)?;

        self.stream
            .write_all(&msg)
            .await
            .map_err(KdbError::IoError)?;

        Ok(())
    }

    /// Send a sync message and wait for response
    ///
    /// # Arguments
    /// * `obj` - K object to send
    ///
    /// # Returns
    /// Response K object or error
    pub async fn send_sync(&mut self, obj: KObject) -> Result<KObject> {
        let mut encoder = Encoder::new();
        let msg = encoder.encode_sync(&obj)?;

        self.stream
            .write_all(&msg)
            .await
            .map_err(KdbError::IoError)?;

        self.read_response().await
    }

    /// Execute a q query string (convenience wrapper for send_sync)
    ///
    /// # Arguments
    /// * `query` - Query string to execute
    ///
    /// # Returns
    /// Response K object or error
    pub async fn query(&mut self, query: &str) -> Result<KObject> {
        let obj = KObject::CharList(query.as_bytes().to_vec());
        self.send_sync(obj).await
    }

    /// Read a response from the server
    ///
    /// # Returns
    /// Decoded K object or error
    pub async fn read_response(&mut self) -> Result<KObject> {
        // Read header (8 bytes) with timeout
        let mut header = [0u8; 8];
        timeout(NETWORK_TIMEOUT, self.stream.read_exact(&mut header))
            .await
            .map_err(|_| KdbError::ConnectionError("Read timeout (header)".to_string()))?
            .map_err(KdbError::IoError)?;

        // Parse message length from header
        let mut cursor = std::io::Cursor::new(&header[4..8]);
        let total_length = byteorder::ReadBytesExt::read_u32::<LittleEndian>(&mut cursor)?;

        // Validate message size
        if total_length < 8 {
            return Err(KdbError::InvalidMessage(format!(
                "Message length {} is less than minimum header size 8",
                total_length
            )));
        }

        if total_length > MAX_MESSAGE_SIZE {
            return Err(KdbError::InvalidMessage(format!(
                "Message length {} exceeds maximum {}",
                total_length, MAX_MESSAGE_SIZE
            )));
        }

        // Read full message (including header we already read) with timeout
        let mut full_msg = vec![0u8; total_length as usize];
        full_msg[..8].copy_from_slice(&header);
        timeout(NETWORK_TIMEOUT, self.stream.read_exact(&mut full_msg[8..]))
            .await
            .map_err(|_| KdbError::ConnectionError("Read timeout (payload)".to_string()))?
            .map_err(KdbError::IoError)?;

        // Decode message
        let mut decoder = Decoder::new(full_msg);
        let obj = decoder.decode_message()?;

        // Check for kdb+ error response
        if let KObject::Error(msg) = &obj {
            return Err(KdbError::KdbRuntimeError(msg.clone()));
        }

        Ok(obj)
    }

    /// Subscribe to updates from kdb+ (continuous read loop)
    ///
    /// # Arguments
    /// * `callback` - Function to call for each received message
    ///
    /// # Returns
    /// Error if subscription fails (never returns on success)
    pub async fn subscribe<F>(&mut self, mut callback: F) -> Result<()>
    where
        F: FnMut(KObject) -> Result<()>,
    {
        loop {
            let obj = self.read_response().await?;
            callback(obj)?;
        }
    }

    /// Disconnect from kdb+ process
    pub async fn disconnect(mut self) -> Result<()> {
        self.stream
            .shutdown()
            .await
            .map_err(KdbError::IoError)?;
        tracing::info!("Disconnected from kdb+");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests - require a running kdb+ process
    // Run with: cargo test -- --ignored

    #[tokio::test]
    #[ignore]
    async fn test_connect_and_query() {
        let mut client = KdbClient::connect("localhost", 5001, "", "")
            .await
            .unwrap();

        let result = client.query("2+2").await.unwrap();
        assert!(matches!(result, KObject::Long(4)));

        client.disconnect().await.unwrap();
    }

    #[tokio::test]
    #[ignore]
    async fn test_send_async() {
        let mut client = KdbClient::connect("localhost", 5001, "", "")
            .await
            .unwrap();

        let obj = KObject::CharList(b"show `async_test".to_vec());
        client.send_async(obj).await.unwrap();

        client.disconnect().await.unwrap();
    }

    #[tokio::test]
    #[ignore]
    async fn test_auth_failure() {
        let result = KdbClient::connect("localhost", 5001, "bad", "creds").await;
        assert!(matches!(result, Err(KdbError::AuthenticationFailed)));
    }

    #[tokio::test]
    async fn test_connect_unreachable() {
        // 192.0.2.1 is TEST-NET-1, guaranteed unreachable
        let result = KdbClient::connect("192.0.2.1", 9999, "", "").await;
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), KdbError::ConnectionError(_)));
    }
}
