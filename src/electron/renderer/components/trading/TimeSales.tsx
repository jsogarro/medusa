import { memo } from 'react'
import { Card } from '../ui/card'
import { formatPrice, formatTimestamp } from '../../lib/utils'
import { LinkColor } from '../../stores/symbolLink'

interface TimeSale {
  time: Date
  price: number
  size: number
  side: 'buy' | 'sell'
}

interface TimeSalesProps {
  sales: TimeSale[]
  linkColor?: LinkColor
}

export const TimeSales = memo(function TimeSales({ sales, linkColor = 'none' }: TimeSalesProps) {
  // NOTE: In production, linkColor would be used to subscribe to the correct symbol's trades
  // @ts-ignore - linkColor for future implementation
  const _linkColor = linkColor
  return (
    <Card className="h-full flex flex-col overflow-hidden">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2 px-3 pt-3">TIME & SALES</h3>
      <div className="flex-1 overflow-y-auto">
        <table className="w-full text-xs font-mono">
          <thead className="sticky top-0 bg-card border-b border-border">
            <tr className="text-muted-foreground text-[10px]">
              <th className="text-left p-1.5 font-medium">TIME</th>
              <th className="text-right p-1.5 font-medium">PRICE</th>
              <th className="text-right p-1.5 font-medium">SIZE</th>
            </tr>
          </thead>
          <tbody>
            {sales.map((sale, idx) => (
              <tr key={idx} className="border-b border-border/50 data-row hover:bg-card-hover">
                <td className="p-1.5">{formatTimestamp(sale.time)}</td>
                <td className={`p-1.5 text-right ${sale.side === 'buy' ? 'text-buy-green' : 'text-sell-red'}`}>
                  {formatPrice(sale.price, 2)}
                </td>
                <td className="p-1.5 text-right">{sale.size.toFixed(4)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  )
})
