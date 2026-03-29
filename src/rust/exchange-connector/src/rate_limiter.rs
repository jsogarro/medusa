//! Token bucket rate limiter for exchange API requests
//!
//! Implements a token bucket algorithm with per-second and per-minute limits,
//! supporting per-endpoint rate limits for fine-grained control.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::time::sleep;

/// Token bucket for rate limiting
#[derive(Debug, Clone)]
struct Bucket {
    /// Maximum tokens (capacity)
    capacity: u32,
    /// Current token count
    tokens: f64,
    /// Token refill rate (tokens per second)
    refill_rate: f64,
    /// Last refill timestamp
    last_refill: Instant,
}

impl Bucket {
    fn new(capacity: u32, refill_rate: f64) -> Self {
        Self {
            capacity,
            tokens: capacity as f64,
            refill_rate,
            last_refill: Instant::now(),
        }
    }

    /// Refill tokens based on elapsed time
    fn refill(&mut self) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_refill).as_secs_f64();
        let new_tokens = elapsed * self.refill_rate;
        self.tokens = (self.tokens + new_tokens).min(self.capacity as f64);
        self.last_refill = now;
    }

    /// Try to acquire tokens, returns true if successful
    fn try_acquire(&mut self, tokens: u32) -> bool {
        self.refill();
        if self.tokens >= tokens as f64 {
            self.tokens -= tokens as f64;
            true
        } else {
            false
        }
    }

    /// Calculate wait time needed to acquire tokens
    fn wait_time_for(&self, tokens: u32) -> Duration {
        if self.tokens >= tokens as f64 {
            Duration::ZERO
        } else {
            let deficit = tokens as f64 - self.tokens;
            let wait_seconds = deficit / self.refill_rate;
            Duration::from_secs_f64(wait_seconds)
        }
    }
}

/// Rate limiter with support for global and per-endpoint limits
#[derive(Debug)]
pub struct RateLimiter {
    /// Global rate limit bucket
    global: Arc<Mutex<Bucket>>,
    /// Per-endpoint rate limit buckets
    endpoints: Arc<Mutex<HashMap<String, Bucket>>>,
}

impl RateLimiter {
    /// Create a new rate limiter
    ///
    /// # Arguments
    /// * `requests_per_second` - Global rate limit (requests per second)
    /// * `requests_per_minute` - Optional minute-level limit (stricter than per-second * 60)
    ///
    /// # Example
    /// ```
    /// use exchange_connector::rate_limiter::RateLimiter;
    ///
    /// // 10 requests/sec, max 500/minute
    /// let limiter = RateLimiter::new(10, Some(500));
    /// ```
    pub fn new(requests_per_second: u32, requests_per_minute: Option<u32>) -> Self {
        // Use the stricter of the two limits
        let effective_rate = if let Some(per_minute) = requests_per_minute {
            let rate_from_minute = per_minute as f64 / 60.0;
            rate_from_minute.min(requests_per_second as f64)
        } else {
            requests_per_second as f64
        };

        Self {
            global: Arc::new(Mutex::new(Bucket::new(
                requests_per_second * 2, // Burst capacity = 2x rate
                effective_rate,
            ))),
            endpoints: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Set a per-endpoint rate limit
    ///
    /// # Arguments
    /// * `endpoint` - Endpoint identifier (e.g., "/order_book", "/balance")
    /// * `requests_per_second` - Rate limit for this endpoint
    ///
    /// # Example
    /// ```
    /// # use exchange_connector::rate_limiter::RateLimiter;
    /// # tokio_test::block_on(async {
    /// let limiter = RateLimiter::new(10, None);
    /// limiter.set_endpoint_limit("/balance", 2).await;
    /// # });
    /// ```
    pub async fn set_endpoint_limit(&self, endpoint: &str, requests_per_second: u32) {
        let mut endpoints = self.endpoints.lock().await;
        endpoints.insert(
            endpoint.to_string(),
            Bucket::new(requests_per_second * 2, requests_per_second as f64),
        );
    }

    /// Acquire a token, waiting if necessary
    ///
    /// This method will block until a token is available. For global-only rate limiting,
    /// pass `None` as the endpoint.
    ///
    /// # Arguments
    /// * `endpoint` - Optional endpoint identifier for per-endpoint limiting
    /// * `tokens` - Number of tokens to acquire (default: 1)
    ///
    /// # Example
    /// ```
    /// # use exchange_connector::rate_limiter::RateLimiter;
    /// # tokio_test::block_on(async {
    /// let limiter = RateLimiter::new(10, None);
    /// limiter.acquire(None, 1).await;
    /// // Make API request here
    /// # });
    /// ```
    pub async fn acquire(&self, endpoint: Option<&str>, tokens: u32) {
        loop {
            // Acquire both locks atomically to avoid race conditions
            let wait_time = {
                let mut global = self.global.lock().await;
                let mut endpoints = self.endpoints.lock().await;

                let global_acquired = global.try_acquire(tokens);
                let endpoint_acquired = if let Some(ep) = endpoint {
                    if let Some(bucket) = endpoints.get_mut(ep) {
                        bucket.try_acquire(tokens)
                    } else {
                        true // No endpoint limit configured
                    }
                } else {
                    true // No endpoint specified
                };

                if global_acquired && endpoint_acquired {
                    return; // Both succeeded
                }

                // Calculate wait time for failed acquisitions
                let global_wait = if !global_acquired {
                    global.wait_time_for(tokens)
                } else {
                    Duration::ZERO
                };

                let endpoint_wait = if !endpoint_acquired {
                    if let Some(ep) = endpoint {
                        if let Some(bucket) = endpoints.get_mut(ep) {
                            bucket.wait_time_for(tokens)
                        } else {
                            Duration::ZERO
                        }
                    } else {
                        Duration::ZERO
                    }
                } else {
                    Duration::ZERO
                };

                global_wait.max(endpoint_wait)
            };

            tracing::trace!(
                "Rate limit wait: {:?} for endpoint: {:?}",
                wait_time,
                endpoint
            );
            sleep(wait_time + Duration::from_millis(10)).await; // Add 10ms buffer
        }
    }

    /// Try to acquire a token without waiting
    ///
    /// Returns `true` if token was acquired, `false` if rate limit would be exceeded.
    ///
    /// # Example
    /// ```
    /// # use exchange_connector::rate_limiter::RateLimiter;
    /// # tokio_test::block_on(async {
    /// let limiter = RateLimiter::new(10, None);
    /// if limiter.try_acquire(None, 1).await {
    ///     // Make API request
    /// } else {
    ///     // Rate limit exceeded, handle gracefully
    /// }
    /// # });
    /// ```
    pub async fn try_acquire(&self, endpoint: Option<&str>, tokens: u32) -> bool {
        // Check global limit
        let global_ok = {
            let mut global = self.global.lock().await;
            global.try_acquire(tokens)
        };

        if !global_ok {
            return false;
        }

        // Check endpoint-specific limit
        if let Some(ep) = endpoint {
            let mut endpoints = self.endpoints.lock().await;
            if let Some(bucket) = endpoints.get_mut(ep) {
                if !bucket.try_acquire(tokens) {
                    return false;
                }
            }
        }

        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::Instant as TokioInstant;

    #[tokio::test]
    async fn test_token_bucket_basic() {
        let mut bucket = Bucket::new(10, 5.0);
        assert!(bucket.try_acquire(5));
        assert!((bucket.tokens - 5.0).abs() < 0.01);
        assert!(bucket.try_acquire(5));
        assert!(bucket.tokens < 0.01);
        assert!(!bucket.try_acquire(1));
    }

    #[tokio::test]
    async fn test_token_bucket_refill() {
        let mut bucket = Bucket::new(10, 5.0); // 5 tokens/sec
        bucket.try_acquire(10); // Drain all tokens
        assert_eq!(bucket.tokens, 0.0);

        tokio::time::sleep(Duration::from_millis(200)).await; // Wait 200ms
        bucket.refill();

        // Should have ~1 token after 0.2 seconds (5 tokens/sec * 0.2s = 1)
        assert!(bucket.tokens >= 0.9 && bucket.tokens <= 1.1);
    }

    #[tokio::test]
    async fn test_rate_limiter_global() {
        let limiter = RateLimiter::new(10, None);

        // First request should succeed immediately
        let start = TokioInstant::now();
        limiter.acquire(None, 1).await;
        assert!(start.elapsed() < Duration::from_millis(10));

        // Drain all tokens
        for _ in 0..19 {
            limiter.acquire(None, 1).await;
        }

        // Next request should wait
        let start = TokioInstant::now();
        limiter.acquire(None, 1).await;
        let elapsed = start.elapsed();
        assert!(
            elapsed >= Duration::from_millis(50),
            "Should wait at least 50ms, waited {:?}",
            elapsed
        );
    }

    #[tokio::test]
    async fn test_rate_limiter_endpoint() {
        let limiter = RateLimiter::new(100, None); // High global limit
        limiter.set_endpoint_limit("/balance", 2).await; // Low endpoint limit

        // First two requests should succeed
        assert!(limiter.try_acquire(Some("/balance"), 1).await);
        assert!(limiter.try_acquire(Some("/balance"), 1).await);

        // Third should fail (burst capacity = 4, so 5th fails)
        assert!(limiter.try_acquire(Some("/balance"), 1).await);
        assert!(limiter.try_acquire(Some("/balance"), 1).await);
        assert!(!limiter.try_acquire(Some("/balance"), 1).await);
    }

    #[tokio::test]
    async fn test_rate_limiter_per_minute() {
        let limiter = RateLimiter::new(1000, Some(60)); // 1000/sec but only 60/min

        // Effective rate should be 1/sec (60/min)
        // Burst capacity = 2000, so first 2000 requests are instant
        // After burst, we need to wait for tokens to refill

        // Drain the burst capacity first
        for _ in 0..2000 {
            assert!(limiter.try_acquire(None, 1).await);
        }

        // Now subsequent acquires should wait
        let start = TokioInstant::now();
        limiter.acquire(None, 2).await;
        let elapsed = start.elapsed();

        // Should take at least 1.5 seconds for 2 tokens at 1 token/sec
        assert!(
            elapsed >= Duration::from_millis(1500),
            "Should take ~2s, took {:?}",
            elapsed
        );
    }

    #[tokio::test]
    async fn test_wait_time_calculation() {
        let mut bucket = Bucket::new(10, 5.0); // 5 tokens/sec
        bucket.try_acquire(10); // Drain all tokens

        let wait = bucket.wait_time_for(5);
        // Need 5 tokens at 5 tokens/sec = 1 second
        assert!(
            wait >= Duration::from_millis(950) && wait <= Duration::from_millis(1050),
            "Wait time should be ~1s, got {:?}",
            wait
        );
    }

    // ====================================================================
    // EDGE CASE TESTS
    // ====================================================================

    #[tokio::test]
    async fn test_bucket_zero_capacity() {
        let mut bucket = Bucket::new(0, 1.0);
        assert!(!bucket.try_acquire(1), "Cannot acquire from zero-capacity bucket");
        assert_eq!(bucket.tokens, 0.0);
    }

    #[tokio::test]
    async fn test_bucket_max_capacity_overflow() {
        let mut bucket = Bucket::new(u32::MAX, 1000.0);
        // After long delay, tokens should cap at capacity
        tokio::time::sleep(Duration::from_millis(100)).await;
        bucket.refill();
        assert!(
            bucket.tokens <= u32::MAX as f64,
            "Tokens should not exceed capacity"
        );
    }

    #[tokio::test]
    async fn test_bucket_fractional_tokens() {
        let mut bucket = Bucket::new(10, 0.5); // 0.5 tokens/sec
        bucket.try_acquire(10); // Drain
        tokio::time::sleep(Duration::from_millis(500)).await;
        bucket.refill();
        // Should have ~0.25 tokens after 0.5s at 0.5 tokens/sec
        assert!(
            bucket.tokens >= 0.2 && bucket.tokens <= 0.3,
            "Fractional refill incorrect: {}",
            bucket.tokens
        );
    }

    #[tokio::test]
    async fn test_rate_limiter_zero_tokens_request() {
        let limiter = RateLimiter::new(10, None);
        // Requesting 0 tokens should succeed immediately
        let start = TokioInstant::now();
        limiter.acquire(None, 0).await;
        assert!(start.elapsed() < Duration::from_millis(10));
    }

    #[tokio::test]
    async fn test_rate_limiter_concurrent_access() {
        let limiter = Arc::new(RateLimiter::new(10, None));
        let mut handles = vec![];

        // Spawn 100 concurrent tasks trying to acquire
        for _ in 0..100 {
            let limiter_clone = limiter.clone();
            let handle = tokio::spawn(async move {
                limiter_clone.acquire(None, 1).await;
            });
            handles.push(handle);
        }

        // All should complete without panic
        for handle in handles {
            handle.await.expect("Task should complete");
        }
    }

    #[tokio::test]
    async fn test_rate_limiter_endpoint_not_registered() {
        let limiter = RateLimiter::new(10, None);
        // Endpoint not registered should only check global limit
        assert!(limiter.try_acquire(Some("/unknown"), 1).await);
        assert!(limiter.try_acquire(Some("/unknown"), 1).await);
    }

    #[tokio::test]
    async fn test_rate_limiter_multiple_endpoints() {
        let limiter = RateLimiter::new(100, None);
        limiter.set_endpoint_limit("/orderbook", 5).await;
        limiter.set_endpoint_limit("/balance", 2).await;

        // Exhaust /balance
        for _ in 0..4 {
            assert!(limiter.try_acquire(Some("/balance"), 1).await);
        }
        assert!(!limiter.try_acquire(Some("/balance"), 1).await);

        // /orderbook should still work
        assert!(limiter.try_acquire(Some("/orderbook"), 1).await);
    }

    #[tokio::test]
    async fn test_wait_time_for_zero_tokens() {
        let bucket = Bucket::new(10, 5.0);
        let wait = bucket.wait_time_for(0);
        assert_eq!(wait, Duration::ZERO, "Wait time for 0 tokens should be zero");
    }

    #[tokio::test]
    async fn test_bucket_refill_clamping() {
        let mut bucket = Bucket::new(10, 100.0); // Very fast refill
        bucket.try_acquire(10); // Drain
        tokio::time::sleep(Duration::from_secs(5)).await;
        bucket.refill();
        // Should be clamped to capacity
        assert!(
            bucket.tokens <= 10.0,
            "Tokens {} should not exceed capacity 10",
            bucket.tokens
        );
        assert!(bucket.tokens >= 9.9, "Should be nearly full");
    }

    #[tokio::test]
    async fn test_rate_limiter_acquire_after_drain() {
        let limiter = RateLimiter::new(100, None); // Fast refill (100/s), burst = 200
        // Drain burst capacity
        limiter.acquire(None, 200).await;
        // Acquire 5 more — should wait briefly for refill then succeed
        let start = TokioInstant::now();
        limiter.acquire(None, 5).await;
        let elapsed = start.elapsed();
        assert!(elapsed >= Duration::from_millis(10), "Should wait for refill");
        assert!(elapsed < Duration::from_secs(5), "Should not wait too long");
    }
}
