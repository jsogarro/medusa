import { create } from 'zustand'
import type { Order } from '../lib/types'

interface OrdersState {
  orders: Order[]
  addOrder: (order: Order) => void
  updateOrder: (orderId: string, updates: Partial<Order>) => void
  removeOrder: (orderId: string) => void
  setOrders: (orders: Order[]) => void
}

export const useOrdersStore = create<OrdersState>((set) => ({
  orders: [],
  // Upsert by orderId: kdb+ publishes a row for every status change of the same order.
  addOrder: (order) =>
    set((state) => ({
      orders: state.orders.some((o) => o.orderId === order.orderId)
        ? state.orders.map((o) => (o.orderId === order.orderId ? { ...o, ...order } : o))
        : [order, ...state.orders]
    })),
  updateOrder: (orderId, updates) =>
    set((state) => ({
      orders: state.orders.map((o) =>
        o.orderId === orderId ? { ...o, ...updates } : o
      )
    })),
  removeOrder: (orderId) =>
    set((state) => ({
      orders: state.orders.filter((o) => o.orderId !== orderId)
    })),
  setOrders: (orders) => set({ orders })
}))
