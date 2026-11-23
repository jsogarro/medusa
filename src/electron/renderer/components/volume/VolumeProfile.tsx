import { Card } from '../ui/card'
import { BarChart, Bar, XAxis, YAxis, Cell, ResponsiveContainer } from 'recharts'
import { generateMockVolumeProfile } from '../../lib/mock-data'
import { useMemo } from 'react'

export function VolumeProfile() {
  const volumeData = useMemo(() => generateMockVolumeProfile(), [])

  // Find Point of Control (POC) - price level with highest volume
  const poc = volumeData.reduce((max, level) =>
    level.volume > max.volume ? level : max
  )

  // Calculate Value Area (70% of volume)
  const totalVolume = volumeData.reduce((sum, level) => sum + level.volume, 0)
  const targetVolume = totalVolume * 0.7
  let cumulativeVolume = 0
  const valueAreaLevels = new Set<number>()

  // Start from POC and expand outward
  const sortedByVolume = [...volumeData].sort((a, b) => b.volume - a.volume)
  for (const level of sortedByVolume) {
    if (cumulativeVolume >= targetVolume) break
    valueAreaLevels.add(level.price)
    cumulativeVolume += level.volume
  }

  return (
    <Card className="h-full p-3 flex flex-col">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2">VOLUME PROFILE</h3>
      <div
        className="flex-1 min-h-0"
        role="img"
        aria-label="Volume profile by price level"
        aria-description={`Horizontal volume histogram showing distribution of traded volume across price levels. Point of Control (highest volume) at $${poc.price.toFixed(2)}, value area contains ${valueAreaLevels.size} levels`}
      >
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={volumeData}
            layout="vertical"
            margin={{ top: 0, right: 10, left: 50, bottom: 0 }}
          >
            <XAxis type="number" hide />
            <YAxis
              type="number"
              dataKey="price"
              domain={['dataMin', 'dataMax']}
              tick={{ fill: '#9ca3af', fontSize: 10, fontFamily: 'monospace' }}
              tickFormatter={(value) => value.toFixed(0)}
            />
            <Bar dataKey="volume" radius={[0, 2, 2, 0]}>
              {volumeData.map((entry) => (
                <Cell
                  key={entry.price}
                  fill={
                    entry.price === poc.price
                      ? '#ffffff'
                      : valueAreaLevels.has(entry.price)
                      ? '#ff9100'
                      : '#ff910066'
                  }
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <div className="mt-2 space-y-1 text-xs font-mono">
        <div className="flex justify-between">
          <span className="text-muted-foreground">POC</span>
          <span className="font-semibold">${poc.price.toFixed(2)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-muted-foreground">Value Area</span>
          <span className="font-semibold">{valueAreaLevels.size} levels</span>
        </div>
      </div>
    </Card>
  )
}
