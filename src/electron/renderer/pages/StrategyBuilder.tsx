import { useState } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '../components/ui/card'
import { Button } from '../components/ui/button'
import { Input } from '../components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue
} from '../components/ui/select'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts'
import {
  strategyTemplates,
  generateMockBacktestResult,
  type BacktestResult,
  type StrategyTemplate
} from '../lib/strategy-builder-mock'
import { Loader2 } from 'lucide-react'

interface ComparisonRow {
  id: number
  template: string
  symbol: string
  return: number
  sharpe: number
  maxDD: number
  winRate: number
  trades: number
  pf: number
}

export function StrategyBuilder() {
  const [selectedTemplate, setSelectedTemplate] = useState<StrategyTemplate>(strategyTemplates[0])
  const [symbol, setSymbol] = useState('BTCUSD')
  const [exchange, setExchange] = useState('binance')
  const [params, setParams] = useState(selectedTemplate.defaultParams)
  const [result, setResult] = useState<BacktestResult | null>(null)
  const [isRunning, setIsRunning] = useState(false)
  const [comparisonRows, setComparisonRows] = useState<ComparisonRow[]>([])

  const handleTemplateChange = (templateName: string) => {
    const template = strategyTemplates.find((t) => t.name === templateName)!
    setSelectedTemplate(template)
    setParams(template.defaultParams)
  }

  const handleParamChange = (key: string, value: string) => {
    setParams({ ...params, [key]: parseFloat(value) || 0 })
  }

  const handleRunBacktest = () => {
    setIsRunning(true)
    // Simulate 2 second backtest
    setTimeout(() => {
      const backtestResult = generateMockBacktestResult({
        template: selectedTemplate.name,
        symbol,
        exchange,
        params
      })
      setResult(backtestResult)
      setIsRunning(false)
    }, 2000)
  }

  const handleAddToComparison = () => {
    if (!result) return
    const newRow: ComparisonRow = {
      id: comparisonRows.length + 1,
      template: selectedTemplate.name,
      symbol,
      return: result.metrics.totalReturn,
      sharpe: result.metrics.sharpe,
      maxDD: result.metrics.maxDrawdown,
      winRate: result.metrics.winRate,
      trades: result.metrics.totalTrades,
      pf: result.metrics.profitFactor
    }
    setComparisonRows([...comparisonRows, newRow])
  }

  return (
    <div className="h-full grid grid-cols-12 gap-2 p-2">
      {/* Left panel - Configuration */}
      <div className="col-span-4 flex flex-col gap-2">
        <Card className="flex-1">
          <CardHeader>
            <CardTitle className="text-base">Strategy Configuration</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Template selection */}
            <div className="space-y-2">
              <label className="text-xs text-muted-foreground">Template</label>
              <Select value={selectedTemplate.name} onValueChange={handleTemplateChange}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {strategyTemplates.map((template) => (
                    <SelectItem key={template.name} value={template.name}>
                      {template.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">{selectedTemplate.description}</p>
            </div>

            {/* Symbol selection */}
            <div className="space-y-2">
              <label className="text-xs text-muted-foreground">Symbol</label>
              <Select value={symbol} onValueChange={setSymbol}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="BTCUSD">BTCUSD</SelectItem>
                  <SelectItem value="ETHUSD">ETHUSD</SelectItem>
                  <SelectItem value="SOLUSD">SOLUSD</SelectItem>
                  <SelectItem value="ADAUSD">ADAUSD</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Exchange selection */}
            <div className="space-y-2">
              <label className="text-xs text-muted-foreground">Exchange</label>
              <Select value={exchange} onValueChange={setExchange}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="binance">Binance</SelectItem>
                  <SelectItem value="coinbase">Coinbase</SelectItem>
                  <SelectItem value="kraken">Kraken</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Parameters */}
            <div className="space-y-3 pt-2 border-t border-border">
              <label className="text-xs text-muted-foreground font-semibold">Parameters</label>
              {Object.entries(params).map(([key, value]) => (
                <div key={key} className="space-y-1">
                  <label className="text-xs text-muted-foreground capitalize">
                    {key.replace(/_/g, ' ')}
                  </label>
                  <Input
                    type="number"
                    value={value}
                    onChange={(e) => handleParamChange(key, e.target.value)}
                    className="h-8 text-xs font-mono"
                    step={key.includes('pct') ? 0.1 : 1}
                  />
                </div>
              ))}
            </div>

            {/* Action buttons */}
            <div className="flex flex-col gap-2 pt-4">
              <Button
                onClick={handleRunBacktest}
                disabled={isRunning}
                className="w-full bg-primary hover:bg-primary/90"
              >
                {isRunning ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Running...
                  </>
                ) : (
                  'Run Backtest'
                )}
              </Button>
              <Button
                onClick={handleAddToComparison}
                disabled={!result}
                variant="outline"
                className="w-full"
              >
                Add to Comparison
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Right panel - Results */}
      <div className="col-span-8 flex flex-col gap-2 overflow-y-auto">
        {result ? (
          <>
            {/* Equity curve */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Equity Curve</CardTitle>
              </CardHeader>
              <CardContent>
                <ResponsiveContainer width="100%" height={200}>
                  <AreaChart data={result.equityCurve}>
                    <defs>
                      <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#16a34a" stopOpacity={0.3} />
                        <stop offset="95%" stopColor="#16a34a" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#26262a" />
                    <XAxis dataKey="time" stroke="#6b6b80" tick={{ fontSize: 10 }} />
                    <YAxis stroke="#6b6b80" tick={{ fontSize: 10 }} />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: '#141419',
                        border: '1px solid #26262a',
                        borderRadius: '4px',
                        fontSize: '12px'
                      }}
                    />
                    <Area
                      type="monotone"
                      dataKey="equity"
                      stroke="#16a34a"
                      fill="url(#equityGradient)"
                      strokeWidth={2}
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>

            {/* Metrics */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Performance Metrics</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-6 gap-4">
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">Return</div>
                    <div className={`text-sm font-mono font-semibold ${
                      result.metrics.totalReturn >= 0 ? 'text-buy-green' : 'text-sell-red'
                    }`}>
                      {result.metrics.totalReturn >= 0 ? '+' : ''}{result.metrics.totalReturn}%
                    </div>
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">Sharpe</div>
                    <div className="text-sm font-mono font-semibold">{result.metrics.sharpe}</div>
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">Max DD</div>
                    <div className="text-sm font-mono font-semibold text-sell-red">
                      -{result.metrics.maxDrawdown}%
                    </div>
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">Win Rate</div>
                    <div className="text-sm font-mono font-semibold">{result.metrics.winRate}%</div>
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">Trades</div>
                    <div className="text-sm font-mono font-semibold">{result.metrics.totalTrades}</div>
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-muted-foreground">PF</div>
                    <div className="text-sm font-mono font-semibold">{result.metrics.profitFactor}</div>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* P&L Distribution */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">P&L Distribution</CardTitle>
              </CardHeader>
              <CardContent>
                <ResponsiveContainer width="100%" height={150}>
                  <BarChart data={result.pnlDistribution}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#26262a" />
                    <XAxis dataKey="range" stroke="#6b6b80" tick={{ fontSize: 10 }} />
                    <YAxis stroke="#6b6b80" tick={{ fontSize: 10 }} />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: '#141419',
                        border: '1px solid #26262a',
                        borderRadius: '4px',
                        fontSize: '12px'
                      }}
                    />
                    <Bar dataKey="count" fill="#ff6b35" />
                  </BarChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>

            {/* Trade log */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Trade Log (Last 20)</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-border">
                        <th className="text-left font-medium text-muted-foreground py-2">#</th>
                        <th className="text-left font-medium text-muted-foreground py-2">Entry</th>
                        <th className="text-left font-medium text-muted-foreground py-2">Exit</th>
                        <th className="text-left font-medium text-muted-foreground py-2">Side</th>
                        <th className="text-right font-medium text-muted-foreground py-2">Entry $</th>
                        <th className="text-right font-medium text-muted-foreground py-2">Exit $</th>
                        <th className="text-right font-medium text-muted-foreground py-2">P&L</th>
                        <th className="text-right font-medium text-muted-foreground py-2">P&L%</th>
                        <th className="text-right font-medium text-muted-foreground py-2">Duration</th>
                      </tr>
                    </thead>
                    <tbody>
                      {result.trades.slice(0, 20).map((trade) => (
                        <tr key={trade.id} className="border-b border-border/50 hover:bg-muted/30">
                          <td className="py-2 font-mono">{trade.id}</td>
                          <td className="py-2 font-mono text-xs">
                            {trade.entry.toLocaleString('en-US', {
                              month: '2-digit',
                              day: '2-digit',
                              hour: '2-digit',
                              minute: '2-digit'
                            })}
                          </td>
                          <td className="py-2 font-mono text-xs">
                            {trade.exit.toLocaleString('en-US', {
                              month: '2-digit',
                              day: '2-digit',
                              hour: '2-digit',
                              minute: '2-digit'
                            })}
                          </td>
                          <td className="py-2">
                            <span className={`font-semibold ${
                              trade.side === 'long' ? 'text-buy-green' : 'text-sell-red'
                            }`}>
                              {trade.side.toUpperCase()}
                            </span>
                          </td>
                          <td className="py-2 text-right font-mono">${trade.entryPrice.toFixed(2)}</td>
                          <td className="py-2 text-right font-mono">${trade.exitPrice.toFixed(2)}</td>
                          <td className={`py-2 text-right font-mono font-semibold ${
                            trade.pnl >= 0 ? 'text-buy-green' : 'text-sell-red'
                          }`}>
                            {trade.pnl >= 0 ? '+' : ''}${trade.pnl.toFixed(2)}
                          </td>
                          <td className={`py-2 text-right font-mono font-semibold ${
                            trade.pnlPct >= 0 ? 'text-buy-green' : 'text-sell-red'
                          }`}>
                            {trade.pnlPct >= 0 ? '+' : ''}{trade.pnlPct.toFixed(2)}%
                          </td>
                          <td className="py-2 text-right font-mono text-muted-foreground">{trade.duration}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>

            {/* Comparison table */}
            {comparisonRows.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Strategy Comparison</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="border-b border-border">
                          <th className="text-left font-medium text-muted-foreground py-2">#</th>
                          <th className="text-left font-medium text-muted-foreground py-2">Template</th>
                          <th className="text-left font-medium text-muted-foreground py-2">Symbol</th>
                          <th className="text-right font-medium text-muted-foreground py-2">Return</th>
                          <th className="text-right font-medium text-muted-foreground py-2">Sharpe</th>
                          <th className="text-right font-medium text-muted-foreground py-2">Max DD</th>
                          <th className="text-right font-medium text-muted-foreground py-2">Win Rate</th>
                          <th className="text-right font-medium text-muted-foreground py-2">Trades</th>
                          <th className="text-right font-medium text-muted-foreground py-2">PF</th>
                        </tr>
                      </thead>
                      <tbody>
                        {comparisonRows.map((row) => (
                          <tr key={row.id} className="border-b border-border/50 hover:bg-muted/30">
                            <td className="py-2 font-mono">{row.id}</td>
                            <td className="py-2">{row.template}</td>
                            <td className="py-2 font-mono">{row.symbol}</td>
                            <td className={`py-2 text-right font-mono font-semibold ${
                              row.return >= 0 ? 'text-buy-green' : 'text-sell-red'
                            }`}>
                              {row.return >= 0 ? '+' : ''}{row.return}%
                            </td>
                            <td className="py-2 text-right font-mono">{row.sharpe}</td>
                            <td className="py-2 text-right font-mono text-sell-red">-{row.maxDD}%</td>
                            <td className="py-2 text-right font-mono">{row.winRate}%</td>
                            <td className="py-2 text-right font-mono">{row.trades}</td>
                            <td className="py-2 text-right font-mono">{row.pf}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </>
        ) : (
          <Card className="flex-1 flex items-center justify-center">
            <CardContent>
              <p className="text-muted-foreground text-sm">
                Configure your strategy and click "Run Backtest" to see results
              </p>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
