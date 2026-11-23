import { Card } from '../components/ui/card'
import {
  BarChart,
  Bar,
  ResponsiveContainer,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Cell
} from 'recharts'
import {
  generateMaturityBuckets,
  generateCashFlows
} from '../lib/bond-mock-data'
import { formatPrice } from '../lib/utils'

export function BondLadder() {
  const buckets = generateMaturityBuckets()
  const cashFlows = generateCashFlows()

  // Prepare chart data
  const chartData = buckets.map(b => ({
    year: b.year.toString(),
    notional: b.notional / 1_000_000 // in millions
  }))

  // Orange gradient for bars
  const getBarColor = (index: number, total: number) => {
    const intensity = 60 + (index / total) * 30
    return `hsl(14 100% ${intensity}%)`
  }

  // All holdings flattened
  const allHoldings = buckets.flatMap(b => b.holdings)

  return (
    <div className="h-full flex flex-col gap-2 p-2 overflow-y-auto">
      {/* Maturity Ladder Chart */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">MATURITY LADDER</h3>
        <ResponsiveContainer width="100%" height={240}>
          <BarChart data={chartData} layout="vertical" margin={{ top: 5, right: 30, left: 50, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
            <XAxis
              type="number"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              tickFormatter={(value) => `$${value.toFixed(1)}M`}
            />
            <YAxis
              type="category"
              dataKey="year"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              width={45}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(240 8% 9%)',
                border: '1px solid hsl(240 7% 16%)',
                borderRadius: '4px',
                fontSize: '11px'
              }}
              formatter={(value: number) => [`$${value.toFixed(2)}M`, 'Notional']}
            />
            <Bar dataKey="notional" radius={[0, 4, 4, 0]}>
              {chartData.map((_, index) => (
                <Cell key={`cell-${index}`} fill={getBarColor(index, chartData.length)} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </Card>

      {/* Holdings Table */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">BOND HOLDINGS</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-[11px] font-mono">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left text-muted-foreground font-semibold pb-2 pr-4">Maturity</th>
                <th className="text-left text-muted-foreground font-semibold pb-2 pr-4">CUSIP</th>
                <th className="text-right text-muted-foreground font-semibold pb-2 pr-4">Coupon</th>
                <th className="text-right text-muted-foreground font-semibold pb-2 pr-4">YTM</th>
                <th className="text-right text-muted-foreground font-semibold pb-2 pr-4">Face Value</th>
                <th className="text-right text-muted-foreground font-semibold pb-2 pr-4">Market Value</th>
                <th className="text-right text-muted-foreground font-semibold pb-2">Duration</th>
              </tr>
            </thead>
            <tbody>
              {allHoldings.map(holding => (
                <tr key={holding.cusip} className="border-b border-border/50 hover:bg-card-hover transition-colors">
                  <td className="py-2 pr-4">{holding.maturity}</td>
                  <td className="py-2 pr-4 text-muted-foreground">{holding.cusip}</td>
                  <td className="text-right py-2 pr-4">{holding.coupon.toFixed(3)}%</td>
                  <td className="text-right py-2 pr-4">{holding.ytm.toFixed(2)}%</td>
                  <td className="text-right py-2 pr-4">${formatPrice(holding.faceValue, 0)}</td>
                  <td className="text-right py-2 pr-4">
                    <span className={holding.marketValue < holding.faceValue ? 'text-sell-red' : 'text-buy-green'}>
                      ${formatPrice(holding.marketValue, 0)}
                    </span>
                  </td>
                  <td className="text-right py-2">{holding.duration.toFixed(1)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-border font-semibold">
                <td colSpan={4} className="py-2 pr-4">TOTAL</td>
                <td className="text-right py-2 pr-4">
                  ${formatPrice(allHoldings.reduce((sum, h) => sum + h.faceValue, 0), 0)}
                </td>
                <td className="text-right py-2 pr-4">
                  ${formatPrice(allHoldings.reduce((sum, h) => sum + h.marketValue, 0), 0)}
                </td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </Card>

      {/* Cash Flows */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">UPCOMING CASH FLOWS (6 Months)</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-[11px] font-mono">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left text-muted-foreground font-semibold pb-2 pr-4">Date</th>
                <th className="text-left text-muted-foreground font-semibold pb-2 pr-4">Type</th>
                <th className="text-left text-muted-foreground font-semibold pb-2 pr-4">CUSIP</th>
                <th className="text-right text-muted-foreground font-semibold pb-2">Amount</th>
              </tr>
            </thead>
            <tbody>
              {cashFlows.map((flow, idx) => (
                <tr key={idx} className="border-b border-border/50">
                  <td className="py-2 pr-4">{flow.date}</td>
                  <td className="py-2 pr-4">
                    <span className={`px-1.5 py-0.5 rounded text-[10px] ${
                      flow.type === 'maturity'
                        ? 'bg-primary/20 text-primary'
                        : 'bg-muted text-muted-foreground'
                    }`}>
                      {flow.type.toUpperCase()}
                    </span>
                  </td>
                  <td className="py-2 pr-4 text-muted-foreground">{flow.cusip}</td>
                  <td className="text-right py-2 font-semibold">${formatPrice(flow.amount, 0)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-border font-semibold">
                <td colSpan={3} className="py-2 pr-4">TOTAL</td>
                <td className="text-right py-2">
                  ${formatPrice(cashFlows.reduce((sum, f) => sum + f.amount, 0), 0)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
      </Card>
    </div>
  )
}
