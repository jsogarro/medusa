// ============================================================================
// circuit_breaker.rs - Circuit Breaker Pattern for Exchange API Calls
// ============================================================================
//
// Implements the circuit breaker pattern to prevent cascading failures when
// an exchange API is experiencing issues. The circuit breaker has three states:
//
// - Closed: Normal operation, all requests allowed
// - Open: Too many failures, reject all requests immediately (no network calls)
// - Half-Open: Testing recovery, allow limited requests to test if API recovered
//
// Thresholds:
// - Opens after 5 consecutive failures
// - Cooldown: 30 seconds
// - Half-open max requests: 3
//
// Usage:
// ```rust
// let circuit_breaker = CircuitBreaker::new(CircuitBreakerConfig::default());
//
// let result = circuit_breaker.call("place_order", || async {
//     exchange_client.place_order(&order).await
// }).await?;
// ```
// ============================================================================

use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Circuit breaker configuration
#[derive(Debug, Clone)]
pub struct CircuitBreakerConfig {
    /// Number of consecutive failures before opening circuit
    pub failure_threshold: u32,
    /// Cooldown duration before transitioning from Open to Half-Open
    pub cooldown_duration: Duration,
    /// Maximum requests allowed in Half-Open state
    pub half_open_max_requests: u32,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 5,
            cooldown_duration: Duration::from_secs(30),
            half_open_max_requests: 3,
        }
    }
}

/// Circuit breaker state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    /// Normal operation - all requests allowed
    Closed,
    /// Too many failures - reject all requests
    Open,
    /// Testing recovery - limited requests allowed
    HalfOpen,
}

/// Internal circuit breaker state
#[derive(Debug)]
struct CircuitBreakerState {
    state: CircuitState,
    consecutive_failures: u32,
    last_failure_time: Option<Instant>,
    half_open_requests: u32,
}

impl CircuitBreakerState {
    fn new() -> Self {
        Self {
            state: CircuitState::Closed,
            consecutive_failures: 0,
            last_failure_time: None,
            half_open_requests: 0,
        }
    }
}

/// Circuit breaker for exchange API calls
pub struct CircuitBreaker {
    config: CircuitBreakerConfig,
    state: Arc<RwLock<CircuitBreakerState>>,
}

impl CircuitBreaker {
    /// Create a new circuit breaker with the given configuration
    pub fn new(config: CircuitBreakerConfig) -> Self {
        Self {
            config,
            state: Arc::new(RwLock::new(CircuitBreakerState::new())),
        }
    }

    /// Execute a call through the circuit breaker
    ///
    /// # Arguments
    /// * `operation` - Operation name for logging
    /// * `f` - Async function to execute
    ///
    /// # Returns
    /// * `Ok(T)` - Successful result
    /// * `Err(CircuitBreakerError)` - Circuit breaker error or wrapped function error
    pub async fn call<F, T, E>(&self, operation: &str, f: F) -> Result<T, CircuitBreakerError<E>>
    where
        F: std::future::Future<Output = Result<T, E>>,
    {
        // Check if request is allowed
        {
            let mut state = self.state.write().await;
            match self.check_state(&mut state).await {
                Ok(_) => {}
                Err(CircuitBreakerError::CircuitOpen) => {
                    return Err(CircuitBreakerError::CircuitOpen)
                }
                Err(CircuitBreakerError::InnerError(_)) => {
                    unreachable!("check_state returns CircuitOpen, not InnerError")
                }
            }
        }

        // Execute the function
        let result = f.await;

        // Update state based on result
        {
            let mut state = self.state.write().await;
            match result {
                Ok(_) => self.on_success(&mut state, operation).await,
                Err(_) => self.on_failure(&mut state, operation).await,
            }
        }

        result.map_err(CircuitBreakerError::InnerError)
    }

    /// Check if request is allowed based on current state
    async fn check_state(
        &self,
        state: &mut CircuitBreakerState,
    ) -> Result<(), CircuitBreakerError<()>> {
        match state.state {
            CircuitState::Closed => Ok(()),
            CircuitState::Open => {
                // Check if cooldown period has elapsed
                if let Some(last_failure) = state.last_failure_time {
                    if last_failure.elapsed() >= self.config.cooldown_duration {
                        // Transition to half-open and count this request as the
                        // first recovery probe that is allowed through.
                        state.state = CircuitState::HalfOpen;
                        state.half_open_requests = 1;
                        info!("Circuit breaker transitioning to Half-Open state");
                        Ok(())
                    } else {
                        debug!("Circuit breaker Open - request rejected");
                        Err(CircuitBreakerError::CircuitOpen)
                    }
                } else {
                    Err(CircuitBreakerError::CircuitOpen)
                }
            }
            CircuitState::HalfOpen => {
                if state.half_open_requests < self.config.half_open_max_requests {
                    state.half_open_requests += 1;
                    Ok(())
                } else {
                    debug!("Circuit breaker Half-Open - max requests reached");
                    Err(CircuitBreakerError::CircuitOpen)
                }
            }
        }
    }

    /// Handle successful request
    async fn on_success(&self, state: &mut CircuitBreakerState, operation: &str) {
        match state.state {
            CircuitState::Closed => {
                // Reset failure count
                state.consecutive_failures = 0;
            }
            CircuitState::HalfOpen => {
                // Check if enough successful requests to close circuit
                if state.half_open_requests >= self.config.half_open_max_requests {
                    state.state = CircuitState::Closed;
                    state.consecutive_failures = 0;
                    state.last_failure_time = None;
                    state.half_open_requests = 0;
                    info!("Circuit breaker closed - {} recovered", operation);
                }
            }
            CircuitState::Open => {
                // This shouldn't happen, but handle it gracefully
                warn!("Unexpected success in Open state");
            }
        }
    }

    /// Handle failed request
    async fn on_failure(&self, state: &mut CircuitBreakerState, operation: &str) {
        state.consecutive_failures += 1;
        state.last_failure_time = Some(Instant::now());

        match state.state {
            CircuitState::Closed => {
                if state.consecutive_failures >= self.config.failure_threshold {
                    state.state = CircuitState::Open;
                    warn!(
                        "Circuit breaker opened for {} - {} consecutive failures",
                        operation, state.consecutive_failures
                    );
                }
            }
            CircuitState::HalfOpen => {
                // Failed during half-open - reopen circuit
                state.state = CircuitState::Open;
                state.half_open_requests = 0;
                warn!(
                    "Circuit breaker re-opened for {} - failure during half-open state",
                    operation
                );
            }
            CircuitState::Open => {
                // Already open, just update failure count
                debug!(
                    "Circuit breaker Open - failure count: {}",
                    state.consecutive_failures
                );
            }
        }
    }

    /// Get current circuit breaker status
    pub async fn status(&self) -> CircuitBreakerStatus {
        let state = self.state.read().await;
        CircuitBreakerStatus {
            state: state.state,
            consecutive_failures: state.consecutive_failures,
            half_open_requests: state.half_open_requests,
        }
    }
}

/// Circuit breaker error
#[derive(Debug, thiserror::Error)]
pub enum CircuitBreakerError<E> {
    #[error("Circuit breaker open - too many failures")]
    CircuitOpen,
    #[error("Inner error: {0}")]
    InnerError(E),
}

/// Circuit breaker status (for monitoring)
#[derive(Debug, Clone)]
pub struct CircuitBreakerStatus {
    pub state: CircuitState,
    pub consecutive_failures: u32,
    pub half_open_requests: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_circuit_breaker_closed_state() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 3,
            cooldown_duration: Duration::from_secs(1),
            half_open_max_requests: 2,
        });

        // Successful requests should keep circuit closed
        for _ in 0..10 {
            let result = cb.call("test", async { Ok::<_, ()>(42) }).await;
            assert!(result.is_ok());
        }

        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::Closed);
        assert_eq!(status.consecutive_failures, 0);
    }

    #[tokio::test]
    async fn test_circuit_breaker_opens_after_failures() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 3,
            cooldown_duration: Duration::from_secs(1),
            half_open_max_requests: 2,
        });

        // First 2 failures should not open circuit
        for _ in 0..2 {
            let _result = cb.call("test", async { Err::<(), _>("test error") }).await;
        }

        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::Closed);

        // 3rd failure should open circuit
        let _result = cb.call("test", async { Err::<(), _>("test error") }).await;

        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::Open);
        assert_eq!(status.consecutive_failures, 3);
    }

    #[tokio::test]
    async fn test_circuit_breaker_rejects_when_open() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 2,
            cooldown_duration: Duration::from_secs(10),
            half_open_max_requests: 2,
        });

        // Open the circuit with failures
        for _ in 0..2 {
            let _result = cb.call("test", async { Err::<(), _>("test error") }).await;
        }

        // Next request should be rejected immediately
        let result = cb.call("test", async { Ok::<_, ()>(42) }).await;

        assert!(matches!(result, Err(CircuitBreakerError::CircuitOpen)));
    }

    #[tokio::test]
    async fn test_circuit_breaker_transitions_to_half_open() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 2,
            cooldown_duration: Duration::from_millis(100),
            half_open_max_requests: 2,
        });

        // Open the circuit
        for _ in 0..2 {
            let _result = cb.call("test", async { Err::<(), _>("test error") }).await;
        }

        assert_eq!(cb.status().await.state, CircuitState::Open);

        // Wait for cooldown
        tokio::time::sleep(Duration::from_millis(150)).await;

        // Next request should transition to half-open
        let result = cb.call("test", async { Ok::<_, ()>(42) }).await;

        assert!(result.is_ok());
        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::HalfOpen);
    }

    #[tokio::test]
    async fn test_circuit_breaker_closes_after_half_open_success() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 2,
            cooldown_duration: Duration::from_millis(100),
            half_open_max_requests: 2,
        });

        // Open the circuit
        for _ in 0..2 {
            let _result = cb.call("test", async { Err::<(), _>("test error") }).await;
        }

        // Wait for cooldown
        tokio::time::sleep(Duration::from_millis(150)).await;

        // Successful half-open requests should close circuit
        for _ in 0..2 {
            let result = cb.call("test", async { Ok::<_, ()>(42) }).await;
            assert!(result.is_ok());
        }

        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::Closed);
        assert_eq!(status.consecutive_failures, 0);
    }

    #[tokio::test]
    async fn test_circuit_breaker_reopens_on_half_open_failure() {
        let cb = CircuitBreaker::new(CircuitBreakerConfig {
            failure_threshold: 2,
            cooldown_duration: Duration::from_millis(100),
            half_open_max_requests: 2,
        });

        // Open the circuit
        for _ in 0..2 {
            let _result = cb.call("test", async { Err::<(), _>("test error") }).await;
        }

        // Wait for cooldown
        tokio::time::sleep(Duration::from_millis(150)).await;

        // First half-open request succeeds
        let result = cb.call("test", async { Ok::<_, ()>(42) }).await;
        assert!(result.is_ok());

        // Second half-open request fails - should reopen circuit
        let _result = cb.call("test", async { Err::<(), _>("test error") }).await;

        let status = cb.status().await;
        assert_eq!(status.state, CircuitState::Open);
    }
}
