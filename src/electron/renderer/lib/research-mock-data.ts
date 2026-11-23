// Mock data for Research & Backtesting screen

export interface StrategyEquityCurve {
  strategy: string
  color: string
  data: Array<{ day: number; equity: number }>
}

export interface BacktestRun {
  runId: string
  strategy: string
  pair: string
  period: string
  sharpe: number
  returnPct: number
  maxDrawdownPct: number
  status: 'Complete' | 'Running' | 'Failed'
}

export interface MLPrediction {
  time: number
  actual: number
  predicted: number
  confidenceUpper: number
  confidenceLower: number
  directionCorrect: boolean
}

export interface FeatureImportance {
  feature: string
  importance: number
  category: 'Technical' | 'Volume' | 'Momentum'
}

export interface ParameterOptimization {
  fastPeriod: number
  slowPeriod: number
  sharpe: number
}

export interface StrategyPipelineStatus {
  strategy: string
  research: boolean
  backtest: boolean
  paperTrading: boolean
  live: boolean
  paperTradingSince?: string
  paperTradingPnL?: number
  liveSince?: string
}

// Generate 4 strategy equity curves + benchmark (500 days each)
export function generateStrategyEquityCurves(): StrategyEquityCurve[] {
  const numDays = 500

  // simpleArb: steady upward, low volatility, high Sharpe
  const simpleArbData = []
  let simpleArbEquity = 100000
  for (let i = 0; i < numDays; i++) {
    simpleArbEquity += simpleArbEquity * (0.00025 + (Math.random() - 0.5) * 0.0005)
    simpleArbData.push({ day: i, equity: simpleArbEquity })
  }

  // simpleMM: moderate upward, medium volatility
  const simpleMMData = []
  let simpleMMEquity = 100000
  for (let i = 0; i < numDays; i++) {
    simpleMMEquity += simpleMMEquity * (0.00015 + (Math.random() - 0.5) * 0.001)
    simpleMMData.push({ day: i, equity: simpleMMEquity })
  }

  // momentum: choppy, recent drawdown
  const momentumData = []
  let momentumEquity = 100000
  for (let i = 0; i < numDays; i++) {
    const drift = i > 400 ? -0.0002 : 0.00005 // recent drawdown
    momentumEquity += momentumEquity * (drift + (Math.random() - 0.5) * 0.002)
    momentumData.push({ day: i, equity: momentumEquity })
  }

  // meanReversion: declining, stopped
  const meanReversionData = []
  let meanReversionEquity = 100000
  for (let i = 0; i < numDays; i++) {
    meanReversionEquity += meanReversionEquity * (-0.0002 + (Math.random() - 0.5) * 0.0015)
    meanReversionData.push({ day: i, equity: meanReversionEquity })
  }

  // benchmark: buy-and-hold BTC with realistic volatility
  const benchmarkData = []
  let benchmarkEquity = 100000
  for (let i = 0; i < numDays; i++) {
    benchmarkEquity += benchmarkEquity * (0.0002 + (Math.random() - 0.5) * 0.003)
    benchmarkData.push({ day: i, equity: benchmarkEquity })
  }

  return [
    { strategy: 'simpleArb', color: '#00c853', data: simpleArbData },
    { strategy: 'simpleMM', color: '#2196f3', data: simpleMMData },
    { strategy: 'momentum', color: '#ff9800', data: momentumData },
    { strategy: 'meanReversion', color: '#9c27b0', data: meanReversionData },
    { strategy: 'Buy & Hold BTC', color: '#757575', data: benchmarkData }
  ]
}

// Generate 5 backtest runs
export const mockBacktestRuns: BacktestRun[] = [
  {
    runId: 'BT-001',
    strategy: 'SMA Crossover',
    pair: 'BTCUSD',
    period: 'Jan-Dec 2025',
    sharpe: 1.85,
    returnPct: 22.3,
    maxDrawdownPct: 9.1,
    status: 'Complete'
  },
  {
    runId: 'BT-002',
    strategy: 'LSTM Signals',
    pair: 'ETHUSD',
    period: 'Mar-Sep 2025',
    sharpe: 1.12,
    returnPct: 8.7,
    maxDrawdownPct: 14.2,
    status: 'Complete'
  },
  {
    runId: 'BT-003',
    strategy: 'Mean Reversion',
    pair: 'SOLUSD',
    period: 'Jun-Dec 2025',
    sharpe: 0.67,
    returnPct: -3.4,
    maxDrawdownPct: 18.5,
    status: 'Complete'
  },
  {
    runId: 'BT-004',
    strategy: 'Momentum + ML',
    pair: 'BTCUSD',
    period: 'Jan-Dec 2025',
    sharpe: 2.45,
    returnPct: 31.2,
    maxDrawdownPct: 6.8,
    status: 'Complete'
  },
  {
    runId: 'BT-005',
    strategy: 'Arb v2',
    pair: 'Multi',
    period: 'Jan-Dec 2025',
    sharpe: 2.89,
    returnPct: 28.1,
    maxDrawdownPct: 5.2,
    status: 'Running'
  }
]

// Generate ML prediction data (200 points)
export function generateMLPredictions(): MLPrediction[] {
  const data: MLPrediction[] = []
  let actualPrice = 67000
  const now = Date.now()
  const oneHour = 60 * 60 * 1000

  for (let i = 0; i < 200; i++) {
    // Random walk for actual price
    actualPrice += (Math.random() - 0.5) * 200

    // Predicted price with some lag/error
    const predictionError = (Math.random() - 0.5) * 300
    const predicted = actualPrice + predictionError

    // Confidence interval
    const confidenceWidth = 150 + Math.random() * 100
    const confidenceUpper = predicted + confidenceWidth
    const confidenceLower = predicted - confidenceWidth

    // Direction correctness
    const actualChange = i > 0 ? actualPrice - data[i - 1].actual : 0
    const predictedChange = i > 0 ? predicted - data[i - 1].predicted : 0
    const directionCorrect = i === 0 || (actualChange * predictedChange >= 0)

    data.push({
      time: Math.floor((now - (200 - i) * oneHour) / 1000),
      actual: actualPrice,
      predicted,
      confidenceUpper,
      confidenceLower,
      directionCorrect
    })
  }

  return data
}

// Feature importance data (15 features)
export const mockFeatureImportance: FeatureImportance[] = [
  { feature: 'RSI_14', importance: 0.15, category: 'Momentum' },
  { feature: 'MACD', importance: 0.13, category: 'Momentum' },
  { feature: 'Volume_MA_20', importance: 0.12, category: 'Volume' },
  { feature: 'Bollinger_Width', importance: 0.11, category: 'Technical' },
  { feature: 'SMA_20', importance: 0.10, category: 'Technical' },
  { feature: 'SMA_50', importance: 0.09, category: 'Technical' },
  { feature: 'ATR_14', importance: 0.08, category: 'Technical' },
  { feature: 'OBV', importance: 0.07, category: 'Volume' },
  { feature: 'Stochastic_K', importance: 0.06, category: 'Momentum' },
  { feature: 'EMA_12', importance: 0.05, category: 'Technical' },
  { feature: 'Volume_Ratio', importance: 0.04, category: 'Volume' },
  { feature: 'ADX_14', importance: 0.03, category: 'Momentum' },
  { feature: 'CCI_20', importance: 0.03, category: 'Momentum' },
  { feature: 'Williams_R', importance: 0.02, category: 'Momentum' },
  { feature: 'MFI_14', importance: 0.02, category: 'Volume' }
]

// Training history (50 epochs)
export function generateTrainingHistory() {
  const epochs = 50
  const data: Array<{ epoch: number; trainLoss: number; valLoss: number }> = []

  let trainLoss = 0.8
  let valLoss = 0.85

  for (let i = 0; i < epochs; i++) {
    // Exponential decay with noise
    trainLoss = trainLoss * 0.95 + (Math.random() - 0.5) * 0.02
    valLoss = valLoss * 0.96 + (Math.random() - 0.5) * 0.03

    // Ensure validation loss is higher than training (realistic)
    valLoss = Math.max(valLoss, trainLoss + 0.01)

    data.push({
      epoch: i + 1,
      trainLoss: Math.max(0.02, trainLoss),
      valLoss: Math.max(0.02, valLoss)
    })
  }

  return data
}

// Parameter optimization heatmap (10x10 grid)
export function generateOptimizationHeatmap(): ParameterOptimization[] {
  const data: ParameterOptimization[] = []

  const fastPeriods = [5, 8, 10, 12, 15, 18, 20, 25, 30, 35]
  const slowPeriods = [20, 30, 40, 48, 55, 65, 80, 100, 150, 200]

  // Optimal parameters: fast=12, slow=55 (center-ish)
  const optimalFast = 12
  const optimalSlow = 55

  for (const fast of fastPeriods) {
    for (const slow of slowPeriods) {
      // Distance from optimal
      const distanceFast = Math.abs(fast - optimalFast) / 10
      const distanceSlow = Math.abs(slow - optimalSlow) / 50

      // Sharpe peaks near optimal, falls off with distance
      const baseSharpe = 2.5
      const decay = Math.exp(-(distanceFast ** 2 + distanceSlow ** 2) / 2)
      const sharpe = Math.max(0.2, baseSharpe * decay + (Math.random() - 0.5) * 0.3)

      data.push({ fastPeriod: fast, slowPeriod: slow, sharpe })
    }
  }

  return data
}

// Top 10 parameter sets
export const mockTopParameterSets = [
  { rank: 1, fastPeriod: 12, slowPeriod: 55, threshold: 0.02, sharpe: 2.45, returnPct: 31.2, maxDrawdownPct: 6.8 },
  { rank: 2, fastPeriod: 15, slowPeriod: 48, threshold: 0.015, sharpe: 2.38, returnPct: 28.9, maxDrawdownPct: 7.1 },
  { rank: 3, fastPeriod: 10, slowPeriod: 65, threshold: 0.018, sharpe: 2.32, returnPct: 27.5, maxDrawdownPct: 7.3 },
  { rank: 4, fastPeriod: 18, slowPeriod: 55, threshold: 0.022, sharpe: 2.28, returnPct: 26.8, maxDrawdownPct: 7.5 },
  { rank: 5, fastPeriod: 12, slowPeriod: 48, threshold: 0.017, sharpe: 2.21, returnPct: 25.4, maxDrawdownPct: 7.8 },
  { rank: 6, fastPeriod: 15, slowPeriod: 65, threshold: 0.021, sharpe: 2.15, returnPct: 24.2, maxDrawdownPct: 8.2 },
  { rank: 7, fastPeriod: 10, slowPeriod: 55, threshold: 0.019, sharpe: 2.08, returnPct: 22.9, maxDrawdownPct: 8.6 },
  { rank: 8, fastPeriod: 20, slowPeriod: 48, threshold: 0.016, sharpe: 2.02, returnPct: 21.7, maxDrawdownPct: 9.1 },
  { rank: 9, fastPeriod: 12, slowPeriod: 80, threshold: 0.023, sharpe: 1.95, returnPct: 20.3, maxDrawdownPct: 9.5 },
  { rank: 10, fastPeriod: 18, slowPeriod: 65, threshold: 0.020, sharpe: 1.89, returnPct: 19.1, maxDrawdownPct: 9.8 }
]

// Strategy pipeline statuses
export const mockStrategyPipeline: StrategyPipelineStatus[] = [
  {
    strategy: 'simpleArb',
    research: true,
    backtest: true,
    paperTrading: true,
    live: true,
    liveSince: 'Apr 10'
  },
  {
    strategy: 'simpleMM',
    research: true,
    backtest: true,
    paperTrading: true,
    live: true,
    liveSince: 'Apr 15'
  },
  {
    strategy: 'momentum',
    research: true,
    backtest: true,
    paperTrading: true,
    live: false,
    paperTradingSince: '7 days',
    paperTradingPnL: 2.3
  },
  {
    strategy: 'meanReversion',
    research: true,
    backtest: false,
    paperTrading: false,
    live: false
  },
  {
    strategy: 'lstm_signals',
    research: true,
    backtest: true,
    paperTrading: true,
    live: false,
    paperTradingSince: '3 days',
    paperTradingPnL: 0.8
  }
]

// ML Model metrics
export const mockMLModelMetrics = {
  mse: 0.0234,
  mae: 0.089,
  r2: 0.72,
  directionAccuracy: 64.2,
  sharpeSIgnal: 1.45
}
