//! kdb+ IPC protocol implementation
//!
//! Provides async client for communicating with kdb+ processes.

pub mod client;
pub mod decode;
pub mod encode;
pub mod error;
pub mod types;

pub use client::KdbClient;
pub use error::{KdbError, Result};
pub use types::KObject;
