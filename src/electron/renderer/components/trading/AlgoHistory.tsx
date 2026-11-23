import { useState } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { Badge } from '../ui/badge'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { AlgoOrder } from '../../lib/types'
import { cn } from '../../lib/utils'

interface AlgoHistoryProps {
  completedOrders: AlgoOrder[]
}

export function AlgoHistory({ completedOrders }: AlgoHistoryProps) {
  const [expandedId, setExpandedId] = useState<string | null>(null)

  if (completedOrders.length === 0) {
    return (
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Algo History</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground text-center py-8">
            No completed algo orders
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Algo History</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-1">
          {/* Header */}
          <div className="grid grid-cols-12 gap-2 text-[10px] text-muted-foreground font-medium px-2 pb-2 border-b border-border">
            <div className="col-span-1"></div>
            <div className="col-span-1">Type</div>
            <div className="col-span-2">Symbol</div>
            <div className="col-span-1 text-right">Target</div>
            <div className="col-span-1 text-right">Filled</div>
            <div className="col-span-2 text-right">Avg Fill</div>
            <div className="col-span-2 text-right">Slippage</div>
            <div className="col-span-2 text-right">Duration</div>
          </div>

          {/* Rows */}
          {completedOrders.map((order) => {
            const isExpanded = expandedId === order.orderId
            // CRITICAL FIX: Slippage sign depends on side
            const rawSlippage = ((order.avgFillPrice - order.arrivalPrice) / order.arrivalPrice) * 10000
            const slippageBps = order.side === 'buy' ? rawSlippage : -rawSlippage

            return (
              <div key={order.orderId}>
                <div
                  className="grid grid-cols-12 gap-2 text-xs px-2 py-2 hover:bg-muted/50 cursor-pointer rounded transition-colors"
                  onClick={() => setExpandedId(isExpanded ? null : order.orderId)}
                >
                  <div className="col-span-1 flex items-center">
                    {isExpanded ? (
                      <ChevronDown className="w-3 h-3 text-muted-foreground" />
                    ) : (
                      <ChevronRight className="w-3 h-3 text-muted-foreground" />
                    )}
                  </div>
                  <div className="col-span-1">
                    <Badge variant="outline" className="h-5 text-[9px] px-1">
                      {order.algoType.toUpperCase()}
                    </Badge>
                  </div>
                  <div className="col-span-2 font-mono font-medium">
                    <span className={cn(order.side === 'buy' ? 'text-buy-green' : 'text-sell-red')}>
                      {order.side === 'buy' ? 'B' : 'S'}
                    </span>{' '}
                    {order.pair}
                  </div>
                  <div className="col-span-1 text-right font-mono">{order.targetQty.toFixed(4)}</div>
                  <div className="col-span-1 text-right font-mono">{order.filled.toFixed(4)}</div>
                  <div className="col-span-2 text-right font-mono">
                    ${order.avgFillPrice.toLocaleString(undefined, { minimumFractionDigits: 2 })}
                  </div>
                  <div
                    className={cn(
                      'col-span-2 text-right font-mono',
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
                  <div className="col-span-2 text-right text-muted-foreground">{order.duration}</div>
                </div>

                {/* Expanded child orders */}
                {isExpanded && order.childOrders && order.childOrders.length > 0 && (
                  <div className="ml-8 mt-1 mb-2 border-l-2 border-muted pl-4 space-y-1">
                    <div className="text-[10px] text-muted-foreground font-medium mb-2">
                      Child Orders ({order.childOrders.length})
                    </div>
                    {order.childOrders.map((child, idx) => (
                      <div
                        key={idx}
                        className="grid grid-cols-11 gap-2 text-[10px] text-muted-foreground py-1"
                      >
                        <div className="col-span-2 font-mono">{child.time}</div>
                        <div className="col-span-2 font-mono">{child.orderId}</div>
                        <div className="col-span-2 text-right font-mono">{child.qty.toFixed(4)}</div>
                        <div className="col-span-2 text-right font-mono">
                          ${child.price.toFixed(2)}
                        </div>
                        <div className="col-span-3">
                          <Badge
                            variant={child.status === 'filled' ? 'outline' : 'secondary'}
                            className="h-4 text-[8px] px-1"
                          >
                            {child.status}
                          </Badge>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}
