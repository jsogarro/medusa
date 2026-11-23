import { X } from 'lucide-react'
import type { Order } from '../../lib/types'
import { Button } from '../ui/button'
import { cn } from '../../lib/utils'

interface OrderRowProps {
  order: Order
  onCancel: (orderId: string) => void
}

export function OrderRow({ order, onCancel }: OrderRowProps) {
  const statusColor = {
    open: 'text-pending-yellow',
    filled: 'text-buy-green',
    cancelled: 'text-muted-foreground',
    rejected: 'text-sell-red'
  }[order.status]

  return (
    <tr className="border-b border-border hover:bg-accent/50">
      <td className="px-3 py-2 text-xs font-mono">{order.time.toLocaleTimeString()}</td>
      <td className="px-3 py-2 text-xs">{order.strategy}</td>
      <td className="px-3 py-2 text-xs uppercase">{order.exchange}</td>
      <td className="px-3 py-2 text-xs font-mono">{order.pair}</td>
      <td className={cn('px-3 py-2 text-xs font-semibold', order.side === 'buy' ? 'text-buy-green' : 'text-sell-red')}>
        {order.side.toUpperCase()}
      </td>
      <td className="px-3 py-2 text-xs">{order.orderType}</td>
      <td className="px-3 py-2 text-xs font-mono">{order.price.toFixed(2)}</td>
      <td className="px-3 py-2 text-xs font-mono">{order.quantity.toFixed(4)}</td>
      <td className="px-3 py-2 text-xs font-mono">{order.filled.toFixed(4)}</td>
      <td className={cn('px-3 py-2 text-xs font-semibold', statusColor)}>
        {order.status.toUpperCase()}
      </td>
      <td className="px-3 py-2">
        {order.status === 'open' && (
          <Button
            variant="ghost"
            size="icon"
            className="h-6 w-6"
            onClick={() => onCancel(order.orderId)}
          >
            <X className="w-3 h-3" />
          </Button>
        )}
      </td>
    </tr>
  )
}
