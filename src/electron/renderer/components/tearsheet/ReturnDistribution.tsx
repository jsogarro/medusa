import { Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Line, ComposedChart } from 'recharts'
import { Card } from '../ui/card'
import type { DailyReturn } from '../../lib/tearsheet-data'

interface ReturnDistributionProps {
  dailyReturns: DailyReturn[]
}

export function ReturnDistribution({ dailyReturns }: ReturnDistributionProps) {
  const returns = dailyReturns.map((r) => r.dailyReturn)

  // Calculate histogram bins
  const numBins = 40
  const min = Math.min(...returns)
  const max = Math.max(...returns)
  const binWidth = (max - min) / numBins

  const bins = Array.from({ length: numBins }, (_, i) => ({
    binStart: min + i * binWidth,
    binEnd: min + (i + 1) * binWidth,
    count: 0
  }))

  returns.forEach((ret) => {
    const binIndex = Math.min(Math.floor((ret - min) / binWidth), numBins - 1)
    if (binIndex >= 0 && binIndex < numBins) {
      bins[binIndex].count++
    }
  })

  // Calculate normal distribution overlay
  const mean = returns.reduce((sum, r) => sum + r, 0) / returns.length
  const variance = returns.reduce((sum, r) => sum + Math.pow(r - mean, 2), 0) / returns.length
  const std = Math.sqrt(variance)

  const normalDist = bins.map(({ binStart, binEnd }) => {
    const x = (binStart + binEnd) / 2
    const exponent = -Math.pow(x - mean, 2) / (2 * variance)
    const y = (1 / (std * Math.sqrt(2 * Math.PI))) * Math.exp(exponent)
    // Scale to match histogram height
    const scaledY = y * returns.length * binWidth
    return scaledY
  })

  const chartData = bins.map((bin, i) => ({
    bin: `${(bin.binStart * 100).toFixed(1)}`,
    count: bin.count,
    normal: normalDist[i]
  }))

  // Calculate skew and kurtosis
  const skew = returns.reduce((sum, r) => sum + Math.pow((r - mean) / std, 3), 0) / returns.length
  const kurtosis = returns.reduce((sum, r) => sum + Math.pow((r - mean) / std, 4), 0) / returns.length

  return (
    <Card className="p-3">
      <div className="flex items-start justify-between mb-3">
        <h3 className="text-xs font-semibold text-muted-foreground">RETURN DISTRIBUTION</h3>
        <div className="text-[10px] font-mono space-x-3">
          <span className="text-muted-foreground">
            Skew: <span className="text-foreground">{skew.toFixed(2)}</span>
          </span>
          <span className="text-muted-foreground">
            Kurtosis: <span className="text-foreground">{kurtosis.toFixed(2)}</span>
          </span>
        </div>
      </div>
      <div
        role="img"
        aria-label="Return distribution histogram"
        aria-description={`Histogram showing distribution of daily returns with normal distribution overlay. Skewness: ${skew.toFixed(2)}, Kurtosis: ${kurtosis.toFixed(2)}`}
      >
        <ResponsiveContainer width="100%" height={200}>
          <ComposedChart data={chartData}>
          <XAxis
            dataKey="bin"
            tick={{ fontSize: 8, fontFamily: 'monospace' }}
            interval={Math.floor(numBins / 10)}
            angle={-45}
            textAnchor="end"
            height={40}
          />
          <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
          <Tooltip
            contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
            labelFormatter={(label) => `Return: ${label}%`}
          />
          <Bar dataKey="count" fill="#6b6b80" opacity={0.8} />
          <Line type="monotone" dataKey="normal" stroke="#00c853" strokeWidth={2} dot={false} />
        </ComposedChart>
      </ResponsiveContainer>
      </div>
    </Card>
  )
}
