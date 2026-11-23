import { create } from 'zustand'
import { MosaicNode } from 'react-mosaic-component'
import { WorkspaceLayout, WidgetConfig } from '../lib/workspace-types'
import { PRESET_LAYOUTS } from '../lib/preset-layouts'

interface WorkspaceState {
  currentLayout: WorkspaceLayout
  savedLayouts: Record<string, WorkspaceLayout>

  // Actions
  setMosaicTree: (tree: MosaicNode<string> | null) => void
  addWidget: (widgetId: string, config: WidgetConfig) => void
  removeWidget: (widgetId: string) => void
  updateWidget: (widgetId: string, config: Partial<WidgetConfig>) => void

  loadLayout: (name: string) => void
  saveLayout: (name: string) => void
  deleteLayout: (name: string) => void

  exportLayout: () => string
  importLayout: (json: string) => void
  persistCurrentLayout: () => void
}

const STORAGE_KEY = 'medusa-workspace-layouts'
const LAST_LAYOUT_KEY = 'medusa-last-layout'
const AUTOSAVE_LAYOUT_KEY = 'medusa-autosave-layout'

// Debounce auto-save to avoid thrashing
let autoSaveTimeout: NodeJS.Timeout | null = null
const AUTO_SAVE_DELAY_MS = 500

// Load saved layouts from localStorage
function loadSavedLayouts(): Record<string, WorkspaceLayout> {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      return JSON.parse(saved)
    }
  } catch (err) {
    console.error('[Workspace] Failed to load saved layouts:', err)
  }
  return {}
}

// Save layouts to localStorage (async to avoid blocking)
function persistLayouts(layouts: Record<string, WorkspaceLayout>) {
  // Use requestIdleCallback to avoid blocking render
  if ('requestIdleCallback' in window) {
    requestIdleCallback(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(layouts))
      } catch (err) {
        console.error('[Workspace] Failed to save layouts:', err)
      }
    })
  } else {
    // Fallback for browsers without requestIdleCallback
    setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(layouts))
      } catch (err) {
        console.error('[Workspace] Failed to save layouts:', err)
      }
    }, 0)
  }
}

// Auto-save current layout (debounced + async)
function autoSaveCurrentLayout(layout: WorkspaceLayout) {
  if (autoSaveTimeout) {
    clearTimeout(autoSaveTimeout)
  }

  autoSaveTimeout = setTimeout(() => {
    // Use requestIdleCallback to avoid blocking render during high-frequency updates
    if ('requestIdleCallback' in window) {
      requestIdleCallback(() => {
        try {
          localStorage.setItem(AUTOSAVE_LAYOUT_KEY, JSON.stringify(layout))
          console.log('[Workspace] Auto-saved layout')
        } catch (err) {
          console.error('[Workspace] Failed to auto-save layout:', err)
        }
      })
    } else {
      // Fallback
      setTimeout(() => {
        try {
          localStorage.setItem(AUTOSAVE_LAYOUT_KEY, JSON.stringify(layout))
          console.log('[Workspace] Auto-saved layout')
        } catch (err) {
          console.error('[Workspace] Failed to auto-save layout:', err)
        }
      }, 0)
    }
  }, AUTO_SAVE_DELAY_MS)
}

// Load last active layout on app start
function loadLastActiveLayout(): WorkspaceLayout {
  try {
    const lastLayoutName = localStorage.getItem(LAST_LAYOUT_KEY)
    if (lastLayoutName) {
      const savedLayouts = loadSavedLayouts()
      const layout = savedLayouts[lastLayoutName] || PRESET_LAYOUTS[lastLayoutName]
      if (layout) {
        console.log('[Workspace] Restored last layout:', lastLayoutName)
        return layout
      }
    }

    // Check for auto-saved layout
    const autoSaved = localStorage.getItem(AUTOSAVE_LAYOUT_KEY)
    if (autoSaved) {
      console.log('[Workspace] Restored auto-saved layout')
      return JSON.parse(autoSaved)
    }
  } catch (err) {
    console.error('[Workspace] Failed to load last layout:', err)
  }

  // Default to Trading preset
  console.log('[Workspace] Using default Trading layout')
  return PRESET_LAYOUTS.trading
}

export const useWorkspaceStore = create<WorkspaceState>((set, get) => ({
  currentLayout: loadLastActiveLayout(),
  savedLayouts: loadSavedLayouts(),

  setMosaicTree: (tree) => {
    set((state) => {
      const newLayout = {
        ...state.currentLayout,
        mosaicTree: tree
      }
      autoSaveCurrentLayout(newLayout)
      return { currentLayout: newLayout }
    })
  },

  addWidget: (widgetId, config) => {
    set((state) => {
      const newLayout = {
        ...state.currentLayout,
        widgets: {
          ...state.currentLayout.widgets,
          [widgetId]: config
        }
      }
      autoSaveCurrentLayout(newLayout)
      return { currentLayout: newLayout }
    })
  },

  removeWidget: (widgetId) => {
    set((state) => {
      const { [widgetId]: removed, ...rest } = state.currentLayout.widgets
      const newLayout = {
        ...state.currentLayout,
        widgets: rest
      }
      autoSaveCurrentLayout(newLayout)
      return { currentLayout: newLayout }
    })
  },

  updateWidget: (widgetId, config) => {
    set((state) => {
      const newLayout = {
        ...state.currentLayout,
        widgets: {
          ...state.currentLayout.widgets,
          [widgetId]: {
            ...state.currentLayout.widgets[widgetId],
            ...config
          }
        }
      }
      autoSaveCurrentLayout(newLayout)
      return { currentLayout: newLayout }
    })
  },

  loadLayout: (name) => {
    const preset = PRESET_LAYOUTS[name]
    const saved = get().savedLayouts[name]
    const layout = saved || preset

    if (layout) {
      set({ currentLayout: layout })
      // Remember last active layout
      try {
        localStorage.setItem(LAST_LAYOUT_KEY, name)
      } catch (err) {
        console.error('[Workspace] Failed to save last layout name:', err)
      }
    } else {
      console.warn(`[Workspace] Layout "${name}" not found`)
    }
  },

  saveLayout: (name) => {
    const currentLayout = get().currentLayout
    const layoutToSave = {
      ...currentLayout,
      name
    }

    set((state) => {
      const newLayouts = {
        ...state.savedLayouts,
        [name]: layoutToSave
      }
      persistLayouts(newLayouts)
      return { savedLayouts: newLayouts }
    })
  },

  deleteLayout: (name) => {
    set((state) => {
      const { [name]: deleted, ...rest } = state.savedLayouts
      persistLayouts(rest)
      return { savedLayouts: rest }
    })
  },

  exportLayout: () => {
    return JSON.stringify(get().currentLayout, null, 2)
  },

  importLayout: (json) => {
    try {
      const layout = JSON.parse(json) as WorkspaceLayout
      set({ currentLayout: layout })
      autoSaveCurrentLayout(layout)
    } catch (err) {
      console.error('[Workspace] Failed to import layout:', err)
      throw new Error('Invalid layout JSON')
    }
  },

  persistCurrentLayout: () => {
    const layout = get().currentLayout
    try {
      localStorage.setItem(AUTOSAVE_LAYOUT_KEY, JSON.stringify(layout))
      if (layout.name) {
        localStorage.setItem(LAST_LAYOUT_KEY, layout.name)
      }
    } catch (err) {
      console.error('[Workspace] Failed to persist current layout:', err)
    }
  }
}))
