import { beforeEach, describe, expect, it } from 'vitest'
import { useOrdersStore } from '../stores/orders'
import { usePositionsStore } from '../stores/positions'
import { routeUpdate } from './route-update'

beforeEach(() => {
  useOrdersStore.setState({ orders: [] })
  usePositionsStore.setState({ positions: [] } as any)
})

describe('routeUpdate', () => {
  it('replaces orders on an array update and upserts on a single-row update', () => {
    routeUpdate('order', [{ orderId: 'A', status: 'open' }, { orderId: 'B', status: 'open' }])
    routeUpdate('order', { orderId: 'A', status: 'filled' })
    const orders = useOrdersStore.getState().orders
    expect(orders).toHaveLength(2)
    expect(orders.find((o) => o.orderId === 'A')?.status).toBe('filled')
  })

  it('routes positions and ignores unknown tables', () => {
    routeUpdate('position', [{ pair: 'X' }])
    expect(usePositionsStore.getState().positions).toHaveLength(1)
    expect(() => routeUpdate('nope', {})).not.toThrow()
  })
})
