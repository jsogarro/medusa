//! In-memory orderbook state management
//!
//! Maintains sorted bid/ask levels and applies snapshot/delta updates.
//! Uses integer price keys (price * 1e8) to avoid float comparison issues.

use anyhow::{Context, Result};
use chrono::Utc;
use exchange_connector::types::{OrderBook, PriceLevel};
use std::collections::{BTreeMap, HashMap};

/// Precision multiplier for price keys (1e8 = 8 decimal places)
const PRICE_PRECISION: f64 = 1e8;

/// Managed orderbook with sequence tracking
#[derive(Debug, Clone)]
pub struct ManagedOrderbook {
    /// Bids: price -> quantity (sorted descending by price)
    pub bids: BTreeMap<i64, f64>,
    /// Asks: price -> quantity (sorted ascending by price)
    pub asks: BTreeMap<i64, f64>,
    /// Last sequence number (for gap detection)
    pub sequence: u64,
}

impl ManagedOrderbook {
    /// Create a new empty orderbook
    pub fn new() -> Self {
        Self {
            bids: BTreeMap::new(),
            asks: BTreeMap::new(),
            sequence: 0,
        }
    }

    /// Apply a snapshot (full orderbook replacement)
    pub fn apply_snapshot(&mut self, bids: Vec<[f64; 2]>, asks: Vec<[f64; 2]>, sequence: u64) {
        self.bids.clear();
        self.asks.clear();

        for [price, qty] in bids {
            if qty > 0.0 {
                self.bids.insert(price_to_key(price), qty);
            }
        }

        for [price, qty] in asks {
            if qty > 0.0 {
                self.asks.insert(price_to_key(price), qty);
            }
        }

        self.sequence = sequence;
    }

    /// Apply a delta update (incremental change)
    ///
    /// Returns Ok(()) if successful, Err if sequence gap detected.
    pub fn apply_delta(
        &mut self,
        bids: Vec<[f64; 2]>,
        asks: Vec<[f64; 2]>,
        sequence: u64,
    ) -> Result<()> {
        // Check sequence number (validate all deltas, including first after snapshot)
        if sequence != self.sequence + 1 {
            return Err(anyhow::anyhow!(
                "Sequence gap: expected {}, got {}",
                self.sequence + 1,
                sequence
            ));
        }

        // Apply bid updates
        for [price, qty] in bids {
            let key = price_to_key(price);
            if qty == 0.0 {
                self.bids.remove(&key);
            } else {
                self.bids.insert(key, qty);
            }
        }

        // Apply ask updates
        for [price, qty] in asks {
            let key = price_to_key(price);
            if qty == 0.0 {
                self.asks.remove(&key);
            } else {
                self.asks.insert(key, qty);
            }
        }

        self.sequence = sequence;
        Ok(())
    }

    /// Convert to exchange_connector::types::OrderBook
    pub fn to_orderbook(&self, symbol: &str, exchange: &str, max_levels: usize) -> OrderBook {
        // Take top N bids (highest prices first, so reverse iteration)
        let bid_levels: Vec<PriceLevel> = self
            .bids
            .iter()
            .rev()
            .take(max_levels)
            .map(|(key, qty)| PriceLevel {
                price: key_to_price(*key),
                quantity: *qty,
            })
            .collect();

        // Take top N asks (lowest prices first)
        let ask_levels: Vec<PriceLevel> = self
            .asks
            .iter()
            .take(max_levels)
            .map(|(key, qty)| PriceLevel {
                price: key_to_price(*key),
                quantity: *qty,
            })
            .collect();

        OrderBook {
            pair: symbol.to_string(),
            exchange: exchange.to_string(),
            bids: bid_levels,
            asks: ask_levels,
            timestamp: Utc::now(),
            sequence: Some(self.sequence),
        }
    }
}

impl Default for ManagedOrderbook {
    fn default() -> Self {
        Self::new()
    }
}

/// Container for multiple symbol orderbooks
pub struct OrderbookState {
    books: HashMap<String, ManagedOrderbook>,
}

#[allow(dead_code)]
impl OrderbookState {
    /// Create a new orderbook state container
    pub fn new() -> Self {
        Self {
            books: HashMap::new(),
        }
    }

    /// Get or create a managed orderbook for a symbol
    pub fn get_or_create(&mut self, symbol: &str) -> &mut ManagedOrderbook {
        self.books
            .entry(symbol.to_string())
            .or_default()
    }

    /// Get a reference to a managed orderbook
    pub fn get(&self, symbol: &str) -> Option<&ManagedOrderbook> {
        self.books.get(symbol)
    }

    /// Check if a delta sequence is valid (expected next)
    pub fn check_sequence(&self, symbol: &str, delta_sequence: u64) -> Result<()> {
        if let Some(book) = self.books.get(symbol) {
            if book.sequence > 0 && delta_sequence != book.sequence + 1 {
                return Err(anyhow::anyhow!(
                    "Sequence gap for {}: expected {}, got {}",
                    symbol,
                    book.sequence + 1,
                    delta_sequence
                ));
            }
        }
        Ok(())
    }

    /// Apply snapshot to a symbol
    pub fn apply_snapshot(
        &mut self,
        symbol: &str,
        bids: Vec<[f64; 2]>,
        asks: Vec<[f64; 2]>,
        sequence: u64,
    ) {
        let book = self.get_or_create(symbol);
        book.apply_snapshot(bids, asks, sequence);
    }

    /// Apply delta to a symbol
    pub fn apply_delta(
        &mut self,
        symbol: &str,
        bids: Vec<[f64; 2]>,
        asks: Vec<[f64; 2]>,
        sequence: u64,
    ) -> Result<()> {
        let book = self.get_or_create(symbol);
        book.apply_delta(bids, asks, sequence)
            .context(format!("Failed to apply delta for {}", symbol))
    }

    /// Get orderbook snapshot for publishing
    pub fn get_snapshot(
        &self,
        symbol: &str,
        exchange: &str,
        max_levels: usize,
    ) -> Option<OrderBook> {
        self.books
            .get(symbol)
            .map(|book| book.to_orderbook(symbol, exchange, max_levels))
    }
}

impl Default for OrderbookState {
    fn default() -> Self {
        Self::new()
    }
}

/// Convert price to integer key (avoids float comparison)
fn price_to_key(price: f64) -> i64 {
    (price * PRICE_PRECISION).round() as i64
}

/// Convert integer key back to price
fn key_to_price(key: i64) -> f64 {
    key as f64 / PRICE_PRECISION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_price_key_roundtrip() {
        let price = 50000.12345678;
        let key = price_to_key(price);
        let recovered = key_to_price(key);
        assert!((price - recovered).abs() < 1e-7);
    }

    #[test]
    fn test_price_key_ordering() {
        let p1 = price_to_key(50000.0);
        let p2 = price_to_key(50001.0);
        let p3 = price_to_key(49999.0);
        assert!(p1 < p2);
        assert!(p3 < p1);
    }

    #[test]
    fn test_managed_orderbook_snapshot() {
        let mut book = ManagedOrderbook::new();
        let bids = vec![[50000.0, 1.5], [49999.0, 2.0]];
        let asks = vec![[50001.0, 0.8], [50002.0, 1.2]];

        book.apply_snapshot(bids, asks, 100);

        assert_eq!(book.sequence, 100);
        assert_eq!(book.bids.len(), 2);
        assert_eq!(book.asks.len(), 2);
    }

    #[test]
    fn test_managed_orderbook_delta_add_level() {
        let mut book = ManagedOrderbook::new();
        book.apply_snapshot(vec![[50000.0, 1.0]], vec![[50001.0, 1.0]], 1);

        let result = book.apply_delta(vec![[49999.0, 0.5]], vec![], 2);
        assert!(result.is_ok());
        assert_eq!(book.bids.len(), 2);
        assert_eq!(book.sequence, 2);
    }

    #[test]
    fn test_managed_orderbook_delta_remove_level() {
        let mut book = ManagedOrderbook::new();
        book.apply_snapshot(
            vec![[50000.0, 1.0], [49999.0, 0.5]],
            vec![[50001.0, 1.0]],
            1,
        );

        let result = book.apply_delta(vec![[49999.0, 0.0]], vec![], 2);
        assert!(result.is_ok());
        assert_eq!(book.bids.len(), 1);
    }

    #[test]
    fn test_managed_orderbook_sequence_gap() {
        let mut book = ManagedOrderbook::new();
        book.apply_snapshot(vec![[50000.0, 1.0]], vec![[50001.0, 1.0]], 1);

        // Try to apply sequence 3 (skipping 2)
        let result = book.apply_delta(vec![], vec![], 3);
        assert!(result.is_err());
    }

    #[test]
    fn test_managed_orderbook_to_orderbook() {
        let mut book = ManagedOrderbook::new();
        book.apply_snapshot(
            vec![[50000.0, 1.0], [49999.0, 0.5], [49998.0, 0.3]],
            vec![[50001.0, 0.8], [50002.0, 1.2]],
            42,
        );

        let ob = book.to_orderbook("BTCUSD", "test", 2);
        assert_eq!(ob.bids.len(), 2);
        assert_eq!(ob.asks.len(), 2);
        assert_eq!(ob.bids[0].price, 50000.0); // Highest bid first
        assert_eq!(ob.asks[0].price, 50001.0); // Lowest ask first
        assert_eq!(ob.sequence, Some(42));
    }

    #[test]
    fn test_orderbook_state_get_or_create() {
        let mut state = OrderbookState::new();
        let book = state.get_or_create("BTCUSD");
        assert_eq!(book.sequence, 0);
    }

    #[test]
    fn test_orderbook_state_apply_snapshot() {
        let mut state = OrderbookState::new();
        state.apply_snapshot("BTCUSD", vec![[50000.0, 1.0]], vec![[50001.0, 1.0]], 1);

        let snapshot = state.get_snapshot("BTCUSD", "test", 10);
        assert!(snapshot.is_some());
        let ob = snapshot.unwrap();
        assert_eq!(ob.bids.len(), 1);
        assert_eq!(ob.asks.len(), 1);
    }

    #[test]
    fn test_orderbook_state_sequence_validation() {
        let mut state = OrderbookState::new();
        state.apply_snapshot("BTCUSD", vec![[50000.0, 1.0]], vec![[50001.0, 1.0]], 1);

        // Valid delta
        let result = state.apply_delta("BTCUSD", vec![], vec![], 2);
        assert!(result.is_ok());

        // Invalid delta (gap)
        let result = state.apply_delta("BTCUSD", vec![], vec![], 5);
        assert!(result.is_err());
    }

    #[test]
    fn test_empty_orderbook_snapshot() {
        let mut state = OrderbookState::new();
        state.apply_snapshot("BTCUSD", vec![], vec![], 0);

        let snapshot = state.get_snapshot("BTCUSD", "test", 10);
        assert!(snapshot.is_some());
        let ob = snapshot.unwrap();
        assert_eq!(ob.bids.len(), 0);
        assert_eq!(ob.asks.len(), 0);
    }
}
