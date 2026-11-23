import { useState } from 'react'
import { Card } from '../components/ui/card'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../components/ui/tabs'
import { Input } from '../components/ui/input'
import { useOrdersStore } from '../stores/orders'
import { formatPrice, formatTimestamp } from '../lib/utils'
import { AlgoHistory } from '../components/trading/AlgoHistory'
import { mockCompletedAlgoOrders } from '../lib/mock-data'
import type { Order } from '../lib/types'

export function Orders() {
  const orders = useOrdersStore((state) => state.orders)
  const [searchTerm, setSearchTerm] = useState('')

  const filterOrders = (status?: Order['status']) => {
    let filtered = orders

    if (status) {
      filtered = filtered.filter((o) => o.status === status)
    }

    if (searchTerm) {
      filtered = filtered.filter(
        (o) =>
          o.pair.toLowerCase().includes(searchTerm.toLowerCase()) ||
          o.strategy.toLowerCase().includes(searchTerm.toLowerCase()) ||
          o.exchange.toLowerCase().includes(searchTerm.toLowerCase())
      )
    }

    return filtered.sort((a, b) => b.time.getTime() - a.time.getTime())
  }

  const renderOrdersTable = (filteredOrders: Order[]) => (
    <div className="overflow-auto">
      <table className="w-full text-xs font-mono">
        <thead className="sticky top-0 bg-card border-b border-border">
          <tr className="text-muted-foreground text-[10px]">
            <th className="text-left p-1.5 font-medium">TIME</th>
            <th className="text-left p-1.5 font-medium">ORDER ID</th>
            <th className="text-left p-1.5 font-medium">STRATEGY</th>
            <th className="text-left p-1.5 font-medium">EXCHANGE</th>
            <th className="text-left p-1.5 font-medium">PAIR</th>
            <th className="text-left p-1.5 font-medium">SIDE</th>
            <th className="text-left p-1.5 font-medium">TYPE</th>
            <th className="text-right p-1.5 font-medium">PRICE</th>
            <th className="text-right p-1.5 font-medium">QTY</th>
            <th className="text-right p-1.5 font-medium">FILLED</th>
            <th className="text-left p-1.5 font-medium">STATUS</th>
          </tr>
        </thead>
        <tbody>
          {filteredOrders.map((order) => (
            <tr key={order.orderId} className="border-b border-border/50 data-row hover:bg-card-hover">
              <td className="p-1.5">{formatTimestamp(order.time)}</td>
              <td className="p-1.5">{order.orderId}</td>
              <td className="p-1.5">{order.strategy}</td>
              <td className="p-1.5 uppercase">{order.exchange}</td>
              <td className="p-1.5">{order.pair}</td>
              <td className={`p-1.5 ${order.side === 'buy' ? 'text-buy-green' : 'text-sell-red'}`}>
                {order.side.toUpperCase()}
              </td>
              <td className="p-1.5 uppercase">{order.orderType}</td>
              <td className="p-1.5 text-right">{formatPrice(order.price, 2)}</td>
              <td className="p-1.5 text-right">{order.quantity.toFixed(4)}</td>
              <td className="p-1.5 text-right">{order.filled.toFixed(4)}</td>
              <td className="p-1.5">
                <span
                  className={`px-1.5 py-0.5 rounded text-[9px] font-semibold uppercase ${
                    order.status === 'filled'
                      ? 'bg-buy-green/20 text-buy-green'
                      : order.status === 'open'
                      ? 'bg-info-blue/20 text-info-blue'
                      : order.status === 'cancelled'
                      ? 'bg-pending-yellow/20 text-pending-yellow'
                      : 'bg-sell-red/20 text-sell-red'
                  }`}
                >
                  {order.status}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )

  return (
    <div className="h-full flex flex-col p-2 gap-2">
      {/* Filters */}
      <Card className="p-3">
        <div className="flex items-center gap-4">
          <Input
            placeholder="Search by pair, strategy, or exchange..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="max-w-md text-xs h-7"
          />
          <div className="text-xs text-muted-foreground font-mono">
            Total: {filterOrders().length} orders
          </div>
        </div>
      </Card>

      {/* Tabs */}
      <Card className="flex-1 overflow-hidden flex flex-col p-3">
        <Tabs defaultValue="all" className="h-full flex flex-col">
          <TabsList>
            <TabsTrigger value="all">All ({orders.length})</TabsTrigger>
            <TabsTrigger value="open">
              Open ({orders.filter((o) => o.status === 'open').length})
            </TabsTrigger>
            <TabsTrigger value="filled">
              Filled ({orders.filter((o) => o.status === 'filled').length})
            </TabsTrigger>
            <TabsTrigger value="cancelled">
              Cancelled ({orders.filter((o) => o.status === 'cancelled').length})
            </TabsTrigger>
            <TabsTrigger value="rejected">
              Rejected ({orders.filter((o) => o.status === 'rejected').length})
            </TabsTrigger>
            <TabsTrigger value="algo-history">
              Algo History ({mockCompletedAlgoOrders.length})
            </TabsTrigger>
          </TabsList>

          <TabsContent value="all" className="flex-1 overflow-hidden">
            {renderOrdersTable(filterOrders())}
          </TabsContent>
          <TabsContent value="open" className="flex-1 overflow-hidden">
            {renderOrdersTable(filterOrders('open'))}
          </TabsContent>
          <TabsContent value="filled" className="flex-1 overflow-hidden">
            {renderOrdersTable(filterOrders('filled'))}
          </TabsContent>
          <TabsContent value="cancelled" className="flex-1 overflow-hidden">
            {renderOrdersTable(filterOrders('cancelled'))}
          </TabsContent>
          <TabsContent value="rejected" className="flex-1 overflow-hidden">
            {renderOrdersTable(filterOrders('rejected'))}
          </TabsContent>
          <TabsContent value="algo-history" className="flex-1 overflow-auto">
            <AlgoHistory completedOrders={mockCompletedAlgoOrders} />
          </TabsContent>
        </Tabs>
      </Card>
    </div>
  )
}
