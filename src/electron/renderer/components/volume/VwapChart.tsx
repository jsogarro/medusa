import { Card } from '../ui/card'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, Area } from 'recharts'
import { generateMockVwapData } from '../../lib/mock-data'
import { useMemo } from 'react'

export function VwapChart() {
  const vwapData = useMemo(() => generateMockVwapData(), [])

  return (
    <Card className="h-full p-3 flex flex-col">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2">VWAP & BANDS</h3>
      <div className="flex-1 min-h-0">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart
            data={vwapData}
            margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
          >
            <XAxis
              dataKey="time"
              hide
            />
            <YAxis
              domain={['auto', 'auto']}
              tick={{ fill: '#9ca3af', fontSize: 10, fontFamily: 'monospace' }}
              tickFormatter={(value) => value.toFixed(0)}
              width={50}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#1c1c21',
                border: '1px solid #26262a',
                borderRadius: '4px',
                fontSize: '11px',
                fontFamily: 'monospace'
              }}
              formatter={(value: number) => [`$${value.toFixed(2)}`, '']}
              labelFormatter={() => ''}
            />
            {/* Upper band area */}
            <Area
              type="monotone"
              dataKey="upperBand"
              stroke="none"
              fill="#ff910033"
              fillOpacity={0.3}
            />
            {/* Lower band area */}
            <Area
              type="monotone"
              dataKey="lowerBand"
              stroke="none"
              fill="#ff910033"
              fillOpacity={0.3}
            />
            {/* Price line */}
            <Line
              type="monotone"
              dataKey="price"
              stroke="#9ca3af"
              strokeWidth={1.5}
              dot={false}
            />
            {/* VWAP line */}
            <Line
              type="monotone"
              dataKey="vwap"
              stroke="#ff9100"
              strokeWidth={2}
              dot={false}
            />
            {/* Bands */}
            <Line
              type="monotone"
              dataKey="upperBand"
              stroke="#ff9100"
              strokeWidth={1}
              strokeDasharray="3 3"
              dot={false}
            />
            <Line
              type="monotone"
              dataKey="lowerBand"
              stroke="#ff9100"
              strokeWidth={1}
              strokeDasharray="3 3"
              dot={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <div className="mt-2 flex items-center gap-4 text-xs font-mono">
        <div className="flex items-center gap-1">
          <div className="w-3 h-0.5 bg-[#9ca3af]" />
          <span className="text-muted-foreground">Price</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-0.5 bg-chart-orange" />
          <span className="text-muted-foreground">VWAP</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-0.5 bg-chart-orange opacity-50 border-t border-dashed border-chart-orange" />
          <span className="text-muted-foreground">±1σ</span>
        </div>
      </div>
    </Card>
  )
}
