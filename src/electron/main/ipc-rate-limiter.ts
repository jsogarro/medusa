/**
 * ipc-rate-limiter.ts - Token Bucket Rate Limiter for IPC Calls
 *
 * Prevents the renderer from overwhelming the main process with IPC calls.
 * Uses a token bucket algorithm for fair rate limiting.
 *
 * Thresholds:
 * - Capacity: 100 tokens
 * - Refill rate: 10 tokens/second
 * - Per-channel limits configurable
 */

export interface RateLimitConfig {
  capacity: number
  refillRate: number // tokens per second
}

interface Bucket {
  tokens: number
  lastRefill: number
}

export class IpcRateLimiter {
  private buckets = new Map<string, Bucket>()

  constructor(
    private capacity: number = 100,
    private refillRate: number = 10,
    private overrides: Record<string, RateLimitConfig> = {},
    private now: () => number = () => Date.now()
  ) {}

  private configFor(channel: string): RateLimitConfig {
    return this.overrides[channel] ?? { capacity: this.capacity, refillRate: this.refillRate }
  }

  /**
   * Check if request is allowed (consumes 1 token if available).
   * Call this only after the request has passed validation, so malformed
   * requests cannot burn the caller's budget.
   */
  checkLimit(channel: string): boolean {
    const { capacity, refillRate } = this.configFor(channel)
    const now = this.now()
    let bucket = this.buckets.get(channel)

    if (!bucket) {
      bucket = { tokens: capacity, lastRefill: now }
      this.buckets.set(channel, bucket)
    }

    // Fractional refill: always advance lastRefill so sub-token elapsed time is not discarded.
    // A backwards clock step must not move lastRefill back, or the catch-up would refill twice.
    const elapsed = Math.max(0, now - bucket.lastRefill) / 1000
    bucket.tokens = Math.max(0, Math.min(capacity, bucket.tokens + elapsed * refillRate))
    bucket.lastRefill = Math.max(bucket.lastRefill, now)

    if (bucket.tokens >= 1) {
      bucket.tokens--
      return true
    }

    return false
  }

  /**
   * Get current status for a channel.
   * @param channel - IPC channel name
   * @returns Current token count and capacity
   */
  getStatus(channel: string): { tokens: number; capacity: number } {
    const { capacity } = this.configFor(channel)
    return { tokens: this.buckets.get(channel)?.tokens ?? capacity, capacity }
  }

  /**
   * Reset rate limiter for a specific channel.
   * @param channel - IPC channel name
   */
  reset(channel: string): void {
    this.buckets.delete(channel)
  }

  /**
   * Reset all rate limiters.
   */
  resetAll(): void {
    this.buckets.clear()
  }
}
