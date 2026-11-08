import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  handlers: new Map<string, (...args: any[]) => any>(),
  queries: [] as { fn: string; args: any[] | undefined }[],
  clients: [] as any[],
  respond: (_fn: string, _args?: any[]): any => undefined
}))

vi.mock('electron', () => ({
  ipcMain: {
    handle: (ch: string, fn: (...a: any[]) => any) => {
      if (h.handlers.has(ch)) throw new Error(`Attempted to register a second handler for '${ch}'`)
      h.handlers.set(ch, fn)
    },
    removeHandler: (ch: string) => h.handlers.delete(ch)
  },
  BrowserWindow: class {},
  app: { isPackaged: true }
}))

vi.mock('./kdb-client', async () => {
  const { EventEmitter } = await import('events')
  class FakeKdbClient extends EventEmitter {
    connected = false
    disconnects = 0
    constructor(public cfg: unknown) {
      super()
      h.clients.push(this)
    }
    async connect() {
      this.connected = true
    }
    async disconnect() {
      this.connected = false
      this.disconnects++
    }
    isConnected() {
      return this.connected
    }
    async subscribe() {}
    async query(fn: string, args?: any[]) {
      h.queries.push({ fn, args })
      return h.respond(fn, args)
    }
  }
  return { KdbClient: FakeKdbClient }
})

import { setupIpcHandlers } from './ipc-handlers'

const TRUSTED = { senderFrame: { url: 'file:///app/out/renderer/index.html' } }
const EVIL = { senderFrame: { url: 'https://evil.example/' } }
const win = { isDestroyed: () => false, webContents: { send: vi.fn() } } as any
const cfg = { tp: { host: 'localhost', port: 5010 }, rdb: { host: 'localhost', port: 5011 } }

const call = (ch: string, ...args: any[]) => h.handlers.get(ch)!(TRUSTED, ...args)
const order = {
  exchange: 'alpaca',
  pair: 'BTC/USD',
  side: 'buy',
  orderType: 'limit',
  price: 100.5,
  quantity: 2,
  strategy: 'manual'
}
const typed = (a: any) => ({ type: a.type(), value: a.value() })

beforeEach(async () => {
  h.handlers.clear()
  h.queries.length = 0
  h.respond = (fn) => (fn === '.risk.validateOrder' ? [true, null] : { orderId: 'ORD_1_alpaca', status: 'open' })
  setupIpcHandlers(win) // fresh rate limiter per setup
  expect((await call('kdb:connect', cfg)).success).toBe(true)
  h.queries.length = 0
})

describe('kdb:placeOrder', () => {
  it('rejects an order the risk module rejected and never reaches the coordinator', async () => {
    h.respond = (fn) => (fn === '.risk.validateOrder' ? [false, 'emergencyStop', {}] : { orderId: 'X' })
    const r = await call('kdb:placeOrder', order)
    expect(r.success).toBe(false)
    expect(r.error).toMatch(/emergencyStop/)
    expect(h.queries.map((q) => q.fn)).toEqual(['.risk.validateOrder'])
  })

  it.each([[undefined], [null], [true], [[]], [{}], [[null, '']], [['y', '']]])(
    'fails closed on unexpected risk verdict %j',
    async (verdict) => {
      h.respond = (fn) => (fn === '.risk.validateOrder' ? verdict : { orderId: 'X' })
      const r = await call('kdb:placeOrder', order)
      expect(r.success).toBe(false)
      expect(h.queries.map((q) => q.fn)).toEqual(['.risk.validateOrder'])
    }
  )

  it('places through the coordinator with typed symbols and 6-dp fixed-point longs', async () => {
    const r = await call('kdb:placeOrder', order)
    expect(r).toEqual({ success: true, data: { orderId: 'ORD_1_alpaca', status: 'open' } })
    expect(h.queries.map((q) => q.fn)).toEqual(['.risk.validateOrder', '.exchange.coordinator.placeOrder'])

    const [exchange, pair, orderType, side, price, quantity] = h.queries[1].args!.map(typed)
    expect(exchange).toEqual({ type: 'symbol', value: 'alpaca' })
    expect(pair).toEqual({ type: 'symbol', value: 'BTC/USD' })
    expect(orderType).toEqual({ type: 'symbol', value: 'limit' })
    expect(side).toEqual({ type: 'symbol', value: 'buy' })
    expect(price.type).toBe('long')
    expect(price.value.toString()).toBe('100500000')
    expect(quantity.value.toString()).toBe('2000000')
  })

  it('sends a null long price for market orders', async () => {
    await call('kdb:placeOrder', { ...order, orderType: 'market', price: 0 })
    const price = typed(h.queries[1].args![4])
    expect(price).toEqual({ type: 'long', value: null })
  })

  it('fails if the coordinator returns no orderId (never reports a fabricated success)', async () => {
    h.respond = (fn) => (fn === '.risk.validateOrder' ? [true, null] : null)
    const r = await call('kdb:placeOrder', order)
    expect(r.success).toBe(false)
  })

  it('invalid orders do not consume rate-limit tokens', async () => {
    for (let i = 0; i < 50; i++) {
      expect((await call('kdb:placeOrder', { ...order, quantity: -1 })).success).toBe(false)
    }
    expect((await call('kdb:placeOrder', order)).success).toBe(true)
  })

  it('rate limits a burst of valid orders', async () => {
    const results = []
    for (let i = 0; i < 40; i++) results.push((await call('kdb:placeOrder', order)).success)
    expect(results.filter(Boolean).length).toBeLessThan(40)
    expect(results.filter(Boolean).length).toBeGreaterThan(0)
  })

  it('rejects calls from an untrusted sender', async () => {
    const r = await h.handlers.get('kdb:placeOrder')!(EVIL, { ...order, pair: 'BTC_USD' })
    expect(r.success).toBe(false)
    expect(h.queries).toHaveLength(0)
  })
})

describe('kdb:cancelOrder', () => {
  it('routes to the coordinator cancel with the exchange', async () => {
    h.respond = () => ({ status: 'cancelled' })
    const r = await call('kdb:cancelOrder', 'ORD_1_alpaca', 'alpaca')
    expect(r.success).toBe(true)
    expect(h.queries[0].fn).toBe('.exchange.coordinator.cancelOrder')
    expect(h.queries[0].args!.map(typed)).toEqual([
      { type: 'symbol', value: 'alpaca' },
      { type: 'symbol', value: 'ORD_1_alpaca' }
    ])
  })

  it('rejects an invalid order id or exchange', async () => {
    expect((await call('kdb:cancelOrder', 'a;b', 'alpaca')).success).toBe(false)
    expect((await call('kdb:cancelOrder', 'ORD_1', 'a b')).success).toBe(false)
    expect(h.queries).toHaveLength(0)
  })
})

describe('kdb:strategyControl', () => {
  it('sends the strategy name as a q symbol', async () => {
    await call('kdb:strategyControl', 'simpleMM', 'pause')
    expect(h.queries[0].fn).toBe('.engine.strategy.pause')
    expect(h.queries[0].args!.map(typed)).toEqual([{ type: 'symbol', value: 'simpleMM' }])
  })
})

describe('handlers for q functions that do not exist', () => {
  it.each([
    ['kdb:getCandles', ['alpaca', 'BTC_USD', '1m']],
    ['kdb:getRiskMetrics', []]
  ])('%s reports not implemented without calling q', async (ch, args) => {
    const r = await call(ch, ...args)
    expect(r).toEqual({ success: false, error: 'not implemented' })
    expect(h.queries).toHaveLength(0)
  })
})

describe('kdb:connect', () => {
  it('rejects hosts outside the allowlist without creating clients', async () => {
    const before = h.clients.length
    const r = await call('kdb:connect', { ...cfg, tp: { host: 'evil.example.com', port: 5010 } })
    expect(r.success).toBe(false)
    expect(h.clients.length).toBe(before)
  })

  it('is idempotent for an unchanged config so a second window does not tear down the link', async () => {
    const before = h.clients.length
    const first = h.clients[h.clients.length - 2]
    const r = await call('kdb:connect', cfg)
    expect(r.success).toBe(true)
    expect(h.clients.length).toBe(before)
    expect(first.disconnects).toBe(0)
    expect(first.isConnected()).toBe(true)
  })

  it('reconnects when the config changes', async () => {
    const before = h.clients.length
    await call('kdb:connect', { ...cfg, rdb: { host: 'localhost', port: 6000 } })
    expect(h.clients.length).toBe(before + 2)
  })
})

describe('setupIpcHandlers', () => {
  it('can be called again (macOS activate) without throwing', () => {
    expect(() => setupIpcHandlers(win)).not.toThrow()
    expect(h.handlers.has('kdb:placeOrder')).toBe(true)
  })
})
