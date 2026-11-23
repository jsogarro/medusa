import { AreaChart, Area, LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend } from 'recharts'
import { Card } from '../ui/card'
import type { DailyReturn } from '../../lib/tearsheet-data'

interface ReturnsSummaryProps {
  dailyReturns: DailyReturn[]
}

export function ReturnsSummary({ dailyReturns }: ReturnsSummaryProps) {
  // Calculate rolling 30-day and 90-day returns
  const rollingData = dailyReturns.map((point, i) => {
    const window30 = dailyReturns.slice(Math.max(0, i - 29), i + 1)
    const window90 = dailyReturns.slice(Math.max(0, i - 89), i + 1)

    const rolling30 = window30.length > 0 ? window30.reduce((sum, r) => sum * (1 + r.dailyReturn), 1) - 1 : 0
    const rolling90 = window90.length > 0 ? window90.reduce((sum, r) => sum * (1 + r.dailyReturn), 1) - 1 : 0

    return {
      date: point.date,
      cumulative: point.cumulativeReturn,
      rolling30d: rolling30,
      rolling90d: rolling90
    }
  })

  // Sample every 5th point for performance
  const sampledCumulative = dailyReturns.filter((_, i) => i % 5 === 0).map(r => ({ date: r.date, value: r.cumulativeReturn }))
  const sampledRolling = rollingData.filter((_, i) => i % 5 === 0)

  return (
    <div className="space-y-4">
      {/* Cumulative Returns */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">CUMULATIVE RETURNS</h3>
        <ResponsiveContainer width="100%" height={200}>
          <AreaChart data={sampledCumulative}>
            <defs>
              <linearGradient id="cumulativeGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#00c853" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#00c853" stopOpacity={0} />
              </linearGradient>
            </defs>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(2)}%`}
            />
            <Area type="monotone" dataKey="value" stroke="#00c853" fill="url(#cumulativeGradient)" />
          </AreaChart>
        </ResponsiveContainer>
      </Card>

      {/* Rolling Returns */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ROLLING RETURNS (30D / 90D)</h3>
        <ResponsiveContainer width="100%" height={180}>
          <LineChart data={sampledRolling}>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(2)}%`}
            />
            <Legend wrapperStyle={{ fontSize: '10px' }} />
            <Line type="monotone" dataKey="rolling30d" stroke="#ff9100" strokeWidth={1.5} dot={false} name="30-day" />
            <Line type="monotone" dataKey="rolling90d" stroke="#00c853" strokeWidth={1.5} dot={false} name="90-day" />
          </LineChart>
        </ResponsiveContainer>
      </Card>
    </div>
  )
}
