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

use crate::client::ExchangeError;
use crate::types::Trade;

/// Reject a parsed trade whose price or quantity is not a finite positive
/// number, so malformed venue data is never published as a real trade.
pub(crate) fn check_trade(t: Trade) -> Result<Trade, ExchangeError> {
    for (name, v) in [("price", t.price), ("quantity", t.quantity)] {
        if !v.is_finite() || v <= 0.0 {
            return Err(ExchangeError::Other(format!(
                "Invalid trade {name} from {}: {v}",
                t.exchange
            )));
        }
    }
    Ok(t)
}
