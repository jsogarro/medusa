import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { generateVolSurfaceData, generateSkewMetrics } from '../lib/options-mock-data'
import { ScatterChart, Scatter, XAxis, YAxis, ZAxis, ResponsiveContainer, Tooltip, Cell } from 'recharts'

export function VolatilitySurface() {
  const surfaceData = useMemo(() => generateVolSurfaceData(), [])
  const skewMetrics = useMemo(() => generateSkewMetrics(), [])

  // Color scale: blue (low IV) -> green -> yellow -> orange -> red (high IV)
  const getColor = (iv: number) => {
    if (iv < 0.22) return '#3b82f6' // blue
    if (iv < 0.26) return '#10b981' // green
    if (iv < 0.30) return '#eab308' // yellow
    if (iv < 0.34) return '#f97316' // orange
    return '#ef4444' // red
  }

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">Volatility Surface</h1>
        <p className="text-sm text-muted-foreground">
          Implied volatility by strike and expiry
        </p>
      </div>

      {/* IV Surface Heatmap */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            IV Surface (%)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-96">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart>
                <XAxis
                  dataKey="moneyness"
                  type="number"
                  domain={[0.85, 1.15]}
                  tickFormatter={(val) => `${(val * 100).toFixed(0)}%`}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                  label={{
                    value: 'Moneyness (Strike / Spot)',
                    position: 'insideBottom',
                    offset: -5,
                    style: { fontSize: 11, fill: '#666' }
                  }}
                />
                <YAxis
                  dataKey="dte"
                  type="number"
                  stroke="#666"
                  style={{ fontSize: 10 }}
                  label={{
                    value: 'Days to Expiry',
                    angle: -90,
                    position: 'insideLeft',
                    style: { fontSize: 11, fill: '#666' }
                  }}
                />
                <ZAxis dataKey="iv" range={[100, 400]} />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'hsl(var(--card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '6px',
                    fontSize: 11
                  }}
                  formatter={(value: number, name: string) => {
                    if (name === 'iv') return [`${(value * 100).toFixed(1)}%`, 'IV']
                    if (name === 'moneyness') return [`${(value * 100).toFixed(1)}%`, 'Moneyness']
                    if (name === 'dte') return [value, 'DTE']
                    return [value, name]
                  }}
                  labelFormatter={(label) => `Strike: $${label}`}
                />
                <Scatter data={surfaceData}>
                  {surfaceData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={getColor(entry.iv)} />
                  ))}
                </Scatter>
              </ScatterChart>
            </ResponsiveContainer>
          </div>

          {/* Legend */}
          <div className="flex items-center justify-center gap-4 mt-4 text-xs">
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: '#3b82f6' }} />
              <span className="text-muted-foreground">Low IV (&lt;22%)</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: '#10b981' }} />
              <span className="text-muted-foreground">22-26%</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: '#eab308' }} />
              <span className="text-muted-foreground">26-30%</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: '#f97316' }} />
              <span className="text-muted-foreground">30-34%</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: '#ef4444' }} />
              <span className="text-muted-foreground">High IV (&gt;34%)</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Skew Metrics */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Volatility Skew Metrics
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-5 gap-4">
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">ATM IV</p>
              <p className="text-2xl font-mono font-bold">
                {(skewMetrics.atmIV * 100).toFixed(1)}%
              </p>
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">Put Skew</p>
              <p className="text-2xl font-mono font-bold text-sell-red">
                {(skewMetrics.putSkew * 100).toFixed(1)}%
              </p>
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">Call Skew</p>
              <p className="text-2xl font-mono font-bold text-buy-green">
                {(skewMetrics.callSkew * 100).toFixed(1)}%
              </p>
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">25Δ Risk Reversal</p>
              <p className="text-2xl font-mono font-bold">
                {(skewMetrics.riskReversal25d * 100).toFixed(1)}%
              </p>
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">25Δ Butterfly</p>
              <p className="text-2xl font-mono font-bold">
                {(skewMetrics.butterfly25d * 100).toFixed(1)}%
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
