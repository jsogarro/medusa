import type {
  Order,
  Position,
  Trade,
  RiskMetrics,
  ExchangeStatus,
  Strategy,
  Candlestick,
  VolumeSpike,
  VwapData,
  VolumeLevelData,
  CvdData,
  OrderFlowData,
  Settings,
  AlgoOrder
} from './types'

// Generate realistic mock orders (15-20 orders)
export const mockOrders: Order[] = [
  {
    orderId: 'ORD-001',
    time: new Date('2026-04-25T14:30:00'),
    strategy: 'simpleArb',
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'buy',
    orderType: 'limit',
    price: 67234.50,
    quantity: 0.5,
    filled: 0.5,
    status: 'filled'
  },
  {
    orderId: 'ORD-002',
    time: new Date('2026-04-25T14:31:15'),
    strategy: 'simpleMM',
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'sell',
    orderType: 'limit',
    price: 3215.80,
    quantity: 5.0,
    filled: 3.2,
    status: 'open'
  },
  {
    orderId: 'ORD-003',
    time: new Date('2026-04-25T14:28:45'),
    strategy: 'simpleArb',
    exchange: 'kraken',
    pair: 'BTCUSD',
    side: 'sell',
    orderType: 'limit',
    price: 67250.00,
    quantity: 0.75,
    filled: 0.75,
    status: 'filled'
  },
  {
    orderId: 'ORD-004',
    time: new Date('2026-04-25T14:32:00'),
    strategy: 'momentum',
    exchange: 'binance',
    pair: 'SOLUSD',
    side: 'buy',
    orderType: 'market',
    price: 145.30,
    quantity: 20,
    filled: 20,
    status: 'filled'
  },
  {
    orderId: 'ORD-005',
    time: new Date('2026-04-25T14:29:30'),
    strategy: 'meanReversion',
    exchange: 'coinbase',
    pair: 'ADAUSD',
    side: 'buy',
    orderType: 'limit',
    price: 0.45,
    quantity: 1000,
    filled: 0,
    status: 'cancelled'
  },
  {
    orderId: 'ORD-006',
    time: new Date('2026-04-25T14:33:10'),
    strategy: 'simpleMM',
    exchange: 'binance',
    pair: 'ETHUSD',
    side: 'buy',
    orderType: 'limit',
    price: 3210.00,
    quantity: 3.0,
    filled: 1.5,
    status: 'open'
  },
  {
    orderId: 'ORD-007',
    time: new Date('2026-04-25T14:27:20'),
    strategy: 'simpleArb',
    exchange: 'kraken',
    pair: 'ETHUSD',
    side: 'sell',
    orderType: 'limit',
    price: 3218.50,
    quantity: 2.0,
    filled: 2.0,
    status: 'filled'
  },
  {
    orderId: 'ORD-008',
    time: new Date('2026-04-25T14:34:00'),
    strategy: 'momentum',
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'buy',
    orderType: 'stop',
    price: 67300.00,
    quantity: 0.25,
    filled: 0,
    status: 'open'
  },
  {
    orderId: 'ORD-009',
    time: new Date('2026-04-25T14:26:15'),
    strategy: 'simpleMM',
    exchange: 'coinbase',
    pair: 'SOLUSD',
    side: 'sell',
    orderType: 'limit',
    price: 146.00,
    quantity: 15,
    filled: 15,
    status: 'filled'
  },
  {
    orderId: 'ORD-010',
    time: new Date('2026-04-25T14:35:30'),
    strategy: 'simpleArb',
    exchange: 'binance',
    pair: 'ADAUSD',
    side: 'buy',
    orderType: 'limit',
    price: 0.452,
    quantity: 500,
    filled: 0,
    status: 'rejected'
  },
  {
    orderId: 'ORD-011',
    time: new Date('2026-04-25T14:25:00'),
    strategy: 'meanReversion',
    exchange: 'kraken',
    pair: 'BTCUSD',
    side: 'sell',
    orderType: 'limit',
    price: 67280.00,
    quantity: 0.5,
    filled: 0.5,
    status: 'filled'
  },
  {
    orderId: 'ORD-012',
    time: new Date('2026-04-25T14:36:00'),
    strategy: 'simpleMM',
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'sell',
    orderType: 'limit',
    price: 67450.00,
    quantity: 0.3,
    filled: 0,
    status: 'open'
  },
  {
    orderId: 'ORD-013',
    time: new Date('2026-04-25T14:24:30'),
    strategy: 'simpleArb',
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'buy',
    orderType: 'limit',
    price: 3205.00,
    quantity: 4.0,
    filled: 4.0,
    status: 'filled'
  },
  {
    orderId: 'ORD-014',
    time: new Date('2026-04-25T14:37:15'),
    strategy: 'momentum',
    exchange: 'binance',
    pair: 'SOLUSD',
    side: 'sell',
    orderType: 'limit',
    price: 145.80,
    quantity: 10,
    filled: 5,
    status: 'open'
  },
  {
    orderId: 'ORD-015',
    time: new Date('2026-04-25T14:23:00'),
    strategy: 'simpleMM',
    exchange: 'kraken',
    pair: 'ADAUSD',
    side: 'buy',
    orderType: 'limit',
    price: 0.448,
    quantity: 800,
    filled: 800,
    status: 'filled'
  },
  {
    orderId: 'ORD-016',
    time: new Date('2026-04-25T14:38:00'),
    strategy: 'simpleArb',
    exchange: 'binance',
    pair: 'ETHUSD',
    side: 'sell',
    orderType: 'limit',
    price: 3220.00,
    quantity: 2.5,
    filled: 0,
    status: 'open'
  },
  {
    orderId: 'ORD-017',
    time: new Date('2026-04-25T14:22:30'),
    strategy: 'meanReversion',
    exchange: 'coinbase',
    pair: 'BTCUSD',
    side: 'buy',
    orderType: 'market',
    price: 67150.00,
    quantity: 0.4,
    filled: 0.4,
    status: 'filled'
  },
  {
    orderId: 'ORD-018',
    time: new Date('2026-04-25T14:39:00'),
    strategy: 'momentum',
    exchange: 'binance',
    pair: 'ADAUSD',
    side: 'sell',
    orderType: 'limit',
    price: 0.455,
    quantity: 600,
    filled: 0,
    status: 'cancelled'
  }
]

// Generate realistic mock positions (5-6 open positions)
export const mockPositions: Position[] = [
  {
    exchange: 'binance',
    pair: 'BTCUSD',
    quantity: 1.25,
    avgPrice: 66890.00,
    unrealizedPnL: 431.25,
    exposure: 83612.50
  },
  {
    exchange: 'coinbase',
    pair: 'ETHUSD',
    quantity: -10.0,
    avgPrice: 3180.50,
    unrealizedPnL: -352.00,
    exposure: 31805.00
  },
  {
    exchange: 'binance',
    pair: 'SOLUSD',
    quantity: 25.0,
    avgPrice: 144.80,
    unrealizedPnL: 12.50,
    exposure: 3620.00
  },
  {
    exchange: 'kraken',
    pair: 'BTCUSD',
    quantity: -0.5,
    avgPrice: 67100.00,
    unrealizedPnL: 67.50,
    exposure: 33550.00
  },
  {
    exchange: 'coinbase',
    pair: 'ADAUSD',
    quantity: 1500.0,
    avgPrice: 0.447,
    unrealizedPnL: 4.50,
    exposure: 670.50
  },
  {
    exchange: 'kraken',
    pair: 'ETHUSD',
    quantity: 3.0,
    avgPrice: 3200.00,
    unrealizedPnL: -15.00,
    exposure: 9600.00
  }
]

// Generate realistic mock trades (30-40 recent trades)
export const mockTrades: Trade[] = [
  {
    tradeId: 'TRD-001',
    orderId: 'ORD-001',
    time: new Date('2026-04-25T14:30:05'),
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'buy',
    price: 67234.50,
    quantity: 0.5,
    fee: 33.62,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-002',
    orderId: 'ORD-003',
    time: new Date('2026-04-25T14:28:50'),
    exchange: 'kraken',
    pair: 'BTCUSD',
    side: 'sell',
    price: 67250.00,
    quantity: 0.75,
    fee: 50.44,
    realizedPnL: 120.00
  },
  {
    tradeId: 'TRD-003',
    orderId: 'ORD-004',
    time: new Date('2026-04-25T14:32:03'),
    exchange: 'binance',
    pair: 'SOLUSD',
    side: 'buy',
    price: 145.30,
    quantity: 20,
    fee: 29.06,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-004',
    orderId: 'ORD-007',
    time: new Date('2026-04-25T14:27:25'),
    exchange: 'kraken',
    pair: 'ETHUSD',
    side: 'sell',
    price: 3218.50,
    quantity: 2.0,
    fee: 64.37,
    realizedPnL: 76.00
  },
  {
    tradeId: 'TRD-005',
    orderId: 'ORD-009',
    time: new Date('2026-04-25T14:26:20'),
    exchange: 'coinbase',
    pair: 'SOLUSD',
    side: 'sell',
    price: 146.00,
    quantity: 15,
    fee: 21.90,
    realizedPnL: 18.00
  },
  {
    tradeId: 'TRD-006',
    orderId: 'ORD-011',
    time: new Date('2026-04-25T14:25:05'),
    exchange: 'kraken',
    pair: 'BTCUSD',
    side: 'sell',
    price: 67280.00,
    quantity: 0.5,
    fee: 33.64,
    realizedPnL: 195.00
  },
  {
    tradeId: 'TRD-007',
    orderId: 'ORD-013',
    time: new Date('2026-04-25T14:24:35'),
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'buy',
    price: 3205.00,
    quantity: 4.0,
    fee: 128.20,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-008',
    orderId: 'ORD-015',
    time: new Date('2026-04-25T14:23:05'),
    exchange: 'kraken',
    pair: 'ADAUSD',
    side: 'buy',
    price: 0.448,
    quantity: 800,
    fee: 3.58,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-009',
    orderId: 'ORD-017',
    time: new Date('2026-04-25T14:22:32'),
    exchange: 'coinbase',
    pair: 'BTCUSD',
    side: 'buy',
    price: 67150.00,
    quantity: 0.4,
    fee: 26.86,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-010',
    orderId: 'ORD-002',
    time: new Date('2026-04-25T14:31:18'),
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'sell',
    price: 3215.80,
    quantity: 1.0,
    fee: 32.16,
    realizedPnL: 10.80
  },
  {
    tradeId: 'TRD-011',
    orderId: 'ORD-002',
    time: new Date('2026-04-25T14:31:45'),
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'sell',
    price: 3215.80,
    quantity: 2.2,
    fee: 70.75,
    realizedPnL: 23.76
  },
  {
    tradeId: 'TRD-012',
    orderId: 'ORD-006',
    time: new Date('2026-04-25T14:33:15'),
    exchange: 'binance',
    pair: 'ETHUSD',
    side: 'buy',
    price: 3210.00,
    quantity: 1.5,
    fee: 48.15,
    realizedPnL: 0
  },
  {
    tradeId: 'TRD-013',
    orderId: 'ORD-014',
    time: new Date('2026-04-25T14:37:20'),
    exchange: 'binance',
    pair: 'SOLUSD',
    side: 'sell',
    price: 145.80,
    quantity: 5,
    fee: 7.29,
    realizedPnL: 2.50
  }
]

// Mock risk metrics
export const mockRiskMetrics: RiskMetrics = {
  positionLimitUtilization: {
    simpleArb: 0.65,
    simpleMM: 0.42,
    momentum: 0.28,
    meanReversion: 0.15
  },
  exposureUtilization: {
    binance: 0.55,
    coinbase: 0.38,
    kraken: 0.12
  },
  drawdownCurrent: -0.032,
  drawdownMax: 0.15,
  dailyVolumeUsed: 234500,
  dailyVolumeLimit: 1000000
}

// Mock exchange status (3 exchanges)
// NOTE: Binance connector now exists (REST + WebSocket + GDS subscriber built),
// but is not connected until BINANCE_API_KEY and BINANCE_SECRET_KEY are set.
export const mockExchangeStatus: ExchangeStatus[] = [
  {
    exchange: 'Binance',
    connected: false,
    latency: 0,
    errorCount: 0,
    rateLimitUsed: 0,
    rateLimitMax: 1200
  },
  {
    exchange: 'Coinbase',
    connected: true,
    latency: 98,
    errorCount: 2,
    rateLimitUsed: 45,
    rateLimitMax: 600
  },
  {
    exchange: 'Kraken',
    connected: false,
    latency: 0,
    errorCount: 15,
    rateLimitUsed: 0,
    rateLimitMax: 450
  }
]

// Mock strategies (4 strategies)
export const mockStrategies: Strategy[] = [
  {
    name: 'simpleArb',
    status: 'running',
    trades: 142,
    winRate: 0.68,
    sharpe: 2.14,
    pnl: 12450.00
  },
  {
    name: 'simpleMM',
    status: 'running',
    trades: 89,
    winRate: 0.55,
    sharpe: 1.32,
    pnl: 5230.00
  },
  {
    name: 'momentum',
    status: 'paused',
    trades: 34,
    winRate: 0.41,
    sharpe: 0.87,
    pnl: -1240.00
  },
  {
    name: 'meanReversion',
    status: 'stopped',
    trades: 12,
    winRate: 0.33,
    sharpe: -0.45,
    pnl: -3100.00
  }
]

// Generate realistic candlestick data using Geometric Brownian Motion
// This creates 200 1-minute candles with realistic BTC price action
export function generateMockCandles(
  startPrice: number = 66500,
  numBars: number = 200,
  drift: number = 0.0001,
  volatility: number = 0.003
): Candlestick[] {
  const candles: Candlestick[] = []
  const now = Date.now()
  const oneMinute = 60 * 1000

  let currentPrice = startPrice

  for (let i = 0; i < numBars; i++) {
    // Geometric Brownian Motion: price[i] = price[i-1] * exp((mu - sigma^2/2)*dt + sigma*sqrt(dt)*Z)
    const dt = 1 / (60 * 24 * 365) // 1 minute in years
    const randomShock = (Math.random() - 0.5) * 2 // Z ~ N(0,1) approximation
    const priceChange = Math.exp((drift - volatility ** 2 / 2) * dt + volatility * Math.sqrt(dt) * randomShock)

    currentPrice = currentPrice * priceChange

    // Generate OHLC from current price with micro-variations
    const microVol = volatility * 0.5
    const open = currentPrice * (1 + (Math.random() - 0.5) * microVol)
    const close = currentPrice * (1 + (Math.random() - 0.5) * microVol)
    const high = Math.max(open, close) * (1 + Math.random() * microVol)
    const low = Math.min(open, close) * (1 - Math.random() * microVol)

    // Random volume between 50-500
    const volume = 50 + Math.random() * 450

    candles.push({
      time: Math.floor((now - (numBars - i) * oneMinute) / 1000), // Unix timestamp in seconds
      open,
      high,
      low,
      close,
      volume
    })
  }

  return candles
}

// Generate realistic equity curve data (200 points)
// Starting at $100,000, random walk up to ~$115,000
export function generateMockEquityCurve(
  startEquity: number = 100000,
  numPoints: number = 200,
  drift: number = 0.00025,
  volatility: number = 0.002
): Array<{ time: number; equity: number }> {
  const curve: Array<{ time: number; equity: number }> = []
  let currentEquity = startEquity

  for (let i = 0; i < numPoints; i++) {
    const dt = 1 / (60 * 24 * 365) // 1 minute in years
    const randomShock = (Math.random() - 0.5) * 2
    const equityChange = Math.exp((drift - volatility ** 2 / 2) * dt + volatility * Math.sqrt(dt) * randomShock)

    currentEquity = currentEquity * equityChange

    curve.push({
      time: i,
      equity: currentEquity
    })
  }

  return curve
}

// Generate volume profile data (50 price levels around current BTC price)
export function generateMockVolumeProfile(
  centerPrice: number = 67000,
  numLevels: number = 50,
  range: number = 1000
): VolumeLevelData[] {
  const levels: VolumeLevelData[] = []
  const minPrice = centerPrice - range / 2
  const priceStep = range / numLevels

  for (let i = 0; i < numLevels; i++) {
    const price = minPrice + i * priceStep
    // Create a normal-ish distribution centered around centerPrice
    const distanceFromCenter = Math.abs(price - centerPrice)
    const volume = Math.exp(-Math.pow(distanceFromCenter / (range / 4), 2)) * 10000 + Math.random() * 2000
    levels.push({ price, volume })
  }

  return levels.sort((a, b) => a.price - b.price)
}

// Generate VWAP data (200 intraday points)
export function generateMockVwapData(numPoints: number = 200): VwapData[] {
  const data: VwapData[] = []
  const now = Date.now()
  const oneMinute = 60 * 1000
  let price = 67000
  let cumulativeVolumePrice = 0
  let cumulativeVolume = 0

  for (let i = 0; i < numPoints; i++) {
    // Random walk price
    price = price + (Math.random() - 0.5) * 50
    const volume = 50 + Math.random() * 200

    cumulativeVolumePrice += price * volume
    cumulativeVolume += volume
    const vwap = cumulativeVolumePrice / cumulativeVolume

    // Standard deviation for bands (simplified)
    const stdDev = price * 0.002
    const upperBand = vwap + stdDev
    const lowerBand = vwap - stdDev

    data.push({
      time: Math.floor((now - (numPoints - i) * oneMinute) / 1000),
      price,
      vwap,
      upperBand,
      lowerBand,
      volume
    })
  }

  return data
}

// Generate volume spike events (15 events)
export const mockVolumeSpikes: VolumeSpike[] = [
  {
    time: new Date('2026-04-25T14:35:00'),
    symbol: 'BTCUSD',
    volume: 1250,
    avgVolume: 180,
    spikeRatio: 6.94,
    price: 67234.50,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T14:28:00'),
    symbol: 'ETHUSD',
    volume: 4500,
    avgVolume: 850,
    spikeRatio: 5.29,
    price: 3215.80,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T14:15:00'),
    symbol: 'SOLUSD',
    volume: 8200,
    avgVolume: 2100,
    spikeRatio: 3.90,
    price: 145.30,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T14:02:00'),
    symbol: 'BTCUSD',
    volume: 980,
    avgVolume: 180,
    spikeRatio: 5.44,
    price: 67100.00,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T13:45:00'),
    symbol: 'ADAUSD',
    volume: 45000,
    avgVolume: 12000,
    spikeRatio: 3.75,
    price: 0.452,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T13:30:00'),
    symbol: 'ETHUSD',
    volume: 3200,
    avgVolume: 850,
    spikeRatio: 3.76,
    price: 3205.00,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T13:18:00'),
    symbol: 'SOLUSD',
    volume: 6800,
    avgVolume: 2100,
    spikeRatio: 3.24,
    price: 146.00,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T13:05:00'),
    symbol: 'BTCUSD',
    volume: 1100,
    avgVolume: 180,
    spikeRatio: 6.11,
    price: 67280.00,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T12:50:00'),
    symbol: 'ADAUSD',
    volume: 38000,
    avgVolume: 12000,
    spikeRatio: 3.17,
    price: 0.448,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T12:35:00'),
    symbol: 'ETHUSD',
    volume: 2900,
    avgVolume: 850,
    spikeRatio: 3.41,
    price: 3218.50,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T12:20:00'),
    symbol: 'BTCUSD',
    volume: 890,
    avgVolume: 180,
    spikeRatio: 4.94,
    price: 67150.00,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T12:05:00'),
    symbol: 'SOLUSD',
    volume: 7200,
    avgVolume: 2100,
    spikeRatio: 3.43,
    price: 145.80,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T11:50:00'),
    symbol: 'ETHUSD',
    volume: 3800,
    avgVolume: 850,
    spikeRatio: 4.47,
    price: 3210.00,
    direction: 'buy'
  },
  {
    time: new Date('2026-04-25T11:35:00'),
    symbol: 'ADAUSD',
    volume: 42000,
    avgVolume: 12000,
    spikeRatio: 3.50,
    price: 0.455,
    direction: 'sell'
  },
  {
    time: new Date('2026-04-25T11:20:00'),
    symbol: 'BTCUSD',
    volume: 1350,
    avgVolume: 180,
    spikeRatio: 7.50,
    price: 67300.00,
    direction: 'buy'
  }
]

// Generate CVD data (200 points)
export function generateMockCvdData(numPoints: number = 200): CvdData[] {
  const data: CvdData[] = []
  const now = Date.now()
  const oneMinute = 60 * 1000
  let cvd = 0
  let price = 67000

  for (let i = 0; i < numPoints; i++) {
    // Random walk for price
    price = price + (Math.random() - 0.5) * 50

    // Random buy/sell volume delta
    const buyVolume = 50 + Math.random() * 150
    const sellVolume = 50 + Math.random() * 150
    const delta = buyVolume - sellVolume
    cvd += delta

    data.push({
      time: Math.floor((now - (numPoints - i) * oneMinute) / 1000),
      cvd,
      price
    })
  }

  return data
}

// Mock order flow imbalance data
export const mockOrderFlowData: OrderFlowData = {
  buyPressure: 62,
  sellPressure: 38,
  imbalance: 0.24, // (62 - 38) / 100
  history: Array.from({ length: 50 }, (_, i) => ({
    time: Date.now() - (50 - i) * 60000,
    imbalance: (Math.random() - 0.5) * 0.5 // Random between -0.25 and 0.25
  }))
}

// Mock settings
// NOTE: Binance connector now exists (REST + WebSocket + GDS subscriber built),
// but requires BINANCE_API_KEY and BINANCE_SECRET_KEY to be set.
export const mockSettings: Settings = {
  connections: {
    tp: { host: 'localhost', port: 5010, connected: true },
    rdb: { host: 'localhost', port: 5011, connected: true },
    hdb: { host: 'localhost', port: 5012, connected: false }
  },
  exchanges: [
    {
      name: 'Binance',
      enabled: false,
      apiKey: '',
      rateLimit: 1200,
      status: 'disconnected'
    },
    {
      name: 'Coinbase',
      enabled: true,
      apiKey: 'cb_***************************xyz',
      rateLimit: 600,
      status: 'connected'
    },
    {
      name: 'Kraken',
      enabled: false,
      apiKey: '',
      rateLimit: 450,
      status: 'disconnected'
    }
  ],
  riskLimits: {
    maxPositionSize: 100000,
    maxDailyVolume: 1000000,
    maxDrawdownPct: 15,
    maxExposurePerExchange: 500000,
    emergencyStopThreshold: 10,
    circuitBreakerConsecutiveLosses: 5,
    circuitBreakerPauseDuration: 300
  },
  display: {
    theme: 'dark',
    chartTimeframe: '1m',
    numberFormat: 'en-US',
    showExtendedHours: false,
    enableSoundAlerts: true
  },
  paperMode: true
}

// Mock algo orders
export const mockActiveAlgoOrders: AlgoOrder[] = [
  {
    orderId: 'ALGO-001',
    algoType: 'vwap',
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'buy',
    targetQty: 2.5,
    filled: 1.8,
    avgFillPrice: 67245.30,
    arrivalPrice: 67250.00,
    status: 'active',
    eta: '8m 30s'
  },
  {
    orderId: 'ALGO-002',
    algoType: 'twap',
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'sell',
    targetQty: 15.0,
    filled: 6.5,
    avgFillPrice: 3218.45,
    arrivalPrice: 3215.00,
    status: 'paused',
    eta: '15m 12s'
  }
]

export const mockCompletedAlgoOrders: AlgoOrder[] = [
  {
    orderId: 'ALGO-003',
    algoType: 'vwap',
    exchange: 'binance',
    pair: 'BTCUSD',
    side: 'buy',
    targetQty: 5.0,
    filled: 5.0,
    avgFillPrice: 67180.25,
    arrivalPrice: 67200.00,
    status: 'completed',
    eta: '0s',
    duration: '28m 15s',
    childOrders: [
      { orderId: 'CHD-001', time: '14:15:00', qty: 0.8, price: 67195.50, status: 'filled' },
      { orderId: 'CHD-002', time: '14:20:00', qty: 1.2, price: 67185.20, status: 'filled' },
      { orderId: 'CHD-003', time: '14:25:00', qty: 0.9, price: 67175.80, status: 'filled' },
      { orderId: 'CHD-004', time: '14:30:00', qty: 1.1, price: 67170.50, status: 'filled' },
      { orderId: 'CHD-005', time: '14:35:00', qty: 1.0, price: 67180.00, status: 'filled' }
    ]
  },
  {
    orderId: 'ALGO-004',
    algoType: 'twap',
    exchange: 'coinbase',
    pair: 'ETHUSD',
    side: 'sell',
    targetQty: 20.0,
    filled: 20.0,
    avgFillPrice: 3210.15,
    arrivalPrice: 3205.00,
    status: 'completed',
    eta: '0s',
    duration: '45m 30s',
    childOrders: [
      { orderId: 'CHD-006', time: '13:30:00', qty: 4.0, price: 3208.50, status: 'filled' },
      { orderId: 'CHD-007', time: '13:45:00', qty: 4.0, price: 3212.20, status: 'filled' },
      { orderId: 'CHD-008', time: '14:00:00', qty: 4.0, price: 3210.80, status: 'filled' },
      { orderId: 'CHD-009', time: '14:15:00', qty: 4.0, price: 3209.50, status: 'filled' },
      { orderId: 'CHD-010', time: '14:30:00', qty: 4.0, price: 3210.00, status: 'filled' }
    ]
  },
  {
    orderId: 'ALGO-005',
    algoType: 'iceberg',
    exchange: 'binance',
    pair: 'SOLUSD',
    side: 'buy',
    targetQty: 100.0,
    filled: 100.0,
    avgFillPrice: 145.42,
    arrivalPrice: 145.50,
    status: 'completed',
    eta: '0s',
    duration: '18m 45s',
    childOrders: [
      { orderId: 'CHD-011', time: '14:00:00', qty: 10.0, price: 145.48, status: 'filled' },
      { orderId: 'CHD-012', time: '14:05:00', qty: 10.0, price: 145.45, status: 'filled' },
      { orderId: 'CHD-013', time: '14:10:00', qty: 10.0, price: 145.38, status: 'filled' },
      { orderId: 'CHD-014', time: '14:15:00', qty: 10.0, price: 145.40, status: 'filled' },
      { orderId: 'CHD-015', time: '14:18:00', qty: 10.0, price: 145.42, status: 'filled' },
      { orderId: 'CHD-016', time: '14:18:30', qty: 10.0, price: 145.40, status: 'filled' },
      { orderId: 'CHD-017', time: '14:18:45', qty: 10.0, price: 145.43, status: 'filled' },
      { orderId: 'CHD-018', time: '14:18:50', qty: 10.0, price: 145.41, status: 'filled' },
      { orderId: 'CHD-019', time: '14:19:00', qty: 10.0, price: 145.44, status: 'filled' },
      { orderId: 'CHD-020', time: '14:19:15', qty: 10.0, price: 145.42, status: 'filled' }
    ]
  },
  {
    orderId: 'ALGO-006',
    algoType: 'vwap',
    exchange: 'kraken',
    pair: 'ETHUSD',
    side: 'buy',
    targetQty: 8.0,
    filled: 8.0,
    avgFillPrice: 3202.85,
    arrivalPrice: 3200.00,
    status: 'completed',
    eta: '0s',
    duration: '32m 10s'
  },
  {
    orderId: 'ALGO-007',
    algoType: 'twap',
    exchange: 'binance',
    pair: 'ADAUSD',
    side: 'sell',
    targetQty: 5000.0,
    filled: 3200.0,
    avgFillPrice: 0.453,
    arrivalPrice: 0.450,
    status: 'cancelled',
    eta: '0s',
    duration: '12m 00s'
  }
]

// Generate mock aggregated order book (3 exchanges: Binance, Coinbase, Kraken)
// NOTE: Binance connector now exists, but this is historical/cached orderbook data.
// Best bid is from Binance (historical), best ask is from Coinbase (live).
interface AggregatedOrderBookLevel {
  price: number
  size: number
  cumulative: number
  exchanges: Array<{
    exchange: string
    size: number
  }>
}

export interface AggregatedOrderBook {
  bids: AggregatedOrderBookLevel[]
  asks: AggregatedOrderBookLevel[]
}

export const mockAggregatedOrderBook: AggregatedOrderBook = {
  bids: [
    // Best bid from Binance
    {
      price: 67230.0,
      size: 2.5,
      cumulative: 2.5,
      exchanges: [
        { exchange: 'binance', size: 1.8 },
        { exchange: 'coinbase', size: 0.7 }
      ]
    },
    {
      price: 67228.0,
      size: 3.2,
      cumulative: 5.7,
      exchanges: [
        { exchange: 'binance', size: 1.5 },
        { exchange: 'coinbase', size: 1.2 },
        { exchange: 'kraken', size: 0.5 }
      ]
    },
    {
      price: 67226.0,
      size: 2.8,
      cumulative: 8.5,
      exchanges: [
        { exchange: 'coinbase', size: 1.8 },
        { exchange: 'kraken', size: 1.0 }
      ]
    },
    {
      price: 67224.0,
      size: 4.1,
      cumulative: 12.6,
      exchanges: [
        { exchange: 'binance', size: 2.3 },
        { exchange: 'coinbase', size: 1.8 }
      ]
    },
    {
      price: 67222.0,
      size: 3.6,
      cumulative: 16.2,
      exchanges: [
        { exchange: 'binance', size: 2.1 },
        { exchange: 'kraken', size: 1.5 }
      ]
    },
    {
      price: 67220.0,
      size: 5.2,
      cumulative: 21.4,
      exchanges: [
        { exchange: 'binance', size: 2.8 },
        { exchange: 'coinbase', size: 1.9 },
        { exchange: 'kraken', size: 0.5 }
      ]
    },
    {
      price: 67218.0,
      size: 4.3,
      cumulative: 25.7,
      exchanges: [
        { exchange: 'coinbase', size: 2.5 },
        { exchange: 'kraken', size: 1.8 }
      ]
    },
    {
      price: 67216.0,
      size: 3.9,
      cumulative: 29.6,
      exchanges: [
        { exchange: 'binance', size: 2.7 },
        { exchange: 'coinbase', size: 1.2 }
      ]
    },
    {
      price: 67214.0,
      size: 6.1,
      cumulative: 35.7,
      exchanges: [
        { exchange: 'binance', size: 3.2 },
        { exchange: 'coinbase', size: 2.1 },
        { exchange: 'kraken', size: 0.8 }
      ]
    },
    {
      price: 67212.0,
      size: 5.4,
      cumulative: 41.1,
      exchanges: [
        { exchange: 'binance', size: 3.5 },
        { exchange: 'kraken', size: 1.9 }
      ]
    }
  ],
  asks: [
    // Best ask from Coinbase
    {
      price: 67232.0,
      size: 2.3,
      cumulative: 2.3,
      exchanges: [
        { exchange: 'coinbase', size: 1.5 },
        { exchange: 'binance', size: 0.8 }
      ]
    },
    {
      price: 67234.0,
      size: 3.1,
      cumulative: 5.4,
      exchanges: [
        { exchange: 'binance', size: 1.8 },
        { exchange: 'coinbase', size: 0.9 },
        { exchange: 'kraken', size: 0.4 }
      ]
    },
    {
      price: 67236.0,
      size: 2.9,
      cumulative: 8.3,
      exchanges: [
        { exchange: 'coinbase', size: 1.7 },
        { exchange: 'kraken', size: 1.2 }
      ]
    },
    {
      price: 67238.0,
      size: 4.5,
      cumulative: 12.8,
      exchanges: [
        { exchange: 'binance', size: 2.6 },
        { exchange: 'coinbase', size: 1.9 }
      ]
    },
    {
      price: 67240.0,
      size: 3.8,
      cumulative: 16.6,
      exchanges: [
        { exchange: 'binance', size: 2.2 },
        { exchange: 'kraken', size: 1.6 }
      ]
    },
    {
      price: 67242.0,
      size: 5.6,
      cumulative: 22.2,
      exchanges: [
        { exchange: 'binance', size: 3.1 },
        { exchange: 'coinbase', size: 2.0 },
        { exchange: 'kraken', size: 0.5 }
      ]
    },
    {
      price: 67244.0,
      size: 4.7,
      cumulative: 26.9,
      exchanges: [
        { exchange: 'coinbase', size: 2.8 },
        { exchange: 'kraken', size: 1.9 }
      ]
    },
    {
      price: 67246.0,
      size: 4.2,
      cumulative: 31.1,
      exchanges: [
        { exchange: 'binance', size: 2.9 },
        { exchange: 'coinbase', size: 1.3 }
      ]
    },
    {
      price: 67248.0,
      size: 6.3,
      cumulative: 37.4,
      exchanges: [
        { exchange: 'binance', size: 3.4 },
        { exchange: 'coinbase', size: 2.2 },
        { exchange: 'kraken', size: 0.7 }
      ]
    },
    {
      price: 67250.0,
      size: 5.8,
      cumulative: 43.2,
      exchanges: [
        { exchange: 'binance', size: 3.8 },
        { exchange: 'kraken', size: 2.0 }
      ]
    }
  ]
}

// GBBO data derived from aggregated order book
export const mockGBBOData = {
  bestBid: {
    price: 67230.0,
    exchange: 'Binance'
  },
  bestAsk: {
    price: 67232.0,
    exchange: 'Coinbase'
  },
  spread: 2.0,
  spreadBps: 3.0, // (2 / 67231) * 10000 ≈ 3 bps
  savingsVsWorstExchange: {
    amount: 5.0,
    exchange: 'Kraken'
  }
}
