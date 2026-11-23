import { useState, useEffect } from 'react'
import { Card } from '../components/ui/card'
import { Button } from '../components/ui/button'
import { AlertTriangle, PauseCircle, TrendingUp, TrendingDown, Activity } from 'lucide-react'
import { useExchangesStore } from '../stores/exchanges'
import { useStrategiesStore } from '../stores/strategies'
import {
  AreaChart, Area, BarChart, Bar, LineChart, Line,
  ResponsiveContainer, XAxis, YAxis, Tooltip, Legend, CartesianGrid
} from 'recharts'

// Seeded data generator using Geometric Brownian Motion for realistic P&L
class MockDataGenerator {
  private pnlHistory: Array<{ time: string; pnl: number; realized: number; unrealized: number }> = []
  private varHistory: Array<{ time: string; var95: number; var99: number; cvar95: number }> = []

  constructor() {
    this.generateHistoricalPnL()
    this.generateVaRHistory()
  }

  private generateHistoricalPnL() {
    const now = Date.now()
    let totalPnL = 0
    let realizedPnL = 0
    let unrealizedPnL = 0

    // Generate 60 data points (last hour, 1-minute intervals)
    for (let i = 60; i >= 0; i--) {
      const timestamp = new Date(now - i * 60 * 1000)
      const time = timestamp.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })

      // GBM: drift=0.0001 (small upward bias), volatility=0.002
      const drift = 0.0001
      const volatility = 0.002
      const randomShock = (Math.random() - 0.5) * 2 * volatility
      const pnlChange = drift + randomShock

      totalPnL += pnlChange * 10000 // Scale to realistic $ values

      // 70% of P&L change goes to unrealized, 30% realized (periodic closes)
      if (Math.random() > 0.7) {
        realizedPnL += pnlChange * 10000 * 0.3
        unrealizedPnL += pnlChange * 10000 * 0.7
      } else {
        unrealizedPnL += pnlChange * 10000
      }

      this.pnlHistory.push({
        time,
        pnl: parseFloat(totalPnL.toFixed(2)),
        realized: parseFloat(realizedPnL.toFixed(2)),
        unrealized: parseFloat(unrealizedPnL.toFixed(2))
      })
    }
  }

  private generateVaRHistory() {
    const now = Date.now()
    // VaR computed over 30-day rolling window
    for (let i = 30; i >= 0; i--) {
      const timestamp = new Date(now - i * 24 * 60 * 60 * 1000)
      const time = timestamp.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })

      // VaR increases with volatility clustering (GARCH-like)
      const baseVaR = 2500 + Math.sin(i / 5) * 500 + (Math.random() - 0.5) * 200

      this.varHistory.push({
        time,
        var95: parseFloat(baseVaR.toFixed(2)),
        var99: parseFloat((baseVaR * 1.5).toFixed(2)),
        cvar95: parseFloat((baseVaR * 1.3).toFixed(2))
      })
    }
  }

  getPnLHistory() {
    return this.pnlHistory
  }

  getLatestPnL() {
    const latest = this.pnlHistory[this.pnlHistory.length - 1]
    return {
      total: latest.pnl,
      realized: latest.realized,
      unrealized: latest.unrealized,
      dayChange: latest.pnl - this.pnlHistory[0].pnl,
      dayChangePct: ((latest.pnl - this.pnlHistory[0].pnl) / Math.abs(this.pnlHistory[0].pnl || 1)) * 100
    }
  }

  getVaRHistory() {
    return this.varHistory
  }

  getLatestVaR() {
    return this.varHistory[this.varHistory.length - 1]
  }

  getPnLByStrategy(strategies: any[]) {
    return strategies.map(s => {
      const basePnL = (Math.random() - 0.3) * 5000 // Slight negative bias (70% win rate)
      return {
        name: s.name,
        realized: parseFloat((basePnL * 0.6).toFixed(2)),
        unrealized: parseFloat((basePnL * 0.4).toFixed(2)),
        total: parseFloat(basePnL.toFixed(2)),
        tradeCount: Math.floor(Math.random() * 200) + 50,
        winRate: parseFloat((Math.random() * 0.3 + 0.55).toFixed(2)) // 55-85%
      }
    })
  }

  getPnLByExchange(exchanges: any[]) {
    return exchanges.map(ex => {
      const basePnL = (Math.random() - 0.4) * 8000
      return {
        name: ex.exchange,
        realized: parseFloat((basePnL * 0.65).toFixed(2)),
        unrealized: parseFloat((basePnL * 0.35).toFixed(2)),
        total: parseFloat(basePnL.toFixed(2)),
        tradeCount: Math.floor(Math.random() * 300) + 100
      }
    })
  }

  getOrderFlowMetrics() {
    const now = Date.now()
    const metrics = []

    // Last 20 minutes, 1-minute granularity
    for (let i = 20; i >= 0; i--) {
      const timestamp = new Date(now - i * 60 * 1000)
      const time = timestamp.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })

      // Order flow varies throughout the trading session
      const baseRate = 50 + Math.sin(i / 3) * 20
      const ordersPerSec = parseFloat((baseRate + (Math.random() - 0.5) * 10).toFixed(2))
      const fillRate = parseFloat((0.85 + (Math.random() - 0.5) * 0.1).toFixed(3)) // 80-90%
      const rejectionRate = parseFloat((0.05 + (Math.random()) * 0.03).toFixed(3)) // 5-8%

      metrics.push({
        time,
        ordersPerSec,
        fillRate: fillRate * 100,
        rejectionRate: rejectionRate * 100
      })
    }

    return metrics
  }

  getPositionExposure(strategies: any[]) {
    // Heatmap data: strategy x asset class
    const assetClasses = ['BTC', 'ETH', 'SOL', 'MATIC', 'AVAX', 'DOT']
    const data = []

    for (const strategy of strategies) {
      for (const asset of assetClasses) {
        // Some strategies have high exposure to specific assets
        const exposure = Math.random() > 0.6
          ? (Math.random() - 0.5) * 100000 // Large position
          : (Math.random() - 0.5) * 20000  // Small position

        data.push({
          strategy: strategy.name,
          asset,
          exposure: parseFloat(exposure.toFixed(2)),
          exposurePct: parseFloat(((exposure / 150000) * 100).toFixed(1)) // As % of limit
        })
      }
    }

    return data
  }

  getActiveAlerts() {
    const messages = [
      { severity: 'INFO', message: 'Daily P&L limit at 60% utilization', time: '10:23 AM' },
      { severity: 'WARNING', message: 'BTC concentration above 35% threshold', time: '10:18 AM' },
      { severity: 'WARNING', message: 'Bitstamp fill rate dropped below 80%', time: '10:12 AM' },
      { severity: 'INFO', message: 'Kraken rate limit at 75%', time: '10:05 AM' }
    ]

    return messages
  }
}

export function RiskDashboard() {
  const exchanges = useExchangesStore((state) => state.exchanges)
  const strategies = useStrategiesStore((state) => state.strategies)

  const [mockData] = useState(() => new MockDataGenerator())
  const [pnlData, setPnlData] = useState(mockData.getLatestPnL())
  const [pnlByStrategy, setPnlByStrategy] = useState(mockData.getPnLByStrategy(strategies))
  const [pnlByExchange, setPnlByExchange] = useState(mockData.getPnLByExchange(exchanges))
  const [orderFlowData, setOrderFlowData] = useState(mockData.getOrderFlowMetrics())
  const [varData, setVarData] = useState(mockData.getLatestVaR())
  const [alerts] = useState(mockData.getActiveAlerts())

  // Simulate live updates every 5 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      setPnlData(mockData.getLatestPnL())
      setPnlByStrategy(mockData.getPnLByStrategy(strategies))
      setPnlByExchange(mockData.getPnLByExchange(exchanges))
      setOrderFlowData(mockData.getOrderFlowMetrics())
      setVarData(mockData.getLatestVaR())
    }, 5000)

    return () => clearInterval(interval)
  }, [mockData, strategies, exchanges])

  const handleKillSwitch = () => {
    if (confirm('KILL SWITCH: This will cancel ALL orders and close ALL positions across ALL exchanges. Continue?')) {
      window.kdb.emergencyStop()
        .then(() => alert('Kill switch activated - all positions closed'))
        .catch((err: unknown) => alert(`Kill switch failed: ${err}`))
    }
  }

  const handlePauseAll = () => {
    if (confirm('Pause all strategies? This will stop new orders but keep existing positions.')) {
      strategies.forEach(s => window.kdb.strategyControl(s.name, 'pause'))
      alert('All strategies paused')
    }
  }

  return (
    <div className="h-full overflow-auto p-4 space-y-4">
      {/* Top Row: P&L Overview + Emergency Controls */}
      <div className="grid grid-cols-4 gap-4">
        {/* Total P&L Card */}
        <Card className="p-4 col-span-2">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">TOTAL P&L</h3>
          <div className="flex items-baseline gap-2">
            <div className={`text-4xl font-bold font-mono ${pnlData.total >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
              ${pnlData.total.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            </div>
            <div className="flex items-center gap-1 text-sm font-mono">
              {pnlData.dayChange >= 0 ? (
                <TrendingUp className="w-4 h-4 text-buy-green" />
              ) : (
                <TrendingDown className="w-4 h-4 text-sell-red" />
              )}
              <span className={pnlData.dayChange >= 0 ? 'text-buy-green' : 'text-sell-red'}>
                ${Math.abs(pnlData.dayChange).toFixed(2)} ({pnlData.dayChangePct >= 0 ? '+' : ''}{pnlData.dayChangePct.toFixed(2)}%)
              </span>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4 mt-4">
            <div>
              <div className="text-xs text-muted-foreground">Realized</div>
              <div className={`text-xl font-mono ${pnlData.realized >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                ${pnlData.realized.toLocaleString('en-US', { minimumFractionDigits: 2 })}
              </div>
            </div>
            <div>
              <div className="text-xs text-muted-foreground">Unrealized</div>
              <div className={`text-xl font-mono ${pnlData.unrealized >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                ${pnlData.unrealized.toLocaleString('en-US', { minimumFractionDigits: 2 })}
              </div>
            </div>
          </div>
        </Card>

        {/* VaR Metrics */}
        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">VALUE AT RISK (95%)</h3>
          <div className="text-3xl font-bold font-mono text-sell-red">
            ${varData.var95.toLocaleString('en-US')}
          </div>
          <div className="space-y-2 mt-3">
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">VaR 99%</span>
              <span className="font-mono">${varData.var99.toLocaleString('en-US')}</span>
            </div>
            <div className="flex justify-between text-xs">
              <span className="text-muted-foreground">CVaR 95%</span>
              <span className="font-mono">${varData.cvar95.toLocaleString('en-US')}</span>
            </div>
          </div>
        </Card>

        {/* Emergency Controls */}
        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">EMERGENCY CONTROLS</h3>
          <div className="space-y-2">
            <Button
              variant="destructive"
              className="w-full gap-2 text-xs"
              onClick={handleKillSwitch}
            >
              <AlertTriangle className="w-4 h-4" />
              KILL SWITCH
            </Button>
            <Button
              variant="outline"
              className="w-full gap-2 text-xs"
              onClick={handlePauseAll}
            >
              <PauseCircle className="w-4 h-4" />
              PAUSE ALL
            </Button>
            <div className="flex items-center justify-center gap-2 text-xs text-muted-foreground mt-3">
              <Activity className="w-3 h-3 animate-pulse text-buy-green" />
              <span>All systems operational</span>
            </div>
          </div>
        </Card>
      </div>

      {/* Second Row: P&L History Chart */}
      <Card className="p-4">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">INTRADAY P&L PROGRESSION</h3>
        <ResponsiveContainer width="100%" height={200}>
          <AreaChart data={mockData.getPnLHistory()}>
            <defs>
              <linearGradient id="colorPnl" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#00c853" stopOpacity={0.8}/>
                <stop offset="95%" stopColor="#00c853" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="time" stroke="hsl(var(--muted-foreground))" fontSize={10} />
            <YAxis stroke="hsl(var(--muted-foreground))" fontSize={10} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              labelStyle={{ color: 'hsl(var(--foreground))' }}
            />
            <Area
              type="monotone"
              dataKey="pnl"
              stroke="#00c853"
              fillOpacity={1}
              fill="url(#colorPnl)"
              strokeWidth={2}
            />
          </AreaChart>
        </ResponsiveContainer>
      </Card>

      {/* Third Row: P&L by Strategy and Exchange */}
      <div className="grid grid-cols-2 gap-4">
        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">P&L BY STRATEGY</h3>
          <div className="space-y-2 max-h-[300px] overflow-y-auto">
            {pnlByStrategy.map((s) => (
              <div key={s.name} className="p-2 bg-card-hover rounded">
                <div className="flex justify-between items-center mb-1">
                  <span className="text-xs font-mono font-semibold">{s.name}</span>
                  <span className={`text-sm font-mono ${s.total >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                    ${s.total.toLocaleString('en-US', { minimumFractionDigits: 2 })}
                  </span>
                </div>
                <div className="flex justify-between text-xs text-muted-foreground">
                  <span>{s.tradeCount} trades • {(s.winRate * 100).toFixed(0)}% win rate</span>
                  <span>R: ${s.realized.toFixed(0)} | U: ${s.unrealized.toFixed(0)}</span>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">P&L BY EXCHANGE</h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={pnlByExchange}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="name" stroke="hsl(var(--muted-foreground))" fontSize={10} />
              <YAxis stroke="hsl(var(--muted-foreground))" fontSize={10} />
              <Tooltip
                contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              />
              <Bar dataKey="total" fill="#448aff" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>
      </div>

      {/* Fourth Row: Order Flow Analytics */}
      <Card className="p-4">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ORDER FLOW ANALYTICS (Last 20 Minutes)</h3>
        <ResponsiveContainer width="100%" height={200}>
          <LineChart data={orderFlowData}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="time" stroke="hsl(var(--muted-foreground))" fontSize={10} />
            <YAxis yAxisId="left" stroke="hsl(var(--muted-foreground))" fontSize={10} />
            <YAxis yAxisId="right" orientation="right" stroke="hsl(var(--muted-foreground))" fontSize={10} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
            />
            <Legend />
            <Line yAxisId="left" type="monotone" dataKey="ordersPerSec" stroke="#00c853" name="Orders/sec" strokeWidth={2} dot={false} />
            <Line yAxisId="right" type="monotone" dataKey="fillRate" stroke="#448aff" name="Fill Rate %" strokeWidth={2} dot={false} />
            <Line yAxisId="right" type="monotone" dataKey="rejectionRate" stroke="#ff1744" name="Rejection Rate %" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </Card>

      {/* Fifth Row: VaR History + Alerts */}
      <div className="grid grid-cols-2 gap-4">
        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">VAR HISTORY (30-Day Rolling)</h3>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={mockData.getVaRHistory()}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="time" stroke="hsl(var(--muted-foreground))" fontSize={10} />
              <YAxis stroke="hsl(var(--muted-foreground))" fontSize={10} />
              <Tooltip
                contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              />
              <Legend />
              <Line type="monotone" dataKey="var95" stroke="#ff9100" name="VaR 95%" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="var99" stroke="#ff1744" name="VaR 99%" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="cvar95" stroke="#ff5722" name="CVaR 95%" strokeWidth={2} dot={false} strokeDasharray="5 5" />
            </LineChart>
          </ResponsiveContainer>
        </Card>

        <Card className="p-4">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">ACTIVE ALERTS</h3>
          <div className="space-y-2 max-h-[200px] overflow-y-auto">
            {alerts.map((alert, idx) => (
              <div key={idx} className="flex items-start gap-2 p-2 bg-card-hover rounded">
                <div className={`w-2 h-2 rounded-full mt-1 ${
                  alert.severity === 'CRITICAL' ? 'bg-sell-red animate-pulse' :
                  alert.severity === 'WARNING' ? 'bg-pending-yellow' :
                  'bg-info-blue'
                }`} />
                <div className="flex-1">
                  <div className="flex justify-between items-start">
                    <div className="text-xs font-mono">{alert.message}</div>
                    <div className="text-xs text-muted-foreground whitespace-nowrap ml-2">{alert.time}</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  )
}
