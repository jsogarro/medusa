import { formatPrice, formatPnL, formatPercent, formatVolume } from '../../lib/utils'

interface SymbolBarProps {
  pair: string
  lastPrice: number
  change: number
  changePct: number
  bid: number
  ask: number
  volume: number
  high24h: number
  low24h: number
}

export function SymbolBar({
  pair,
  lastPrice,
  change,
  changePct,
  bid,
  ask,
  volume,
  high24h,
  low24h
}: SymbolBarProps) {
  const isPositive = change >= 0

  return (
    <div className="h-8 border-b border-border bg-card px-4 flex items-center gap-6 text-xs font-mono">
      <span className="font-bold text-sm">{pair}</span>
      <span className="text-foreground text-base font-semibold">{formatPrice(lastPrice, 2)}</span>
      <span className={isPositive ? 'text-buy-green' : 'text-sell-red'}>
        {formatPnL(change)} ({formatPercent(changePct)})
      </span>
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">Bid:</span>
        <span className="text-buy-green">{formatPrice(bid, 2)}</span>
        <span className="text-muted-foreground">/</span>
        <span className="text-muted-foreground">Ask:</span>
        <span className="text-sell-red">{formatPrice(ask, 2)}</span>
      </div>
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">Vol:</span>
        <span>{formatVolume(volume)}</span>
      </div>
      <div className="flex items-center gap-2">
        <span className="text-muted-foreground">H:</span>
        <span className="text-buy-green">{formatPrice(high24h, 2)}</span>
        <span className="text-muted-foreground">L:</span>
        <span className="text-sell-red">{formatPrice(low24h, 2)}</span>
      </div>
    </div>
  )
}
