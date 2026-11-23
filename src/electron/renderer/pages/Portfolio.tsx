import { Card } from '../components/ui/card'
import { usePositionsStore } from '../stores/positions'
import { useStrategiesStore } from '../stores/strategies'
import { formatPrice, formatPnL } from '../lib/utils'
import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Cell } from 'recharts'

export function Portfolio() {
  const positions = usePositionsStore((state) => state.positions)
  const strategies = useStrategiesStore((state) => state.strategies)

  // Calculate metrics
  const totalExposure = positions.reduce((sum, p) => sum + Math.abs(p.exposure), 0)
  const netLiquidation = 1234567
  const buyingPower = 567890
  const marginUsed = 234567
  const dayPnL = 2345

  // Allocation by exchange
  const exchangeAllocation = positions.reduce((acc, p) => {
    const ex = p.exchange
    acc[ex] = (acc[ex] || 0) + Math.abs(p.exposure)
    return acc
  }, {} as Record<string, number>)

  const exchangeData = Object.entries(exchangeAllocation).map(([name, value]) => ({
    name: name.charAt(0).toUpperCase() + name.slice(1),
    value,
    pct: (value / totalExposure) * 100
  }))

  // Allocation by asset
  const assetAllocation = positions.reduce((acc, p) => {
    const asset = p.pair.replace('USD', '')
    acc[asset] = (acc[asset] || 0) + Math.abs(p.exposure)
    return acc
  }, {} as Record<string, number>)

  const assetData = Object.entries(assetAllocation)
    .map(([name, value]) => ({
      name,
      value,
      pct: (value / totalExposure) * 100
    }))
    .sort((a, b) => b.value - a.value)

  // Allocation by strategy
  const strategyData = strategies.map((s) => ({
    name: s.name,
    value: Math.abs(s.pnl),
    pct: (Math.abs(s.pnl) / strategies.reduce((sum, st) => sum + Math.abs(st.pnl), 0)) * 100
  }))

  return (
    <div className="h-full flex flex-col p-2 gap-2 overflow-y-auto">
      {/* Summary bar */}
      <Card className="p-3">
        <div className="flex items-center justify-between text-xs font-mono">
          <div>
            <span className="text-muted-foreground">Net Liquidation:</span>
            <span className="ml-2 font-semibold">${formatPrice(netLiquidation, 0)}</span>
          </div>
          <div>
            <span className="text-muted-foreground">Buying Power:</span>
            <span className="ml-2 font-semibold">${formatPrice(buyingPower, 0)}</span>
          </div>
          <div>
            <span className="text-muted-foreground">Margin Used:</span>
            <span className="ml-2 font-semibold">${formatPrice(marginUsed, 0)}</span>
          </div>
          <div>
            <span className="text-muted-foreground">Day P&L:</span>
            <span className={`ml-2 font-semibold ${dayPnL >= 0 ? 'text-buy-green' : 'text-sell-red'}`}>
              {formatPnL(dayPnL)}
            </span>
          </div>
        </div>
      </Card>

      {/* Positions table */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">POSITIONS</h3>
        <div className="overflow-auto">
          <table className="w-full text-xs font-mono">
            <thead className="border-b border-border">
              <tr className="text-muted-foreground text-[10px]">
                <th className="text-left p-1.5 font-medium">EXCHANGE</th>
                <th className="text-left p-1.5 font-medium">PAIR</th>
                <th className="text-left p-1.5 font-medium">SIDE</th>
                <th className="text-right p-1.5 font-medium">QTY</th>
                <th className="text-right p-1.5 font-medium">AVG ENTRY</th>
                <th className="text-right p-1.5 font-medium">EXPOSURE</th>
                <th className="text-right p-1.5 font-medium">UNREALIZED P&L</th>
                <th className="text-right p-1.5 font-medium">% OF PORTFOLIO</th>
              </tr>
            </thead>
            <tbody>
              {positions.map((pos, idx) => {
                const side = pos.quantity > 0 ? 'LONG' : 'SHORT'
                const pctOfPortfolio = (Math.abs(pos.exposure) / totalExposure) * 100

                return (
                  <tr key={idx} className="border-b border-border/50 data-row hover:bg-card-hover">
                    <td className="p-1.5 uppercase">{pos.exchange}</td>
                    <td className="p-1.5">{pos.pair}</td>
                    <td className={`p-1.5 ${side === 'LONG' ? 'text-buy-green' : 'text-sell-red'}`}>
                      {side}
                    </td>
                    <td className="p-1.5 text-right">{Math.abs(pos.quantity).toFixed(4)}</td>
                    <td className="p-1.5 text-right">{formatPrice(pos.avgPrice, 2)}</td>
                    <td className="p-1.5 text-right">${formatPrice(Math.abs(pos.exposure), 0)}</td>
                    <td
                      className={`p-1.5 text-right ${
                        pos.unrealizedPnL >= 0 ? 'text-buy-green' : 'text-sell-red'
                      }`}
                    >
                      {formatPnL(pos.unrealizedPnL)}
                    </td>
                    <td className="p-1.5 text-right">{pctOfPortfolio.toFixed(1)}%</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Allocation charts */}
      <div className="grid grid-cols-3 gap-2">
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">BY EXCHANGE</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={exchangeData} layout="vertical">
              <XAxis type="number" hide />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 10 }} width={60} />
              <Bar dataKey="pct" fill="hsl(var(--primary))" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">BY ASSET</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={assetData} layout="vertical">
              <XAxis type="number" hide />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 10 }} width={40} />
              <Bar dataKey="pct" radius={[0, 4, 4, 0]}>
                {assetData.map((_, index) => (
                  <Cell key={`cell-${index}`} fill="#00c853" />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">BY STRATEGY</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={strategyData} layout="vertical">
              <XAxis type="number" hide />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 10 }} width={80} />
              <Bar dataKey="pct" radius={[0, 4, 4, 0]}>
                {strategyData.map((_, index) => (
                  <Cell key={`cell-${index}`} fill="#ff9100" />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </Card>
      </div>
    </div>
  )
}
