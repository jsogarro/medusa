//! Exchange implementations
//!
//! Each module implements the ExchangeClient trait for a specific exchange.

pub mod bitstamp;
pub mod coinbase;
pub mod kraken;

pub use bitstamp::BitstampClient;
pub use coinbase::CoinbaseClient;
pub use kraken::KrakenClient;
