import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { Button } from '../ui/button'
import { Badge } from '../ui/badge'
import { Play, Pause, X } from 'lucide-react'
import { AlgoOrder } from '../../lib/types'
import { cn } from '../../lib/utils'

interface ExecutionProgressProps {
  algoOrders: AlgoOrder[]
  onPause: (orderId: string) => void
  onResume: (orderId: string) => void
  onCancel: (orderId: string) => void
}

export function ExecutionProgress({ algoOrders, onPause, onResume, onCancel }: ExecutionProgressProps) {
  if (algoOrders.length === 0) {
    return (
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Algo Execution</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground text-center py-8">No active algo orders</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Algo Execution</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {algoOrders.map((order) => {
          const fillPct = (order.filled / order.targetQty) * 100
          // CRITICAL FIX: Slippage sign depends on side
          // For BUY: paying MORE than arrival = positive slippage (adverse)
          // For SELL: receiving LESS than arrival = positive slippage (adverse)
          const rawSlippage = ((order.avgFillPrice - order.arrivalPrice) / order.arrivalPrice) * 10000
          const slippageBps = order.side === 'buy' ? rawSlippage : -rawSlippage
          const isRunning = order.status === 'active'
          const isPaused = order.status === 'paused'

          return (
            <div key={order.orderId} className="p-3 rounded-md bg-muted/30 space-y-2">
              <div className="flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <Badge
                      variant={
                        order.status === 'active'
                          ? 'default'
                          : order.status === 'paused'
                            ? 'secondary'
                            : order.status === 'completed'
                              ? 'outline'
                              : 'destructive'
                      }
                      className="h-5 text-[10px] px-1.5"
                    >
                      {order.status.toUpperCase()}
                    </Badge>
                    <span className="text-xs font-mono font-semibold">{order.pair}</span>
                    <span className="text-xs text-muted-foreground">
                      {order.algoType.toUpperCase()}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-[10px] text-muted-foreground">
                    <span>{order.exchange}</span>
                    <span className={cn(order.side === 'buy' ? 'text-buy-green' : 'text-sell-red')}>
                      {order.side.toUpperCase()}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  {(isRunning || isPaused) && (
                    <>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => (isRunning ? onPause(order.orderId) : onResume(order.orderId))}
                        className="h-6 w-6 p-0"
                        aria-label={isRunning ? `Pause algo order ${order.orderId}` : `Resume algo order ${order.orderId}`}
                      >
                        {isRunning ? <Pause className="w-3 h-3" /> : <Play className="w-3 h-3" />}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => onCancel(order.orderId)}
                        className="h-6 w-6 p-0 text-destructive hover:text-destructive"
                        aria-label={`Cancel algo order ${order.orderId}`}
                      >
                        <X className="w-3 h-3" />
                      </Button>
                    </>
                  )}
                </div>
              </div>

              {/* Progress bar */}
              <div>
                <div className="flex justify-between text-[10px] text-muted-foreground mb-1">
                  <span>
                    Filled: {order.filled.toFixed(4)} / {order.targetQty.toFixed(4)}
                  </span>
                  <span>{fillPct.toFixed(1)}%</span>
                </div>
                <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className={cn(
                      'h-full transition-all duration-300',
                      order.side === 'buy' ? 'bg-buy-green' : 'bg-sell-red'
                    )}
                    style={{ width: `${Math.min(fillPct, 100)}%` }}
                  />
                </div>
              </div>

              {/* Metrics */}
              <div className="grid grid-cols-3 gap-2 text-[10px]">
                <div>
                  <div className="text-muted-foreground">Avg Fill</div>
                  <div className="font-mono font-medium">
                    ${order.avgFillPrice.toLocaleString(undefined, { minimumFractionDigits: 2 })}
                  </div>
                </div>
                <div>
                  <div className="text-muted-foreground">Slippage</div>
                  <div
                    className={cn(
                      'font-mono font-medium',
                      Math.abs(slippageBps) < 5
                        ? 'text-muted-foreground'
                        : slippageBps > 0
                          ? 'text-sell-red'
                          : 'text-buy-green'
                    )}
                  >
                    {slippageBps >= 0 ? '+' : ''}
                    {slippageBps.toFixed(1)} bps
                  </div>
                </div>
                <div>
                  <div className="text-muted-foreground">ETA</div>
                  <div className="font-mono font-medium">{order.eta}</div>
                </div>
              </div>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )
}
