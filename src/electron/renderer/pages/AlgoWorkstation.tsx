import { useState, memo } from 'react'
import Editor from '@monaco-editor/react'
import { Button } from '../components/ui/button'
import { Play, Save, FolderOpen, Loader2 } from 'lucide-react'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'

interface BacktestResult {
  equityCurve: Array<{ time: string; equity: number }>
  metrics: {
    return: number
    sharpe: number
    maxDrawdown: number
    winRate: number
  }
  console: string[]
}

const TEMPLATES = {
  blank: {
    name: 'Blank',
    code: '# Write your strategy here\n\n'
  },
  sma_crossover: {
    name: 'SMA Crossover',
    code: `# SMA Crossover Strategy
from medusa.strategies import BaseStrategy
import pandas as pd

class SMACrossover(BaseStrategy):
    def __init__(self, fast=20, slow=50):
        self.fast = fast
        self.slow = slow

    def generate_signals(self, df):
        df['sma_fast'] = df['close'].rolling(self.fast).mean()
        df['sma_slow'] = df['close'].rolling(self.slow).mean()
        entries = df['sma_fast'] > df['sma_slow']
        exits = df['sma_fast'] < df['sma_slow']
        return entries, exits
`
  },
  mean_reversion: {
    name: 'Mean Reversion',
    code: `# Mean Reversion Strategy
from medusa.strategies import BaseStrategy
import pandas as pd

class MeanReversion(BaseStrategy):
    def __init__(self, window=20, std_dev=2.0):
        self.window = window
        self.std_dev = std_dev

    def generate_signals(self, df):
        df['mean'] = df['close'].rolling(self.window).mean()
        df['std'] = df['close'].rolling(self.window).std()
        df['upper_band'] = df['mean'] + (df['std'] * self.std_dev)
        df['lower_band'] = df['mean'] - (df['std'] * self.std_dev)

        # Buy when price crosses below lower band
        entries = df['close'] < df['lower_band']
        # Sell when price crosses above upper band
        exits = df['close'] > df['upper_band']
        return entries, exits
`
  },
  momentum: {
    name: 'Momentum',
    code: `# Momentum Strategy
from medusa.strategies import BaseStrategy
import pandas as pd

class Momentum(BaseStrategy):
    def __init__(self, lookback=14, threshold=0.02):
        self.lookback = lookback
        self.threshold = threshold

    def generate_signals(self, df):
        # Calculate momentum as percentage change
        df['momentum'] = df['close'].pct_change(self.lookback)

        # Buy when momentum exceeds threshold
        entries = df['momentum'] > self.threshold
        # Sell when momentum falls below negative threshold
        exits = df['momentum'] < -self.threshold
        return entries, exits
`
  }
}

// Memoized chart component
const EquityCurveChart = memo(function EquityCurveChart({ data }: { data: Array<{ time: string; equity: number }> }) {
  return (
    <div role="img" aria-label="Backtest equity curve showing portfolio value over time" style={{ height: 'calc(100% - 24px)' }}>
      <ResponsiveContainer width="100%" height="100%">
      <AreaChart data={data}>
        <defs>
          <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
            <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
          </linearGradient>
        </defs>
        <XAxis
          dataKey="time"
          tick={{ fontSize: 10, fill: '#888' }}
          stroke="#444"
          tickLine={false}
        />
        <YAxis
          tick={{ fontSize: 10, fill: '#888' }}
          stroke="#444"
          tickLine={false}
          tickFormatter={(value) => `$${(value / 1000).toFixed(0)}k`}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1a1a1a',
            border: '1px solid #333',
            borderRadius: '4px',
            fontSize: '11px'
          }}
          formatter={(value: number) => [`$${value.toLocaleString()}`, 'Equity']}
        />
        <Area
          type="monotone"
          dataKey="equity"
          stroke="#10b981"
          strokeWidth={2}
          fill="url(#equityGradient)"
        />
      </AreaChart>
    </ResponsiveContainer>
    </div>
  )
})

export function AlgoWorkstation() {
  const [selectedTemplate, setSelectedTemplate] = useState<keyof typeof TEMPLATES>('blank')
  const [code, setCode] = useState(TEMPLATES.blank.code)
  const [isRunning, setIsRunning] = useState(false)
  const [result, setResult] = useState<BacktestResult | null>(null)

  const handleTemplateChange = (template: keyof typeof TEMPLATES) => {
    setSelectedTemplate(template)
    setCode(TEMPLATES[template].code)
  }

  const handleRunBacktest = async () => {
    setIsRunning(true)
    setResult(null)

    // Simulate backtest execution with 2-second delay
    await new Promise((resolve) => setTimeout(resolve, 2000))

    // Generate mock results
    const mockEquityCurve = Array.from({ length: 100 }, (_, i) => {
      const baseEquity = 100000
      const trend = i * 150
      const volatility = Math.sin(i * 0.2) * 5000
      return {
        time: new Date(Date.now() - (100 - i) * 86400000).toLocaleDateString(),
        equity: baseEquity + trend + volatility
      }
    })

    const mockResult: BacktestResult = {
      equityCurve: mockEquityCurve,
      metrics: {
        return: 14.67,
        sharpe: 2.14,
        maxDrawdown: -8.23,
        winRate: 58.5
      },
      console: [
        'Loading historical data from kdb+ HDB...',
        'Symbol: BTCUSD',
        'Period: 2024-01-01 to 2024-12-31',
        'Generating signals...',
        'Running backtest...',
        '142 trades executed',
        'Average trade duration: 3.2 days',
        'Best trade: +$3,245',
        'Worst trade: -$1,872',
        'Sharpe Ratio: 2.14',
        'Backtest complete.'
      ]
    }

    setResult(mockResult)
    setIsRunning(false)
  }

  const handleSave = () => {
    const scripts = JSON.parse(localStorage.getItem('medusa-algo-scripts') || '{}')
    const name = prompt('Enter script name:')
    if (name) {
      scripts[name] = code
      localStorage.setItem('medusa-algo-scripts', JSON.stringify(scripts))
      alert('Script saved!')
    }
  }

  const handleLoad = () => {
    const scripts = JSON.parse(localStorage.getItem('medusa-algo-scripts') || '{}')
    const names = Object.keys(scripts)
    if (names.length === 0) {
      alert('No saved scripts found')
      return
    }

    const name = prompt(`Enter script name (available: ${names.join(', ')}):`)
    if (name && scripts[name]) {
      setCode(scripts[name])
    } else if (name) {
      alert('Script not found')
    }
  }

  return (
    <div className="h-full flex flex-col bg-background">
      {/* Toolbar */}
      <div className="h-12 border-b border-border px-4 flex items-center justify-between bg-card">
        <div className="flex items-center gap-4">
          <span className="text-sm font-semibold text-foreground">Algo Workstation</span>
          <div className="flex items-center gap-2">
            <label className="text-xs text-muted-foreground">Template:</label>
            <select
              value={selectedTemplate}
              onChange={(e) => handleTemplateChange(e.target.value as keyof typeof TEMPLATES)}
              className="h-8 px-2 text-xs bg-background border border-border rounded text-foreground"
            >
              {Object.entries(TEMPLATES).map(([key, { name }]) => (
                <option key={key} value={key}>
                  {name}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Button size="sm" variant="outline" onClick={handleSave}>
            <Save className="w-3.5 h-3.5 mr-1.5" />
            Save
          </Button>
          <Button size="sm" variant="outline" onClick={handleLoad}>
            <FolderOpen className="w-3.5 h-3.5 mr-1.5" />
            Load
          </Button>
          <Button
            size="sm"
            onClick={handleRunBacktest}
            disabled={isRunning}
            className="bg-orange-600 hover:bg-orange-700 text-white"
          >
            {isRunning ? (
              <Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" />
            ) : (
              <Play className="w-3.5 h-3.5 mr-1.5" />
            )}
            Run Backtest
          </Button>
        </div>
      </div>

      {/* Split Panel Layout */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left: Editor (60%) */}
        <div className="w-[60%] border-r border-border">
          <Editor
            height="100%"
            defaultLanguage="python"
            theme="vs-dark"
            value={code}
            onChange={(value) => setCode(value || '')}
            options={{
              minimap: { enabled: false },
              fontSize: 13,
              lineNumbers: 'on',
              scrollBeyondLastLine: false,
              automaticLayout: true,
              tabSize: 4,
              wordWrap: 'on',
              ariaLabel: 'Python strategy code editor'
            }}
          />
        </div>

        {/* Right: Results (40%) */}
        <div className="w-[40%] flex flex-col bg-card">
          {!result ? (
            <div className="flex-1 flex items-center justify-center text-muted-foreground text-sm">
              Configure your strategy and click Run Backtest
            </div>
          ) : (
            <>
              {/* Equity Curve */}
              <div className="h-[50%] border-b border-border p-4">
                <div className="text-xs font-semibold text-foreground mb-2">Equity Curve</div>
                <EquityCurveChart data={result.equityCurve} />
              </div>

              {/* Metrics Row */}
              <div className="px-4 py-3 border-b border-border">
                <div className="grid grid-cols-4 gap-4">
                  <div>
                    <div className="text-[10px] text-muted-foreground uppercase mb-1">
                      Return
                    </div>
                    <div className="text-lg font-semibold text-buy-green">
                      {result.metrics.return > 0 ? '+' : ''}
                      {result.metrics.return.toFixed(2)}%
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] text-muted-foreground uppercase mb-1">
                      Sharpe Ratio
                    </div>
                    <div className="text-lg font-semibold text-foreground">
                      {result.metrics.sharpe.toFixed(2)}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] text-muted-foreground uppercase mb-1">
                      Max Drawdown
                    </div>
                    <div className="text-lg font-semibold text-sell-red">
                      {result.metrics.maxDrawdown.toFixed(2)}%
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] text-muted-foreground uppercase mb-1">
                      Win Rate
                    </div>
                    <div className="text-lg font-semibold text-foreground">
                      {result.metrics.winRate.toFixed(1)}%
                    </div>
                  </div>
                </div>
              </div>

              {/* Console Output */}
              <div className="flex-1 overflow-auto p-4">
                <div className="text-[10px] font-semibold text-muted-foreground mb-2 uppercase">
                  Console
                </div>
                <div className="bg-black/40 rounded border border-border p-3 font-mono text-[11px] leading-relaxed text-gray-300">
                  {result.console.map((line, i) => (
                    <div key={i}>{line}</div>
                  ))}
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
