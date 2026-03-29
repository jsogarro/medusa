//! kdb+ IPC protocol primitives
//!
//! See: https://code.kx.com/q/basics/ipc/
//!
//! # Implementation Status
//! This is a stub implementation. Full IPC serialization/deserialization
//! will be implemented in later waves. The protocol is complex and requires
//! careful handling of:
//! - Little-endian byte order
//! - Type codes for atoms, vectors, dictionaries, tables
//! - Compression (if enabled)
//! - Message headers (byte[0]=1 for little-endian, bytes[1-3]=message type, bytes[4-7]=length)

use thiserror::Error;

/// IPC message types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    /// Async message (no response expected)
    Async = 0,
    /// Sync message (response expected)
    Sync = 1,
    /// Response message
    Response = 2,
}

/// Protocol-level errors
#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("Invalid message type: {0}")]
    InvalidMessageType(u8),

    #[error("Invalid message format: {0}")]
    InvalidFormat(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("Deserialization error: {0}")]
    Deserialization(String),
}

/// Serialize a q expression to IPC format
///
/// # Current Implementation
/// Stub: just converts the string to bytes. Full implementation will:
/// - Add IPC header (endianness, message type, length)
/// - Serialize the query as a kdb+ char vector
/// - Apply compression if enabled
pub fn serialize_query(query: &str) -> Vec<u8> {
    // TODO: Implement full IPC serialization
    query.as_bytes().to_vec()
}

/// Deserialize IPC response
///
/// # Current Implementation
/// Stub: just converts bytes to UTF-8 string. Full implementation will:
/// - Parse IPC header
/// - Decompress if needed
/// - Deserialize kdb+ types (atoms, lists, dicts, tables)
/// - Convert to Rust types
pub fn deserialize_response(data: &[u8]) -> Result<String, ProtocolError> {
    // TODO: Implement full IPC deserialization
    Ok(String::from_utf8_lossy(data).to_string())
}
