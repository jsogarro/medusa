import { beforeEach, describe, expect, it } from 'vitest'
import { useOrdersStore } from './orders'

const order = (id: string, status: string = 'open', filled = 0): any => ({
  orderId: id,
  time: new Date(0),
  strategy: 's',
  exchange: 'alpaca',
  pair: 'BTC_USD',
  side: 'buy',
  orderType: 'limit',
  price: 1,
  quantity: 1,
  filled,
  status
})

beforeEach(() => useOrdersStore.setState({ orders: [] }))

describe('orders store', () => {
  it('addOrder upserts: a status update for a known order replaces the row instead of duplicating it', () => {
    const { addOrder } = useOrdersStore.getState()
    addOrder(order('A'))
    addOrder(order('B'))
    addOrder(order('A', 'filled', 1))

    const orders = useOrdersStore.getState().orders
    expect(orders.map((o) => o.orderId).sort()).toEqual(['A', 'B'])
    expect(orders.find((o) => o.orderId === 'A')).toMatchObject({ status: 'filled', filled: 1 })
  })

  it('puts a new order first', () => {
    const { addOrder } = useOrdersStore.getState()
    addOrder(order('A'))
    addOrder(order('B'))
    expect(useOrdersStore.getState().orders[0].orderId).toBe('B')
  })
})
