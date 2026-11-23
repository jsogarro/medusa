import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'

interface ExchangeData {
  exchange: string
  bid: number
  ask: number
  spread: number
  latency: number
  liquidity: number
}

interface ExchangeComparisonProps {
  data?: ExchangeData[]
}

const mockExchangeData: ExchangeData[] = [
  {
    exchange: 'Binance',
    bid: 67230.0,
    ask: 67231.5,
    spread: 1.5,
    latency: 45,
    liquidity: 125.3
  },
  {
    exchange: 'Coinbase',
    bid: 67228.5,
    ask: 67233.0,
    spread: 4.5,
    latency: 98,
    liquidity: 87.2
  },
  {
    exchange: 'Kraken',
    bid: 67229.0,
    ask: 67234.5,
    spread: 5.5,
    latency: 112,
    liquidity: 63.8
  }
]

export function ExchangeComparison({ data = mockExchangeData }: ExchangeComparisonProps) {
  // Find best exchange (lowest ask for buy orders)
  const bestExchange = data.reduce((best, curr) =>
    curr.ask < best.ask ? curr : best
  , data[0])

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Exchange Comparison</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left font-medium text-muted-foreground py-2">Exchange</th>
                <th className="text-right font-medium text-muted-foreground py-2">Bid</th>
                <th className="text-right font-medium text-muted-foreground py-2">Ask</th>
                <th className="text-right font-medium text-muted-foreground py-2">Spread</th>
                <th className="text-right font-medium text-muted-foreground py-2">Latency</th>
                <th className="text-right font-medium text-muted-foreground py-2">Liquidity</th>
              </tr>
            </thead>
            <tbody>
              {data.map((row) => {
                const isBest = row.exchange === bestExchange.exchange
                return (
                  <tr
                    key={row.exchange}
                    className={`
                      border-b border-border/50 hover:bg-muted/30
                      ${isBest ? 'bg-buy-green/5' : ''}
                    `}
                  >
                    <td className="py-2">
                      <span className={`font-semibold ${isBest ? 'text-buy-green' : ''}`}>
                        {row.exchange}
                        {isBest && <span className="ml-2 text-xs">✓ Best</span>}
                      </span>
                    </td>
                    <td className="py-2 text-right font-mono">${row.bid.toFixed(2)}</td>
                    <td className="py-2 text-right font-mono">${row.ask.toFixed(2)}</td>
                    <td className="py-2 text-right font-mono">${row.spread.toFixed(2)}</td>
                    <td className="py-2 text-right font-mono">{row.latency}ms</td>
                    <td className="py-2 text-right font-mono">{row.liquidity.toFixed(1)}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}
