import { memo, useMemo } from 'react'
import { Card } from '../ui/card'
import { formatPrice } from '../../lib/utils'
import { LinkColor } from '../../stores/symbolLink'

interface OrderBookLevel {
  price: number
  size: number
  cumulative: number
}

interface OrderBookProps {
  bids: OrderBookLevel[]
  asks: OrderBookLevel[]
  lastPrice: number
  linkColor?: LinkColor
}

export const OrderBook = memo(function OrderBook({ bids, asks, lastPrice, linkColor = 'none' }: OrderBookProps) {
  // NOTE: In production, linkColor would be used to subscribe to the correct symbol's orderbook
  // @ts-ignore - linkColor for future implementation
  const _linkColor = linkColor
  // For now, it's mainly for UI consistency
  const maxCumulative = useMemo(() => Math.max(
    bids[bids.length - 1]?.cumulative || 0,
    asks[asks.length - 1]?.cumulative || 0
  ), [bids, asks])

  return (
    <Card className="h-full flex flex-col overflow-hidden">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2 px-3 pt-3">ORDER BOOK</h3>
      <div
        className="flex-1 overflow-y-auto px-3"
        role="img"
        aria-label="Level 2 order book"
        aria-description={`Real-time order book showing bid and ask levels with cumulative size. Last price is ${formatPrice(lastPrice, 2)}`}
      >
        {/* Asks (reversed) */}
        <div className="mb-2">
          {[...asks].reverse().map((ask, idx) => (
            <div key={idx} className="relative h-5 flex items-center justify-between text-[10px] font-mono">
              <div
                className="absolute inset-0 bg-sell-red/10"
                style={{ width: `${(ask.cumulative / maxCumulative) * 100}%` }}
              />
              <span className="relative text-sell-red">{formatPrice(ask.price, 2)}</span>
              <span className="relative">{ask.size.toFixed(4)}</span>
              <span className="relative text-muted-foreground">{ask.cumulative.toFixed(4)}</span>
            </div>
          ))}
        </div>

        {/* Spread */}
        <div className="h-6 flex items-center justify-center border-y border-border bg-card-hover text-xs font-mono font-semibold">
          {formatPrice(lastPrice, 2)}
        </div>

        {/* Bids */}
        <div className="mt-2">
          {bids.map((bid, idx) => (
            <div key={idx} className="relative h-5 flex items-center justify-between text-[10px] font-mono">
              <div
                className="absolute inset-0 bg-buy-green/10"
                style={{ width: `${(bid.cumulative / maxCumulative) * 100}%` }}
              />
              <span className="relative text-buy-green">{formatPrice(bid.price, 2)}</span>
              <span className="relative">{bid.size.toFixed(4)}</span>
              <span className="relative text-muted-foreground">{bid.cumulative.toFixed(4)}</span>
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
})
