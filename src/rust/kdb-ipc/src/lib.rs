//! kdb+ IPC protocol implementation
//!
//! Provides async client for communicating with kdb+ processes.

pub mod client;
pub mod protocol;

pub use client::KdbClient;
