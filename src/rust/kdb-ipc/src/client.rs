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
    pub async fn connect(host: &str, port: u16, username: &str, password: &str) -> Result<Self> {
        tracing::info!("Connecting to kdb+ at {}:{}", host, port);

        let mut stream = TcpStream::connect(format!("{}:{}", host, port))
            .await
            .map_err(|e| KdbError::ConnectionError(e.to_string()))?;

        // Login string: "username:password" plus an optional capability byte, then NUL.
        // Capability bytes 1-3 let the server compress replies and the decoder cannot
        // read those, so none is sent: that is capability 0 (kdb+ IPC protocol docs).
        let auth_msg = format!("{}:{}\0", username, password);

        stream
            .write_all(auth_msg.as_bytes())
            .await
            .map_err(|e| KdbError::ConnectionError(e.to_string()))?;

        // The server replies with one capability byte (the protocol version both
        // sides agreed on; 0 for a capability-0 login) and closes the socket if the
        // login is rejected.
        let mut response = [0u8; 1];
        match timeout(NETWORK_TIMEOUT, stream.read_exact(&mut response))
            .await
            .map_err(|_| KdbError::ConnectionError("Authentication timeout".to_string()))?
        {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                return Err(KdbError::AuthenticationFailed)
            }
            Err(e) => return Err(KdbError::ConnectionError(e.to_string())),
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
        self.stream.shutdown().await.map_err(KdbError::IoError)?;
        tracing::info!("Disconnected from kdb+");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests - require a running kdb+ process (port from KDB_TEST_PORT,
    // default 5001). Run with: cargo test -- --ignored
    fn test_port() -> u16 {
        std::env::var("KDB_TEST_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(5001)
    }

    #[tokio::test]
    #[ignore]
    async fn test_connect_and_query() {
        let mut client = KdbClient::connect("localhost", test_port(), "", "")
            .await
            .unwrap();

        let result = client.query("2+2").await.unwrap();
        assert!(matches!(result, KObject::Long(4)));

        client.disconnect().await.unwrap();
    }

    #[tokio::test]
    #[ignore]
    async fn test_send_async() {
        let mut client = KdbClient::connect("localhost", test_port(), "", "")
            .await
            .unwrap();

        let obj = KObject::CharList(b"show `async_test".to_vec());
        client.send_async(obj).await.unwrap();

        client.disconnect().await.unwrap();
    }

    #[tokio::test]
    #[ignore]
    async fn test_auth_failure() {
        let result = KdbClient::connect("localhost", test_port(), "bad", "creds").await;
        assert!(matches!(result, Err(KdbError::AuthenticationFailed)));
    }

    /// Fake kdb+ listener: reads the login string up to its NUL terminator, then
    /// replies with `reply` (or just closes when `None`, as q does on a bad login).
    async fn fake_q(reply: Option<u8>) -> u16 {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
            }
            if let Some(r) = reply {
                sock.write_all(&[r]).await.unwrap();
                // keep the socket open until the client drops it
                let _ = sock.read(&mut b).await;
            }
        });
        port
    }

    #[tokio::test]
    async fn test_handshake_accepts_modern_capability_byte() {
        // q 4.x answers the login with the negotiated capability (3), not 1.
        let port = fake_q(Some(3)).await;
        let result = KdbClient::connect("127.0.0.1", port, "", "").await;
        assert!(result.is_ok(), "{:?}", result.err());
    }

    #[tokio::test]
    async fn test_handshake_closed_connection_is_auth_failure() {
        // q closes the socket without replying when the login is rejected.
        let port = fake_q(None).await;
        let result = KdbClient::connect("127.0.0.1", port, "bad", "creds").await;
        assert!(matches!(result, Err(KdbError::AuthenticationFailed)));
    }

    #[tokio::test]
    async fn test_connect_unreachable() {
        // 192.0.2.1 is TEST-NET-1, guaranteed unreachable
        let result = KdbClient::connect("192.0.2.1", 9999, "", "").await;
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), KdbError::ConnectionError(_)));
    }

    /// Fake kdb+ listener that returns the login string it received (without the NUL).
    async fn capturing_q(reply: u8) -> (u16, tokio::task::JoinHandle<Vec<u8>>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut login = Vec::new();
            let mut b = [0u8; 1];
            loop {
                sock.read_exact(&mut b).await.unwrap();
                if b[0] == 0 {
                    break;
                }
                login.push(b[0]);
            }
            sock.write_all(&[reply]).await.unwrap();
            login
        });
        (port, task)
    }

    #[tokio::test]
    async fn test_login_does_not_advertise_compression() {
        // Capability bytes 1-3 all enable compressed replies, which the decoder
        // rejects; the only byte that does not is 0, which is sent by omitting it.
        let (port, login) = capturing_q(0).await;
        let result = KdbClient::connect("127.0.0.1", port, "user", "pw").await;
        assert!(result.is_ok(), "a capability-0 reply is a successful login");
        assert_eq!(login.await.unwrap(), b"user:pw");
    }
}
