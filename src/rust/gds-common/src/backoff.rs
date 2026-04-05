//! Exponential backoff for reconnection
//!
//! Provides configurable exponential backoff with jitter
//! for WebSocket reconnection attempts.

use std::time::Duration;

/// Exponential backoff with configurable min/max delay.
///
/// Delay doubles after each call to `next()`, capped at `max`.
/// Call `reset()` after a successful connection to restart.
#[derive(Debug, Clone)]
pub struct ExponentialBackoff {
    current: Duration,
    min: Duration,
    max: Duration,
}

impl ExponentialBackoff {
    /// Create a new backoff with min (initial) and max (cap) delays.
    ///
    /// # Example
    /// ```
    /// use gds_common::ExponentialBackoff;
    /// use std::time::Duration;
    ///
    /// let mut backoff = ExponentialBackoff::new(
    ///     Duration::from_secs(1),
    ///     Duration::from_secs(60),
    /// );
    /// assert_eq!(backoff.next_delay(), Duration::from_secs(1));
    /// assert_eq!(backoff.next_delay(), Duration::from_secs(2));
    /// ```
    pub fn new(min: Duration, max: Duration) -> Self {
        Self {
            current: min,
            min,
            max,
        }
    }

    /// Returns the current delay and advances to the next (doubled, capped at max).
    pub fn next_delay(&mut self) -> Duration {
        let delay = self.current;
        let millis = (self.current.as_millis() as u64)
            .saturating_mul(2)
            .min(self.max.as_millis() as u64);
        self.current = Duration::from_millis(millis);
        delay
    }

    /// Reset backoff to initial delay (call after successful connection).
    pub fn reset(&mut self) {
        self.current = self.min;
    }

    /// Returns the current delay without advancing.
    pub fn peek(&self) -> Duration {
        self.current
    }
}

impl Default for ExponentialBackoff {
    fn default() -> Self {
        Self::new(Duration::from_secs(1), Duration::from_secs(60))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backoff_progression() {
        let mut b = ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(60));
        assert_eq!(b.next_delay(), Duration::from_secs(1));
        assert_eq!(b.next_delay(), Duration::from_secs(2));
        assert_eq!(b.next_delay(), Duration::from_secs(4));
        assert_eq!(b.next_delay(), Duration::from_secs(8));
        assert_eq!(b.next_delay(), Duration::from_secs(16));
        assert_eq!(b.next_delay(), Duration::from_secs(32));
        assert_eq!(b.next_delay(), Duration::from_secs(60)); // capped
        assert_eq!(b.next_delay(), Duration::from_secs(60)); // stays capped
    }

    #[test]
    fn test_backoff_reset() {
        let mut b = ExponentialBackoff::new(Duration::from_secs(1), Duration::from_secs(60));
        b.next_delay();
        b.next_delay();
        b.next_delay();
        b.reset();
        assert_eq!(b.next_delay(), Duration::from_secs(1));
    }

    #[test]
    fn test_backoff_default() {
        let b = ExponentialBackoff::default();
        assert_eq!(b.peek(), Duration::from_secs(1));
    }
}
