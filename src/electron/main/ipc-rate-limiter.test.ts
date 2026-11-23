import { describe, expect, it } from 'vitest'
import { IpcRateLimiter } from './ipc-rate-limiter'

function setup(capacity: number, refill: number, overrides = {}) {
  let t = 1_000_000
  const limiter = new IpcRateLimiter(capacity, refill, overrides, () => t)
  return { limiter, advance: (ms: number) => (t += ms) }
}

describe('IpcRateLimiter', () => {
  it('allows a burst up to capacity then blocks', () => {
    const { limiter } = setup(3, 1)
    expect([1, 2, 3, 4].map(() => limiter.checkLimit('c'))).toEqual([true, true, true, false])
  })

  it('accumulates fractional refill across frequent calls', () => {
    const { limiter, advance } = setup(1, 1)
    expect(limiter.checkLimit('c')).toBe(true)
    // 10 polls 150ms apart: each adds 0.15 token; floor() per call would discard all of it.
    let allowed = 0
    for (let i = 0; i < 10; i++) {
      advance(150)
      if (limiter.checkLimit('c')) allowed++
    }
    expect(allowed).toBe(1) // 1.5s elapsed at 1 token/s
  })

  it('refills over time and caps at capacity', () => {
    const { limiter, advance } = setup(2, 1)
    limiter.checkLimit('c')
    limiter.checkLimit('c')
    expect(limiter.checkLimit('c')).toBe(false)
    advance(1000)
    expect(limiter.checkLimit('c')).toBe(true)
    expect(limiter.checkLimit('c')).toBe(false)
    advance(60_000)
    expect([1, 2, 3].map(() => limiter.checkLimit('c'))).toEqual([true, true, false])
  })

  it('uses per-channel overrides and isolates channels', () => {
    const { limiter } = setup(100, 10, { strict: { capacity: 1, refillRate: 0.1 } })
    expect(limiter.checkLimit('strict')).toBe(true)
    expect(limiter.checkLimit('strict')).toBe(false)
    expect(limiter.checkLimit('other')).toBe(true)
  })

  it('reports status', () => {
    const { limiter } = setup(5, 1)
    limiter.checkLimit('c')
    expect(limiter.getStatus('c').tokens).toBeCloseTo(4)
  })

  it('a backwards clock step neither grants tokens now nor double-refills when the clock catches up', () => {
    const { limiter, advance } = setup(5, 1)
    for (let i = 0; i < 5; i++) limiter.checkLimit('c')
    advance(-10_000)
    expect(limiter.checkLimit('c')).toBe(false)
    expect(limiter.getStatus('c').tokens).toBeGreaterThanOrEqual(0)
    advance(10_000)
    expect(limiter.checkLimit('c')).toBe(false)
  })
})
