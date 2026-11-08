import { useState, useEffect, useRef, memo } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { Input } from '../ui/input'
import { Button } from '../ui/button'
import { LinkColor, useSymbolLinkStore } from '../../stores/symbolLink'
import { AlgoSelector, AlgoParams } from '../trading/AlgoSelector'
import { AssetClassSwitcher } from './AssetClassSwitcher'
import { createSubmitGuard } from '../../lib/kdb-actions'
import {
  ASSET_CLASS_CONFIG,
  inferTradingAssetClass,
  useAssetClassStore
} from '../../stores/assetClass'

interface TradeTicketProps {
  linkColor?: LinkColor
}

export const TradeTicket = memo(function TradeTicket({ linkColor = 'none' }: TradeTicketProps) {
  const assetClass = useAssetClassStore((state) => state.assetClass)
  const exchange = useAssetClassStore((state) => state.exchange)
  const pair = useAssetClassStore((state) => state.symbol)
  const setAssetClass = useAssetClassStore((state) => state.setAssetClass)
  const setAssetContext = useAssetClassStore((state) => state.setContext)
  const setExchange = useAssetClassStore((state) => state.setExchange)
  const setPair = useAssetClassStore((state) => state.setSymbol)
  const linkedSymbol = useSymbolLinkStore((state) =>
    linkColor !== 'none' ? state.groups[linkColor]?.symbol : undefined
  )
  const linkedExchange = useSymbolLinkStore((state) =>
    linkColor !== 'none' ? state.groups[linkColor]?.exchange : undefined
  )

  const assetConfig = ASSET_CLASS_CONFIG[assetClass]

  // Update pair/exchange when linked symbol changes
  useEffect(() => {
    if (linkColor !== 'none' && linkedSymbol) {
      const inferredAssetClass = inferTradingAssetClass(linkedSymbol)
      const fallbackExchange = ASSET_CLASS_CONFIG[inferredAssetClass].defaultExchange
      setAssetContext(inferredAssetClass, linkedSymbol, linkedExchange || fallbackExchange)
    }
  }, [linkColor, linkedExchange, linkedSymbol, setAssetContext])

  useEffect(() => {
    if (linkColor !== 'none' && linkedExchange) {
      setExchange(linkedExchange)
    }
  }, [linkColor, linkedExchange, setExchange])
  const [side, setSide] = useState<'buy' | 'sell'>('buy')
  const [orderType, setOrderType] = useState<'market' | 'limit'>('limit')
  const [price, setPrice] = useState('')
  const [quantity, setQuantity] = useState('')
  const [strategy, setStrategy] = useState('manual')
  const [algoParams, setAlgoParams] = useState<AlgoParams>({ type: 'direct' })
  const [submitting, setSubmitting] = useState(false)
  const submitGuard = useRef(createSubmitGuard()).current

  useEffect(() => {
    if (!assetConfig.supportedOrderTypes.includes(orderType)) {
      setOrderType(assetConfig.supportedOrderTypes[0])
    }
  }, [assetConfig.supportedOrderTypes, orderType])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    const order = {
      exchange,
      pair,
      side,
      orderType,
      price: orderType === 'market' ? 0 : parseFloat(price),
      quantity: parseFloat(quantity),
      strategy
    }

    if (!Number.isFinite(order.quantity) || (orderType === 'limit' && !Number.isFinite(order.price))) {
      alert('Enter a valid price and quantity')
      return
    }
    const summary = `${side.toUpperCase()} ${order.quantity} ${pair} on ${exchange} (${
      orderType === 'market' ? 'market' : `limit @ ${order.price}`
    })`
    if (!confirm(`Submit order?\n${summary}`)) return

    // One submission at a time: a second click or Enter while one is in flight is dropped.
    await submitGuard(async () => {
      setSubmitting(true)
      try {
        const result = await window.kdb.placeOrder(order)
        if (result.success) {
          alert(`Order submitted: ${result.data.orderId}`)
          setPrice('')
          setQuantity('')
        } else {
          alert(`Order failed: ${result.error}`)
        }
      } catch (err) {
        alert(`Order failed: ${String(err)}`)
      } finally {
        setSubmitting(false)
      }
    })
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Trade Ticket</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-3">
          <AssetClassSwitcher value={assetClass} onChange={setAssetClass} />

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-xs text-muted-foreground">Exchange</label>
              <Input
                aria-label="Exchange"
                value={exchange}
                onChange={(e) => setExchange(e.target.value)}
                className="h-8"
              />
            </div>
            <div>
              <label className="text-xs text-muted-foreground">{assetConfig.symbolLabel}</label>
              <Input
                aria-label={assetConfig.symbolLabel}
                value={pair}
                onChange={(e) => setPair(e.target.value)}
                className="h-8"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <Button
              type="button"
              variant={side === 'buy' ? 'buy' : 'outline'}
              size="sm"
              onClick={() => setSide('buy')}
            >
              BUY
            </Button>
            <Button
              type="button"
              variant={side === 'sell' ? 'sell' : 'outline'}
              size="sm"
              onClick={() => setSide('sell')}
            >
              SELL
            </Button>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <Button
              type="button"
              variant={orderType === 'market' ? 'default' : 'outline'}
              size="sm"
              disabled={!assetConfig.supportedOrderTypes.includes('market')}
              onClick={() => setOrderType('market')}
            >
              Market
            </Button>
            <Button
              type="button"
              variant={orderType === 'limit' ? 'default' : 'outline'}
              size="sm"
              onClick={() => setOrderType('limit')}
            >
              Limit
            </Button>
          </div>

          {orderType === 'limit' && (
            <div>
              <label className="text-xs text-muted-foreground">Price</label>
              <Input
                aria-label="Price"
                type="number"
                step="0.01"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                className="h-8 font-mono"
                required
              />
            </div>
          )}

          <div>
            <label className="text-xs text-muted-foreground">Quantity</label>
            <Input
              aria-label={assetConfig.quantityLabel}
              type="number"
              step={assetConfig.quantityStep}
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              className="h-8 font-mono"
              required
            />
            <div className="mt-1 text-[10px] text-muted-foreground">{assetConfig.quantityLabel}</div>
          </div>

          <div>
            <label className="text-xs text-muted-foreground">Strategy</label>
            <Input
              aria-label="Strategy"
              value={strategy}
              onChange={(e) => setStrategy(e.target.value)}
              className="h-8"
            />
          </div>

          <AlgoSelector value={algoParams} onChange={setAlgoParams} />

          <Button
            type="submit"
            className="w-full"
            disabled={submitting}
            variant={algoParams.type === 'direct' ? (side === 'buy' ? 'buy' : 'sell') : 'default'}
            style={
              algoParams.type !== 'direct'
                ? { backgroundColor: '#fb8c00', color: 'white' }
                : undefined
            }
          >
            {algoParams.type === 'direct' ? 'Submit Order' : 'Start Algo'}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
})
