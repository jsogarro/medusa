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
  private capacity: number
  private refillRate: number

  constructor(capacity: number = 100, refillRate: number = 10) {
    this.capacity = capacity
    this.refillRate = refillRate
  }

  /**
   * Check if request is allowed (consumes 1 token if available).
   * @param channel - IPC channel name
   * @returns true if allowed, false if rate limited
   */
  checkLimit(channel: string): boolean {
    const now = Date.now()
    let bucket = this.buckets.get(channel)

    if (!bucket) {
      bucket = { tokens: this.capacity, lastRefill: now }
      this.buckets.set(channel, bucket)
    }

    // Refill tokens based on time elapsed
    const elapsed = (now - bucket.lastRefill) / 1000 // seconds
    const tokensToAdd = Math.floor(elapsed * this.refillRate)

    if (tokensToAdd > 0) {
      bucket.tokens = Math.min(this.capacity, bucket.tokens + tokensToAdd)
      bucket.lastRefill = now
    }

    // Check if token available
    if (bucket.tokens > 0) {
      bucket.tokens--
      return true
    }

    return false // Rate limited
  }

  /**
   * Get current status for a channel.
   * @param channel - IPC channel name
   * @returns Current token count and capacity
   */
  getStatus(channel: string): { tokens: number; capacity: number } {
    const bucket = this.buckets.get(channel)
    return {
      tokens: bucket?.tokens ?? this.capacity,
      capacity: this.capacity
    }
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
