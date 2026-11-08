import { describe, expect, it, vi } from 'vitest'
import {
  createSubmitGuard,
  DEFAULT_KDB_CONFIG,
  isPopOutSearch,
  loadKdbConfig,
  pauseAllStrategies,
  runEmergencyStop
} from './kdb-actions'

const controls = (over: Partial<Record<'emergencyStop' | 'strategyControl', any>> = {}) => ({
  emergencyStop: vi.fn().mockResolvedValue({ success: true }),
  strategyControl: vi.fn().mockResolvedValue({ success: true }),
  ...over
})

describe('runEmergencyStop', () => {
  it('reports success only when the main process says so', async () => {
    expect(await runEmergencyStop(controls())).toEqual({ ok: true, message: 'Emergency stop executed' })
  })

  it('reports failure when the call resolves with success:false', async () => {
    const r = await runEmergencyStop(controls({ emergencyStop: vi.fn().mockResolvedValue({ success: false, error: 'Not connected to RDB' }) }))
    expect(r.ok).toBe(false)
    expect(r.message).toContain('Not connected to RDB')
  })

  it('reports failure on rejection and on a missing bridge', async () => {
    expect((await runEmergencyStop(controls({ emergencyStop: vi.fn().mockRejectedValue(new Error('boom')) }))).ok).toBe(false)
    expect((await runEmergencyStop(undefined)).ok).toBe(false)
  })
})

describe('pauseAllStrategies', () => {
  it('succeeds when every strategy pauses', async () => {
    const kdb = controls()
    expect((await pauseAllStrategies(kdb, ['a', 'b'])).ok).toBe(true)
    expect(kdb.strategyControl).toHaveBeenCalledTimes(2)
  })

  it('names the strategies that failed, whether by success:false or rejection', async () => {
    const kdb = controls({
      strategyControl: vi.fn(async (n: string) => {
        if (n === 'b') return { success: false, error: 'x' }
        if (n === 'c') throw new Error('y')
        return { success: true }
      })
    })
    const r = await pauseAllStrategies(kdb, ['a', 'b', 'c'])
    expect(r.ok).toBe(false)
    expect(r.message).toContain('2 of 3')
    expect(r.message).toContain('b, c')
  })
})

describe('loadKdbConfig', () => {
  it('falls back to defaults for null, corrupt, and malformed values', () => {
    expect(loadKdbConfig(null)).toEqual(DEFAULT_KDB_CONFIG)
    expect(loadKdbConfig('{not json')).toEqual(DEFAULT_KDB_CONFIG)
    expect(loadKdbConfig('{"tp":{"host":"h"}}')).toEqual(DEFAULT_KDB_CONFIG)
    expect(loadKdbConfig('null')).toEqual(DEFAULT_KDB_CONFIG)
  })

  it('returns a valid saved config', () => {
    const cfg = { tp: { host: 'h', port: 1 }, rdb: { host: 'h', port: 2 } }
    expect(loadKdbConfig(JSON.stringify(cfg))).toEqual(cfg)
  })
})

describe('isPopOutSearch', () => {
  it('detects pop-out windows by their widgetType param', () => {
    expect(isPopOutSearch('?widget=w1&widgetType=chart&linked=red')).toBe(true)
    expect(isPopOutSearch('')).toBe(false)
  })
})

describe('createSubmitGuard', () => {
  it('drops a second submit while the first is in flight, then allows another', async () => {
    const guard = createSubmitGuard()
    let release!: () => void
    const fn = vi.fn(() => new Promise<string>((res) => (release = () => res('done'))))

    const first = guard(fn)
    const second = await guard(fn)
    expect(second).toBeUndefined()
    expect(fn).toHaveBeenCalledTimes(1)

    release()
    expect(await first).toBe('done')
    const third = guard(async () => 'again')
    expect(await third).toBe('again')
  })

  it('releases the guard when the submission throws', async () => {
    const guard = createSubmitGuard()
    await expect(guard(async () => { throw new Error('x') })).rejects.toThrow('x')
    expect(await guard(async () => 'ok')).toBe('ok')
  })
})
