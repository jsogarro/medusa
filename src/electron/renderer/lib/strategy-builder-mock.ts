export interface StrategyTemplate {
  name: string
  description: string
  defaultParams: {
    fast_period?: number
    slow_period?: number
    stop_loss_pct?: number
    take_profit_pct?: number
    rsi_period?: number
    rsi_overbought?: number
    rsi_oversold?: number
    bb_period?: number
    bb_std_dev?: number
  }
}

export interface BacktestParams {
  template: string
  symbol: string
  exchange: string
  params: Record<string, number>
}

export interface BacktestTrade {
  id: number
  entry: Date
  exit: Date
  side: 'long' | 'short'
  entryPrice: number
  exitPrice: number
  pnl: number
  pnlPct: number
  duration: string
}

export interface BacktestResult {
  equityCurve: Array<{ time: number; equity: number }>
  metrics: {
    totalReturn: number
    sharpe: number
    maxDrawdown: number
    winRate: number
    totalTrades: number
    profitFactor: number
  }
  trades: BacktestTrade[]
  pnlDistribution: Array<{ range: string; count: number }>
}

export const strategyTemplates: StrategyTemplate[] = [
  {
    name: 'SMA Crossover',
    description: 'Buy when fast SMA crosses above slow SMA, sell on opposite cross',
    defaultParams: {
      fast_period: 20,
      slow_period: 50,
      stop_loss_pct: 2,
      take_profit_pct: 5
    }
  },
  {
    name: 'Mean Reversion',
    description: 'Trade price reversions to the mean using Bollinger Bands',
    defaultParams: {
      bb_period: 20,
      bb_std_dev: 2,
      stop_loss_pct: 1.5,
      take_profit_pct: 3
    }
  },
  {
    name: 'Momentum',
    description: 'Follow price momentum using RSI indicator',
    defaultParams: {
      rsi_period: 14,
      rsi_overbought: 70,
      rsi_oversold: 30,
      stop_loss_pct: 2.5,
      take_profit_pct: 6
    }
  },
  {
    name: 'Bollinger Breakout',
    description: 'Enter on Bollinger Band breakouts',
    defaultParams: {
      bb_period: 20,
      bb_std_dev: 2.5,
      stop_loss_pct: 1,
      take_profit_pct: 4
    }
  },
  {
    name: 'RSI',
    description: 'Simple RSI overbought/oversold strategy',
    defaultParams: {
      rsi_period: 14,
      rsi_overbought: 75,
      rsi_oversold: 25,
      stop_loss_pct: 2,
      take_profit_pct: 5
    }
  }
]

/**
 * Generate a realistic mock backtest result
 */
export function generateMockBacktestResult(params: BacktestParams): BacktestResult {
  const startEquity = 100000
  const numTrades = 15 + Math.floor(Math.random() * 10) // 15-25 trades
  const trades: BacktestTrade[] = []

  // Generate trades with realistic P&L distribution
  let currentEquity = startEquity
  const now = Date.now()
  const oneDay = 24 * 60 * 60 * 1000
  let currentTime = now - 30 * oneDay // Start 30 days ago

  for (let i = 0; i < numTrades; i++) {
    const entryTime = new Date(currentTime)
    const durationHours = 2 + Math.random() * 72 // 2-74 hours
    const exitTime = new Date(currentTime + durationHours * 60 * 60 * 1000)

    const side = Math.random() > 0.5 ? 'long' : 'short'
    const entryPrice = 67000 + (Math.random() - 0.5) * 2000

    // Win rate around 55-65%
    const isWin = Math.random() > 0.4
    const pnlPct = isWin
      ? 0.5 + Math.random() * (params.params.take_profit_pct || 4)
      : -(0.5 + Math.random() * (params.params.stop_loss_pct || 2))

    const exitPrice = side === 'long'
      ? entryPrice * (1 + pnlPct / 100)
      : entryPrice * (1 - pnlPct / 100)

    const positionSize = 10000 + Math.random() * 5000 // $10k-$15k per trade
    const pnl = (positionSize * pnlPct) / 100
    currentEquity += pnl

    const durationStr = durationHours < 24
      ? `${Math.floor(durationHours)}h`
      : `${Math.floor(durationHours / 24)}d ${Math.floor(durationHours % 24)}h`

    trades.push({
      id: i + 1,
      entry: entryTime,
      exit: exitTime,
      side,
      entryPrice,
      exitPrice,
      pnl,
      pnlPct,
      duration: durationStr
    })

    currentTime = exitTime.getTime() + (Math.random() * 12 * 60 * 60 * 1000) // Random gap between trades
  }

  // Generate equity curve (200 points)
  const equityCurve: Array<{ time: number; equity: number }> = []
  let equity = startEquity
  const finalEquity = currentEquity
  const equityChange = finalEquity - startEquity
  const drift = equityChange / 200

  for (let i = 0; i < 200; i++) {
    equity += drift + (Math.random() - 0.5) * 500 // Add some noise
    equityCurve.push({
      time: i,
      equity: Math.max(equity, startEquity * 0.9) // Don't drop below 90% of start
    })
  }

  // Calculate metrics
  const winningTrades = trades.filter(t => t.pnl > 0)
  const losingTrades = trades.filter(t => t.pnl < 0)
  const totalGains = winningTrades.reduce((sum, t) => sum + t.pnl, 0)
  const totalLosses = Math.abs(losingTrades.reduce((sum, t) => sum + t.pnl, 0))

  const totalReturn = ((finalEquity - startEquity) / startEquity) * 100
  const winRate = (winningTrades.length / trades.length) * 100

  // Calculate max drawdown
  let maxEquity = startEquity
  let maxDrawdown = 0
  for (const point of equityCurve) {
    if (point.equity > maxEquity) {
      maxEquity = point.equity
    }
    const drawdown = ((maxEquity - point.equity) / maxEquity) * 100
    if (drawdown > maxDrawdown) {
      maxDrawdown = drawdown
    }
  }

  // Sharpe ratio (simplified calculation)
  const avgReturn = totalReturn / 200 // Daily average
  const stdDev = Math.sqrt(
    equityCurve.reduce((sum, point, idx) => {
      if (idx === 0) return 0
      const dailyReturn = ((point.equity - equityCurve[idx - 1].equity) / equityCurve[idx - 1].equity) * 100
      return sum + Math.pow(dailyReturn - avgReturn, 2)
    }, 0) / equityCurve.length
  )
  const sharpe = stdDev > 0 ? (avgReturn / stdDev) * Math.sqrt(252) : 0

  const profitFactor = totalLosses > 0 ? totalGains / totalLosses : totalGains > 0 ? 999 : 0

  // P&L distribution
  const pnlDistribution: Array<{ range: string; count: number }> = [
    { range: '< -2%', count: 0 },
    { range: '-2% to -1%', count: 0 },
    { range: '-1% to 0%', count: 0 },
    { range: '0% to 1%', count: 0 },
    { range: '1% to 2%', count: 0 },
    { range: '2% to 3%', count: 0 },
    { range: '> 3%', count: 0 }
  ]

  trades.forEach(trade => {
    if (trade.pnlPct < -2) pnlDistribution[0].count++
    else if (trade.pnlPct < -1) pnlDistribution[1].count++
    else if (trade.pnlPct < 0) pnlDistribution[2].count++
    else if (trade.pnlPct < 1) pnlDistribution[3].count++
    else if (trade.pnlPct < 2) pnlDistribution[4].count++
    else if (trade.pnlPct < 3) pnlDistribution[5].count++
    else pnlDistribution[6].count++
  })

  return {
    equityCurve,
    metrics: {
      totalReturn: Number(totalReturn.toFixed(2)),
      sharpe: Number(sharpe.toFixed(2)),
      maxDrawdown: Number(maxDrawdown.toFixed(2)),
      winRate: Number(winRate.toFixed(1)),
      totalTrades: trades.length,
      profitFactor: Number(profitFactor.toFixed(2))
    },
    trades: trades.sort((a, b) => b.entry.getTime() - a.entry.getTime()), // Sort by most recent first
    pnlDistribution
  }
}
