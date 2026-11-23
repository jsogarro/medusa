import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell } from 'recharts'
import { Card } from '../ui/card'

interface AnnualReturnsBarProps {
  annualReturns: { year: number; return: number }[]
}

export function AnnualReturnsBar({ annualReturns }: AnnualReturnsBarProps) {
  const chartData = annualReturns.map((r) => ({
    year: r.year.toString(),
    return: r.return * 100
  }))

  return (
    <Card className="p-3">
      <h3 className="text-xs font-semibold text-muted-foreground mb-3">ANNUAL RETURNS</h3>
      <div
        role="img"
        aria-label="Annual returns bar chart"
        aria-description="Bar chart showing annual portfolio returns by year, with green bars for positive returns and red bars for negative returns"
      >
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={chartData}>
          <XAxis dataKey="year" tick={{ fontSize: 10, fontFamily: 'monospace' }} />
          <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `${v.toFixed(0)}%`} />
          <Tooltip
            contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
            formatter={(value: number) => `${value.toFixed(2)}%`}
          />
          <Bar dataKey="return" radius={[4, 4, 0, 0]}>
            {chartData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.return >= 0 ? '#00c853' : '#ff1744'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      </div>
    </Card>
  )
}
