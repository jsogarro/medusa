import { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { generateOptionsChain, generateStrategyTemplates } from '../lib/options-mock-data'
import { formatPrice, formatPnL } from '../lib/utils'
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip, ReferenceLine, CartesianGrid } from 'recharts'

interface StrategyLeg {
  strike: number
  type: 'call' | 'put'
  side: 'buy' | 'sell'
  quantity: number
  price: number
}

export function OptionsStrategyBuilder() {
  const [symbol] = useState('AAPL')
  const [spotPrice] = useState(155)
  const [expiry] = useState('2026-06-16')
  const [legs, setLegs] = useState<StrategyLeg[]>([])

  const chain = generateOptionsChain(symbol, spotPrice, expiry)
  const templates = useMemo(() => generateStrategyTemplates(spotPrice), [spotPrice])

  // Calculate net Greeks
  const netGreeks = useMemo(() => legs.reduce(
    (acc, leg) => {
      const option = chain.find(c => c.strike === leg.strike)
      if (!option) return acc

      const multiplier = leg.side === 'buy' ? 1 : -1
      const delta = leg.type === 'call' ? option.callDelta : option.putDelta
      const iv = leg.type === 'call' ? option.callIV : option.putIV

      return {
        delta: acc.delta + delta * multiplier * leg.quantity,
        gamma: acc.gamma + 0.05 * multiplier * leg.quantity,
        theta: acc.theta + (leg.side === 'sell' ? 0.8 : -0.5) * leg.quantity,
        vega: acc.vega + iv * 10 * multiplier * leg.quantity
      }
    },
    { delta: 0, gamma: 0, theta: 0, vega: 0 }
  ), [legs, chain])

  // Calculate max profit, max loss, breakevens
  const calculatePayoff = useMemo(() => {
    if (legs.length === 0) return { maxProfit: 0, maxLoss: 0, breakevens: [], data: [] }

    const netCredit = legs.reduce((sum, leg) => {
      return sum + (leg.side === 'sell' ? leg.price : -leg.price) * leg.quantity * 100
    }, 0)

    const data = []
    let maxProfit = netCredit
    let maxLoss = netCredit

    for (let price = spotPrice * 0.7; price <= spotPrice * 1.3; price += 0.5) {
      let payoff = netCredit

      legs.forEach(leg => {
        if (leg.type === 'call' && price > leg.strike) {
          const intrinsic = (price - leg.strike) * leg.quantity * 100
          payoff += leg.side === 'sell' ? -intrinsic : intrinsic
        } else if (leg.type === 'put' && price < leg.strike) {
          const intrinsic = (leg.strike - price) * leg.quantity * 100
          payoff += leg.side === 'sell' ? -intrinsic : intrinsic
        }
      })

      data.push({ price, payoff })
      maxProfit = Math.max(maxProfit, payoff)
      maxLoss = Math.min(maxLoss, payoff)
    }

    // Find breakevens (zero crossings)
    const breakevens: number[] = []
    for (let i = 1; i < data.length; i++) {
      if ((data[i - 1].payoff <= 0 && data[i].payoff > 0) || (data[i - 1].payoff > 0 && data[i].payoff <= 0)) {
        breakevens.push(data[i].price)
      }
    }

    return { maxProfit, maxLoss, breakevens, data }
  }, [legs, spotPrice])

  const { maxProfit, maxLoss, breakevens, data } = calculatePayoff

  const addLeg = (strike: number, type: 'call' | 'put', side: 'buy' | 'sell') => {
    const option = chain.find(c => c.strike === strike)
    if (!option) return

    const price = type === 'call'
      ? (option.callBid + option.callAsk) / 2
      : (option.putBid + option.putAsk) / 2

    setLegs([...legs, { strike, type, side, quantity: 1, price }])
  }

  const removeLeg = (index: number) => {
    setLegs(legs.filter((_, i) => i !== index))
  }

  const loadTemplate = (template: typeof templates[0]) => {
    setLegs(template.legs.map(leg => {
      const option = chain.find(c => c.strike === leg.strike)
      const price = leg.type === 'call'
        ? ((option?.callBid || 0) + (option?.callAsk || 0)) / 2
        : ((option?.putBid || 0) + (option?.putAsk || 0)) / 2

      return {
        strike: leg.strike,
        type: leg.type,
        side: leg.position as 'buy' | 'sell',
        quantity: leg.quantity,
        price
      }
    }))
  }

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Options Strategy Builder</h1>
          <p className="text-sm text-muted-foreground">
            Construct multi-leg options strategies
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        {/* Left: Leg Builder */}
        <div className="space-y-4">
          {/* Templates */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Strategy Templates
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {templates.map((template, idx) => (
                <button
                  key={idx}
                  onClick={() => loadTemplate(template)}
                  className="w-full px-3 py-2 text-xs text-left rounded bg-card hover:bg-muted/50 border border-border transition-colors"
                >
                  <div className="font-medium">{template.name}</div>
                  <div className="text-muted-foreground text-[10px]">{template.description}</div>
                </button>
              ))}
            </CardContent>
          </Card>

          {/* Current Legs */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Strategy Legs ({legs.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {legs.length === 0 ? (
                <p className="text-xs text-muted-foreground text-center py-6">
                  Add legs to build your strategy
                </p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-border">
                        <th className="text-left py-2 px-3 font-medium text-muted-foreground">Strike</th>
                        <th className="text-center py-2 px-3 font-medium text-muted-foreground">Type</th>
                        <th className="text-center py-2 px-3 font-medium text-muted-foreground">Side</th>
                        <th className="text-right py-2 px-3 font-medium text-muted-foreground">Qty</th>
                        <th className="text-right py-2 px-3 font-medium text-muted-foreground">Price</th>
                        <th className="text-right py-2 px-3 font-medium text-muted-foreground"></th>
                      </tr>
                    </thead>
                    <tbody className="font-mono">
                      {legs.map((leg, idx) => (
                        <tr key={idx} className="border-b border-border/50 hover:bg-muted/50 transition-colors">
                          <td className="py-1.5 px-3">${leg.strike.toFixed(2)}</td>
                          <td className="text-center py-1.5 px-3 uppercase">{leg.type}</td>
                          <td className={`text-center py-1.5 px-3 uppercase ${leg.side === 'buy' ? 'text-buy-green' : 'text-sell-red'}`}>
                            {leg.side}
                          </td>
                          <td className="text-right py-1.5 px-3">{leg.quantity}</td>
                          <td className="text-right py-1.5 px-3">{formatPrice(leg.price)}</td>
                          <td className="text-right py-1.5 px-3">
                            <button
                              onClick={() => removeLeg(idx)}
                              className="text-sell-red hover:underline"
                            >
                              Remove
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Net Greeks */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Net Greeks
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">Delta</p>
                  <p className="text-xl font-mono font-bold">{netGreeks.delta.toFixed(2)}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">Gamma</p>
                  <p className="text-xl font-mono font-bold">{netGreeks.gamma.toFixed(2)}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">Theta</p>
                  <p className="text-xl font-mono font-bold">{netGreeks.theta.toFixed(2)}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">Vega</p>
                  <p className="text-xl font-mono font-bold">{netGreeks.vega.toFixed(2)}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* P&L Summary */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                P&L Summary
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Max Profit:</span>
                  <span className="font-mono text-buy-green">{formatPnL(maxProfit)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Max Loss:</span>
                  <span className="font-mono text-sell-red">{formatPnL(maxLoss)}</span>
                </div>
                {breakevens.length > 0 && (
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Breakevens:</span>
                    <span className="font-mono">
                      {breakevens.map(b => `$${b.toFixed(2)}`).join(', ')}
                    </span>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Right: Payoff Diagram + Strike Selection */}
        <div className="space-y-4">
          {/* Payoff Preview */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Payoff Diagram
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-80">
                {data.length === 0 ? (
                  <div className="flex items-center justify-center h-full text-xs text-muted-foreground">
                    Add legs to see payoff diagram
                  </div>
                ) : (
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={data}>
                      <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                      <XAxis
                        dataKey="price"
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
                          fontSize: 11
                        }}
                        formatter={(value: number) => [`$${value.toFixed(0)}`, 'P&L']}
                        labelFormatter={(val) => `Price: $${val}`}
                      />
                      <ReferenceLine y={0} stroke="#666" strokeDasharray="3 3" />
                      <ReferenceLine
                        x={spotPrice}
                        stroke="hsl(var(--primary))"
                        strokeDasharray="5 5"
                        label={{
                          value: `Spot: $${spotPrice}`,
                          position: 'top',
                          fill: 'hsl(var(--primary))',
                          fontSize: 10
                        }}
                      />
                      <Line
                        type="monotone"
                        dataKey="payoff"
                        stroke="hsl(var(--primary))"
                        strokeWidth={2.5}
                        dot={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Strike Picker */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                Add Leg
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <div className="max-h-64 overflow-y-auto">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-card">
                    <tr className="border-b border-border">
                      <th className="text-left py-2 px-3 font-medium text-muted-foreground">Strike</th>
                      <th className="text-center py-2 px-3 font-medium text-muted-foreground">Call</th>
                      <th className="text-center py-2 px-3 font-medium text-muted-foreground">Put</th>
                    </tr>
                  </thead>
                  <tbody className="font-mono">
                    {chain.filter((_, idx) => idx % 2 === 0).map((row) => (
                      <tr
                        key={row.strike}
                        className={`border-b border-border/50 hover:bg-muted/50 transition-colors ${row.isATM ? 'bg-primary/10' : ''}`}
                      >
                        <td className={`py-1.5 px-3 font-semibold ${row.isATM ? 'text-primary' : ''}`}>
                          ${row.strike.toFixed(2)}
                        </td>
                        <td className="text-center py-1.5 px-3 space-x-1">
                          <button
                            onClick={() => addLeg(row.strike, 'call', 'buy')}
                            className="text-buy-green hover:underline text-[10px]"
                          >
                            BUY
                          </button>
                          <button
                            onClick={() => addLeg(row.strike, 'call', 'sell')}
                            className="text-sell-red hover:underline text-[10px]"
                          >
                            SELL
                          </button>
                        </td>
                        <td className="text-center py-1.5 px-3 space-x-1">
                          <button
                            onClick={() => addLeg(row.strike, 'put', 'buy')}
                            className="text-buy-green hover:underline text-[10px]"
                          >
                            BUY
                          </button>
                          <button
                            onClick={() => addLeg(row.strike, 'put', 'sell')}
                            className="text-sell-red hover:underline text-[10px]"
                          >
                            SELL
                          </button>
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
    </div>
  )
}
