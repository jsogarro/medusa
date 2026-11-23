import { AreaChart, Area, Line, BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Legend } from 'recharts'
import { Card } from '../ui/card'
import type { ExposurePoint } from '../../lib/tearsheet-data'

interface ExposureAnalysisProps {
  exposure: ExposurePoint[]
}

export function ExposureAnalysis({ exposure }: ExposureAnalysisProps) {
  // Sample data for performance
  const sampledExposure = exposure.filter((_, i) => i % 5 === 0)

  // Mock position concentration (top 10 positions)
  const positionConcentration = [
    { symbol: 'BTC/USD', pct: 0.32 },
    { symbol: 'ETH/USD', pct: 0.24 },
    { symbol: 'SOL/USD', pct: 0.15 },
    { symbol: 'AVAX/USD', pct: 0.08 },
    { symbol: 'MATIC/USD', pct: 0.07 },
    { symbol: 'ADA/USD', pct: 0.05 },
    { symbol: 'DOT/USD', pct: 0.04 },
    { symbol: 'LINK/USD', pct: 0.03 },
    { symbol: 'UNI/USD', pct: 0.02 }
  ]

  // Mock turnover data
  const turnoverData = sampledExposure.map((point) => ({
    date: point.date,
    turnover: 0.05 + Math.random() * 0.15 // 5-20% daily turnover
  }))

  return (
    <div className="space-y-4">
      {/* Gross/Net Exposure */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">GROSS & NET EXPOSURE</h3>
        <ResponsiveContainer width="100%" height={200}>
          <AreaChart data={sampledExposure}>
            <defs>
              <linearGradient id="longGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#00c853" stopOpacity={0.6} />
                <stop offset="95%" stopColor="#00c853" stopOpacity={0.2} />
              </linearGradient>
              <linearGradient id="shortGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#ff1744" stopOpacity={0.2} />
                <stop offset="95%" stopColor="#ff1744" stopOpacity={0.6} />
              </linearGradient>
            </defs>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(1)}%`}
            />
            <Legend wrapperStyle={{ fontSize: '10px' }} />
            <Area
              type="monotone"
              dataKey="grossLong"
              stackId="1"
              stroke="#00c853"
              fill="url(#longGradient)"
              name="Long Exposure"
            />
            <Area
              type="monotone"
              dataKey="grossShort"
              stackId="1"
              stroke="#ff1744"
              fill="url(#shortGradient)"
              name="Short Exposure"
            />
            <Line type="monotone" dataKey="netExposure" stroke="#ffffff" strokeWidth={2} dot={false} name="Net Exposure" />
          </AreaChart>
        </ResponsiveContainer>
      </Card>

      {/* Position Concentration */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">POSITION CONCENTRATION (TOP 9)</h3>
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={positionConcentration} layout="horizontal">
            <XAxis type="number" tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <YAxis type="category" dataKey="symbol" tick={{ fontSize: 10, fontFamily: 'monospace' }} width={80} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(1)}%`}
            />
            <Bar dataKey="pct" fill="#ff9100" radius={[0, 4, 4, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </Card>

      {/* Turnover */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">DAILY PORTFOLIO TURNOVER</h3>
        <ResponsiveContainer width="100%" height={150}>
          <BarChart data={turnoverData}>
            <XAxis dataKey="date" hide />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${(v * 100).toFixed(0)}%`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `${(value * 100).toFixed(1)}%`}
            />
            <Bar dataKey="turnover" fill="#6b6b80" />
          </BarChart>
        </ResponsiveContainer>
      </Card>
    </div>
  )
}
