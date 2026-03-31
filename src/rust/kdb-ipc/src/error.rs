//! Error types for kdb+ IPC

use thiserror::Error;

pub type Result<T> = std::result::Result<T, KdbError>;

/// kdb+ IPC errors
#[derive(Debug, Error)]
pub enum KdbError {
    #[error("Connection error: {0}")]
    ConnectionError(String),

    #[error("Authentication failed")]
    AuthenticationFailed,

    #[error("Invalid message: {0}")]
    InvalidMessage(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Encoding error: {0}")]
    EncodingError(String),

    #[error("Decoding error: {0}")]
    DecodingError(String),

    #[error("kdb+ runtime error: {0}")]
    KdbRuntimeError(String),

    #[error("Not connected")]
    NotConnected,

    #[error("Invalid type code: {0}")]
    InvalidTypeCode(i8),
}
