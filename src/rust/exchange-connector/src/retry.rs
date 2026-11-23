//! Retry logic with exponential backoff for rate limit and network errors
//!
//! Provides automatic retry with exponential backoff for transient failures.

use crate::client::ExchangeError;
use rand::Rng;
use std::future::Future;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{debug, warn};

/// Exponential backoff retry configuration
#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Maximum number of retry attempts
    pub max_retries: u32,
    /// Initial delay before first retry (e.g., 1 second)
    pub initial_delay: Duration,
    /// Maximum delay between retries (cap)
    pub max_delay: Duration,
    /// Jitter factor (0.0 to 1.0) to add randomness to delays
    pub jitter_factor: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 5,
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(60),
            jitter_factor: 0.1,
        }
    }
}

impl RetryConfig {
    /// Create a new retry config for rate limit errors
    /// Uses conservative backoff: 2s → 4s → 8s → 16s → 32s (max 5 retries)
    pub fn for_rate_limit() -> Self {
        Self {
            max_retries: 5,
            initial_delay: Duration::from_secs(2),
            max_delay: Duration::from_secs(60),
            jitter_factor: 0.2, // ±20% jitter
        }
    }

    /// Create a new retry config for network errors
    /// Uses aggressive backoff for faster recovery: 1s → 2s → 4s → 8s → 16s
    pub fn for_network() -> Self {
        Self {
            max_retries: 5,
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(30),
            jitter_factor: 0.1, // ±10% jitter
        }
    }

    /// Calculate the delay for a given attempt number with jitter
    fn calculate_delay(&self, attempt: u32) -> Duration {
        let base_delay = self.initial_delay.as_millis() as u64 * 2_u64.pow(attempt);
        let capped_delay = base_delay.min(self.max_delay.as_millis() as u64);

        // Add jitter: randomness in range [-jitter_factor, +jitter_factor]
        let jitter = if self.jitter_factor > 0.0 {
            let jitter_range = (capped_delay as f64 * self.jitter_factor).round() as i64;
            rand::thread_rng().gen_range(-jitter_range..=jitter_range)
        } else {
            0
        };

        let final_delay = (capped_delay as i64 + jitter).max(0) as u64;
        Duration::from_millis(final_delay)
    }
}

/// Retry a fallible async operation with exponential backoff
///
/// # Arguments
/// * `config` - Retry configuration
/// * `operation_name` - Name for logging purposes
/// * `operation` - Async function that returns Result<T, ExchangeError>
///
/// # Returns
/// * `Ok(T)` if operation succeeds within max retries
/// * `Err(ExchangeError)` if all retries exhausted or non-retryable error
///
/// # Example
/// ```no_run
/// use exchange_connector::retry::{retry_with_backoff, RetryConfig};
/// use exchange_connector::client::ExchangeError;
///
/// async fn fetch_data() -> Result<String, ExchangeError> {
///     // ... implementation
///     Ok("data".to_string())
/// }
///
/// #[tokio::main]
/// async fn main() {
///     let config = RetryConfig::for_rate_limit();
///     let result = retry_with_backoff(config, "fetch_data", || fetch_data()).await;
/// }
/// ```
pub async fn retry_with_backoff<F, Fut, T>(
    config: RetryConfig,
    operation_name: &str,
    mut operation: F,
) -> Result<T, ExchangeError>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, ExchangeError>>,
{
    let mut attempt = 0;

    loop {
        match operation().await {
            Ok(result) => {
                if attempt > 0 {
                    debug!(
                        operation = operation_name,
                        attempt = attempt + 1,
                        "Operation succeeded after retry"
                    );
                }
                return Ok(result);
            }
            Err(err) if err.is_retryable() && attempt < config.max_retries => {
                let delay = config.calculate_delay(attempt);
                warn!(
                    operation = operation_name,
                    attempt = attempt + 1,
                    max_retries = config.max_retries,
                    delay_ms = delay.as_millis(),
                    error = %err,
                    "Retryable error occurred, backing off"
                );

                sleep(delay).await;
                attempt += 1;
            }
            Err(err) => {
                if err.is_retryable() {
                    warn!(
                        operation = operation_name,
                        attempt = attempt + 1,
                        max_retries = config.max_retries,
                        error = %err,
                        "Max retries exhausted"
                    );
                } else {
                    debug!(
                        operation = operation_name,
                        error = %err,
                        "Non-retryable error, failing immediately"
                    );
                }
                return Err(err);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    #[test]
    fn test_retry_config_default() {
        let config = RetryConfig::default();
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.initial_delay, Duration::from_secs(1));
        assert_eq!(config.max_delay, Duration::from_secs(60));
    }

    #[test]
    fn test_retry_config_rate_limit() {
        let config = RetryConfig::for_rate_limit();
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.initial_delay, Duration::from_secs(2));
        assert_eq!(config.max_delay, Duration::from_secs(60));
        assert_eq!(config.jitter_factor, 0.2);
    }

    #[test]
    fn test_retry_config_network() {
        let config = RetryConfig::for_network();
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.initial_delay, Duration::from_secs(1));
        assert_eq!(config.max_delay, Duration::from_secs(30));
    }

    #[test]
    fn test_calculate_delay_progression() {
        let config = RetryConfig {
            max_retries: 5,
            initial_delay: Duration::from_secs(2),
            max_delay: Duration::from_secs(60),
            jitter_factor: 0.0, // No jitter for deterministic test
        };

        // Progression: 2s → 4s → 8s → 16s → 32s → 60s (capped)
        assert_eq!(config.calculate_delay(0), Duration::from_secs(2));
        assert_eq!(config.calculate_delay(1), Duration::from_secs(4));
        assert_eq!(config.calculate_delay(2), Duration::from_secs(8));
        assert_eq!(config.calculate_delay(3), Duration::from_secs(16));
        assert_eq!(config.calculate_delay(4), Duration::from_secs(32));
        assert_eq!(config.calculate_delay(5), Duration::from_secs(60)); // capped
        assert_eq!(config.calculate_delay(10), Duration::from_secs(60)); // stays capped
    }

    #[test]
    fn test_calculate_delay_with_jitter() {
        let config = RetryConfig::for_rate_limit(); // jitter_factor = 0.2

        // With jitter, delay should be in range [base * 0.8, base * 1.2]
        for attempt in 0..5 {
            let delay = config.calculate_delay(attempt);
            let base = config.initial_delay.as_millis() as u64 * 2_u64.pow(attempt);
            let capped = base.min(config.max_delay.as_millis() as u64);
            let lower = (capped as f64 * 0.8) as u64;
            let upper = (capped as f64 * 1.2) as u64;

            assert!(
                delay.as_millis() as u64 >= lower && delay.as_millis() as u64 <= upper,
                "Delay {} out of range [{}, {}] for attempt {}",
                delay.as_millis(),
                lower,
                upper,
                attempt
            );
        }
    }

    #[tokio::test]
    async fn test_retry_succeeds_immediately() {
        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let config = RetryConfig::default();
        let result = retry_with_backoff(config, "test_op", || {
            let counter = counter_clone.clone();
            async move {
                counter.fetch_add(1, Ordering::SeqCst);
                Ok::<_, ExchangeError>(42)
            }
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(counter.load(Ordering::SeqCst), 1); // Called once
    }

    #[tokio::test]
    async fn test_retry_succeeds_after_retries() {
        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let config = RetryConfig {
            max_retries: 3,
            initial_delay: Duration::from_millis(10),
            max_delay: Duration::from_millis(100),
            jitter_factor: 0.0,
        };

        let result = retry_with_backoff(config, "test_op", || {
            let counter = counter_clone.clone();
            async move {
                let attempt = counter.fetch_add(1, Ordering::SeqCst);
                if attempt < 2 {
                    Err(ExchangeError::RateLimit("Too many requests".to_string()))
                } else {
                    Ok(42)
                }
            }
        })
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(counter.load(Ordering::SeqCst), 3); // Called 3 times
    }

    #[tokio::test]
    async fn test_retry_fails_after_max_retries() {
        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let config = RetryConfig {
            max_retries: 2,
            initial_delay: Duration::from_millis(10),
            max_delay: Duration::from_millis(100),
            jitter_factor: 0.0,
        };

        let result = retry_with_backoff(config, "test_op", || {
            let counter = counter_clone.clone();
            async move {
                counter.fetch_add(1, Ordering::SeqCst);
                Err::<i32, _>(ExchangeError::RateLimit("Too many requests".to_string()))
            }
        })
        .await;

        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), ExchangeError::RateLimit(_)));
        assert_eq!(counter.load(Ordering::SeqCst), 3); // Called 3 times (initial + 2 retries)
    }

    #[tokio::test]
    async fn test_retry_fails_immediately_on_non_retryable() {
        let counter = Arc::new(AtomicU32::new(0));
        let counter_clone = counter.clone();

        let config = RetryConfig::default();
        let result = retry_with_backoff(config, "test_op", || {
            let counter = counter_clone.clone();
            async move {
                counter.fetch_add(1, Ordering::SeqCst);
                Err::<i32, _>(ExchangeError::InvalidRequest("Bad params".to_string()))
            }
        })
        .await;

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            ExchangeError::InvalidRequest(_)
        ));
        assert_eq!(counter.load(Ordering::SeqCst), 1); // Called once, no retries
    }
}
