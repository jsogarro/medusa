import { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip, CartesianGrid, ReferenceLine } from 'recharts'
import { formatPnL } from '../lib/utils'

export function ScenarioAnalysis() {
  const [rateShift, setRateShift] = useState(0)
  const portfolioValue = 8045000 // Sum of all bond market values
  const dv01 = 13200 // Dollar value of 1bp move

  // Generate P&L curve data
  const pnlCurveData = useMemo(() => {
    const data = []
    for (let shift = -200; shift <= 200; shift += 10) {
      const pnl = -dv01 * shift // Negative because higher rates = lower bond prices
      data.push({ shift, pnl, value: portfolioValue + pnl })
    }
    return data
  }, [dv01, portfolioValue])

  // Standard scenarios
  const scenarios = useMemo(() => [
    { name: '+25bp', shift: 25, pnl: -dv01 * 25 },
    { name: '+50bp', shift: 50, pnl: -dv01 * 50 },
    { name: '+100bp', shift: 100, pnl: -dv01 * 100 },
    { name: '-50bp', shift: -50, pnl: -dv01 * -50 },
    { name: '-100bp', shift: -100, pnl: -dv01 * -100 }
  ], [dv01])

  // Custom scenario per-tenor shifts (simplified: assume parallel shift for now)
  const [customShifts, setCustomShifts] = useState({
    '1Y': 0,
    '2Y': 0,
    '5Y': 0,
    '10Y': 0,
    '30Y': 0
  })

  const customPnL = useMemo(
    () => Object.values(customShifts).reduce((sum, shift) => sum - dv01 * shift / 5, 0),
    [customShifts, dv01]
  )

  const handleCustomShiftChange = (tenor: string, value: string) => {
    setCustomShifts({
      ...customShifts,
      [tenor]: parseFloat(value) || 0
    })
  }

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">Scenario Analysis</h1>
        <p className="text-sm text-muted-foreground">
          P&L impact of rate shifts
        </p>
      </div>

      {/* Parallel Shift Slider */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Parallel Rate Shift
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted-foreground">Shift (bp)</span>
              <span className="text-lg font-mono font-bold">
                {rateShift >= 0 ? '+' : ''}{rateShift}bp
              </span>
            </div>
            <input
              type="range"
              min="-200"
              max="200"
              step="5"
              value={rateShift}
              onChange={(e) => setRateShift(parseInt(e.target.value))}
              className="w-full h-2 bg-muted rounded-lg appearance-none cursor-pointer accent-primary"
            />
            <div className="flex justify-between text-[10px] text-muted-foreground font-mono">
              <span>-200bp</span>
              <span>0</span>
              <span>+200bp</span>
            </div>
          </div>

          <div className="space-y-1">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Portfolio Value:</span>
              <span className="font-mono">${portfolioValue.toLocaleString()}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">P&L Impact:</span>
              <span
                className={`font-mono font-semibold ${
                  -dv01 * rateShift >= 0 ? 'text-buy-green' : 'text-sell-red'
                }`}
              >
                {formatPnL(-dv01 * rateShift)}
              </span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">New Value:</span>
              <span className="font-mono">
                ${(portfolioValue - dv01 * rateShift).toLocaleString()}
              </span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* P&L Curve */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            P&L vs Rate Shift
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={pnlCurveData}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                <XAxis
                  dataKey="shift"
                  tickFormatter={(val) => `${val >= 0 ? '+' : ''}${val}bp`}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                />
                <YAxis
                  tickFormatter={(val) => `$${(val / 1000).toFixed(0)}k`}
                  stroke="#666"
                  style={{ fontSize: 10 }}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'hsl(var(--card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '6px',
                    fontSize: 11
                  }}
                  formatter={(value: number) => [`$${value.toLocaleString()}`, 'P&L']}
                  labelFormatter={(val) => `Shift: ${val >= 0 ? '+' : ''}${val}bp`}
                />
                <ReferenceLine y={0} stroke="#666" strokeDasharray="3 3" />
                <ReferenceLine
                  x={0}
                  stroke="hsl(var(--primary))"
                  strokeDasharray="5 5"
                />
                <Line
                  type="monotone"
                  dataKey="pnl"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2.5}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-2 gap-4">
        {/* Standard Scenarios */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Standard Scenarios
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-border">
                    <th className="text-left py-2 px-3 font-medium text-muted-foreground">Scenario</th>
                    <th className="text-right py-2 px-3 font-medium text-muted-foreground">Shift</th>
                    <th className="text-right py-2 px-3 font-medium text-muted-foreground">P&L</th>
                    <th className="text-right py-2 px-3 font-medium text-muted-foreground">P&L %</th>
                  </tr>
                </thead>
                <tbody className="font-mono">
                  {scenarios.map((scenario, idx) => {
                    const pnlPct = (scenario.pnl / portfolioValue) * 100

                    return (
                      <tr
                        key={idx}
                        className="border-b border-border/50 hover:bg-muted/50 transition-colors"
                      >
                        <td className="py-1.5 px-3 font-semibold">{scenario.name}</td>
                        <td className="text-right py-1.5 px-3">
                          {scenario.shift >= 0 ? '+' : ''}{scenario.shift}bp
                        </td>
                        <td
                          className={`text-right py-1.5 px-3 font-semibold ${
                            scenario.pnl >= 0 ? 'text-buy-green' : 'text-sell-red'
                          }`}
                        >
                          {formatPnL(scenario.pnl)}
                        </td>
                        <td
                          className={`text-right py-1.5 px-3 font-semibold ${
                            pnlPct >= 0 ? 'text-buy-green' : 'text-sell-red'
                          }`}
                        >
                          {pnlPct >= 0 ? '+' : ''}{pnlPct.toFixed(2)}%
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>

        {/* Custom Scenario */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Custom Scenario (per-tenor)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {Object.keys(customShifts).map((tenor) => (
                <div key={tenor} className="flex items-center justify-between">
                  <label className="text-xs font-semibold w-12">{tenor}</label>
                  <input
                    type="number"
                    value={customShifts[tenor as keyof typeof customShifts]}
                    onChange={(e) => handleCustomShiftChange(tenor, e.target.value)}
                    className="w-24 px-2 py-1 text-xs font-mono rounded bg-muted border border-border text-right"
                    placeholder="0"
                    step="5"
                  />
                  <span className="text-xs text-muted-foreground w-8">bp</span>
                </div>
              ))}

              <div className="pt-3 border-t border-border space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Estimated P&L:</span>
                  <span
                    className={`font-mono font-semibold ${
                      customPnL >= 0 ? 'text-buy-green' : 'text-sell-red'
                    }`}
                  >
                    {formatPnL(customPnL)}
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">P&L %:</span>
                  <span
                    className={`font-mono font-semibold ${
                      customPnL >= 0 ? 'text-buy-green' : 'text-sell-red'
                    }`}
                  >
                    {customPnL >= 0 ? '+' : ''}{((customPnL / portfolioValue) * 100).toFixed(2)}%
                  </span>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
