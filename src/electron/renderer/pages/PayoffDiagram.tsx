import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import {
  mockPayoffData,
  mockPayoffMetrics
} from '../lib/options-mock-data'
import { formatPnL } from '../lib/utils'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  ResponsiveContainer,
  Tooltip,
  ReferenceLine,
  CartesianGrid
} from 'recharts'

type Strategy = 'iron-condor' | 'vertical-spread' | 'straddle'

export function PayoffDiagram() {
  const [strategy] = useState<Strategy>('iron-condor')

  // Use Iron Condor data for now (other strategies would be generated similarly)
  const payoffData = mockPayoffData
  const metrics = mockPayoffMetrics

  const spotPrice = 155

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Payoff Diagram</h1>
          <p className="text-sm text-muted-foreground">
            P&L analysis at expiration
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            className={`
              px-3 py-1.5 text-xs font-medium rounded transition-colors
              ${
                strategy === 'iron-condor'
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-card text-muted-foreground hover:text-foreground border border-border'
              }
            `}
          >
            Iron Condor
          </button>
          <button
            className="px-3 py-1.5 text-xs font-medium rounded bg-card text-muted-foreground border border-border opacity-50 cursor-not-allowed"
            disabled
          >
            Vertical Spread
          </button>
          <button
            className="px-3 py-1.5 text-xs font-medium rounded bg-card text-muted-foreground border border-border opacity-50 cursor-not-allowed"
            disabled
          >
            Straddle
          </button>
        </div>
      </div>

      {/* Payoff Chart */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            P&L vs Underlying Price
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-96">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={payoffData}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                <XAxis
                  dataKey="underlyingPrice"
                  tickFormatter={(val) => `$${val}`}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                />
                <YAxis
                  tickFormatter={(val) => `$${val}`}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'hsl(var(--card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '6px',
                    fontSize: 12
                  }}
                  formatter={(value: number, name: string) => [
                    `$${value.toFixed(0)}`,
                    name === 'payoffAtExpiry' ? 'At Expiry' : 'Current P&L'
                  ]}
                  labelFormatter={(val) => `Price: $${val}`}
                />

                {/* Zero line */}
                <ReferenceLine y={0} stroke="#666" strokeDasharray="3 3" />

                {/* Current spot price */}
                <ReferenceLine
                  x={spotPrice}
                  stroke="hsl(var(--primary))"
                  strokeDasharray="5 5"
                  label={{
                    value: `Spot: $${spotPrice}`,
                    position: 'top',
                    fill: 'hsl(var(--primary))',
                    fontSize: 11
                  }}
                />

                {/* Breakeven lines */}
                {metrics.breakevens.map((be, idx) => (
                  <ReferenceLine
                    key={idx}
                    x={be}
                    stroke="#10b981"
                    strokeDasharray="3 3"
                    label={{
                      value: `BE: $${be.toFixed(2)}`,
                      position: 'top',
                      fill: '#10b981',
                      fontSize: 10
                    }}
                  />
                ))}

                {/* Current P&L (dashed) */}
                <Line
                  type="monotone"
                  dataKey="currentPnL"
                  stroke="hsl(var(--muted-foreground))"
                  strokeWidth={1.5}
                  strokeDasharray="5 5"
                  dot={false}
                />

                {/* Payoff at expiry (solid) */}
                <Line
                  type="monotone"
                  dataKey="payoffAtExpiry"
                  stroke="hsl(var(--primary))"
                  strokeWidth={3}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Strategy Summary */}
      <div className="grid grid-cols-2 gap-4">
        {/* Position Summary */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Position Summary
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Strategy:</span>
                <span className="font-medium">{metrics.strategy}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Max Profit:</span>
                <span className="font-mono text-buy-green">
                  {formatPnL(metrics.maxProfit)}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Max Loss:</span>
                <span className="font-mono text-sell-red">
                  {formatPnL(metrics.maxLoss)}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Break-even:</span>
                <span className="font-mono">
                  ${metrics.breakevens[0].toFixed(2)} / $
                  {metrics.breakevens[1].toFixed(2)}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Prob. of Profit:</span>
                <span className="font-mono">
                  {(metrics.probabilityOfProfit * 100).toFixed(1)}%
                </span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Legs */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Strategy Legs
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-border">
                    <th className="text-left py-2 px-3 font-medium text-muted-foreground">
                      Strike
                    </th>
                    <th className="text-center py-2 px-3 font-medium text-muted-foreground">
                      Type
                    </th>
                    <th className="text-center py-2 px-3 font-medium text-muted-foreground">
                      Position
                    </th>
                    <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                      Qty
                    </th>
                  </tr>
                </thead>
                <tbody className="font-mono">
                  {metrics.legs.map((leg, idx) => (
                    <tr
                      key={idx}
                      className="border-b border-border/50 hover:bg-muted/50 transition-colors"
                    >
                      <td className="py-1.5 px-3">${leg.strike.toFixed(2)}</td>
                      <td className="text-center py-1.5 px-3 uppercase">
                        {leg.type}
                      </td>
                      <td
                        className={`text-center py-1.5 px-3 uppercase ${
                          leg.position === 'long'
                            ? 'text-buy-green'
                            : 'text-sell-red'
                        }`}
                      >
                        {leg.position}
                      </td>
                      <td className="text-right py-1.5 px-3">
                        {leg.quantity}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
