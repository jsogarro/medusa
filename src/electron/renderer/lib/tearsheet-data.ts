/**
 * Generate comprehensive tearsheet data for pyfolio-style analytics
 * All data is realistic and follows Geometric Brownian Motion with trading-like characteristics
 */

// Type definitions for tearsheet data
export interface DailyReturn {
  date: string
  timestamp: number
  dailyReturn: number
  cumulativeReturn: number
  equity: number
}

export interface MonthlyReturn {
  year: number
  month: number
  monthName: string
  return: number
}

export interface DrawdownPeriod {
  peakDate: string
  valleyDate: string
  recoveryDate: string | null
  duration: number
  maxDrawdown: number
  isActive: boolean
}

export interface RollingMetric {
  date: string
  sharpe: number
  beta: number
  volatility30d: number
  volatility90d: number
}

export interface ExposurePoint {
  date: string
  grossLong: number
  grossShort: number
  netExposure: number
}

export interface RoundTripTrade {
  tradeId: number
  entryDate: string
  exitDate: string
  durationHours: number
  pnl: number
  return: number
  isWin: boolean
}

export interface TearsheetData {
  dailyReturns: DailyReturn[]
  monthlyReturns: MonthlyReturn[]
  annualReturns: { year: number; return: number }[]
  drawdowns: {
    underwater: { date: string; drawdown: number }[]
    periods: DrawdownPeriod[]
  }
  rollingMetrics: RollingMetric[]
  exposure: ExposurePoint[]
  roundTrips: RoundTripTrade[]
  metrics: {
    // Returns
    annualReturn: number
    cumulativeReturn: number
    annualVolatility: number
    dailyVaR95: number
    // Risk-adjusted
    sharpe: number
    sortino: number
    calmar: number
    omega: number
    // Tail risk
    maxDrawdown: number
    stability: number
    tailRatio: number
    skew: number
    kurtosis: number
    // Trading
    totalTrades: number
    winRate: number
    profitFactor: number
    avgWinLossRatio: number
    avgTradeDurationHours: number
  }
}

/**
 * Generate realistic daily returns using Geometric Brownian Motion
 * with trading-like characteristics (positive drift, volatility clustering)
 */
function generateDailyReturns(
  numDays: number = 500,
  startEquity: number = 100000,
  annualDrift: number = 0.18, // 18% annual return
  annualVol: number = 0.15 // 15% annual volatility
): DailyReturn[] {
  const returns: DailyReturn[] = []
  const dt = 1 / 252 // Daily timestep in years (252 trading days)
  let equity = startEquity
  let cumulativeReturn = 0

  const now = Date.now()
  const oneDayMs = 24 * 60 * 60 * 1000

  for (let i = 0; i < numDays; i++) {
    // Volatility clustering: occasional spikes
    const volMultiplier = Math.random() < 0.05 ? 1.5 + Math.random() * 0.5 : 1.0

    // Geometric Brownian Motion
    const drift = annualDrift * dt
    const shock = (Math.random() - 0.5) * 2 * Math.sqrt(3) // ~N(0,1) with Box-Muller
    const dailyReturn = drift + annualVol * Math.sqrt(dt) * shock * volMultiplier

    equity *= 1 + dailyReturn
    cumulativeReturn = (equity - startEquity) / startEquity

    const timestamp = now - (numDays - i) * oneDayMs
    const date = new Date(timestamp).toISOString().split('T')[0]

    returns.push({
      date,
      timestamp,
      dailyReturn,
      cumulativeReturn,
      equity
    })
  }

  return returns
}

/**
 * Aggregate daily returns into monthly returns
 */
function aggregateMonthlyReturns(dailyReturns: DailyReturn[]): MonthlyReturn[] {
  const monthlyMap = new Map<string, { year: number; month: number; returns: number[] }>()

  dailyReturns.forEach(({ date, dailyReturn }) => {
    const [year, month] = date.split('-').map(Number)
    const key = `${year}-${String(month).padStart(2, '0')}`

    if (!monthlyMap.has(key)) {
      monthlyMap.set(key, { year, month, returns: [] })
    }
    monthlyMap.get(key)!.returns.push(dailyReturn)
  })

  const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

  return Array.from(monthlyMap.values())
    .map(({ year, month, returns }) => {
      // Compound daily returns to get monthly return
      const monthlyReturn = returns.reduce((acc, r) => acc * (1 + r), 1) - 1
      return {
        year,
        month,
        monthName: monthNames[month - 1],
        return: monthlyReturn
      }
    })
    .sort((a, b) => a.year - b.year || a.month - b.month)
}

/**
 * Aggregate monthly returns into annual returns
 */
function aggregateAnnualReturns(monthlyReturns: MonthlyReturn[]): { year: number; return: number }[] {
  const yearlyMap = new Map<number, number[]>()

  monthlyReturns.forEach(({ year, return: monthlyReturn }) => {
    if (!yearlyMap.has(year)) {
      yearlyMap.set(year, [])
    }
    yearlyMap.get(year)!.push(monthlyReturn)
  })

  return Array.from(yearlyMap.entries())
    .map(([year, returns]) => ({
      year,
      return: returns.reduce((acc, r) => acc * (1 + r), 1) - 1
    }))
    .sort((a, b) => a.year - b.year)
}

/**
 * Calculate drawdown series and identify drawdown periods
 */
function calculateDrawdowns(dailyReturns: DailyReturn[]): {
  underwater: { date: string; drawdown: number }[]
  periods: DrawdownPeriod[]
} {
  let peak = dailyReturns[0].equity
  let peakDate = dailyReturns[0].date
  let inDrawdown = false
  let currentValley = peak
  let valleyDate = peakDate

  const underwater: { date: string; drawdown: number }[] = []
  const periods: DrawdownPeriod[] = []

  dailyReturns.forEach(({ date, equity }) => {
    if (equity > peak) {
      // New peak
      if (inDrawdown) {
        // End of drawdown period
        periods.push({
          peakDate,
          valleyDate,
          recoveryDate: date,
          duration: Math.floor((new Date(date).getTime() - new Date(peakDate).getTime()) / (1000 * 60 * 60 * 24)),
          maxDrawdown: (currentValley - peak) / peak,
          isActive: false
        })
        inDrawdown = false
      }
      peak = equity
      peakDate = date
      currentValley = equity
    } else {
      // Below peak
      if (!inDrawdown) {
        inDrawdown = true
        currentValley = equity
        valleyDate = date
      } else if (equity < currentValley) {
        currentValley = equity
        valleyDate = date
      }
    }

    const drawdown = (equity - peak) / peak
    underwater.push({ date, drawdown })
  })

  // If still in drawdown at end
  if (inDrawdown) {
    periods.push({
      peakDate,
      valleyDate,
      recoveryDate: null,
      duration: Math.floor(
        (new Date(dailyReturns[dailyReturns.length - 1].date).getTime() - new Date(peakDate).getTime()) /
          (1000 * 60 * 60 * 24)
      ),
      maxDrawdown: (currentValley - peak) / peak,
      isActive: true
    })
  }

  // Sort by max drawdown and take top 5
  const top5Periods = periods.sort((a, b) => a.maxDrawdown - b.maxDrawdown).slice(0, 5)

  return { underwater, periods: top5Periods }
}

/**
 * Calculate rolling metrics (Sharpe, beta, volatility)
 */
function calculateRollingMetrics(dailyReturns: DailyReturn[]): RollingMetric[] {
  const metrics: RollingMetric[] = []
  const riskFreeRate = 0.03 / 252 // 3% annual risk-free rate
  const marketReturn = 0.12 / 252 // Assume 12% market return (BTC proxy)

  for (let i = 89; i < dailyReturns.length; i++) {
    const window90 = dailyReturns.slice(i - 89, i + 1)
    const window30 = dailyReturns.slice(Math.max(0, i - 29), i + 1)

    const returns90 = window90.map((r) => r.dailyReturn)
    const returns30 = window30.map((r) => r.dailyReturn)

    // 90-day rolling Sharpe
    const mean90 = returns90.reduce((sum, r) => sum + r, 0) / returns90.length
    const std90 = Math.sqrt(returns90.reduce((sum, r) => sum + Math.pow(r - mean90, 2), 0) / returns90.length)
    const sharpe = std90 > 0 ? ((mean90 - riskFreeRate) / std90) * Math.sqrt(252) : 0

    // 90-day rolling beta (simplified: correlation with market proxy)
    const marketReturns = returns90.map(() => marketReturn + (Math.random() - 0.5) * 0.01)
    const covarianceNum = returns90.reduce((sum, r, idx) => sum + (r - mean90) * (marketReturns[idx] - marketReturn), 0)
    const marketVariance = marketReturns.reduce((sum, r) => sum + Math.pow(r - marketReturn, 2), 0) / marketReturns.length
    const beta = marketVariance > 0 ? covarianceNum / (returns90.length * marketVariance) : 1.0

    // Rolling volatilities
    const mean30 = returns30.reduce((sum, r) => sum + r, 0) / returns30.length
    const std30 = Math.sqrt(returns30.reduce((sum, r) => sum + Math.pow(r - mean30, 2), 0) / returns30.length)
    const volatility30d = std30 * Math.sqrt(252)
    const volatility90d = std90 * Math.sqrt(252)

    metrics.push({
      date: dailyReturns[i].date,
      sharpe,
      beta,
      volatility30d,
      volatility90d
    })
  }

  return metrics
}

/**
 * Generate exposure time series (long/short/net)
 */
function generateExposure(dailyReturns: DailyReturn[]): ExposurePoint[] {
  return dailyReturns.map(({ date }, i) => {
    // Simulate varying long/short exposure
    const trend = Math.sin((i / dailyReturns.length) * Math.PI * 4) // 4 cycles
    const grossLong = 0.5 + trend * 0.2 + (Math.random() - 0.5) * 0.1
    const grossShort = 0.3 + trend * -0.15 + (Math.random() - 0.5) * 0.08
    const netExposure = grossLong - grossShort

    return {
      date,
      grossLong: Math.max(0, Math.min(1, grossLong)),
      grossShort: Math.max(0, Math.min(1, grossShort)),
      netExposure: Math.max(-1, Math.min(1, netExposure))
    }
  })
}

/**
 * Generate round-trip trades with realistic P&L distribution
 */
function generateRoundTrips(numTrades: number = 200): RoundTripTrade[] {
  const trades: RoundTripTrade[] = []
  const now = Date.now()
  const oneDayMs = 24 * 60 * 60 * 1000

  for (let i = 0; i < numTrades; i++) {
    // Entry date distributed over past 500 days
    const entryTimestamp = now - Math.random() * 500 * oneDayMs
    const entryDate = new Date(entryTimestamp).toISOString().split('T')[0]

    // Trade duration: mean 4 hours, exponential distribution
    const durationHours = -Math.log(Math.random()) * 4 + 0.5

    const exitTimestamp = entryTimestamp + durationHours * 60 * 60 * 1000
    const exitDate = new Date(exitTimestamp).toISOString().split('T')[0]

    // P&L distribution: slight positive skew (62% win rate)
    const isWin = Math.random() < 0.62
    let pnl: number
    let returnPct: number

    if (isWin) {
      // Wins: exponential distribution, mean $450
      pnl = -Math.log(Math.random()) * 400 + 50
      returnPct = pnl / 10000 // Assume $10k position size
    } else {
      // Losses: exponential distribution, mean $230
      pnl = -(-Math.log(Math.random()) * 200 + 30)
      returnPct = pnl / 10000
    }

    trades.push({
      tradeId: i + 1,
      entryDate,
      exitDate,
      durationHours,
      pnl,
      return: returnPct,
      isWin
    })
  }

  return trades.sort((a, b) => new Date(a.entryDate).getTime() - new Date(b.entryDate).getTime())
}

/**
 * Calculate comprehensive performance metrics
 */
function calculateMetrics(dailyReturns: DailyReturn[], roundTrips: RoundTripTrade[]): TearsheetData['metrics'] {
  const returns = dailyReturns.map((r) => r.dailyReturn)
  const mean = returns.reduce((sum, r) => sum + r, 0) / returns.length
  const variance = returns.reduce((sum, r) => sum + Math.pow(r - mean, 2), 0) / returns.length
  const std = Math.sqrt(variance)

  const riskFreeRate = 0.03 / 252

  // Annual metrics
  const annualReturn = mean * 252
  const annualVolatility = std * Math.sqrt(252)
  const cumulativeReturn = dailyReturns[dailyReturns.length - 1].cumulativeReturn

  // Risk-adjusted
  const sharpe = std > 0 ? ((mean - riskFreeRate) / std) * Math.sqrt(252) : 0

  // Sortino: only downside deviation
  const downsideReturns = returns.filter((r) => r < riskFreeRate)
  const downsideVariance =
    downsideReturns.reduce((sum, r) => sum + Math.pow(r - riskFreeRate, 2), 0) / downsideReturns.length
  const downsideStd = Math.sqrt(downsideVariance)
  const sortino = downsideStd > 0 ? ((mean - riskFreeRate) / downsideStd) * Math.sqrt(252) : 0

  // Max drawdown
  let peak = dailyReturns[0].equity
  let maxDrawdown = 0
  dailyReturns.forEach(({ equity }) => {
    if (equity > peak) peak = equity
    const dd = (equity - peak) / peak
    if (dd < maxDrawdown) maxDrawdown = dd
  })

  // Calmar
  const calmar = maxDrawdown !== 0 ? annualReturn / Math.abs(maxDrawdown) : 0

  // Omega ratio (probability weighted ratio of gains vs losses)
  const threshold = riskFreeRate
  const gains = returns.filter((r) => r > threshold).reduce((sum, r) => sum + (r - threshold), 0)
  const losses = Math.abs(returns.filter((r) => r < threshold).reduce((sum, r) => sum + (r - threshold), 0))
  const omega = losses > 0 ? gains / losses : 2.0

  // Stability (R^2 of linear regression on cumulative returns)
  const n = dailyReturns.length
  const xMean = (n - 1) / 2
  const yMean = dailyReturns.reduce((sum, r) => sum + r.cumulativeReturn, 0) / n
  const ssTotal = dailyReturns.reduce((sum, r) => sum + Math.pow(r.cumulativeReturn - yMean, 2), 0)
  const ssRes = dailyReturns.reduce((sum, r, i) => {
    const yPred = yMean + ((i - xMean) * (dailyReturns[n - 1].cumulativeReturn - dailyReturns[0].cumulativeReturn)) / (n - 1)
    return sum + Math.pow(r.cumulativeReturn - yPred, 2)
  }, 0)
  const stability = ssTotal > 0 ? 1 - ssRes / ssTotal : 0

  // Tail ratio (95th percentile of wins / 95th percentile of losses)
  const sortedReturns = [...returns].sort((a, b) => a - b)
  const p95Index = Math.floor(sortedReturns.length * 0.95)
  const p5Index = Math.floor(sortedReturns.length * 0.05)
  const tailRatio = sortedReturns[p5Index] !== 0 ? Math.abs(sortedReturns[p95Index] / sortedReturns[p5Index]) : 1.0

  // Skew and kurtosis
  const skew = returns.reduce((sum, r) => sum + Math.pow((r - mean) / std, 3), 0) / returns.length
  const kurtosis = returns.reduce((sum, r) => sum + Math.pow((r - mean) / std, 4), 0) / returns.length

  // VaR (95% confidence)
  const dailyVaR95 = sortedReturns[p5Index]

  // Trading metrics
  const totalTrades = roundTrips.length
  const winningTrades = roundTrips.filter((t) => t.isWin)
  const losingTrades = roundTrips.filter((t) => !t.isWin)
  const winRate = winningTrades.length / totalTrades

  const totalWins = winningTrades.reduce((sum, t) => sum + t.pnl, 0)
  const totalLosses = Math.abs(losingTrades.reduce((sum, t) => sum + t.pnl, 0))
  const profitFactor = totalLosses > 0 ? totalWins / totalLosses : 2.0

  const avgWin = winningTrades.length > 0 ? totalWins / winningTrades.length : 0
  const avgLoss = losingTrades.length > 0 ? totalLosses / losingTrades.length : 0
  const avgWinLossRatio = avgLoss > 0 ? avgWin / avgLoss : 2.0

  const avgTradeDurationHours = roundTrips.reduce((sum, t) => sum + t.durationHours, 0) / roundTrips.length

  return {
    annualReturn,
    cumulativeReturn,
    annualVolatility,
    dailyVaR95,
    sharpe,
    sortino,
    calmar,
    omega,
    maxDrawdown,
    stability,
    tailRatio,
    skew,
    kurtosis,
    totalTrades,
    winRate,
    profitFactor,
    avgWinLossRatio,
    avgTradeDurationHours
  }
}

/**
 * Generate complete tearsheet data
 */
export function generateTearsheetData(numDays: number = 500, numTrades: number = 200): TearsheetData {
  const dailyReturns = generateDailyReturns(numDays)
  const monthlyReturns = aggregateMonthlyReturns(dailyReturns)
  const annualReturns = aggregateAnnualReturns(monthlyReturns)
  const drawdowns = calculateDrawdowns(dailyReturns)
  const rollingMetrics = calculateRollingMetrics(dailyReturns)
  const exposure = generateExposure(dailyReturns)
  const roundTrips = generateRoundTrips(numTrades)
  const metrics = calculateMetrics(dailyReturns, roundTrips)

  return {
    dailyReturns,
    monthlyReturns,
    annualReturns,
    drawdowns,
    rollingMetrics,
    exposure,
    roundTrips,
    metrics
  }
}
