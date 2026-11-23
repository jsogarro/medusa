import { Card } from '../components/ui/card'
import { Button } from '../components/ui/button'
import { AlertTriangle, PauseCircle } from 'lucide-react'
import { useExchangesStore } from '../stores/exchanges'
import { useStrategiesStore } from '../stores/strategies'
import { pauseAllStrategies, runEmergencyStop } from '../lib/kdb-actions'
import { PieChart, Pie, Cell, ResponsiveContainer } from 'recharts'

export function Risk() {
  const exchanges = useExchangesStore((state) => state.exchanges)
  const strategies = useStrategiesStore((state) => state.strategies)

  const handleKillSwitch = () => {
    if (confirm('KILL SWITCH: This will cancel ALL orders and close ALL positions across ALL exchanges. Continue?')) {
      void runEmergencyStop(window.kdb).then((r) => alert(r.ok ? 'Kill switch activated' : r.message))
    }
  }

  const handlePauseAll = () => {
    if (confirm('Pause all strategies? This will stop new orders but keep existing positions.')) {
      void pauseAllStrategies(window.kdb, strategies.map((s) => s.name)).then((r) => alert(r.message))
    }
  }

  // Mock circuit breaker data
  const circuitBreakers = strategies.map((s) => ({
    name: s.name,
    status: s.status === 'running' ? 'OK' : s.status === 'paused' ? 'WARNING' : 'TRIGGERED',
    reason: s.status === 'running' ? '-' : s.status === 'paused' ? 'Manual pause' : 'Max loss exceeded'
  }))

  // Mock exposure data
  const exposureData = exchanges.map((ex) => ({
    name: ex.exchange,
    exposure: Math.random() * 100000,
    limit: 150000
  }))

  // Mock concentration data
  const concentrationData = [
    { name: 'BTC', value: 40, color: '#ff9100' },
    { name: 'ETH', value: 30, color: '#00c853' },
    { name: 'SOL', value: 15, color: '#448aff' },
    { name: 'Others', value: 15, color: '#ffd740' }
  ]

  // Drawdown gauge data
  const currentDrawdown = -3.2
  const maxDrawdown = -15.0
  const drawdownPct = Math.abs(currentDrawdown / maxDrawdown) * 100

  return (
    <div className="h-full grid grid-cols-2 gap-2 p-2">
      {/* Left column */}
      <div className="flex flex-col gap-2">
        {/* Rate Limits */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">RATE LIMITS</h3>
          <div className="space-y-3">
            {exchanges.map((ex) => (
              <div key={ex.exchange}>
                <div className="flex justify-between mb-1 text-xs font-mono">
                  <span className="text-muted-foreground uppercase">{ex.exchange}</span>
                  <span>
                    {ex.rateLimitUsed}/{ex.rateLimitMax} ({((ex.rateLimitUsed / ex.rateLimitMax) * 100).toFixed(0)}%)
                  </span>
                </div>
                <div className="w-full h-2 bg-border rounded-full overflow-hidden">
                  <div
                    className={`h-full ${
                      ex.rateLimitUsed / ex.rateLimitMax > 0.8
                        ? 'bg-sell-red'
                        : ex.rateLimitUsed / ex.rateLimitMax > 0.5
                        ? 'bg-pending-yellow'
                        : 'bg-buy-green'
                    }`}
                    style={{ width: `${(ex.rateLimitUsed / ex.rateLimitMax) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Circuit Breakers */}
        <Card className="p-3 flex-1">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">CIRCUIT BREAKERS</h3>
          <div className="space-y-2">
            {circuitBreakers.map((cb) => (
              <div key={cb.name} className="flex items-center justify-between p-2 bg-card-hover rounded">
                <div className="flex items-center gap-2">
                  <div
                    className={`w-2 h-2 rounded-full ${
                      cb.status === 'OK'
                        ? 'bg-buy-green'
                        : cb.status === 'WARNING'
                        ? 'bg-pending-yellow'
                        : 'bg-sell-red'
                    }`}
                  />
                  <span className="text-xs font-mono font-semibold">{cb.name}</span>
                </div>
                <div className="text-xs text-muted-foreground">{cb.reason}</div>
              </div>
            ))}
          </div>
        </Card>

        {/* Emergency Controls */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">EMERGENCY CONTROLS</h3>
          <div className="space-y-2">
            <Button
              variant="destructive"
              className="w-full gap-2"
              onClick={handleKillSwitch}
            >
              <AlertTriangle className="w-4 h-4" />
              KILL SWITCH
            </Button>
            <Button
              variant="outline"
              className="w-full gap-2"
              onClick={handlePauseAll}
            >
              <PauseCircle className="w-4 h-4" />
              PAUSE ALL STRATEGIES
            </Button>
          </div>
        </Card>
      </div>

      {/* Right column */}
      <div className="flex flex-col gap-2">
        {/* Exposure */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">EXPOSURE BY EXCHANGE</h3>
          <div className="space-y-3">
            {exposureData.map((ex) => {
              const pct = (ex.exposure / ex.limit) * 100
              return (
                <div key={ex.name}>
                  <div className="flex justify-between mb-1 text-xs font-mono">
                    <span className="text-muted-foreground uppercase">{ex.name}</span>
                    <span>
                      ${ex.exposure.toFixed(0)} / ${ex.limit.toFixed(0)} ({pct.toFixed(0)}%)
                    </span>
                  </div>
                  <div className="w-full h-2 bg-border rounded-full overflow-hidden">
                    <div
                      className={`h-full ${
                        pct > 80
                          ? 'bg-sell-red'
                          : pct > 50
                          ? 'bg-pending-yellow'
                          : 'bg-info-blue'
                      }`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        </Card>

        {/* Concentration */}
        <Card className="p-3 flex-1">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">ASSET CONCENTRATION</h3>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie
                data={concentrationData}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, value }) => `${name} ${value}%`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="value"
              >
                {concentrationData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
            </PieChart>
          </ResponsiveContainer>
        </Card>

        {/* Drawdown Gauge */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">DRAWDOWN</h3>
          <div className="flex items-center justify-center">
            <div className="relative w-48 h-48">
              <svg viewBox="0 0 200 200" className="transform -rotate-90">
                <circle
                  cx="100"
                  cy="100"
                  r="80"
                  fill="none"
                  stroke="hsl(var(--border))"
                  strokeWidth="20"
                />
                <circle
                  cx="100"
                  cy="100"
                  r="80"
                  fill="none"
                  stroke="#ff1744"
                  strokeWidth="20"
                  strokeDasharray={`${(drawdownPct / 100) * 502.4} 502.4`}
                  strokeLinecap="round"
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <div className="text-3xl font-bold font-mono text-sell-red">{currentDrawdown}%</div>
                <div className="text-xs text-muted-foreground">of {maxDrawdown}% max</div>
              </div>
            </div>
          </div>
        </Card>
      </div>
    </div>
  )
}
