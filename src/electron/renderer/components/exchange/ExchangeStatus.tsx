import { useExchangesStore } from '../../stores/exchanges'
import { useKdbSubscription } from '../../hooks/use-kdb-subscription'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { cn } from '../../lib/utils'

export function ExchangeStatus() {
  useKdbSubscription('exchangeStatus')
  const exchanges = useExchangesStore((state) => state.exchanges)

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Exchanges</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {exchanges.map((ex) => (
          <div key={ex.exchange} className="space-y-1">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div
                  className={cn(
                    'w-2 h-2 rounded-full',
                    ex.connected ? 'bg-buy-green' : 'bg-sell-red'
                  )}
                />
                <span className="text-sm font-medium uppercase">{ex.exchange}</span>
              </div>
              <span className="text-xs text-muted-foreground font-mono">{ex.latency}ms</span>
            </div>
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>Errors: {ex.errorCount}</span>
              <span>
                Rate: {ex.rateLimitUsed}/{ex.rateLimitMax}
              </span>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
