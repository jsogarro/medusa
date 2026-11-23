import { Card } from '../components/ui/card'
import { PriceChart } from '../components/charts/PriceChart'
import { PositionMonitor } from '../components/positions/PositionMonitor'
import { useStrategiesStore } from '../stores/strategies'
import { useOrdersStore } from '../stores/orders'
import { formatPrice, formatPnL, formatPercent, formatTimestamp } from '../lib/utils'

export function Dashboard() {
  const strategies = useStrategiesStore((state) => state.strategies)
  const orders = useOrdersStore((state) => state.orders)

  // Calculate portfolio metrics
  const totalPnL = strategies.reduce((sum, s) => sum + s.pnl, 0)
  const portfolioValue = 1234567
  const dayPnL = 2345
  const dayPnLPct = dayPnL / (portfolioValue - dayPnL)
  const sharpeRatio = 2.14

  // Get recent trades (last 10)
  const recentTrades = orders
    .filter((o) => o.status === 'filled')
    .sort((a, b) => b.time.getTime() - a.time.getTime())
    .slice(0, 10)

  return (
    <div className="h-full grid grid-cols-12 gap-2 p-2">
      {/* Left column - 25% */}
      <div className="col-span-3 flex flex-col gap-2 overflow-y-auto">
        {/* Portfolio Summary */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">PORTFOLIO SUMMARY</h3>
          <div className="space-y-2 text-xs font-mono">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Portfolio Value</span>
              <span className="font-semibold">${formatPrice(portfolioValue, 0)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Day P&L</span>
              <span className={dayPnL >= 0 ? 'text-buy-green' : 'text-sell-red'}>
                {formatPnL(dayPnL)} ({formatPercent(dayPnLPct)})
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Total P&L</span>
              <span className={totalPnL >= 0 ? 'text-buy-green' : 'text-sell-red'}>
                {formatPnL(totalPnL)} ({formatPercent(totalPnL / (portfolioValue - totalPnL))})
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Sharpe Ratio</span>
              <span className="font-semibold">{sharpeRatio.toFixed(2)}</span>
            </div>
          </div>
        </Card>

        {/* Strategy Summary */}
        <div className="flex-1 overflow-y-auto space-y-2">
          <h3 className="text-xs font-semibold text-muted-foreground px-1">STRATEGIES</h3>
          {strategies.map((strategy) => (
            <Card key={strategy.name} className="p-2">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs font-semibold font-mono">{strategy.name}</span>
                <div className="flex items-center gap-1">
                  <div
                    className={`w-1.5 h-1.5 rounded-full ${
                      strategy.status === 'running'
                        ? 'bg-buy-green'
                        : strategy.status === 'paused'
                        ? 'bg-pending-yellow'
                        : 'bg-sell-red'
                    }`}
                  />
                  <span className="text-[10px] text-muted-foreground uppercase">{strategy.status}</span>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2 text-[10px] font-mono">
                <div>
                  <div className="text-muted-foreground">Trades</div>
                  <div className="font-semibold">{strategy.trades}</div>
                </div>
                <div>
                  <div className="text-muted-foreground">WR</div>
                  <div className="font-semibold">{(strategy.winRate * 100).toFixed(0)}%</div>
                </div>
                <div>
                  <div className="text-muted-foreground">P&L</div>
                  <div className={strategy.pnl >= 0 ? 'text-buy-green' : 'text-sell-red'}>
                    {formatPnL(strategy.pnl)}
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      </div>

      {/* Center column - 50% */}
      <div className="col-span-6 flex flex-col gap-2">
        {/* Mini Chart */}
        <div className="h-[60%]">
          <PriceChart pair="BTCUSD" exchange="bitstamp" />
        </div>

        {/* Recent Trades */}
        <Card className="flex-1 overflow-hidden flex flex-col">
          <h3 className="text-xs font-semibold text-muted-foreground mb-2 px-3 pt-3">RECENT TRADES</h3>
          <div className="flex-1 overflow-y-auto">
            <table className="w-full text-xs font-mono">
              <thead className="sticky top-0 bg-card border-b border-border">
                <tr className="text-muted-foreground text-[10px]">
                  <th className="text-left p-1.5 font-medium">TIME</th>
                  <th className="text-left p-1.5 font-medium">PAIR</th>
                  <th className="text-left p-1.5 font-medium">SIDE</th>
                  <th className="text-right p-1.5 font-medium">PRICE</th>
                  <th className="text-right p-1.5 font-medium">QTY</th>
                </tr>
              </thead>
              <tbody>
                {recentTrades.map((trade, idx) => (
                  <tr key={idx} className="border-b border-border/50 data-row hover:bg-card-hover">
                    <td className="p-1.5">{formatTimestamp(trade.time)}</td>
                    <td className="p-1.5">{trade.pair}</td>
                    <td className={`p-1.5 ${trade.side === 'buy' ? 'text-buy-green' : 'text-sell-red'}`}>
                      {trade.side.toUpperCase()}
                    </td>
                    <td className="p-1.5 text-right">{formatPrice(trade.price, 2)}</td>
                    <td className="p-1.5 text-right">{trade.quantity.toFixed(4)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </div>

      {/* Right column - 25% */}
      <div className="col-span-3 flex flex-col gap-2">
        {/* Positions */}
        <div className="flex-1 overflow-hidden">
          <PositionMonitor />
        </div>

        {/* Risk Snapshot */}
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">RISK SNAPSHOT</h3>
          <div className="space-y-2 text-xs font-mono">
            <div>
              <div className="flex justify-between mb-1">
                <span className="text-muted-foreground">Drawdown</span>
                <span className="text-sell-red">-3.2%</span>
              </div>
              <div className="w-full h-1 bg-border rounded-full overflow-hidden">
                <div className="h-full bg-sell-red" style={{ width: '21.3%' }} />
              </div>
            </div>
            <div>
              <div className="flex justify-between mb-1">
                <span className="text-muted-foreground">Daily Volume</span>
                <span>23.5%</span>
              </div>
              <div className="w-full h-1 bg-border rounded-full overflow-hidden">
                <div className="h-full bg-info-blue" style={{ width: '23.5%' }} />
              </div>
            </div>
            <div>
              <div className="flex justify-between mb-1">
                <span className="text-muted-foreground">Exposure</span>
                <span>55%</span>
              </div>
              <div className="w-full h-1 bg-border rounded-full overflow-hidden">
                <div className="h-full bg-chart-orange" style={{ width: '55%' }} />
              </div>
            </div>
          </div>
        </Card>
      </div>
    </div>
  )
}
