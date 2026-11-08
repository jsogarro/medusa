import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  failConnects: 0,
  conns: [] as any[],
  hangQueries: false
}))

vi.mock('node-q', async () => {
  const { EventEmitter } = await import('events')
  class FakeConn extends EventEmitter {
    ksCalls: string[] = []
    k(..._args: any[]) {
      const cb = _args[_args.length - 1]
      if (!h.hangQueries) cb(undefined, 'ok')
    }
    ks(expr: string, cb: (e?: Error) => void) {
      this.ksCalls.push(expr)
      cb(undefined)
    }
    close(cb: () => void) {
      cb()
    }
  }
  return {
    connect: (_p: unknown, cb: (e?: Error, c?: unknown) => void) => {
      if (h.failConnects > 0) {
        h.failConnects--
        cb(new Error('ECONNREFUSED'))
        return
      }
      const c = new FakeConn()
      h.conns.push(c)
      cb(undefined, c)
    }
  }
})

import { KdbClient } from './kdb-client'

beforeEach(() => {
  vi.useFakeTimers()
  vi.spyOn(console, 'log').mockImplementation(() => {})
  vi.spyOn(console, 'error').mockImplementation(() => {})
  h.failConnects = 0
  h.conns = []
  h.hangQueries = false
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('KdbClient', () => {
  it('does not crash on an error event when nobody listens, and surfaces the connect failure', async () => {
    h.failConnects = 1
    const client = new KdbClient({ host: 'localhost', port: 1 })
    await expect(client.connect()).rejects.toThrow('ECONNREFUSED')
    expect(vi.getTimerCount()).toBe(1) // reconnect was still scheduled
    await client.disconnect()
  })

  it('keeps retrying with backoff until the connection succeeds', async () => {
    h.failConnects = 3
    const client = new KdbClient({ host: 'localhost', port: 1 })
    await expect(client.connect()).rejects.toThrow('ECONNREFUSED')

    await vi.advanceTimersByTimeAsync(5 * 60_000)

    expect(h.failConnects).toBe(0)
    expect(client.isConnected()).toBe(true)
    await client.disconnect()
  })

  it('reconnects after a close and re-subscribes to every subscribed table', async () => {
    const client = new KdbClient({ host: 'localhost', port: 1 })
    await client.connect()
    await client.subscribe('order')
    await client.subscribe('trade')
    expect(h.conns[0].ksCalls).toHaveLength(2)

    h.conns[0].emit('close')
    expect(client.isConnected()).toBe(false)
    await vi.advanceTimersByTimeAsync(10_000)

    expect(client.isConnected()).toBe(true)
    expect(h.conns).toHaveLength(2)
    expect(h.conns[1].ksCalls).toEqual(h.conns[0].ksCalls)
    await client.disconnect()
  })

  it('does not reconnect after an explicit disconnect', async () => {
    const client = new KdbClient({ host: 'localhost', port: 1 })
    await client.connect()
    await client.disconnect()
    h.conns[0].emit('close')
    await vi.advanceTimersByTimeAsync(120_000)
    expect(h.conns).toHaveLength(1)
  })

  it('a late close from a replaced connection does not clobber the live one', async () => {
    const client = new KdbClient({ host: 'localhost', port: 1 })
    await client.connect()
    h.conns[0].emit('close')
    await vi.advanceTimersByTimeAsync(10_000)
    expect(client.isConnected()).toBe(true)

    h.conns[0].emit('close')
    expect(client.isConnected()).toBe(true)
    await client.disconnect()
  })

  it('rejects a query that never answers instead of hanging', async () => {
    const client = new KdbClient({ host: 'localhost', port: 1 }, { queryTimeoutMs: 1000 })
    await client.connect()
    h.hangQueries = true
    const p = client.query('.some.fn', [1])
    const assertion = expect(p).rejects.toThrow(/timed out/)
    await vi.advanceTimersByTimeAsync(1000)
    await assertion
    await client.disconnect()
  })

  it('forwards upd events', async () => {
    const client = new KdbClient({ host: 'localhost', port: 1 })
    const seen: unknown[] = []
    client.on('update', (t, d) => seen.push([t, d]))
    await client.connect()
    h.conns[0].emit('upd', 'order', [1])
    expect(seen).toEqual([['order', [1]]])
    await client.disconnect()
  })
})

