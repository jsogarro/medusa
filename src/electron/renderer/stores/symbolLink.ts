import { create } from 'zustand'

export type LinkColor = 'red' | 'blue' | 'green' | 'yellow' | 'none'

export interface LinkGroup {
  color: LinkColor
  symbol: string
  exchange: string
}

interface SymbolLinkState {
  groups: Record<LinkColor, LinkGroup | undefined>
  setSymbol: (color: LinkColor, symbol: string, exchange: string) => void
  getSymbol: (color: LinkColor) => LinkGroup | undefined
}

const STORAGE_KEY = 'medusa-symbol-link-groups'
const WINDOW_BOUNDS_KEY = 'medusa-popout-window-bounds'

// Load saved link groups from localStorage
function loadSavedLinkGroups(): Record<LinkColor, LinkGroup | undefined> {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      return JSON.parse(saved)
    }
  } catch (err) {
    console.error('[SymbolLink] Failed to load saved link groups:', err)
  }
  return {
    red: undefined,
    blue: undefined,
    green: undefined,
    yellow: undefined,
    none: undefined
  }
}

// Save link groups to localStorage (async to avoid blocking)
function persistLinkGroups(groups: Record<LinkColor, LinkGroup | undefined>) {
  // Use requestIdleCallback to avoid blocking render
  if ('requestIdleCallback' in window) {
    requestIdleCallback(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(groups))
      } catch (err) {
        console.error('[SymbolLink] Failed to save link groups:', err)
      }
    })
  } else {
    // Fallback for browsers without requestIdleCallback
    setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(groups))
      } catch (err) {
        console.error('[SymbolLink] Failed to save link groups:', err)
      }
    }, 0)
  }
}

export const useSymbolLinkStore = create<SymbolLinkState>((set, get) => ({
  groups: loadSavedLinkGroups(),

  setSymbol: (color: LinkColor, symbol: string, exchange: string) => {
    if (color === 'none') return

    set((state) => {
      const newGroups = {
        ...state.groups,
        [color]: { color, symbol, exchange }
      }
      persistLinkGroups(newGroups)
      return { groups: newGroups }
    })

    // Broadcast to other windows via Electron IPC
    if (window.symbolLink?.broadcast) {
      window.symbolLink.broadcast(color, symbol, exchange)
    }
  },

  getSymbol: (color: LinkColor) => {
    return get().groups[color]
  }
}))

// Window bounds persistence
export function saveWindowBounds(widgetId: string, bounds: { x: number; y: number; width: number; height: number }) {
  try {
    const saved = localStorage.getItem(WINDOW_BOUNDS_KEY)
    const allBounds = saved ? JSON.parse(saved) : {}
    allBounds[widgetId] = bounds
    localStorage.setItem(WINDOW_BOUNDS_KEY, JSON.stringify(allBounds))
  } catch (err) {
    console.error('[SymbolLink] Failed to save window bounds:', err)
  }
}

export function loadWindowBounds(widgetId: string): { x: number; y: number; width: number; height: number } | undefined {
  try {
    const saved = localStorage.getItem(WINDOW_BOUNDS_KEY)
    if (saved) {
      const allBounds = JSON.parse(saved)
      return allBounds[widgetId]
    }
  } catch (err) {
    console.error('[SymbolLink] Failed to load window bounds:', err)
  }
  return undefined
}

// Setup cross-window symbol link listener (cleanup on module unload)
let symbolLinkCleanup: (() => void) | null = null
if (typeof window !== 'undefined' && window.symbolLink?.onChange) {
  symbolLinkCleanup = window.symbolLink.onChange((color: LinkColor, symbol: string, exchange: string) => {
    useSymbolLinkStore.setState((state) => {
      const newGroups = {
        ...state.groups,
        [color]: { color, symbol, exchange }
      }
      persistLinkGroups(newGroups)
      return { groups: newGroups }
    })
  })
}

// Setup window bounds listener with cleanup
let windowBoundsHandler: ((event: MessageEvent) => void) | null = null
if (typeof window !== 'undefined') {
  windowBoundsHandler = (event: MessageEvent) => {
    if (event.data.type === 'window:boundsChanged') {
      saveWindowBounds(event.data.widgetId, event.data.bounds)
    }
  }
  window.addEventListener('message', windowBoundsHandler)
}

// Export cleanup function for module hot reload / unmount
export function cleanupSymbolLinkListeners() {
  if (symbolLinkCleanup) {
    symbolLinkCleanup()
    symbolLinkCleanup = null
  }
  if (windowBoundsHandler && typeof window !== 'undefined') {
    window.removeEventListener('message', windowBoundsHandler)
    windowBoundsHandler = null
  }
}
