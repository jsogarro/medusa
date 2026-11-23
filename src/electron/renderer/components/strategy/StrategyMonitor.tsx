import { Pause, Play, Square } from 'lucide-react'
import { useStrategiesStore } from '../../stores/strategies'
import { useKdbSubscription } from '../../hooks/use-kdb-subscription'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { Button } from '../ui/button'
import { cn } from '../../lib/utils'

export function StrategyMonitor() {
  useKdbSubscription('strategyStatus')
  const strategies = useStrategiesStore((state) => state.strategies)
  const updateStrategy = useStrategiesStore((state) => state.updateStrategy)

  const handleToggleStrategy = async (name: string, currentStatus: string) => {
    const action = currentStatus === 'running' ? 'pause' : 'resume'
    const newStatus = currentStatus === 'running' ? 'paused' : 'running'
    const result = await window.kdb.strategyControl(name, action)
    if (result.success) {
      updateStrategy(name, { status: newStatus as any })
    }
  }

  const handleStopStrategy = async (name: string) => {
    const result = await window.kdb.strategyControl(name, 'stop')
    if (result.success) {
      updateStrategy(name, { status: 'stopped' })
    }
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Strategies</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {strategies.map((strat) => (
          <div key={strat.name} className="space-y-2 pb-3 border-b border-border last:border-0">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium">{strat.name}</span>
              <div className="flex items-center gap-1">
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6"
                  onClick={() => handleToggleStrategy(strat.name, strat.status)}
                  disabled={strat.status === 'stopped'}
                >
                  {strat.status === 'running' ? (
                    <Pause className="w-3 h-3" />
                  ) : (
                    <Play className="w-3 h-3" />
                  )}
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6"
                  onClick={() => handleStopStrategy(strat.name)}
                >
                  <Square className="w-3 h-3" />
                </Button>
              </div>
            </div>
            <div className="grid grid-cols-4 gap-2 text-xs">
              <div>
                <div className="text-muted-foreground">Trades</div>
                <div className="font-mono">{strat.trades}</div>
              </div>
              <div>
                <div className="text-muted-foreground">Win Rate</div>
                <div className="font-mono">{(strat.winRate * 100).toFixed(0)}%</div>
              </div>
              <div>
                <div className="text-muted-foreground">Sharpe</div>
                <div className="font-mono">{strat.sharpe.toFixed(2)}</div>
              </div>
              <div>
                <div className="text-muted-foreground">P&L</div>
                <div className={cn('font-mono font-semibold', strat.pnl > 0 ? 'text-buy-green' : strat.pnl < 0 ? 'text-sell-red' : '')}>
                  ${strat.pnl.toFixed(0)}
                </div>
              </div>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
