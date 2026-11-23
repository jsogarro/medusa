import { useEffect, useRef } from 'react'
import { useOrdersStore } from '../stores/orders'
import { usePositionsStore } from '../stores/positions'
import { useTradesStore } from '../stores/trades'
import { useRiskStore } from '../stores/risk'
import { useExchangesStore } from '../stores/exchanges'
import { useStrategiesStore } from '../stores/strategies'
import {
  mockOrders,
  mockPositions,
  mockTrades,
  mockRiskMetrics,
  mockExchangeStatus,
  mockStrategies
} from './mock-data'

/**
 * Hook to populate stores with mock data when kdb+ is not available.
 * Also simulates real-time updates to make the UI feel alive.
 */
export function useMockData() {
  const setOrders = useOrdersStore((state) => state.setOrders)
  const addOrder = useOrdersStore((state) => state.addOrder)
  const updateOrder = useOrdersStore((state) => state.updateOrder)

  const setPositions = usePositionsStore((state) => state.setPositions)
  const updatePosition = usePositionsStore((state) => state.updatePosition)

  const setTrades = useTradesStore((state) => state.setTrades)
  const addTrade = useTradesStore((state) => state.addTrade)

  const setRiskMetrics = useRiskStore((state) => state.setMetrics)
  const updateRiskMetrics = useRiskStore((state) => state.updateMetrics)

  const setExchanges = useExchangesStore((state) => state.setExchanges)
  const updateExchange = useExchangesStore((state) => state.updateExchange)

  const setStrategies = useStrategiesStore((state) => state.setStrategies)

  const intervalsRef = useRef<NodeJS.Timeout[]>([])

  useEffect(() => {
    // Only activate mock data if kdb+ is not available
    if (window.kdb) {
      console.log('[useMockData] window.kdb available — skipping mock data')
      return
    }

    console.log('[useMockData] Populating stores with mock data')

    // Initial population
    setOrders(mockOrders)
    setPositions(mockPositions)
    setTrades(mockTrades)
    setRiskMetrics(mockRiskMetrics)
    setExchanges(mockExchangeStatus)
    setStrategies(mockStrategies)

    // Simulate real-time updates

    // 1. Add a new trade every 3-5 seconds
    const tradeInterval = setInterval(() => {
      const pairs = ['BTCUSD', 'ETHUSD', 'SOLUSD', 'ADAUSD']
      const exchanges = ['binance', 'coinbase', 'kraken']
      const sides: ('buy' | 'sell')[] = ['buy', 'sell']

      const pair = pairs[Math.floor(Math.random() * pairs.length)]
      const exchange = exchanges[Math.floor(Math.random() * exchanges.length)]
      const side = sides[Math.floor(Math.random() * sides.length)]

      // Realistic prices per pair
      const priceMap: Record<string, number> = {
        BTCUSD: 67000 + (Math.random() - 0.5) * 500,
        ETHUSD: 3200 + (Math.random() - 0.5) * 40,
        SOLUSD: 145 + (Math.random() - 0.5) * 5,
        ADAUSD: 0.45 + (Math.random() - 0.5) * 0.02
      }

      const price = priceMap[pair]
      const quantity = pair === 'ADAUSD' ? 500 + Math.random() * 500 : Math.random() * 2
      const fee = price * quantity * 0.001
      const realizedPnL = (Math.random() - 0.4) * 100 // Slight positive bias

      const newTrade = {
        tradeId: `TRD-${Date.now()}`,
        orderId: `ORD-${Date.now()}`,
        time: new Date(),
        exchange,
        pair,
        side,
        price,
        quantity,
        fee,
        realizedPnL
      }

      addTrade(newTrade)
    }, 3000 + Math.random() * 2000) // 3-5 seconds

    // 2. Update position unrealizedPnL every 2 seconds (random walk)
    const positionInterval = setInterval(() => {
      mockPositions.forEach((pos) => {
        const key = `${pos.exchange}-${pos.pair}`
        const pnlDelta = (Math.random() - 0.5) * 50 // ±$25 random walk
        updatePosition(key, {
          unrealizedPnL: pos.unrealizedPnL + pnlDelta
        })
      })
    }, 2000)

    // 3. Randomly change exchange latency every 3 seconds
    const exchangeInterval = setInterval(() => {
      mockExchangeStatus.forEach((ex) => {
        if (ex.connected) {
          const latencyDelta = Math.floor((Math.random() - 0.5) * 20)
          updateExchange(ex.exchange, {
            latency: Math.max(20, ex.latency + latencyDelta)
          })
        }
      })
    }, 3000)

    // 4. Update risk metrics drawdown every 5 seconds
    const riskInterval = setInterval(() => {
      const drawdownDelta = (Math.random() - 0.5) * 0.005 // ±0.25%
      updateRiskMetrics({
        drawdownCurrent: mockRiskMetrics.drawdownCurrent + drawdownDelta
      })
    }, 5000)

    // 5. Occasionally add a new order every 7-10 seconds
    const orderInterval = setInterval(() => {
      const pairs = ['BTCUSD', 'ETHUSD', 'SOLUSD', 'ADAUSD']
      const exchanges = ['binance', 'coinbase', 'kraken']
      const sides: ('buy' | 'sell')[] = ['buy', 'sell']
      const strategies = ['simpleArb', 'simpleMM', 'momentum', 'meanReversion']
      const statuses: ('open' | 'filled' | 'cancelled' | 'rejected')[] = ['open', 'filled', 'cancelled']

      const pair = pairs[Math.floor(Math.random() * pairs.length)]
      const exchange = exchanges[Math.floor(Math.random() * exchanges.length)]
      const side = sides[Math.floor(Math.random() * sides.length)]
      const strategy = strategies[Math.floor(Math.random() * strategies.length)]
      const status = statuses[Math.floor(Math.random() * statuses.length)]

      const priceMap: Record<string, number> = {
        BTCUSD: 67000 + (Math.random() - 0.5) * 500,
        ETHUSD: 3200 + (Math.random() - 0.5) * 40,
        SOLUSD: 145 + (Math.random() - 0.5) * 5,
        ADAUSD: 0.45 + (Math.random() - 0.5) * 0.02
      }

      const price = priceMap[pair]
      const quantity = pair === 'ADAUSD' ? 500 + Math.random() * 500 : Math.random() * 2
      const filled = status === 'filled' ? quantity : status === 'open' ? quantity * Math.random() * 0.5 : 0

      const newOrder = {
        orderId: `ORD-${Date.now()}`,
        time: new Date(),
        strategy,
        exchange,
        pair,
        side,
        orderType: 'limit' as const,
        price,
        quantity,
        filled,
        status
      }

      addOrder(newOrder)
    }, 7000 + Math.random() * 3000) // 7-10 seconds

    // Store intervals for cleanup
    intervalsRef.current = [tradeInterval, positionInterval, exchangeInterval, riskInterval, orderInterval]

    // Cleanup on unmount
    return () => {
      console.log('[useMockData] Cleaning up intervals')
      intervalsRef.current.forEach((interval) => clearInterval(interval))
    }
  }, [
    setOrders,
    addOrder,
    updateOrder,
    setPositions,
    updatePosition,
    setTrades,
    addTrade,
    setRiskMetrics,
    updateRiskMetrics,
    setExchanges,
    updateExchange,
    setStrategies
  ])
}
