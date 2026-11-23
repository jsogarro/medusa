import { memo, useMemo } from 'react'
import { Card } from '../ui/card'
import { formatPrice } from '../../lib/utils'

export interface AggregatedOrderBookLevel {
  price: number
  size: number
  cumulative: number
  exchanges: Array<{
    exchange: string
    size: number
  }>
}

export interface AggregatedOrderBookProps {
  bids: AggregatedOrderBookLevel[]
  asks: AggregatedOrderBookLevel[]
  lastPrice: number
  gbboIndices?: {
    bidIndex: number
    askIndex: number
  }
}

const exchangeColors: Record<string, string> = {
  binance: 'bg-blue-500',
  coinbase: 'bg-green-500',
  kraken: 'bg-red-500'
}

export const AggregatedDOM = memo(function AggregatedDOM({
  bids,
  asks,
  lastPrice,
  gbboIndices
}: AggregatedOrderBookProps) {
  const maxCumulative = useMemo(
    () => Math.max(bids[bids.length - 1]?.cumulative || 0, asks[asks.length - 1]?.cumulative || 0),
    [bids, asks]
  )

  const renderLevel = (
    level: AggregatedOrderBookLevel,
    isBid: boolean,
    isGBBO: boolean,
    idx: number
  ) => {
    const bgColor = isBid ? 'bg-buy-green/10' : 'bg-sell-red/10'
    const priceColor = isBid ? 'text-buy-green' : 'text-sell-red'
    const borderColor = isGBBO ? 'border-l-2 border-orange-400' : ''

    return (
      <div
        key={idx}
        className={`relative h-5 flex items-center justify-between text-[10px] font-mono ${borderColor}`}
      >
        {/* Depth bar */}
        <div
          className={`absolute inset-0 ${bgColor}`}
          style={{ width: `${(level.cumulative / maxCumulative) * 100}%` }}
        />

        {/* Price */}
        <span className={`relative ${priceColor} font-semibold`}>{formatPrice(level.price, 2)}</span>

        {/* Exchange badges */}
        <div className="relative flex items-center gap-1">
          {level.exchanges.map((exch, i) => (
            <div
              key={i}
              className={`w-1.5 h-1.5 rounded-full ${exchangeColors[exch.exchange.toLowerCase()] || 'bg-gray-500'}`}
              title={`${exch.exchange}: ${exch.size.toFixed(4)}`}
            />
          ))}
        </div>

        {/* Size */}
        <span className="relative">{level.size.toFixed(4)}</span>

        {/* Cumulative */}
        <span className="relative text-muted-foreground">{level.cumulative.toFixed(4)}</span>
      </div>
    )
  }

  return (
    <Card className="h-full flex flex-col overflow-hidden">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2 px-3 pt-3">
        AGGREGATED ORDER BOOK
      </h3>
      <div
        className="flex-1 overflow-y-auto px-3"
        role="img"
        aria-label="Aggregated Level 2 order book across multiple exchanges"
        aria-description={`Cross-exchange order book showing merged bid and ask levels. Last price is ${formatPrice(lastPrice, 2)}`}
      >
        {/* Asks (reversed) */}
        <div className="mb-2">
          {[...asks].reverse().map((ask, idx) => {
            const actualIndex = asks.length - 1 - idx
            const isGBBO = gbboIndices?.askIndex === actualIndex
            return renderLevel(ask, false, isGBBO, idx)
          })}
        </div>

        {/* Spread */}
        <div className="h-6 flex items-center justify-center border-y border-border bg-card-hover text-xs font-mono font-semibold">
          {formatPrice(lastPrice, 2)}
        </div>

        {/* Bids */}
        <div className="mt-2">
          {bids.map((bid, idx) => {
            const isGBBO = gbboIndices?.bidIndex === idx
            return renderLevel(bid, true, isGBBO, idx)
          })}
        </div>
      </div>

      {/* Legend */}
      <div className="px-3 pb-2 pt-1 border-t border-border flex items-center gap-3 text-[10px]">
        <div className="flex items-center gap-1">
          <div className="w-1.5 h-1.5 rounded-full bg-blue-500" />
          <span className="text-muted-foreground">Binance</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-1.5 h-1.5 rounded-full bg-green-500" />
          <span className="text-muted-foreground">Coinbase</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-1.5 h-1.5 rounded-full bg-red-500" />
          <span className="text-muted-foreground">Kraken</span>
        </div>
        <div className="flex items-center gap-1 ml-auto">
          <div className="w-3 h-3 border-l-2 border-orange-400" />
          <span className="text-muted-foreground">GBBO</span>
        </div>
      </div>
    </Card>
  )
})
