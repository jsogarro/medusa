//! WebSocket feed implementations for market data streaming
//!
//! Each module implements WebSocket subscriptions for orderbook and trade data.

pub mod alpaca;
pub mod binance;
pub mod bitstamp;
pub mod coinbase;
pub mod kraken;

pub use alpaca::AlpacaFeed;
pub use binance::BinanceFeed;
pub use bitstamp::BitstampFeed;
pub use coinbase::CoinbaseFeed;
pub use kraken::KrakenFeed;
