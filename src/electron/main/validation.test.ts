import { describe, expect, it } from 'vitest'
import { parseRiskVerdict, validateKdbConfig, validateOrder, validateSymbol } from './validation'

const base = {
  exchange: 'alpaca',
  pair: 'BTC_USD',
  strategy: 'manual',
  side: 'buy',
  orderType: 'limit',
  price: 100.5,
  quantity: 2.25
}

describe('validateOrder', () => {
  it('converts price and quantity to 6-dp fixed point', () => {
    const o = validateOrder(base)
    expect(o.price).toBe(100_500_000)
    expect(o.quantity).toBe(2_250_000)
  })

  it('rounds binary-float noise instead of truncating', () => {
    expect(validateOrder({ ...base, price: 0.1 + 0.2 }).price).toBe(300_000)
    expect(validateOrder({ ...base, price: 1.005 }).price).toBe(1_005_000)
  })

  it('sends a null price for market orders regardless of the supplied price', () => {
    expect(validateOrder({ ...base, orderType: 'market', price: 0 }).price).toBeNull()
  })

  it('maps stop to the q order type stop_loss', () => {
    expect(validateOrder({ ...base, orderType: 'stop' }).orderType).toBe('stop_loss')
    expect(validateOrder({ ...base, orderType: 'stop_loss' }).orderType).toBe('stop_loss')
  })

  it('rejects a limit price of 0', () => {
    expect(() => validateOrder({ ...base, price: 0 })).toThrow(/price/)
  })

  it.each([['5'], [null], [undefined], [[5]], [true], [''], [NaN], [Infinity], [-1]])(
    'rejects non-number or invalid quantity %j',
    (q) => {
      expect(() => validateOrder({ ...base, quantity: q })).toThrow(/quantity/)
    }
  )

  it('rejects coerced string prices', () => {
    expect(() => validateOrder({ ...base, price: '100' })).toThrow(/price/)
  })

  it('rejects a quantity that rounds to zero at 6 dp', () => {
    expect(() => validateOrder({ ...base, quantity: 1e-9 })).toThrow(/quantity/)
  })

  it('rejects values that are not exactly representable at 6 dp instead of rounding them', () => {
    expect(() => validateOrder({ ...base, quantity: 0.0000015 })).toThrow(/quantity.*6 decimal/)
    expect(() => validateOrder({ ...base, price: 100.1234567 })).toThrow(/price.*6 decimal/)
    expect(validateOrder({ ...base, quantity: 0.000001 }).quantity).toBe(1)
    expect(validateOrder({ ...base, price: 123456789.123457 }).price).toBe(123456789123457)
  })

  it.each([87775427.6265391, 123456789.0000004, 10000000.0000005, 999999999.9999995])(
    'rejects a 7th decimal digit at any magnitude: %s',
    (v) => {
      expect(() => validateOrder({ ...base, quantity: v })).toThrow(/6 decimal/)
    }
  )

  it.each([0.1, 0.3, 1.1, 64999.99, 0.000001, 123456.789012, 999999999.999999, 2.675, 0.1 + 0.2])(
    'accepts the exact 6 dp value %s',
    (v) => {
      const q = validateOrder({ ...base, quantity: v }).quantity
      expect(q).toBe(Math.round(v * 1e6))
    }
  )

  it('rejects out-of-bounds values', () => {
    expect(() => validateOrder({ ...base, quantity: 1e12 })).toThrow(/quantity/)
    expect(() => validateOrder({ ...base, price: 1e12 })).toThrow(/price/)
  })

  it('accepts pairs containing a slash but not other symbols', () => {
    expect(validateOrder({ ...base, pair: 'BTC/USD' }).pair).toBe('BTC/USD')
    expect(() => validateOrder({ ...base, pair: 'BTC USD' })).toThrow(/pair/)
    expect(() => validateOrder({ ...base, pair: 'BTC`USD' })).toThrow(/pair/)
  })

  it('still rejects slashes in exchange and strategy', () => {
    expect(() => validateOrder({ ...base, exchange: 'a/b' })).toThrow(/exchange/)
    expect(() => validateOrder({ ...base, strategy: 'a/b' })).toThrow(/strategy/)
  })

  it('rejects bad side and order type', () => {
    expect(() => validateOrder({ ...base, side: 'hold' })).toThrow(/side/)
    expect(() => validateOrder({ ...base, orderType: 'iceberg' })).toThrow(/orderType/)
  })

  it('rejects non-objects', () => {
    expect(() => validateOrder(null)).toThrow()
    expect(() => validateOrder('x')).toThrow()
  })
})

describe('validateSymbol', () => {
  it('rejects non-strings and shell/q metacharacters', () => {
    expect(() => validateSymbol('a;b', 'x')).toThrow()
    expect(() => validateSymbol(5 as unknown as string, 'x')).toThrow()
  })
})

describe('parseRiskVerdict (fails closed)', () => {
  it('passes only on (1b; `)', () => {
    expect(parseRiskVerdict([true, null]).ok).toBe(true)
    expect(parseRiskVerdict([true, '']).ok).toBe(true)
  })

  it('rejects (0b;`reason;dict) even though the array is truthy', () => {
    const v = parseRiskVerdict([false, 'emergencyStop', {}])
    expect(v.ok).toBe(false)
    expect(v.reason).toBe('emergencyStop')
  })

  it.each([
    [undefined],
    [null],
    [true],
    [false],
    [1],
    ['ok'],
    [{}],
    [[]],
    [[1, '']],
    [['true', '']],
    [[null, '']]
  ])('rejects unexpected shape %j', (shape) => {
    expect(parseRiskVerdict(shape).ok).toBe(false)
  })
})

describe('validateKdbConfig', () => {
  const ok = { tp: { host: 'localhost', port: 5010 }, rdb: { host: '127.0.0.1', port: 5011 } }

  it('accepts loopback hosts', () => {
    expect(validateKdbConfig(ok)).toEqual(ok)
    expect(() => validateKdbConfig({ ...ok, tp: { host: '::1', port: 5010 } })).not.toThrow()
  })

  it('rejects non-allowlisted hosts', () => {
    expect(() => validateKdbConfig({ ...ok, tp: { host: 'evil.example.com', port: 5010 } })).toThrow(/host/)
    expect(() => validateKdbConfig({ ...ok, rdb: { host: '10.0.0.5', port: 5011 } })).toThrow(/host/)
  })

  it('honours an explicit allowlist', () => {
    const cfg = { ...ok, tp: { host: 'kdb.internal', port: 5010 } }
    expect(validateKdbConfig(cfg, ['kdb.internal', '127.0.0.1']).tp.host).toBe('kdb.internal')
  })

  it.each([[0], [-1], [65536], [5010.5], ['5010'], [NaN], [null]])('rejects port %j', (port) => {
    expect(() => validateKdbConfig({ ...ok, tp: { host: 'localhost', port } })).toThrow(/port/)
  })

  it('rejects malformed configs', () => {
    expect(() => validateKdbConfig(null)).toThrow()
    expect(() => validateKdbConfig({ tp: ok.tp })).toThrow()
  })
})
