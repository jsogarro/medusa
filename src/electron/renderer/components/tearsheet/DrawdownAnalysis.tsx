import { AreaChart, Area, XAxis, YAxis, ResponsiveContainer, Tooltip } from 'recharts'
import { Card } from '../ui/card'
import type { DrawdownPeriod } from '../../lib/tearsheet-data'

interface DrawdownAnalysisProps {
  underwater: { date: string; drawdown: number }[]
  periods: DrawdownPeriod[]
}

export function DrawdownAnalysis({ underwater, periods }: DrawdownAnalysisProps) {
  // Sample underwater data for performance
  const sampledUnderwater = underwater.filter((_, i) => i % 5 === 0)

  return (
    <div className="space-y-4">
      {/* Underwater Plot */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">DRAWDOWN UNDERWATER PLOT</h3>
        <div
          role="img"
          aria-label="Drawdown underwater plot"
          aria-description="Area chart showing portfolio drawdown over time, displaying periods when portfolio is below peak value"
        >
          <ResponsiveContainer width="100%" height={180}>
            <AreaChart data={sampledUnderwater}>
            <defs>
              <linearGradient id="underwaterGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#ff1744" stopOpacity={0.4} />
                <stop offset="95%" stopColor="#ff1744" stopOpacity={0.1} />
              </linearGradient>
            </defs>
            <XAxis dataKey="date" hide />
            <YAxis
              domain={['dataMin', 0]}
              tick={{ fontSize: 10, fontFamily: 'monospace' }}
              tickFormatter={(v) => `${(v * 100).toFixed(0)}%`}
            />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(2)}%`}
            />
            <Area type="monotone" dataKey="drawdown" stroke="#ff1744" fill="url(#underwaterGradient)" />
          </AreaChart>
        </ResponsiveContainer>
        </div>
      </Card>

      {/* Top 5 Drawdowns Table */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">TOP 5 DRAWDOWN PERIODS</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-[10px] font-mono">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left p-2 text-muted-foreground">Peak Date</th>
                <th className="text-left p-2 text-muted-foreground">Valley Date</th>
                <th className="text-left p-2 text-muted-foreground">Recovery Date</th>
                <th className="text-right p-2 text-muted-foreground">Duration (days)</th>
                <th className="text-right p-2 text-muted-foreground">Max Drawdown</th>
                <th className="text-center p-2 text-muted-foreground">Status</th>
              </tr>
            </thead>
            <tbody>
              {periods.map((period, idx) => (
                <tr key={idx} className="border-b border-border/50">
                  <td className="p-2">{period.peakDate}</td>
                  <td className="p-2">{period.valleyDate}</td>
                  <td className="p-2">{period.recoveryDate || '-'}</td>
                  <td className="p-2 text-right">{period.duration}</td>
                  <td className="p-2 text-right text-sell-red font-semibold">
                    {(period.maxDrawdown * 100).toFixed(2)}%
                  </td>
                  <td className="p-2 text-center">
                    {period.isActive ? (
                      <span className="text-sell-red">● Active</span>
                    ) : (
                      <span className="text-muted-foreground">Recovered</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
}
