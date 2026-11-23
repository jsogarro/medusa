import { beforeAll, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  handlers: new Map<string, (...args: any[]) => any>(),
  listeners: new Map<string, (...args: any[]) => any>(),
  appEvents: new Map<string, (...args: any[]) => any>(),
  windows: [] as any[],
  created: 0,
  permissionHandler: undefined as ((...args: any[]) => any) | undefined
}))

vi.mock('electron', () => {
  class FakeWindow {
    destroyed = false
    webContents = {
      setWindowOpenHandler: vi.fn(),
      on: vi.fn(),
      send: vi.fn(),
      openDevTools: vi.fn()
    }
    constructor() {
      h.created++
      h.windows.push(this)
    }
    static getAllWindows() {
      return h.windows
    }
    on = vi.fn()
    removeListener = vi.fn()
    loadFile = vi.fn()
    loadURL = vi.fn()
    getBounds = () => ({})
    isDestroyed() {
      return this.destroyed
    }
  }
  return {
    ipcMain: {
      handle: (ch: string, fn: (...a: any[]) => any) => h.handlers.set(ch, fn),
      removeHandler: (ch: string) => h.handlers.delete(ch),
      on: (ch: string, fn: (...a: any[]) => any) => h.listeners.set(ch, fn)
    },
    app: {
      isPackaged: true,
      whenReady: () => Promise.resolve(),
      on: (ev: string, fn: (...a: any[]) => any) => h.appEvents.set(ev, fn),
      quit: vi.fn()
    },
    BrowserWindow: FakeWindow,
    session: {
      defaultSession: {
        setPermissionRequestHandler: (fn: (...a: any[]) => any) => {
          h.permissionHandler = fn
        }
      }
    }
  }
})

const TRUSTED = { senderFrame: { url: 'file:///app/out/renderer/index.html' } }

beforeAll(async () => {
  await import('./index')
  await Promise.resolve() // let whenReady().then(createWindow) run
})

describe('window:popout', () => {
  it('limits how many pop-out windows can be created in a burst', async () => {
    const before = h.created
    for (let i = 0; i < 30; i++) {
      await Promise.resolve()
        .then(() => h.handlers.get('window:popout')!(TRUSTED, `w${i}`, {}))
        .catch(() => undefined)
    }
    const made = h.created - before
    expect(made).toBeGreaterThan(0)
    expect(made).toBeLessThan(30)
  })
})

describe('symbolLink:changed', () => {
  const changed = (...args: unknown[]) => h.listeners.get('symbolLink:changed')!({ ...TRUSTED }, ...args)
  const sends = (w: any) => w.webContents.send.mock.calls.filter((c: any[]) => c[0] === 'symbolLink:update')

  it('broadcasts a valid change to live windows and skips destroyed ones without throwing', () => {
    const live = new (h.windows[0].constructor as any)()
    const dead = new (h.windows[0].constructor as any)()
    dead.destroyed = true
    dead.webContents.send.mockImplementation(() => {
      throw new Error('Object has been destroyed')
    })
    expect(() => changed('red', 'BTC/USD', 'alpaca')).not.toThrow()
    expect(sends(live)).toEqual([['symbolLink:update', 'red', 'BTC/USD', 'alpaca']])
    expect(dead.webContents.send).not.toHaveBeenCalled()
  })

  it.each([
    ['purple', 'BTC/USD', 'alpaca'],
    ['red', 'BTC USD;', 'alpaca'],
    ['red', 'x'.repeat(100), 'alpaca'],
    ['red', 'BTC/USD', '<script>'],
    ['red', 42, 'alpaca'],
    [undefined, undefined, undefined]
  ])('drops an invalid payload %j', (...args) => {
    const w = new (h.windows[0].constructor as any)()
    changed(...args)
    expect(sends(w)).toEqual([])
  })
})
