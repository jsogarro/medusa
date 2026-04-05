//! Trade deduplication using a sliding window
//!
//! Prevents duplicate trades from being published to the Tickerplant,
//! which can occur during reconnects or exchange-side issues.

use std::collections::{HashSet, VecDeque};

/// Sliding window deduplicator for trade IDs.
///
/// Maintains a FIFO queue of the last N trade IDs and a HashSet for O(1) lookup.
/// When capacity is reached, evicts the oldest trade ID.
#[derive(Debug)]
pub struct TradeDeduplicator {
    seen: HashSet<String>,
    order: VecDeque<String>,
    capacity: usize,
}

#[allow(dead_code)]
impl TradeDeduplicator {
    /// Create a new deduplicator with the given capacity.
    ///
    /// Default capacity is 10,000 trade IDs.
    pub fn new(capacity: usize) -> Self {
        Self {
            seen: HashSet::with_capacity(capacity),
            order: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// Check if a trade ID has already been seen.
    pub fn is_duplicate(&self, trade_id: &str) -> bool {
        self.seen.contains(trade_id)
    }

    /// Record a new trade ID.
    ///
    /// If at capacity, evicts the oldest trade ID (FIFO).
    pub fn record(&mut self, trade_id: &str) {
        // If already seen, don't add again
        if self.seen.contains(trade_id) {
            return;
        }

        // Evict oldest if at capacity
        if self.order.len() >= self.capacity {
            if let Some(oldest) = self.order.pop_front() {
                self.seen.remove(&oldest);
            }
        }

        // Add new trade ID
        self.seen.insert(trade_id.to_string());
        self.order.push_back(trade_id.to_string());
    }

    /// Returns the number of trade IDs currently tracked.
    pub fn len(&self) -> usize {
        self.seen.len()
    }

    /// Returns whether the deduplicator is empty.
    pub fn is_empty(&self) -> bool {
        self.seen.is_empty()
    }

    /// Clear all tracked trade IDs.
    pub fn clear(&mut self) {
        self.seen.clear();
        self.order.clear();
    }
}

impl Default for TradeDeduplicator {
    fn default() -> Self {
        Self::new(10_000)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_trade() {
        let mut dedup = TradeDeduplicator::new(100);
        assert!(!dedup.is_duplicate("trade1"));
        dedup.record("trade1");
        assert!(dedup.is_duplicate("trade1"));
        assert_eq!(dedup.len(), 1);
    }

    #[test]
    fn test_duplicate_detection() {
        let mut dedup = TradeDeduplicator::new(100);
        dedup.record("trade1");
        dedup.record("trade2");

        assert!(dedup.is_duplicate("trade1"));
        assert!(dedup.is_duplicate("trade2"));
        assert!(!dedup.is_duplicate("trade3"));
        assert_eq!(dedup.len(), 2);
    }

    #[test]
    fn test_eviction_at_capacity() {
        let mut dedup = TradeDeduplicator::new(3);
        dedup.record("trade1");
        dedup.record("trade2");
        dedup.record("trade3");

        assert_eq!(dedup.len(), 3);
        assert!(dedup.is_duplicate("trade1"));

        // Add 4th trade, should evict trade1 (oldest)
        dedup.record("trade4");
        assert_eq!(dedup.len(), 3);
        assert!(!dedup.is_duplicate("trade1")); // evicted
        assert!(dedup.is_duplicate("trade2"));
        assert!(dedup.is_duplicate("trade3"));
        assert!(dedup.is_duplicate("trade4"));
    }

    #[test]
    fn test_fifo_eviction_order() {
        let mut dedup = TradeDeduplicator::new(2);
        dedup.record("first");
        dedup.record("second");
        dedup.record("third"); // evicts "first"

        assert!(!dedup.is_duplicate("first"));
        assert!(dedup.is_duplicate("second"));
        assert!(dedup.is_duplicate("third"));

        dedup.record("fourth"); // evicts "second"
        assert!(!dedup.is_duplicate("second"));
        assert!(dedup.is_duplicate("third"));
        assert!(dedup.is_duplicate("fourth"));
    }

    #[test]
    fn test_record_duplicate_doesnt_reorder() {
        let mut dedup = TradeDeduplicator::new(3);
        dedup.record("trade1");
        dedup.record("trade2");

        // Recording duplicate should not change anything
        dedup.record("trade1");
        assert_eq!(dedup.len(), 2);

        dedup.record("trade3");
        dedup.record("trade4"); // should evict trade1 (not trade2)

        assert!(!dedup.is_duplicate("trade1"));
        assert!(dedup.is_duplicate("trade2"));
    }

    #[test]
    fn test_clear() {
        let mut dedup = TradeDeduplicator::new(100);
        dedup.record("trade1");
        dedup.record("trade2");
        assert_eq!(dedup.len(), 2);

        dedup.clear();
        assert_eq!(dedup.len(), 0);
        assert!(dedup.is_empty());
        assert!(!dedup.is_duplicate("trade1"));
    }

    #[test]
    fn test_default_capacity() {
        let dedup = TradeDeduplicator::default();
        assert_eq!(dedup.capacity, 10_000);
        assert!(dedup.is_empty());
    }
}
