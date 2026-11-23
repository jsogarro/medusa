import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { mockOptionPositions, mockPortfolioGreeks } from '../lib/options-mock-data'
import { formatPnL } from '../lib/utils'
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip } from 'recharts'

export function GreeksDashboard() {
  const greeks = mockPortfolioGreeks
  const positions = mockOptionPositions

  // Calculate utilization percentages
  const deltaUtil = Math.abs(greeks.totalDelta / greeks.deltaLimit) * 100
  const gammaUtil = Math.abs(greeks.totalGamma / greeks.gammaLimit) * 100
  const thetaUtil = Math.abs(greeks.totalTheta / greeks.thetaLimit) * 100
  const vegaUtil = Math.abs(greeks.totalVega / greeks.vegaLimit) * 100

  const renderGauge = (
    label: string,
    value: number,
    limit: number,
    util: number
  ) => {
    const isNegative = value < 0
    const color =
      util > 80 ? 'bg-sell-red' : util > 50 ? 'bg-primary' : 'bg-buy-green'

    return (
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            {label}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-baseline justify-between">
            <span className="text-3xl font-mono font-bold">
              {isNegative && '-'}
              {Math.abs(value).toFixed(2)}
            </span>
            <span className="text-xs text-muted-foreground">
              / {limit.toFixed(0)}
            </span>
          </div>
          <div className="space-y-1">
            <div className="h-2 bg-muted rounded-full overflow-hidden">
              <div
                className={`h-full ${color} transition-all`}
                style={{ width: `${Math.min(util, 100)}%` }}
              />
            </div>
            <p className="text-xs text-muted-foreground text-right">
              {util.toFixed(1)}% utilized
            </p>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">Portfolio Greeks</h1>
        <p className="text-sm text-muted-foreground">
          Risk metrics for options positions
        </p>
      </div>

      {/* Greek Gauges */}
      <div className="grid grid-cols-4 gap-4">
        {renderGauge('Delta', greeks.totalDelta, greeks.deltaLimit, deltaUtil)}
        {renderGauge('Gamma', greeks.totalGamma, greeks.gammaLimit, gammaUtil)}
        {renderGauge('Theta', greeks.totalTheta, greeks.thetaLimit, thetaUtil)}
        {renderGauge('Vega', greeks.totalVega, greeks.vegaLimit, vegaUtil)}
      </div>

      {/* Historical Greeks Chart */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Greeks History (24h)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={greeks.history}>
                <XAxis
                  dataKey="time"
                  tickFormatter={(ts) => new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                />
                <YAxis
                  stroke="#666"
                  style={{ fontSize: 10 }}
                  yAxisId="delta"
                />
                <YAxis
                  stroke="#666"
                  style={{ fontSize: 10 }}
                  yAxisId="vega"
                  orientation="right"
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'hsl(var(--card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '6px',
                    fontSize: 12
                  }}
                  labelFormatter={(ts) => new Date(ts).toLocaleTimeString()}
                  formatter={(value: number, name: string) => [
                    value.toFixed(2),
                    name === 'delta' ? 'Delta' : 'Vega'
                  ]}
                />
                <Line
                  type="monotone"
                  dataKey="delta"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                  dot={false}
                  yAxisId="delta"
                />
                <Line
                  type="monotone"
                  dataKey="vega"
                  stroke="#10b981"
                  strokeWidth={2}
                  dot={false}
                  yAxisId="vega"
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Positions Table */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Position Greeks Breakdown
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 px-3 font-medium text-muted-foreground">
                    Symbol
                  </th>
                  <th className="text-center py-2 px-3 font-medium text-muted-foreground">
                    Strike
                  </th>
                  <th className="text-center py-2 px-3 font-medium text-muted-foreground">
                    Type
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    Qty
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    Delta
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    Gamma
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    Theta
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    Vega
                  </th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">
                    P&L
                  </th>
                </tr>
              </thead>
              <tbody className="font-mono">
                {positions.map((pos, idx) => (
                  <tr
                    key={idx}
                    className="border-b border-border/50 hover:bg-muted/50 transition-colors"
                  >
                    <td className="py-1.5 px-3">{pos.symbol}</td>
                    <td className="text-center py-1.5 px-3">
                      {pos.strike.toFixed(2)}
                    </td>
                    <td className="text-center py-1.5 px-3 uppercase">
                      {pos.type}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        pos.quantity > 0 ? 'text-buy-green' : 'text-sell-red'
                      }`}
                    >
                      {pos.quantity > 0 ? '+' : ''}
                      {pos.quantity}
                    </td>
                    <td className="text-right py-1.5 px-3">
                      {pos.delta.toFixed(2)}
                    </td>
                    <td className="text-right py-1.5 px-3">
                      {pos.gamma.toFixed(3)}
                    </td>
                    <td className="text-right py-1.5 px-3">
                      {pos.theta.toFixed(2)}
                    </td>
                    <td className="text-right py-1.5 px-3">
                      {pos.vega.toFixed(2)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        pos.unrealizedPnL >= 0 ? 'text-buy-green' : 'text-sell-red'
                      }`}
                    >
                      {formatPnL(pos.unrealizedPnL)}
                    </td>
                  </tr>
                ))}
                <tr className="border-t-2 border-border font-semibold bg-muted/30">
                  <td colSpan={4} className="py-2 px-3">
                    TOTAL
                  </td>
                  <td className="text-right py-2 px-3">
                    {positions
                      .reduce((sum, p) => sum + p.delta, 0)
                      .toFixed(2)}
                  </td>
                  <td className="text-right py-2 px-3">
                    {positions
                      .reduce((sum, p) => sum + p.gamma, 0)
                      .toFixed(3)}
                  </td>
                  <td className="text-right py-2 px-3">
                    {positions
                      .reduce((sum, p) => sum + p.theta, 0)
                      .toFixed(2)}
                  </td>
                  <td className="text-right py-2 px-3">
                    {positions
                      .reduce((sum, p) => sum + p.vega, 0)
                      .toFixed(2)}
                  </td>
                  <td
                    className={`text-right py-2 px-3 ${
                      positions.reduce((sum, p) => sum + p.unrealizedPnL, 0) >= 0
                        ? 'text-buy-green'
                        : 'text-sell-red'
                    }`}
                  >
                    {formatPnL(
                      positions.reduce((sum, p) => sum + p.unrealizedPnL, 0)
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
