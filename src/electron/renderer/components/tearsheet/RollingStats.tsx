import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend, ReferenceLine } from 'recharts'
import { Card } from '../ui/card'
import type { RollingMetric } from '../../lib/tearsheet-data'

interface RollingStatsProps {
  rollingMetrics: RollingMetric[]
}

export function RollingStats({ rollingMetrics }: RollingStatsProps) {
  // Sample data for performance
  const sampledMetrics = rollingMetrics.filter((_, i) => i % 5 === 0)

  return (
    <div className="space-y-4">
      {/* Rolling Sharpe */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ROLLING SHARPE RATIO (90-DAY)</h3>
        <div
          role="img"
          aria-label="Rolling 90-day Sharpe ratio chart"
          aria-description="Line chart showing rolling 90-day Sharpe ratio over time with reference lines at 0, 1, and 2"
        >
          <ResponsiveContainer width="100%" height={180}>
            <LineChart data={sampledMetrics}>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => value.toFixed(2)}
            />
            <ReferenceLine y={0} stroke="#6b6b80" strokeDasharray="3 3" />
            <ReferenceLine y={1} stroke="#6b6b80" strokeDasharray="3 3" />
            <ReferenceLine y={2} stroke="#6b6b80" strokeDasharray="3 3" />
            <Line type="monotone" dataKey="sharpe" stroke="#00c853" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
        </div>
      </Card>

      {/* Rolling Beta */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ROLLING BETA (90-DAY)</h3>
        <div
          role="img"
          aria-label="Rolling 90-day beta chart"
          aria-description="Line chart showing rolling 90-day portfolio beta versus market over time"
        >
          <ResponsiveContainer width="100%" height={180}>
            <LineChart data={sampledMetrics}>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => value.toFixed(2)}
            />
            <ReferenceLine y={1} stroke="#6b6b80" strokeDasharray="3 3" />
            <Line type="monotone" dataKey="beta" stroke="#ff9100" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
        </div>
      </Card>

      {/* Rolling Volatility */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ROLLING VOLATILITY (30D / 90D)</h3>
        <div
          role="img"
          aria-label="Rolling volatility chart"
          aria-description="Line chart comparing 30-day and 90-day rolling portfolio volatility over time"
        >
          <ResponsiveContainer width="100%" height={180}>
            <LineChart data={sampledMetrics}>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(2)}%`}
            />
            <Legend wrapperStyle={{ fontSize: '10px' }} />
            <Line type="monotone" dataKey="volatility30d" stroke="#ff1744" strokeWidth={1.5} dot={false} name="30-day" />
            <Line type="monotone" dataKey="volatility90d" stroke="#00c853" strokeWidth={1.5} dot={false} name="90-day" />
          </LineChart>
        </ResponsiveContainer>
        </div>
      </Card>
    </div>
  )
}
