//! Health monitoring for WebSocket connections
//!
//! Tracks last message time and marks connections unhealthy
//! when no data is received within the configured timeout.

use std::time::Duration;
use tokio::time::Instant;

/// Monitors WebSocket connection health based on message frequency.
///
/// If no message is received within `timeout`, the connection is considered stale.
/// Default timeout: 30 seconds.
#[derive(Debug)]
pub struct HealthMonitor {
    last_message: Instant,
    timeout: Duration,
    healthy: bool,
}

impl HealthMonitor {
    /// Create a new health monitor with the given staleness timeout.
    pub fn new(timeout: Duration) -> Self {
        Self {
            last_message: Instant::now(),
            timeout,
            healthy: false,
        }
    }

    /// Reset the last-message timer (call on every received message).
    pub fn reset_timer(&mut self) {
        self.last_message = Instant::now();
    }

    /// Mark connection as healthy (e.g., after successful subscribe).
    pub fn mark_healthy(&mut self) {
        self.healthy = true;
        self.last_message = Instant::now();
    }

    /// Mark connection as unhealthy (e.g., after disconnect).
    pub fn mark_unhealthy(&mut self) {
        self.healthy = false;
    }

    /// Returns true if no message received within timeout.
    pub fn is_stale(&self) -> bool {
        self.healthy && self.last_message.elapsed() > self.timeout
    }

    /// Returns whether the connection is currently marked healthy.
    pub fn is_healthy(&self) -> bool {
        self.healthy
    }

    /// Returns the configured timeout duration.
    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    /// Returns elapsed time since the last message.
    pub fn elapsed(&self) -> Duration {
        self.last_message.elapsed()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state() {
        let monitor = HealthMonitor::new(Duration::from_secs(30));
        assert!(!monitor.is_healthy());
        assert!(!monitor.is_stale()); // not stale because not healthy yet
    }

    #[test]
    fn test_mark_healthy() {
        let mut monitor = HealthMonitor::new(Duration::from_secs(30));
        monitor.mark_healthy();
        assert!(monitor.is_healthy());
        assert!(!monitor.is_stale()); // just marked healthy, not stale yet
    }

    #[test]
    fn test_mark_unhealthy() {
        let mut monitor = HealthMonitor::new(Duration::from_secs(30));
        monitor.mark_healthy();
        monitor.mark_unhealthy();
        assert!(!monitor.is_healthy());
    }

    #[tokio::test]
    async fn test_staleness_detection() {
        let mut monitor = HealthMonitor::new(Duration::from_millis(50));
        monitor.mark_healthy();
        assert!(!monitor.is_stale());

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(monitor.is_stale());
    }

    #[tokio::test]
    async fn test_reset_prevents_staleness() {
        let mut monitor = HealthMonitor::new(Duration::from_millis(100));
        monitor.mark_healthy();

        tokio::time::sleep(Duration::from_millis(60)).await;
        monitor.reset_timer();

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(!monitor.is_stale()); // reset extended the window
    }
}
