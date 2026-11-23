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
