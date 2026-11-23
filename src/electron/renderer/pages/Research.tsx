import { useState, useMemo, useCallback } from 'react'
import { Card } from '../components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select'
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  ScatterChart,
  Scatter,
  ResponsiveContainer,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  Cell
} from 'recharts'
import {
  generateStrategyEquityCurves,
  mockBacktestRuns,
  generateMLPredictions,
  mockFeatureImportance,
  generateTrainingHistory,
  generateOptimizationHeatmap,
  mockTopParameterSets,
  mockStrategyPipeline,
  mockMLModelMetrics,
  type StrategyEquityCurve,
} from '../lib/research-mock-data'
import { formatPrice, formatPercent } from '../lib/utils'

export function Research() {
  const [selectedStrategies, setSelectedStrategies] = useState<string[]>(['simpleArb', 'simpleMM', 'Buy & Hold BTC'])
  const [selectedModel, setSelectedModel] = useState<'LSTM' | 'Transformer' | 'XGBoost' | 'N-BEATS'>('LSTM')
  const [expandedBacktest, setExpandedBacktest] = useState<string | null>(null)

  // Memoize expensive data generation (only once on mount)
  const equityCurves = useMemo(() => generateStrategyEquityCurves(), [])
  const mlPredictions = useMemo(() => generateMLPredictions(), [])
  const trainingHistory = useMemo(() => generateTrainingHistory(), [])
  const optimizationHeatmap = useMemo(() => generateOptimizationHeatmap(), [])

  // Filter equity curves by selected strategies (memoized)
  const filteredCurves = useMemo(
    () => equityCurves.filter((curve) => selectedStrategies.includes(curve.strategy)),
    [equityCurves, selectedStrategies]
  )

  // Combine all curves into a single dataset for recharts (memoized)
  const combinedEquityData = useMemo(() => {
    if (filteredCurves.length === 0) return []
    return filteredCurves[0].data.map((_, index) => {
      const dataPoint: Record<string, number> = { day: index }
      filteredCurves.forEach((curve) => {
        dataPoint[curve.strategy] = curve.data[index].equity
      })
      return dataPoint
    })
  }, [filteredCurves])

  // Calculate comparison metrics (memoized callback)
  const getStrategyMetrics = useCallback((curve: StrategyEquityCurve) => {
    const finalEquity = curve.data[curve.data.length - 1].equity
    const initialEquity = curve.data[0].equity
    const totalReturn = ((finalEquity - initialEquity) / initialEquity) * 100
    const annualReturn = totalReturn / (curve.data.length / 365)

    // Calculate max drawdown
    let maxDrawdown = 0
    let peak = initialEquity
    for (const point of curve.data) {
      if (point.equity > peak) peak = point.equity
      const drawdown = ((peak - point.equity) / peak) * 100
      if (drawdown > maxDrawdown) maxDrawdown = drawdown
    }

    return {
      totalReturn,
      annualReturn,
      maxDrawdown,
      sharpe: curve.strategy === 'simpleArb' ? 2.14 : curve.strategy === 'simpleMM' ? 1.32 : curve.strategy === 'momentum' ? 0.87 : curve.strategy === 'meanReversion' ? -0.45 : 0.95,
      sortino: curve.strategy === 'simpleArb' ? 3.21 : curve.strategy === 'simpleMM' ? 1.89 : curve.strategy === 'momentum' ? 1.12 : curve.strategy === 'meanReversion' ? -0.62 : 1.23,
      winRate: curve.strategy === 'simpleArb' ? 68 : curve.strategy === 'simpleMM' ? 55 : curve.strategy === 'momentum' ? 41 : curve.strategy === 'meanReversion' ? 33 : null,
      profitFactor: curve.strategy === 'simpleArb' ? 2.12 : curve.strategy === 'simpleMM' ? 1.45 : curve.strategy === 'momentum' ? 0.82 : curve.strategy === 'meanReversion' ? 0.56 : null,
      trades: curve.strategy === 'simpleArb' ? 142 : curve.strategy === 'simpleMM' ? 89 : curve.strategy === 'momentum' ? 34 : curve.strategy === 'meanReversion' ? 12 : null,
      avgDuration: curve.strategy === 'simpleArb' ? 2.3 : curve.strategy === 'simpleMM' ? 5.1 : curve.strategy === 'momentum' ? 8.4 : curve.strategy === 'meanReversion' ? 12.2 : null
    }
  }, [])

  const strategyMetrics = useMemo(
    () => filteredCurves.map((curve) => ({
      strategy: curve.strategy,
      ...getStrategyMetrics(curve)
    })),
    [filteredCurves, getStrategyMetrics]
  )

  // Find best/worst for each metric
  const getBestWorst = (metric: keyof ReturnType<typeof getStrategyMetrics>) => {
    const values = strategyMetrics.map((m) => m[metric] as number).filter((v) => v !== null)
    const best = Math.max(...values)
    const worst = Math.min(...values)
    return { best, worst }
  }

  const getCellColor = (value: number | null, metric: keyof ReturnType<typeof getStrategyMetrics>) => {
    if (value === null) return ''
    const { best, worst } = getBestWorst(metric)
    if (value === best) return 'text-buy-green'
    if (value === worst) return 'text-sell-red'
    return ''
  }

  return (
    <div className="h-full flex flex-col p-2 gap-2 overflow-y-auto">
      {/* Section 1: Strategy Comparison */}
      <Card className="p-3 space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xs font-semibold text-muted-foreground">STRATEGY COMPARISON</h2>
          <Select
            value={selectedStrategies.join(',')}
            onValueChange={(value: string) => setSelectedStrategies(value.split(','))}
          >
            <SelectTrigger className="w-64 h-7 text-xs">
              <SelectValue placeholder="Select strategies" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="simpleArb,simpleMM,Buy & Hold BTC">Simple Arb + MM + Benchmark</SelectItem>
              <SelectItem value="simpleArb,simpleMM,momentum,meanReversion">All Strategies</SelectItem>
              <SelectItem value="simpleArb,momentum">Arb vs Momentum</SelectItem>
              <SelectItem value="simpleMM,meanReversion">MM vs Mean Reversion</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {/* Equity curves */}
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={combinedEquityData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#333" />
              <XAxis
                dataKey="day"
                stroke="#666"
                tick={{ fontSize: 10 }}
                label={{ value: 'Days', position: 'insideBottom', offset: -5, fontSize: 10 }}
              />
              <YAxis
                stroke="#666"
                tick={{ fontSize: 10 }}
                label={{ value: 'Equity ($)', angle: -90, position: 'insideLeft', fontSize: 10 }}
              />
              <Tooltip
                contentStyle={{ backgroundColor: '#1a1a1a', border: '1px solid #333', fontSize: 11 }}
                formatter={(value: number) => `$${value.toFixed(0)}`}
              />
              <Legend wrapperStyle={{ fontSize: 10 }} />
              {filteredCurves.map((curve) => (
                <Line
                  key={curve.strategy}
                  type="monotone"
                  dataKey={curve.strategy}
                  stroke={curve.color}
                  strokeWidth={curve.strategy === 'Buy & Hold BTC' ? 1 : 2}
                  strokeDasharray={curve.strategy === 'Buy & Hold BTC' ? '5 5' : '0'}
                  dot={false}
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Comparison table */}
        <div className="overflow-x-auto">
          <table className="w-full text-xs font-mono">
            <thead className="border-b border-border">
              <tr className="text-muted-foreground text-[10px]">
                <th className="text-left p-1.5 font-medium">METRIC</th>
                {strategyMetrics.map((m) => (
                  <th key={m.strategy} className="text-right p-1.5 font-medium">{m.strategy}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Total Return</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${getCellColor(m.totalReturn, 'totalReturn')}`}>
                    {formatPercent(m.totalReturn / 100)}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Annual Return</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${getCellColor(m.annualReturn, 'annualReturn')}`}>
                    {formatPercent(m.annualReturn / 100)}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Sharpe</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${getCellColor(m.sharpe, 'sharpe')}`}>
                    {m.sharpe.toFixed(2)}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Sortino</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${getCellColor(m.sortino, 'sortino')}`}>
                    {m.sortino.toFixed(2)}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Max Drawdown</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${getCellColor(-m.maxDrawdown, 'maxDrawdown')}`}>
                    -{m.maxDrawdown.toFixed(1)}%
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Win Rate</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${m.winRate !== null ? getCellColor(m.winRate, 'winRate') : ''}`}>
                    {m.winRate !== null ? `${m.winRate}%` : '—'}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Profit Factor</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className={`p-1.5 text-right ${m.profitFactor !== null ? getCellColor(m.profitFactor, 'profitFactor') : ''}`}>
                    {m.profitFactor !== null ? m.profitFactor.toFixed(2) : '—'}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Trades</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className="p-1.5 text-right">
                    {m.trades !== null ? m.trades : '—'}
                  </td>
                ))}
              </tr>
              <tr className="border-b border-border/50">
                <td className="p-1.5">Avg Duration</td>
                {strategyMetrics.map((m) => (
                  <td key={m.strategy} className="p-1.5 text-right">
                    {m.avgDuration !== null ? `${m.avgDuration.toFixed(1)}h` : '—'}
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      </Card>

      {/* Section 2: Backtest Results Viewer */}
      <Card className="p-3 space-y-3">
        <h2 className="text-xs font-semibold text-muted-foreground">BACKTEST RUNS</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-xs font-mono">
            <thead className="border-b border-border">
              <tr className="text-muted-foreground text-[10px]">
                <th className="text-left p-1.5 font-medium">RUN ID</th>
                <th className="text-left p-1.5 font-medium">STRATEGY</th>
                <th className="text-left p-1.5 font-medium">PAIR</th>
                <th className="text-left p-1.5 font-medium">PERIOD</th>
                <th className="text-right p-1.5 font-medium">SHARPE</th>
                <th className="text-right p-1.5 font-medium">RETURN</th>
                <th className="text-right p-1.5 font-medium">MAX DD</th>
                <th className="text-left p-1.5 font-medium">STATUS</th>
              </tr>
            </thead>
            <tbody>
              {mockBacktestRuns.map((run) => (
                <tr
                  key={run.runId}
                  className="border-b border-border/50 hover:bg-card-hover cursor-pointer"
                  onClick={() => setExpandedBacktest(expandedBacktest === run.runId ? null : run.runId)}
                >
                  <td className="p-1.5 font-semibold">{run.runId}</td>
                  <td className="p-1.5">{run.strategy}</td>
                  <td className="p-1.5">{run.pair}</td>
                  <td className="p-1.5">{run.period}</td>
                  <td className="p-1.5 text-right">{run.sharpe.toFixed(2)}</td>
                  <td className={`p-1.5 text-right ${run.returnPct >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                    {formatPercent(run.returnPct / 100)}
                  </td>
                  <td className="p-1.5 text-right">-{run.maxDrawdownPct.toFixed(1)}%</td>
                  <td className="p-1.5">
                    <span
                      className={`px-1.5 py-0.5 rounded text-[9px] ${
                        run.status === 'Complete' ? 'bg-buy-green/20 text-buy-green' :
                        run.status === 'Running' ? 'bg-pending-yellow/20 text-pending-yellow' :
                        'bg-sell-red/20 text-sell-red'
                      }`}
                    >
                      {run.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Section 3: ML Model Performance + Section 4: Parameter Optimization (side by side) */}
      <div className="grid grid-cols-2 gap-2">
        {/* ML Model Performance */}
        <Card className="p-3 space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-xs font-semibold text-muted-foreground">ML MODEL PERFORMANCE</h2>
            <Select value={selectedModel} onValueChange={(v: string) => setSelectedModel(v as typeof selectedModel)}>
              <SelectTrigger className="w-36 h-7 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="LSTM">LSTM</SelectItem>
                <SelectItem value="Transformer">Transformer</SelectItem>
                <SelectItem value="XGBoost">XGBoost</SelectItem>
                <SelectItem value="N-BEATS">N-BEATS</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Prediction vs Actual */}
          <div className="h-48">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={mlPredictions}>
                <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                <XAxis dataKey="time" stroke="#666" tick={{ fontSize: 9 }} tickFormatter={(t) => new Date(t * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} />
                <YAxis stroke="#666" tick={{ fontSize: 9 }} domain={['dataMin - 500', 'dataMax + 500']} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#1a1a1a', border: '1px solid #333', fontSize: 10 }}
                  formatter={(value: number) => formatPrice(value, 2)}
                />
                <Line type="monotone" dataKey="actual" stroke="#00c853" strokeWidth={2} dot={false} name="Actual" />
                <Line type="monotone" dataKey="predicted" stroke="#ff9800" strokeWidth={1.5} strokeDasharray="5 5" dot={false} name="Predicted" />
                <Line type="monotone" dataKey="confidenceUpper" stroke="#666" strokeWidth={0.5} dot={false} strokeDasharray="2 2" name="Upper" />
                <Line type="monotone" dataKey="confidenceLower" stroke="#666" strokeWidth={0.5} dot={false} strokeDasharray="2 2" name="Lower" />
              </LineChart>
            </ResponsiveContainer>
          </div>

          {/* Feature Importance */}
          <div>
            <h3 className="text-[10px] font-medium text-muted-foreground mb-2">FEATURE IMPORTANCE</h3>
            <div className="h-64 overflow-y-auto">
              <ResponsiveContainer width="100%" height={mockFeatureImportance.length * 20}>
                <BarChart data={mockFeatureImportance} layout="vertical" margin={{ left: 80, right: 10 }}>
                  <XAxis type="number" stroke="#666" tick={{ fontSize: 9 }} />
                  <YAxis dataKey="feature" type="category" stroke="#666" tick={{ fontSize: 9 }} width={75} />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#1a1a1a', border: '1px solid #333', fontSize: 10 }}
                    formatter={(value: number) => value.toFixed(3)}
                  />
                  <Bar dataKey="importance">
                    {mockFeatureImportance.map((entry) => (
                      <Cell key={entry.feature} fill={entry.category === 'Technical' ? '#ff9800' : entry.category === 'Volume' ? '#2196f3' : '#00c853'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Model Metrics */}
          <div className="grid grid-cols-5 gap-2">
            <div className="bg-card-hover p-2 rounded">
              <div className="text-[9px] text-muted-foreground">MSE</div>
              <div className="text-xs font-mono">{mockMLModelMetrics.mse.toFixed(4)}</div>
            </div>
            <div className="bg-card-hover p-2 rounded">
              <div className="text-[9px] text-muted-foreground">MAE</div>
              <div className="text-xs font-mono">{mockMLModelMetrics.mae.toFixed(3)}</div>
            </div>
            <div className="bg-card-hover p-2 rounded">
              <div className="text-[9px] text-muted-foreground">R²</div>
              <div className="text-xs font-mono">{mockMLModelMetrics.r2.toFixed(2)}</div>
            </div>
            <div className="bg-card-hover p-2 rounded">
              <div className="text-[9px] text-muted-foreground">DIR ACC</div>
              <div className="text-xs font-mono">{mockMLModelMetrics.directionAccuracy.toFixed(1)}%</div>
            </div>
            <div className="bg-card-hover p-2 rounded">
              <div className="text-[9px] text-muted-foreground">SHARPE</div>
              <div className="text-xs font-mono">{mockMLModelMetrics.sharpeSIgnal.toFixed(2)}</div>
            </div>
          </div>

          {/* Training History */}
          <div>
            <h3 className="text-[10px] font-medium text-muted-foreground mb-2">TRAINING HISTORY</h3>
            <div className="h-32">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={trainingHistory}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                  <XAxis dataKey="epoch" stroke="#666" tick={{ fontSize: 9 }} label={{ value: 'Epoch', position: 'insideBottom', offset: -5, fontSize: 9 }} />
                  <YAxis stroke="#666" tick={{ fontSize: 9 }} label={{ value: 'Loss', angle: -90, position: 'insideLeft', fontSize: 9 }} />
                  <Tooltip contentStyle={{ backgroundColor: '#1a1a1a', border: '1px solid #333', fontSize: 10 }} />
                  <Legend wrapperStyle={{ fontSize: 9 }} />
                  <Line type="monotone" dataKey="trainLoss" stroke="#2196f3" strokeWidth={1.5} dot={false} name="Train Loss" />
                  <Line type="monotone" dataKey="valLoss" stroke="#ff9800" strokeWidth={1.5} dot={false} name="Val Loss" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </Card>

        {/* Parameter Optimization */}
        <Card className="p-3 space-y-3">
          <h2 className="text-xs font-semibold text-muted-foreground">PARAMETER OPTIMIZATION</h2>

          {/* Heatmap */}
          <div>
            <h3 className="text-[10px] font-medium text-muted-foreground mb-2">SHARPE BY PARAMETERS</h3>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <ScatterChart margin={{ top: 10, right: 10, bottom: 20, left: 40 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                  <XAxis
                    type="number"
                    dataKey="fastPeriod"
                    name="Fast Period"
                    stroke="#666"
                    tick={{ fontSize: 9 }}
                    label={{ value: 'Fast Period', position: 'insideBottom', offset: -10, fontSize: 9 }}
                  />
                  <YAxis
                    type="number"
                    dataKey="slowPeriod"
                    name="Slow Period"
                    stroke="#666"
                    tick={{ fontSize: 9 }}
                    label={{ value: 'Slow Period', angle: -90, position: 'insideLeft', fontSize: 9 }}
                  />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#1a1a1a', border: '1px solid #333', fontSize: 10 }}
                    formatter={(value: number, name: string) => {
                      if (name === 'sharpe') return value.toFixed(2)
                      return value
                    }}
                  />
                  <Scatter name="Sharpe" data={optimizationHeatmap} fill="#8884d8">
                    {optimizationHeatmap.map((entry, index) => (
                      <Cell
                        key={`cell-${index}`}
                        fill={
                          entry.sharpe > 2.3 ? '#00c853' :
                          entry.sharpe > 1.8 ? '#8bc34a' :
                          entry.sharpe > 1.2 ? '#cddc39' :
                          entry.sharpe > 0.8 ? '#ff9800' :
                          '#f44336'
                        }
                      />
                    ))}
                  </Scatter>
                </ScatterChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Top 10 Parameter Sets */}
          <div>
            <h3 className="text-[10px] font-medium text-muted-foreground mb-2">TOP 10 PARAMETER SETS</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-xs font-mono">
                <thead className="border-b border-border">
                  <tr className="text-muted-foreground text-[9px]">
                    <th className="text-left p-1 font-medium">RANK</th>
                    <th className="text-right p-1 font-medium">FAST</th>
                    <th className="text-right p-1 font-medium">SLOW</th>
                    <th className="text-right p-1 font-medium">THRESH</th>
                    <th className="text-right p-1 font-medium">SHARPE</th>
                    <th className="text-right p-1 font-medium">RETURN</th>
                    <th className="text-right p-1 font-medium">MAX DD</th>
                  </tr>
                </thead>
                <tbody>
                  {mockTopParameterSets.map((set) => (
                    <tr key={set.rank} className="border-b border-border/50 hover:bg-card-hover">
                      <td className="p-1">{set.rank}</td>
                      <td className="p-1 text-right">{set.fastPeriod}</td>
                      <td className="p-1 text-right">{set.slowPeriod}</td>
                      <td className="p-1 text-right">{set.threshold.toFixed(3)}</td>
                      <td className="p-1 text-right text-buy-green">{set.sharpe.toFixed(2)}</td>
                      <td className="p-1 text-right text-buy-green">{formatPercent(set.returnPct / 100)}</td>
                      <td className="p-1 text-right">-{set.maxDrawdownPct.toFixed(1)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </Card>
      </div>

      {/* Section 5: Strategy Pipeline */}
      <Card className="p-3 space-y-3">
        <h2 className="text-xs font-semibold text-muted-foreground">STRATEGY PIPELINE</h2>
        <div className="space-y-2">
          {mockStrategyPipeline.map((pipeline) => (
            <div key={pipeline.strategy} className="flex items-center gap-4 p-2 bg-card-hover rounded">
              <div className="w-32 text-xs font-mono font-semibold">{pipeline.strategy}</div>
              <div className="flex items-center gap-2 flex-1">
                <div className={`flex items-center justify-center w-24 h-6 rounded text-[9px] font-medium ${pipeline.research ? 'bg-buy-green/20 text-buy-green' : 'bg-muted/20 text-muted-foreground'}`}>
                  Research {pipeline.research && '✓'}
                </div>
                <span className="text-muted-foreground">→</span>
                <div className={`flex items-center justify-center w-24 h-6 rounded text-[9px] font-medium ${pipeline.backtest ? 'bg-buy-green/20 text-buy-green' : 'bg-sell-red/20 text-sell-red'}`}>
                  Backtest {pipeline.backtest ? '✓' : '✗'}
                </div>
                <span className="text-muted-foreground">→</span>
                <div className={`flex items-center justify-center w-24 h-6 rounded text-[9px] font-medium ${pipeline.paperTrading ? 'bg-pending-yellow/20 text-pending-yellow' : 'bg-muted/20 text-muted-foreground'}`}>
                  Paper {pipeline.paperTrading && '🔄'}
                </div>
                <span className="text-muted-foreground">→</span>
                <div className={`flex items-center justify-center w-24 h-6 rounded text-[9px] font-medium ${pipeline.live ? 'bg-buy-green/20 text-buy-green' : 'bg-muted/20 text-muted-foreground'}`}>
                  Live {pipeline.live && '✓'}
                </div>
              </div>
              <div className="text-xs font-mono text-muted-foreground min-w-32 text-right">
                {pipeline.liveSince && <div>Live since {pipeline.liveSince}</div>}
                {pipeline.paperTradingSince && <div>{pipeline.paperTradingSince}, {pipeline.paperTradingPnL && `${pipeline.paperTradingPnL > 0 ? '+' : ''}${pipeline.paperTradingPnL.toFixed(1)}%`}</div>}
                {!pipeline.liveSince && !pipeline.paperTradingSince && pipeline.backtest === false && <div>Sharpe &lt; 1.0</div>}
              </div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  )
}
