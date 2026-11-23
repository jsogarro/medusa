import { useRiskStore } from '../../stores/risk'
import { useKdbSubscription } from '../../hooks/use-kdb-subscription'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { cn } from '../../lib/utils'

export function RiskDashboard() {
  useKdbSubscription('riskMetrics')
  const metrics = useRiskStore((state) => state.metrics)

  const utilizationColor = (pct: number) => {
    if (pct > 90) return 'bg-sell-red'
    if (pct > 70) return 'bg-pending-yellow'
    return 'bg-buy-green'
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Risk Limits</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <div className="flex items-center justify-between text-xs mb-1">
            <span className="text-muted-foreground">Daily Volume</span>
            <span className="font-mono">
              ${metrics.dailyVolumeUsed.toLocaleString()} / ${metrics.dailyVolumeLimit.toLocaleString()}
            </span>
          </div>
          <div className="h-2 bg-muted rounded-full overflow-hidden">
            <div
              className={cn(
                'h-full transition-all duration-300',
                utilizationColor((metrics.dailyVolumeUsed / metrics.dailyVolumeLimit) * 100)
              )}
              style={{ width: `${(metrics.dailyVolumeUsed / metrics.dailyVolumeLimit) * 100}%` }}
            />
          </div>
        </div>

        {Object.entries(metrics.positionLimitUtilization).map(([pair, pct]) => (
          <div key={pair}>
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-muted-foreground font-mono">{pair}</span>
              <span className="font-mono">{(pct * 100).toFixed(0)}%</span>
            </div>
            <div className="h-2 bg-muted rounded-full overflow-hidden">
              <div
                className={cn('h-full transition-all duration-300', utilizationColor(pct * 100))}
                style={{ width: `${pct * 100}%` }}
              />
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
