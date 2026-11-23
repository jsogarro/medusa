import { Card } from '../ui/card'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import { generateMockCvdData } from '../../lib/mock-data'
import { useMemo } from 'react'

export function CumulativeVolumeDelta() {
  const cvdData = useMemo(() => generateMockCvdData(), [])

  // Determine if CVD is net positive or negative
  const latestCvd = cvdData[cvdData.length - 1]?.cvd || 0
  const cvdColor = latestCvd >= 0 ? '#00c853' : '#ff1744'

  return (
    <Card className="h-full p-3 flex flex-col">
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-xs font-semibold text-muted-foreground">CUMULATIVE VOLUME DELTA</h3>
        <span className={`text-xs font-mono font-semibold ${latestCvd >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
          {latestCvd >= 0 ? '+' : ''}{latestCvd.toFixed(0)}
        </span>
      </div>
      <div className="flex-1 min-h-0">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart
            data={cvdData}
            margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
          >
            <XAxis dataKey="time" hide />
            <YAxis
              tick={{ fill: '#9ca3af', fontSize: 10, fontFamily: 'monospace' }}
              tickFormatter={(value) => value.toFixed(0)}
              width={45}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#1c1c21',
                border: '1px solid #26262a',
                borderRadius: '4px',
                fontSize: '11px',
                fontFamily: 'monospace'
              }}
              formatter={(value: number) => [value.toFixed(0), 'CVD']}
              labelFormatter={() => ''}
            />
            <ReferenceLine y={0} stroke="#26262a" strokeWidth={1} />
            <Line
              type="monotone"
              dataKey="cvd"
              stroke={cvdColor}
              strokeWidth={2}
              dot={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <div className="mt-2 flex items-center gap-4 text-xs font-mono">
        <div className="flex items-center gap-1">
          <div className="w-3 h-0.5 bg-buy-green" />
          <span className="text-muted-foreground">Net Buy Pressure</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-0.5 bg-sell-red" />
          <span className="text-muted-foreground">Net Sell Pressure</span>
        </div>
      </div>
    </Card>
  )
}
