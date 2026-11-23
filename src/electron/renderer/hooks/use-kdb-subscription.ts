import { useEffect } from 'react'
import { useOrdersStore } from '../stores/orders'
import { usePositionsStore } from '../stores/positions'
import { useTradesStore } from '../stores/trades'
import { useRiskStore } from '../stores/risk'
import { useExchangesStore } from '../stores/exchanges'
import { useStrategiesStore } from '../stores/strategies'

// Check if kdb API is available (only in Electron, not in browser dev mode)
const isKdbAvailable = () => typeof window !== 'undefined' && window.kdb !== undefined

export function useKdbSubscription(table: string) {
  const ordersStore = useOrdersStore()
  const positionsStore = usePositionsStore()
  const tradesStore = useTradesStore()
  const riskStore = useRiskStore()
  const exchangesStore = useExchangesStore()
  const strategiesStore = useStrategiesStore()

  useEffect(() => {
    if (!isKdbAvailable()) {
      console.warn(`[KDB] window.kdb not available — skipping subscription to ${table}`)
      return
    }

    // Subscribe to kdb+ table updates
    window.kdb.subscribe(table).catch((err: unknown) => {
      console.warn(`[KDB] Failed to subscribe to ${table}:`, err)
    })

    // Register update handler
    const removeListener = window.kdb.onUpdate((tableName: string, data: any) => {
      if (tableName !== table) return

      // Route updates to appropriate store
      switch (tableName) {
        case 'order':
          if (Array.isArray(data)) {
            ordersStore.setOrders(data)
          } else {
            ordersStore.addOrder(data)
          }
          break
        case 'position':
          if (Array.isArray(data)) {
            positionsStore.setPositions(data)
          }
          break
        case 'trade':
          if (Array.isArray(data)) {
            tradesStore.setTrades(data)
          } else {
            tradesStore.addTrade(data)
          }
          break
        case 'riskMetrics':
          riskStore.setMetrics(data)
          break
        case 'exchangeStatus':
          if (Array.isArray(data)) {
            exchangesStore.setExchanges(data)
          }
          break
        case 'strategyStatus':
          if (Array.isArray(data)) {
            strategiesStore.setStrategies(data)
          }
          break
      }
    })

    return () => {
      removeListener()
    }
  }, [table, ordersStore, positionsStore, tradesStore, riskStore, exchangesStore, strategiesStore])
}
