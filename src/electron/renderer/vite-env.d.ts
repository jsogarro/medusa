/// <reference types="vite/client" />

export interface KdbApi {
  connect: (config: { tp: { host: string; port: number }; rdb: { host: string; port: number } }) => Promise<{ success: boolean; error?: string }>
  subscribe: (table: string) => Promise<{ success: boolean; error?: string }>
  placeOrder: (order: any) => Promise<{ success: boolean; data?: any; error?: string }>
  cancelOrder: (orderId: string) => Promise<{ success: boolean; data?: any; error?: string }>
  getOrders: () => Promise<{ success: boolean; data?: any; error?: string }>
  getPositions: () => Promise<{ success: boolean; data?: any; error?: string }>
  getRiskMetrics: () => Promise<{ success: boolean; data?: any; error?: string }>
  emergencyStop: () => Promise<{ success: boolean; data?: any; error?: string }>
  strategyControl: (name: string, action: 'pause' | 'resume' | 'stop') => Promise<{ success: boolean; data?: any; error?: string }>
  getCandles: (exchange: string, pair: string, timeframe: string) => Promise<{ success: boolean; data?: any; error?: string }>
  onUpdate: (callback: (table: string, data: any) => void) => () => void
}

declare global {
  interface Window {
    kdb: KdbApi
  }
}
