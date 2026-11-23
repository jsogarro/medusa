import { memo } from 'react'
import { formatPrice } from '../../lib/utils'

export interface GBBOData {
  bestBid: {
    price: number
    exchange: string
  }
  bestAsk: {
    price: number
    exchange: string
  }
  spread: number
  spreadBps: number
  savingsVsWorstExchange?: {
    amount: number
    exchange: string
  }
}

interface GBBOStripProps {
  data: GBBOData
}

export const GBBOStrip = memo(function GBBOStrip({ data }: GBBOStripProps) {
  return (
    <div className="h-7 border-b border-border bg-card/50 px-4 flex items-center gap-6 text-xs font-mono">
      {/* Best Bid */}
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">Best Bid:</span>
        <span className="text-buy-green font-semibold">{formatPrice(data.bestBid.price, 2)}</span>
        <span className="text-muted-foreground text-[10px]">({data.bestBid.exchange})</span>
      </div>

      {/* Spread */}
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">|</span>
        <span className="text-muted-foreground">Spread:</span>
        <span className="font-semibold">{formatPrice(data.spread, 2)}</span>
        <span className="text-muted-foreground text-[10px]">({data.spreadBps} bps)</span>
      </div>

      {/* Best Ask */}
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">|</span>
        <span className="text-muted-foreground">Best Ask:</span>
        <span className="text-sell-red font-semibold">{formatPrice(data.bestAsk.price, 2)}</span>
        <span className="text-muted-foreground text-[10px]">({data.bestAsk.exchange})</span>
      </div>

      {/* Savings indicator */}
      {data.savingsVsWorstExchange && (
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">|</span>
          <span className="text-orange-400 text-[10px]">
            Routing saves ${formatPrice(data.savingsVsWorstExchange.amount, 2)} vs{' '}
            {data.savingsVsWorstExchange.exchange}
          </span>
        </div>
      )}
    </div>
  )
})
