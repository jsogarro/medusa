//! Exchange implementations
//!
//! Each module implements the ExchangeClient trait for a specific exchange.

pub mod alpaca;
pub mod binance;
pub mod bitstamp;
pub mod coinbase;
pub mod kraken;

pub use alpaca::AlpacaClient;
pub use binance::BinanceClient;
pub use bitstamp::BitstampClient;
pub use coinbase::CoinbaseClient;
pub use kraken::KrakenClient;
