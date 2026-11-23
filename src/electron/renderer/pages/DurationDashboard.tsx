import { Card } from '../components/ui/card'
import {
  BarChart,
  Bar,
  ResponsiveContainer,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Cell
} from 'recharts'
import {
  generateDurationMetrics,
  generateKeyRateDurations,
  generateRateScenarios
} from '../lib/bond-mock-data'
import { formatPrice } from '../lib/utils'

export function DurationDashboard() {
  const metrics = generateDurationMetrics()
  const krdData = generateKeyRateDurations()
  const scenarios = generateRateScenarios()

  // Color gradient for KRD bars (orange gradient)
  const getBarColor = (index: number, total: number) => {
    const intensity = 100 - (index / total) * 40
    return `hsl(14 100% ${intensity}%)`
  }

  return (
    <div className="h-full flex flex-col gap-2 p-2 overflow-y-auto">
      {/* Duration Metrics Cards */}
      <div className="grid grid-cols-3 gap-2">
        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">MODIFIED DURATION</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            {metrics.modifiedDuration.toFixed(1)}
            <span className="text-sm text-muted-foreground ml-1">years</span>
          </div>
          <div className="text-[10px] text-muted-foreground mt-1">
            Portfolio sensitivity to parallel rate shifts
          </div>
        </Card>

        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">DV01</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            ${(metrics.dv01 / 1000).toFixed(1)}K
          </div>
          <div className="text-[10px] text-muted-foreground mt-1">
            P&L impact per 1bp rate change
          </div>
        </Card>

        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">CONVEXITY</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            {metrics.convexity.toFixed(1)}
          </div>
          <div className="text-[10px] text-muted-foreground mt-1">
            Second-order price sensitivity
          </div>
        </Card>
      </div>

      {/* Key Rate Duration Chart */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">
          KEY RATE DURATIONS (DV01 by Tenor)
        </h3>
        <ResponsiveContainer width="100%" height={280}>
          <BarChart
            data={krdData}
            layout="vertical"
            margin={{ top: 5, right: 30, left: 50, bottom: 5 }}
          >
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
            <XAxis
              type="number"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              tickFormatter={(value) => `$${(value / 1000).toFixed(1)}K`}
            />
            <YAxis
              type="category"
              dataKey="tenor"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              width={40}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(240 8% 9%)',
                border: '1px solid hsl(240 7% 16%)',
                borderRadius: '4px',
                fontSize: '11px'
              }}
              formatter={(value: number) => [`$${formatPrice(value, 0)}`, 'DV01']}
            />
            <Bar dataKey="dv01" radius={[0, 4, 4, 0]}>
              {krdData.map((_, index) => (
                <Cell key={`cell-${index}`} fill={getBarColor(index, krdData.length)} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
        <div className="mt-2 text-[10px] text-muted-foreground">
          Shows portfolio sensitivity to rate changes at specific tenors
        </div>
      </Card>

      {/* Scenario Analysis */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">RATE SCENARIO ANALYSIS</h3>
        <div className="space-y-1">
          {scenarios.map(scenario => (
            <div
              key={scenario.name}
              className="flex items-center justify-between py-2 border-b border-border/50 last:border-0"
            >
              <div className="flex-1">
                <div className="text-xs font-mono font-semibold">{scenario.name}</div>
                <div className="text-[10px] text-muted-foreground mt-0.5">{scenario.description}</div>
              </div>
              <div
                className={`text-sm font-mono font-semibold ${
                  scenario.pnlImpact >= 0 ? 'text-buy-green' : 'text-sell-red'
                }`}
              >
                {scenario.pnlImpact >= 0 ? '+' : ''}${formatPrice(scenario.pnlImpact, 0)}
              </div>
            </div>
          ))}
        </div>
        <div className="mt-3 text-[10px] text-muted-foreground">
          P&L impact estimates based on current portfolio duration profile
        </div>
      </Card>
    </div>
  )
}
