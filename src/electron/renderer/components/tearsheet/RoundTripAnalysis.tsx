import { BarChart, Bar, LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip } from 'recharts'
import { Card } from '../ui/card'
import type { RoundTripTrade } from '../../lib/tearsheet-data'

interface RoundTripAnalysisProps {
  roundTrips: RoundTripTrade[]
}

export function RoundTripAnalysis({ roundTrips }: RoundTripAnalysisProps) {
  // P&L distribution histogram
  const pnlBins = 30
  const pnlMin = Math.min(...roundTrips.map((t) => t.pnl))
  const pnlMax = Math.max(...roundTrips.map((t) => t.pnl))
  const pnlBinWidth = (pnlMax - pnlMin) / pnlBins

  const pnlHistogram = Array.from({ length: pnlBins }, (_, i) => ({
    binStart: pnlMin + i * pnlBinWidth,
    count: 0
  }))

  roundTrips.forEach((trade) => {
    const binIndex = Math.min(Math.floor((trade.pnl - pnlMin) / pnlBinWidth), pnlBins - 1)
    if (binIndex >= 0 && binIndex < pnlBins) {
      pnlHistogram[binIndex].count++
    }
  })

  const pnlChartData = pnlHistogram.map((bin) => ({
    bin: `$${bin.binStart.toFixed(0)}`,
    count: bin.count
  }))

  // Duration distribution histogram
  const durationBins = 20
  const durationMax = Math.max(...roundTrips.map((t) => t.durationHours))
  const durationBinWidth = durationMax / durationBins

  const durationHistogram = Array.from({ length: durationBins }, (_, i) => ({
    binStart: i * durationBinWidth,
    count: 0
  }))

  roundTrips.forEach((trade) => {
    const binIndex = Math.min(Math.floor(trade.durationHours / durationBinWidth), durationBins - 1)
    if (binIndex >= 0 && binIndex < durationBins) {
      durationHistogram[binIndex].count++
    }
  })

  const durationChartData = durationHistogram.map((bin) => ({
    bin: `${bin.binStart.toFixed(0)}h`,
    count: bin.count
  }))

  // Cumulative P&L by trade
  let cumulativePnL = 0
  const cumulativeData = roundTrips.slice(0, 200).map((trade, i) => {
    cumulativePnL += trade.pnl
    return {
      tradeNum: i + 1,
      cumulative: cumulativePnL
    }
  })

  // Win/Loss streaks
  const streaks: number[] = []
  let currentStreak = 0
  let lastWasWin = roundTrips[0]?.isWin ?? false

  roundTrips.forEach((trade) => {
    if (trade.isWin === lastWasWin) {
      currentStreak++
    } else {
      streaks.push(lastWasWin ? currentStreak : -currentStreak)
      currentStreak = 1
      lastWasWin = trade.isWin
    }
  })
  streaks.push(lastWasWin ? currentStreak : -currentStreak)

  // Group streaks into bins
  const streakCounts = new Map<number, number>()
  streaks.forEach((streak) => {
    const absStreak = Math.abs(streak)
    streakCounts.set(absStreak, (streakCounts.get(absStreak) || 0) + 1)
  })

  const streakChartData = Array.from(streakCounts.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([streak]) => ({
      streak: streak.toString(),
      wins: streaks.filter((s) => s === streak).length,
      losses: streaks.filter((s) => s === -streak).length
    }))

  return (
    <div className="space-y-4">
      {/* P&L Distribution */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ROUND TRIP P&L DISTRIBUTION</h3>
        <ResponsiveContainer width="100%" height={180}>
          <BarChart data={pnlChartData}>
            <XAxis
              dataKey="bin"
              tick={{ fontSize: 8, fontFamily: 'monospace' }}
              interval={Math.floor(pnlBins / 8)}
              angle={-45}
              textAnchor="end"
              height={40}
            />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              labelFormatter={(label) => `P&L: ${label}`}
            />
            <Bar dataKey="count" fill="#00c853" />
          </BarChart>
        </ResponsiveContainer>
      </Card>

      {/* Duration Distribution */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">TRADE DURATION DISTRIBUTION</h3>
        <ResponsiveContainer width="100%" height={180}>
          <BarChart data={durationChartData}>
            <XAxis
              dataKey="bin"
              tick={{ fontSize: 8, fontFamily: 'monospace' }}
              interval={Math.floor(durationBins / 8)}
              angle={-45}
              textAnchor="end"
              height={40}
            />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              labelFormatter={(label) => `Duration: ${label}`}
            />
            <Bar dataKey="count" fill="#ff9100" />
          </BarChart>
        </ResponsiveContainer>
      </Card>

      {/* Cumulative P&L */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">CUMULATIVE P&L BY TRADE</h3>
        <ResponsiveContainer width="100%" height={180}>
          <LineChart data={cumulativeData}>
            <XAxis dataKey="tradeNum" tick={{ fontSize: 10, fontFamily: 'monospace' }} label={{ value: 'Trade #', position: 'insideBottom', offset: -5, fontSize: 10 }} />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
              formatter={(value: number) => `$${value.toFixed(0)}`}
            />
            <Line type="stepAfter" dataKey="cumulative" stroke="#00c853" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </Card>

      {/* Win/Loss Streaks */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">WIN / LOSS STREAKS</h3>
        <ResponsiveContainer width="100%" height={180}>
          <BarChart data={streakChartData}>
            <XAxis dataKey="streak" tick={{ fontSize: 10, fontFamily: 'monospace' }} label={{ value: 'Streak Length', position: 'insideBottom', offset: -5, fontSize: 10 }} />
            <YAxis tick={{ fontSize: 10, fontFamily: 'monospace' }} />
            <Tooltip
              contentStyle={{ backgroundColor: 'hsl(var(--card))', border: '1px solid hsl(var(--border))' }}
            />
            <Bar dataKey="wins" fill="#00c853" stackId="stack" />
            <Bar dataKey="losses" fill="#ff1744" stackId="stack" />
          </BarChart>
        </ResponsiveContainer>
      </Card>
    </div>
  )
}
