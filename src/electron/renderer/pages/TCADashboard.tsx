import { useState, useMemo, memo } from 'react'
import { Card } from '../components/ui/card'
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  ScatterChart,
  Scatter,
  ResponsiveContainer,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Cell,
  ReferenceLine
} from 'recharts'
import {
  generateTCAOrders,
  generateTCAMetrics,
  generateSlippageByStrategy,
  generateSlippageByExchange,
  generateDailySlippage,
  type SlippageByStrategy,
  type SlippageByExchange,
  type DailySlippage
} from '../lib/tca-mock-data'
import { formatPrice, formatTimestamp } from '../lib/utils'

// Memoized chart components to prevent unnecessary re-renders
const StrategySlippageChart = memo(function StrategySlippageChart({ data }: { data: SlippageByStrategy[] }) {
  return (
    <div role="img" aria-label="Bar chart showing average slippage by trading strategy">
      <ResponsiveContainer width="100%" height={200}>
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 5, right: 30, left: 80, bottom: 5 }}
      >
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
        <XAxis
          type="number"
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          tickFormatter={(value) => `${value.toFixed(1)} bps`}
        />
        <YAxis
          type="category"
          dataKey="strategy"
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          width={70}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: 'hsl(240 8% 9%)',
            border: '1px solid hsl(240 7% 16%)',
            borderRadius: '4px',
            fontSize: '11px'
          }}
          formatter={(value: number) => [`${value.toFixed(2)} bps`, 'Avg Slippage']}
        />
        <Bar dataKey="avgSlippageBps" radius={[0, 4, 4, 0]}>
          {data.map((_entry, index) => (
            <Cell key={`cell-${index}`} fill="hsl(14 100% 60%)" />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
    </div>
  )
})

const ExchangeSlippageChart = memo(function ExchangeSlippageChart({ data }: { data: SlippageByExchange[] }) {
  return (
    <div role="img" aria-label="Bar chart showing average slippage by exchange">
      <ResponsiveContainer width="100%" height={200}>
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 5, right: 30, left: 80, bottom: 5 }}
      >
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
        <XAxis
          type="number"
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          tickFormatter={(value) => `${value.toFixed(1)} bps`}
        />
        <YAxis
          type="category"
          dataKey="exchange"
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          width={70}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: 'hsl(240 8% 9%)',
            border: '1px solid hsl(240 7% 16%)',
            borderRadius: '4px',
            fontSize: '11px'
          }}
          formatter={(value: number) => [`${value.toFixed(2)} bps`, 'Avg Slippage']}
        />
        <Bar dataKey="avgSlippageBps" radius={[0, 4, 4, 0]}>
          {data.map((_entry, index) => (
            <Cell key={`cell-${index}`} fill="hsl(210 100% 60%)" />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
    </div>
  )
})

const DailySlippageLineChart = memo(function DailySlippageLineChart({ data }: { data: DailySlippage[] }) {
  return (
    <div role="img" aria-label="Line chart showing daily average slippage over 30 days">
      <ResponsiveContainer width="100%" height={200}>
      <LineChart data={data} margin={{ top: 5, right: 30, left: 10, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
        <XAxis
          dataKey="date"
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          tickFormatter={(value) => new Date(value).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
        />
        <YAxis
          stroke="hsl(240 5% 54%)"
          tick={{ fontSize: 11 }}
          tickFormatter={(value) => `${value.toFixed(0)} bps`}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: 'hsl(240 8% 9%)',
            border: '1px solid hsl(240 7% 16%)',
            borderRadius: '4px',
            fontSize: '11px'
          }}
          labelFormatter={(label) => new Date(label).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
          formatter={(value: number) => [`${value.toFixed(2)} bps`, 'Avg Slippage']}
        />
        <Line
          type="monotone"
          dataKey="avgSlippageBps"
          stroke="hsl(14 100% 60%)"
          strokeWidth={2}
          dot={false}
        />
      </LineChart>
    </ResponsiveContainer>
    </div>
  )
})

export function TCADashboard() {
  const [expandedOrderId, setExpandedOrderId] = useState<string | null>(null)

  // Memoize all mock data generators - they're now cached singletons
  const metrics = useMemo(() => generateTCAMetrics(), [])
  const orders = useMemo(() => generateTCAOrders(), [])
  const slippageByStrategy = useMemo(() => generateSlippageByStrategy(), [])
  const slippageByExchange = useMemo(() => generateSlippageByExchange(), [])
  const dailySlippage = useMemo(() => generateDailySlippage(), [])

  // Pre-trade vs Post-trade scatter data
  const scatterData = useMemo(() => orders.map(o => ({
    estimated: o.estimatedCost,
    actual: o.actualCost,
    orderId: o.orderId,
    symbol: o.symbol
  })), [orders])

  const toggleExpandOrder = (orderId: string) => {
    setExpandedOrderId(expandedOrderId === orderId ? null : orderId)
  }

  return (
    <div className="h-full flex flex-col gap-2 p-2 overflow-y-auto">
      {/* Row 1: Summary Cards */}
      <div className="grid grid-cols-4 gap-2">
        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">AVG SLIPPAGE</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            {metrics.avgSlippageBps.toFixed(1)}
            <span className="text-sm text-muted-foreground ml-1">bps</span>
          </div>
        </Card>

        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">TOTAL COST</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            ${formatPrice(metrics.totalCost, 0)}
          </div>
        </Card>

        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">BEST EXECUTION</div>
          <div className="text-2xl font-mono font-semibold text-buy-green">
            {metrics.bestExecutionPct.toFixed(0)}%
          </div>
          <div className="text-[10px] text-muted-foreground mt-1">&lt;5bps slippage</div>
        </Card>

        <Card className="p-3">
          <div className="text-[10px] text-muted-foreground font-semibold mb-1">ORDERS ANALYZED</div>
          <div className="text-2xl font-mono font-semibold text-primary">
            {metrics.ordersAnalyzed}
          </div>
        </Card>
      </div>

      {/* Row 2: Slippage by Strategy & Exchange */}
      <div className="grid grid-cols-2 gap-2">
        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">
            SLIPPAGE BY STRATEGY
          </h3>
          <StrategySlippageChart data={slippageByStrategy} />
        </Card>

        <Card className="p-3">
          <h3 className="text-xs font-semibold text-muted-foreground mb-3">
            SLIPPAGE BY EXCHANGE
          </h3>
          <ExchangeSlippageChart data={slippageByExchange} />
        </Card>
      </div>

      {/* Row 3: Slippage Over Time */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">
          SLIPPAGE OVER TIME (30 Days)
        </h3>
        <DailySlippageLineChart data={dailySlippage} />
      </Card>

      {/* Row 4: Order-Level TCA Table */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">ORDER-LEVEL TCA</h3>
        <div className="overflow-auto max-h-[400px]">
          <table className="w-full text-xs font-mono">
            <thead className="sticky top-0 bg-card border-b border-border">
              <tr className="text-muted-foreground text-[10px]">
                <th className="text-left p-1.5 font-medium">TIME</th>
                <th className="text-left p-1.5 font-medium">ORDER ID</th>
                <th className="text-left p-1.5 font-medium">SYMBOL</th>
                <th className="text-left p-1.5 font-medium">SIDE</th>
                <th className="text-right p-1.5 font-medium">QTY</th>
                <th className="text-right p-1.5 font-medium">AVG FILL</th>
                <th className="text-right p-1.5 font-medium">ARRIVAL</th>
                <th className="text-right p-1.5 font-medium">SLIPPAGE</th>
                <th className="text-right p-1.5 font-medium">COST</th>
                <th className="text-left p-1.5 font-medium">ALGO</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => {
                const isExpanded = expandedOrderId === order.orderId
                const isFavorable = order.slippageBps < 0
                const isAdverse = order.slippageBps > 5

                return (
                  <>
                    <tr
                      key={order.orderId}
                      className="border-b border-border/50 data-row hover:bg-card-hover cursor-pointer"
                      onClick={() => toggleExpandOrder(order.orderId)}
                    >
                      <td className="p-1.5">{formatTimestamp(order.time)}</td>
                      <td className="p-1.5">{order.orderId}</td>
                      <td className="p-1.5">{order.symbol}</td>
                      <td className={`p-1.5 ${order.side === 'buy' ? 'text-buy-green' : 'text-sell-red'}`}>
                        {order.side.toUpperCase()}
                      </td>
                      <td className="p-1.5 text-right">{order.quantity.toFixed(4)}</td>
                      <td className="p-1.5 text-right">${formatPrice(order.avgFill, 2)}</td>
                      <td className="p-1.5 text-right">${formatPrice(order.arrivalPrice, 2)}</td>
                      <td className={`p-1.5 text-right font-semibold ${
                        isFavorable ? 'text-buy-green' : isAdverse ? 'text-sell-red' : 'text-pending-yellow'
                      }`}>
                        {order.slippageBps.toFixed(1)} bps
                      </td>
                      <td className="p-1.5 text-right">${formatPrice(order.cost, 2)}</td>
                      <td className="p-1.5">{order.algo}</td>
                    </tr>
                    {isExpanded && (
                      <tr className="border-b border-border/50 bg-card/50">
                        <td colSpan={10} className="p-3">
                          <div className="grid grid-cols-3 gap-4 text-xs">
                            <div>
                              <div className="text-muted-foreground mb-1">Pre-Trade Estimate</div>
                              <div className="font-mono">${formatPrice(order.estimatedCost, 2)}</div>
                            </div>
                            <div>
                              <div className="text-muted-foreground mb-1">Actual Cost</div>
                              <div className="font-mono">${formatPrice(order.actualCost, 2)}</div>
                            </div>
                            <div>
                              <div className="text-muted-foreground mb-1">Variance</div>
                              <div className={`font-mono ${
                                order.actualCost > order.estimatedCost ? 'text-sell-red' : 'text-buy-green'
                              }`}>
                                {(((order.actualCost - order.estimatedCost) / order.estimatedCost) * 100).toFixed(1)}%
                              </div>
                            </div>
                            <div>
                              <div className="text-muted-foreground mb-1">Strategy</div>
                              <div className="font-mono">{order.strategy}</div>
                            </div>
                            <div>
                              <div className="text-muted-foreground mb-1">Exchange</div>
                              <div className="font-mono">{order.exchange}</div>
                            </div>
                            <div>
                              <div className="text-muted-foreground mb-1">Execution Quality</div>
                              <div className="font-mono">
                                {isFavorable ? '✓ Excellent' : isAdverse ? '✗ Poor' : '~ Good'}
                              </div>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Row 5: Pre-trade vs Post-trade Scatter */}
      <Card className="p-3">
        <h3 className="text-xs font-semibold text-muted-foreground mb-3">
          PRE-TRADE VS POST-TRADE (Estimated vs Actual Cost)
        </h3>
        <div role="img" aria-label="Scatter plot comparing estimated vs actual execution costs">
        <ResponsiveContainer width="100%" height={280}>
          <ScatterChart margin={{ top: 20, right: 20, bottom: 20, left: 20 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 7% 16%)" />
            <XAxis
              type="number"
              dataKey="estimated"
              name="Estimated Cost"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              label={{ value: 'Estimated Cost ($)', position: 'insideBottom', offset: -10, fontSize: 11 }}
              tickFormatter={(value) => `$${formatPrice(value, 0)}`}
            />
            <YAxis
              type="number"
              dataKey="actual"
              name="Actual Cost"
              stroke="hsl(240 5% 54%)"
              tick={{ fontSize: 11 }}
              label={{ value: 'Actual Cost ($)', angle: -90, position: 'insideLeft', fontSize: 11 }}
              tickFormatter={(value) => `$${formatPrice(value, 0)}`}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(240 8% 9%)',
                border: '1px solid hsl(240 7% 16%)',
                borderRadius: '4px',
                fontSize: '11px'
              }}
              formatter={(value: number) => `$${formatPrice(value, 2)}`}
              labelFormatter={(_value, payload) => {
                if (payload && payload.length > 0) {
                  return `${payload[0].payload.orderId} - ${payload[0].payload.symbol}`
                }
                return ''
              }}
            />
            <ReferenceLine
              segment={[
                { x: 0, y: 0 },
                { x: Math.max(...scatterData.map(d => d.estimated)), y: Math.max(...scatterData.map(d => d.estimated)) }
              ]}
              stroke="hsl(240 5% 54%)"
              strokeDasharray="3 3"
              label={{ value: 'Perfect Estimation', position: 'insideTopRight', fontSize: 10 }}
            />
            <Scatter name="Orders" data={scatterData} fill="hsl(14 100% 60%)" opacity={0.6} />
          </ScatterChart>
        </ResponsiveContainer>
        </div>
        <div className="text-[10px] text-muted-foreground mt-2 text-center">
          Points on diagonal = perfect estimation | Above diagonal = underestimated cost | Below diagonal = overestimated
        </div>
      </Card>
    </div>
  )
}
