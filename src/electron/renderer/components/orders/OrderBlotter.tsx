import { useState } from 'react'
import { useOrdersStore } from '../../stores/orders'
import { useKdbSubscription } from '../../hooks/use-kdb-subscription'
import { OrderRow } from './OrderRow'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { Input } from '../ui/input'

export function OrderBlotter() {
  useKdbSubscription('order')
  const orders = useOrdersStore((state) => state.orders)
  const [filter, setFilter] = useState('')

  const handleCancelOrder = async (orderId: string) => {
    const order = orders.find((o) => o.orderId === orderId)
    if (!order) return
    const result = await window.kdb.cancelOrder(orderId, order.exchange)
    if (!result.success) {
      alert(`Failed to cancel order: ${result.error}`)
    }
  }

  const filteredOrders = orders.filter((order) => {
    const search = filter.toLowerCase()
    return (
      order.pair.toLowerCase().includes(search) ||
      order.exchange.toLowerCase().includes(search) ||
      order.strategy.toLowerCase().includes(search) ||
      order.status.toLowerCase().includes(search)
    )
  })

  return (
    <Card className="flex flex-col h-full">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Orders</CardTitle>
          <Input
            placeholder="Filter orders..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="w-64 h-8"
          />
        </div>
      </CardHeader>
      <CardContent className="flex-1 overflow-auto p-0">
        <table className="w-full">
          <thead className="sticky top-0 bg-card border-b border-border">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Time</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Strategy</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Exchange</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Pair</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Side</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Type</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Price</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Quantity</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Filled</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredOrders.map((order) => (
              <OrderRow key={order.orderId} order={order} onCancel={handleCancelOrder} />
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}
