import { usePositionsStore } from '../../stores/positions'
import { useKdbSubscription } from '../../hooks/use-kdb-subscription'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { cn } from '../../lib/utils'
import { LinkColor, useSymbolLinkStore } from '../../stores/symbolLink'

interface PositionMonitorProps {
  linkColor?: LinkColor
}

export function PositionMonitor({ linkColor = 'none' }: PositionMonitorProps) {
  const setSymbol = useSymbolLinkStore((state) => state.setSymbol)
  useKdbSubscription('position')
  // NOTE: linkColor will be used to propagate position clicks to linked widgets in production
  // @ts-ignore - variables for future linking implementation
  const _unused = { linkColor, setSymbol }
  const positions = usePositionsStore((state) => state.positions)

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Positions</CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <table className="w-full">
          <thead className="border-b border-border">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Exchange</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Pair</th>
              <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Qty</th>
              <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Avg Price</th>
              <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">P&L</th>
              <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Exposure</th>
            </tr>
          </thead>
          <tbody>
            {positions.map((pos) => (
              <tr key={`${pos.exchange}-${pos.pair}`} className="border-b border-border">
                <td className="px-3 py-2 text-xs uppercase">{pos.exchange}</td>
                <td className="px-3 py-2 text-xs font-mono">{pos.pair}</td>
                <td className={cn(
                  'px-3 py-2 text-xs font-mono text-right',
                  pos.quantity > 0 ? 'text-buy-green' : pos.quantity < 0 ? 'text-sell-red' : ''
                )}>
                  {pos.quantity.toFixed(4)}
                </td>
                <td className="px-3 py-2 text-xs font-mono text-right">{pos.avgPrice.toFixed(2)}</td>
                <td className={cn(
                  'px-3 py-2 text-xs font-mono text-right font-semibold',
                  pos.unrealizedPnL > 0 ? 'text-buy-green' : pos.unrealizedPnL < 0 ? 'text-sell-red' : ''
                )}>
                  ${pos.unrealizedPnL.toFixed(2)}
                </td>
                <td className="px-3 py-2 text-xs font-mono text-right">${pos.exposure.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}
