import { useOrdersStore } from '../stores/orders'
import { usePositionsStore } from '../stores/positions'
import { useTradesStore } from '../stores/trades'
import { useRiskStore } from '../stores/risk'
import { useExchangesStore } from '../stores/exchanges'
import { useStrategiesStore } from '../stores/strategies'

/** Route a kdb+ table update to its store. Reads stores via getState() so callers need no store subscriptions. */
export function routeUpdate(tableName: string, data: any): void {
  switch (tableName) {
    case 'order':
      if (Array.isArray(data)) {
        useOrdersStore.getState().setOrders(data)
      } else {
        useOrdersStore.getState().addOrder(data)
      }
      break
    case 'position':
      if (Array.isArray(data)) {
        usePositionsStore.getState().setPositions(data)
      }
      break
    case 'trade':
      if (Array.isArray(data)) {
        useTradesStore.getState().setTrades(data)
      } else {
        useTradesStore.getState().addTrade(data)
      }
      break
    case 'riskMetrics':
      useRiskStore.getState().setMetrics(data)
      break
    case 'exchangeStatus':
      if (Array.isArray(data)) {
        useExchangesStore.getState().setExchanges(data)
      }
      break
    case 'strategyStatus':
      if (Array.isArray(data)) {
        useStrategiesStore.getState().setStrategies(data)
      }
      break
  }
}
