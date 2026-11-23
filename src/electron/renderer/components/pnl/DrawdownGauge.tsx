import { cn } from '../../lib/utils'

interface DrawdownGaugeProps {
  current: number
  max: number
}

export function DrawdownGauge({ current, max }: DrawdownGaugeProps) {
  const percentage = Math.min((Math.abs(current) / max) * 100, 100)

  return (
    <div
      className="space-y-2"
      role="img"
      aria-label="Drawdown gauge"
      aria-description={`Current drawdown is ${(current * 100).toFixed(2)}% out of a maximum of ${(max * 100).toFixed(2)}%`}
    >
      <div className="flex items-center justify-between text-xs">
        <span className="text-muted-foreground">Drawdown</span>
        <span className={cn('font-mono font-semibold', current < 0 ? 'text-sell-red' : '')}>
          {(current * 100).toFixed(2)}%
        </span>
      </div>
      <div className="h-2 bg-muted rounded-full overflow-hidden">
        <div
          className="h-full bg-sell-red transition-all duration-300"
          style={{ width: `${percentage}%` }}
        />
      </div>
      <div className="text-xs text-muted-foreground">
        Max: {(max * 100).toFixed(2)}%
      </div>
    </div>
  )
}
