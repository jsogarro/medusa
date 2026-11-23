import { useState } from 'react'
import { Card } from '../components/ui/card'
import {
  LineChart,
  Line,
  ResponsiveContainer,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend
} from 'recharts'
import {
  generateYieldCurves,
  generateSpreadMetrics,
  generateRateChanges
} from '../lib/bond-mock-data'

export function YieldCurve() {
  const [selectedCurves, setSelectedCurves] = useState<string[]>(['Current'])

  const yieldCurves = generateYieldCurves()
  const spreadMetrics = generateSpreadMetrics()
  const rateChanges = generateRateChanges()

  // Combine all curves into recharts format
  const chartData = yieldCurves[0].points.map((point, idx) => {
    const dataPoint: Record<string, string | number> = { tenor: point.tenor }
    yieldCurves.forEach(curve => {
      if (selectedCurves.includes(curve.label)) {
        dataPoint[curve.label] = curve.points[idx].rate
      }
    })
    return dataPoint
  })

  const toggleCurve = (label: string) => {
    setSelectedCurves(prev =>
      prev.includes(label)
        ? prev.filter(l => l !== label)
        : [...prev, label]
    )
  }

  return (
    <div className="h-full flex flex-col gap-2 p-2 overflow-y-auto">
      {/* Yield Curve Chart */}
      <Card className="p-3">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-muted-foreground">TREASURY YIELD CURVE</h3>
          <div className="flex items-center gap-2">
            {yieldCurves.map(curve => (
              <button
                key={curve.label}
                onClick={() => toggleCurve(curve.label)}
                className={`text-xs px-2 py-1 rounded transition-colors ${
                  selectedCurves.includes(curve.label)
                    ? 'bg-card-hover text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
                style={{
                  borderLeft: selectedCurves.includes(curve.label)
                    ? `2px solid ${curve.color}`
                    : 'none',
                  paddingLeft: selectedCurves.includes(curve.label) ? '6px' : '8px'
                }}
              >
                {curve.label}
              </button>
            ))}
          </div>
        </div>

        <ResponsiveContainer width="100%" height={320}>
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
            <XAxis
              dataKey="tenor"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
            />
            <YAxis
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              domain={['auto', 'auto']}
              tickFormatter={(value) => `${value.toFixed(2)}%`}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(240 8% 9%)',
                border: '1px solid hsl(240 7% 16%)',
                borderRadius: '4px',
                fontSize: '11px'
              }}
              formatter={(value: number) => [`${value.toFixed(3)}%`, '']}
            />
            <Legend
              wrapperStyle={{ fontSize: '11px' }}
              iconType="line"
            />
            {yieldCurves.map(curve => {
              if (!selectedCurves.includes(curve.label)) return null
              return (
                <Line
                  key={curve.label}
                  type="monotone"
                  dataKey={curve.label}
                  stroke={curve.color}
                  strokeWidth={curve.label === 'Current' ? 2.5 : 1.5}
                  dot={curve.label === 'Current'}
                  activeDot={{ r: 5 }}
                />
              )
            })}
          </LineChart>
        </ResponsiveContainer>
      </Card>

      <div className="grid grid-cols-2 gap-2">
        {/* Spread Metrics */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">CURVE SPREADS (bp)</h3>
          <div className="space-y-1">
            {spreadMetrics.map(metric => (
              <div key={metric.name} className="flex items-center justify-between text-xs font-mono">
                <span className="text-muted-foreground font-semibold">{metric.name}</span>
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{metric.value > 0 ? '+' : ''}{metric.value}</span>
                  <span className={`text-[10px] ${metric.change1D >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                    {metric.change1D >= 0 ? '+' : ''}{metric.change1D}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Rate Changes Table */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">RATE CHANGES</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-[11px] font-mono">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left text-muted-foreground font-semibold pb-1">Tenor</th>
                  <th className="text-right text-muted-foreground font-semibold pb-1">Current</th>
                  <th className="text-right text-muted-foreground font-semibold pb-1">1D</th>
                  <th className="text-right text-muted-foreground font-semibold pb-1">1W</th>
                  <th className="text-right text-muted-foreground font-semibold pb-1">1M</th>
                </tr>
              </thead>
              <tbody>
                {rateChanges.map(rate => (
                  <tr key={rate.tenor} className="border-b border-border/50">
                    <td className="py-1 font-semibold">{rate.tenor}</td>
                    <td className="text-right">{rate.currentRate.toFixed(2)}%</td>
                    <td className={`text-right ${rate.change1D >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                      {rate.change1D >= 0 ? '+' : ''}{rate.change1D.toFixed(2)}
                    </td>
                    <td className={`text-right ${rate.change1W >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                      {rate.change1W >= 0 ? '+' : ''}{rate.change1W.toFixed(2)}
                    </td>
                    <td className={`text-right ${rate.change1M >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
                      {rate.change1M >= 0 ? '+' : ''}{rate.change1M.toFixed(2)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </div>
  )
}
