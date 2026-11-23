// TCA (Transaction Cost Analysis) Mock Data

export interface TCAOrder {
  time: Date
  orderId: string
  symbol: string
  side: 'buy' | 'sell'
  quantity: number
  avgFill: number
  arrivalPrice: number
  slippageBps: number
  cost: number
  algo: string
  strategy: string
  exchange: string
  estimatedCost: number
  actualCost: number
}

export interface TCAMetrics {
  avgSlippageBps: number
  totalCost: number
  bestExecutionPct: number
  ordersAnalyzed: number
}

export interface SlippageByStrategy {
  strategy: string
  avgSlippageBps: number
  orderCount: number
}

export interface SlippageByExchange {
  exchange: string
  avgSlippageBps: number
  orderCount: number
}

export interface DailySlippage {
  date: string
  avgSlippageBps: number
}

// Memoized singleton to avoid regenerating on every render
let cachedTCAOrders: TCAOrder[] | null = null

export function generateTCAOrders(): TCAOrder[] {
  if (cachedTCAOrders) return cachedTCAOrders

  const strategies = ['simpleArb', 'simpleMM', 'momentum']
  const exchanges = ['Binance', 'Coinbase', 'Kraken']
  const symbols = ['BTCUSD', 'ETHUSD', 'SOLUSD']
  const algos = ['TWAP', 'VWAP', 'Iceberg', 'Market']

  const orders: TCAOrder[] = []
  const now = new Date()

  for (let i = 0; i < 30; i++) {
    const strategy = strategies[Math.floor(Math.random() * strategies.length)]
    const exchange = exchanges[Math.floor(Math.random() * exchanges.length)]
    const symbol = symbols[Math.floor(Math.random() * symbols.length)]
    const algo = algos[Math.floor(Math.random() * algos.length)]
    const side = Math.random() > 0.5 ? 'buy' : 'sell'

    const arrivalPrice = 30000 + Math.random() * 10000
    const quantity = Math.random() * 2

    // Slippage varies by strategy and exchange
    let baseSlippage = 0
    if (strategy === 'simpleArb') baseSlippage = 2
    else if (strategy === 'simpleMM') baseSlippage = 5
    else baseSlippage = 8

    if (exchange === 'Binance') baseSlippage += 1
    else if (exchange === 'Coinbase') baseSlippage += 3
    else baseSlippage += 5

    // Add some variance
    const slippageBps = baseSlippage + (Math.random() - 0.5) * 4

    // Calculate prices
    const slippageAmount = arrivalPrice * (slippageBps / 10000)
    const avgFill = side === 'buy'
      ? arrivalPrice + slippageAmount
      : arrivalPrice - slippageAmount

    const cost = Math.abs(slippageAmount) * quantity

    // Pre-trade estimate (usually underestimates)
    const estimatedCost = cost * (0.7 + Math.random() * 0.4)
    const actualCost = cost

    orders.push({
      time: new Date(now.getTime() - i * 3600000), // 1 hour apart
      orderId: `ORD-${10000 + i}`,
      symbol,
      side,
      quantity,
      avgFill,
      arrivalPrice,
      slippageBps,
      cost,
      algo,
      strategy,
      exchange,
      estimatedCost,
      actualCost
    })
  }

  cachedTCAOrders = orders.sort((a, b) => b.time.getTime() - a.time.getTime())
  return cachedTCAOrders
}

// Memoized singleton instance to avoid regenerating every render
let cachedTCAMetrics: TCAMetrics | null = null

export function generateTCAMetrics(): TCAMetrics {
  if (cachedTCAMetrics) return cachedTCAMetrics

  const orders = generateTCAOrders()
  const avgSlippageBps = orders.reduce((sum, o) => sum + o.slippageBps, 0) / orders.length
  const totalCost = orders.reduce((sum, o) => sum + o.cost, 0)
  const bestExecutionPct = (orders.filter(o => o.slippageBps < 5).length / orders.length) * 100

  cachedTCAMetrics = {
    avgSlippageBps,
    totalCost,
    bestExecutionPct,
    ordersAnalyzed: orders.length
  }

  return cachedTCAMetrics
}

let cachedSlippageByStrategy: SlippageByStrategy[] | null = null

export function generateSlippageByStrategy(): SlippageByStrategy[] {
  if (cachedSlippageByStrategy) return cachedSlippageByStrategy

  const orders = generateTCAOrders()
  const strategyMap = new Map<string, { total: number; count: number }>()

  orders.forEach(order => {
    const current = strategyMap.get(order.strategy) || { total: 0, count: 0 }
    strategyMap.set(order.strategy, {
      total: current.total + order.slippageBps,
      count: current.count + 1
    })
  })

  cachedSlippageByStrategy = Array.from(strategyMap.entries()).map(([strategy, data]) => ({
    strategy,
    avgSlippageBps: data.total / data.count,
    orderCount: data.count
  }))

  return cachedSlippageByStrategy
}

let cachedSlippageByExchange: SlippageByExchange[] | null = null

export function generateSlippageByExchange(): SlippageByExchange[] {
  if (cachedSlippageByExchange) return cachedSlippageByExchange

  const orders = generateTCAOrders()
  const exchangeMap = new Map<string, { total: number; count: number }>()

  orders.forEach(order => {
    const current = exchangeMap.get(order.exchange) || { total: 0, count: 0 }
    exchangeMap.set(order.exchange, {
      total: current.total + order.slippageBps,
      count: current.count + 1
    })
  })

  cachedSlippageByExchange = Array.from(exchangeMap.entries()).map(([exchange, data]) => ({
    exchange,
    avgSlippageBps: data.total / data.count,
    orderCount: data.count
  }))

  return cachedSlippageByExchange
}

let cachedDailySlippage: DailySlippage[] | null = null

export function generateDailySlippage(): DailySlippage[] {
  if (cachedDailySlippage) return cachedDailySlippage

  const days = 30
  const data: DailySlippage[] = []
  const now = new Date()

  for (let i = days - 1; i >= 0; i--) {
    const date = new Date(now.getTime() - i * 86400000)
    const avgSlippageBps = 3 + Math.random() * 6 + Math.sin(i / 7) * 2 // Adds weekly seasonality

    data.push({
      date: date.toISOString().split('T')[0],
      avgSlippageBps
    })
  }

  cachedDailySlippage = data
  return cachedDailySlippage
}
