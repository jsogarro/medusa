import { contextBridge, ipcRenderer } from 'electron'

// Type-safe API exposed to renderer — NO raw query passthrough
export interface KdbApi {
  connect: (config: { tp: { host: string; port: number }; rdb: { host: string; port: number } }) => Promise<{ success: boolean; error?: string }>
  subscribe: (table: string) => Promise<{ success: boolean; error?: string }>
  placeOrder: (order: any) => Promise<{ success: boolean; data?: any; error?: string; outcomeUnknown?: boolean }>
  cancelOrder: (orderId: string, exchange: string) => Promise<{ success: boolean; data?: any; error?: string }>
  getOrders: () => Promise<{ success: boolean; data?: any; error?: string }>
  getPositions: () => Promise<{ success: boolean; data?: any; error?: string }>
  getRiskMetrics: () => Promise<{ success: boolean; data?: any; error?: string }>
  emergencyStop: () => Promise<{ success: boolean; data?: any; error?: string }>
  strategyControl: (name: string, action: 'pause' | 'resume' | 'stop') => Promise<{ success: boolean; data?: any; error?: string }>
  getCandles: (exchange: string, pair: string, timeframe: string) => Promise<{ success: boolean; data?: any; error?: string }>
  onUpdate: (callback: (table: string, data: any) => void) => () => void
  healthCheck: () => Promise<{ success: boolean; data?: any; error?: string }>
}

export interface PopOutApi {
  popOutWidget: (widgetId: string, config: any) => Promise<void>
}

export interface SymbolLinkApi {
  onChange: (callback: (color: string, symbol: string, exchange: string) => void) => () => void
  broadcast: (color: string, symbol: string, exchange: string) => void
}

// Expose ONLY validated, named operations — never raw q expressions
contextBridge.exposeInMainWorld('kdb', {
  connect: (config) => ipcRenderer.invoke('kdb:connect', config),
  subscribe: (table) => ipcRenderer.invoke('kdb:subscribe', table),
  placeOrder: (order) => ipcRenderer.invoke('kdb:placeOrder', order),
  cancelOrder: (orderId, exchange) => ipcRenderer.invoke('kdb:cancelOrder', orderId, exchange),
  getOrders: () => ipcRenderer.invoke('kdb:getOrders'),
  getPositions: () => ipcRenderer.invoke('kdb:getPositions'),
  getRiskMetrics: () => ipcRenderer.invoke('kdb:getRiskMetrics'),
  emergencyStop: () => ipcRenderer.invoke('kdb:emergencyStop'),
  strategyControl: (name, action) => ipcRenderer.invoke('kdb:strategyControl', name, action),
  getCandles: (exchange, pair, timeframe) => ipcRenderer.invoke('kdb:getCandles', exchange, pair, timeframe),
  healthCheck: () => ipcRenderer.invoke('system:health'),
  onUpdate: (callback) => {
    const handler = (_event: any, update: { table: string; data: any }) => {
      callback(update.table, update.data)
    }
    ipcRenderer.on('kdb:update', handler)
    return () => {
      ipcRenderer.removeListener('kdb:update', handler)
    }
  }
} as KdbApi)

// Pop-out window API
contextBridge.exposeInMainWorld('popOutWidget', (widgetId: string, config: any) => {
  return ipcRenderer.invoke('window:popout', widgetId, config)
})

// Symbol link API for cross-window communication
contextBridge.exposeInMainWorld('symbolLink', {
  onChange: (callback: (color: string, symbol: string, exchange: string) => void) => {
    const handler = (_event: any, color: string, symbol: string, exchange: string) => {
      callback(color, symbol, exchange)
    }
    ipcRenderer.on('symbolLink:update', handler)
    return () => {
      ipcRenderer.removeListener('symbolLink:update', handler)
    }
  },
  broadcast: (color: string, symbol: string, exchange: string) => {
    ipcRenderer.send('symbolLink:changed', color, symbol, exchange)
  }
} as SymbolLinkApi)

