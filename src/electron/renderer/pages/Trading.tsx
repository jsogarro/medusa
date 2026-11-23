import { AdvancedChart } from '../components/charts/AdvancedChart'
import { OrderBlotter } from '../components/orders/OrderBlotter'
import { TradeTicket } from '../components/trade-ticket/TradeTicket'
import { OrderBook } from '../components/trading/OrderBook'
import { AggregatedDOM } from '../components/trading/AggregatedDOM'
import { TimeSales } from '../components/trading/TimeSales'
import { OrderRouterFlow } from '../components/trading/OrderRouterFlow'
import { ExchangeComparison } from '../components/trading/ExchangeComparison'
import { ExecutionProgress } from '../components/trading/ExecutionProgress'
import { useState } from 'react'
import { ChevronDown, ChevronUp } from 'lucide-react'
import { Button } from '../components/ui/button'
import { mockAggregatedOrderBook, mockActiveAlgoOrders } from '../lib/mock-data'

// Mock data - will be moved to mock-data.ts
const mockOrderBookBids = Array.from({ length: 10 }, (_, i) => ({
  price: 67230 - i * 2,
  size: 0.5 + Math.random() * 2,
  cumulative: (0.5 + Math.random() * 2) * (i + 1)
}))

const mockOrderBookAsks = Array.from({ length: 10 }, (_, i) => ({
  price: 67238 + i * 2,
  size: 0.5 + Math.random() * 2,
  cumulative: (0.5 + Math.random() * 2) * (i + 1)
}))

const mockTimeSales = Array.from({ length: 50 }, (_, i) => ({
  time: new Date(Date.now() - i * 2000),
  price: 67230 + (Math.random() - 0.5) * 20,
  size: 0.1 + Math.random() * 2,
  side: Math.random() > 0.5 ? ('buy' as const) : ('sell' as const)
}))

export function Trading() {
  const [showRouterPanel, setShowRouterPanel] = useState(false)
  const [showAggregatedBook, setShowAggregatedBook] = useState(false)

  const handlePauseAlgo = (orderId: string) => {
    console.log('Pause algo:', orderId)
  }

  const handleResumeAlgo = (orderId: string) => {
    console.log('Resume algo:', orderId)
  }

  const handleCancelAlgo = (orderId: string) => {
    console.log('Cancel algo:', orderId)
  }

  return (
    <div className="h-full grid grid-cols-12 gap-2 p-2">
      {/* Left column - 65% */}
      <div className="col-span-8 flex flex-col gap-2">
        {/* Chart */}
        <div className={showRouterPanel ? 'h-[30%]' : 'h-[50%]'}>
          <AdvancedChart pair="BTCUSD" exchange="bitstamp" />
        </div>

        {/* Execution Progress Panel */}
        <div className="h-[20%]">
          <ExecutionProgress
            algoOrders={mockActiveAlgoOrders}
            onPause={handlePauseAlgo}
            onResume={handleResumeAlgo}
            onCancel={handleCancelAlgo}
          />
        </div>

        {/* Order Router Panel (collapsible) */}
        {showRouterPanel && (
          <div className="h-[20%] flex flex-col gap-2">
            <div className="flex items-center justify-between px-2">
              <h3 className="text-xs font-semibold text-muted-foreground">Smart Order Router</h3>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowRouterPanel(false)}
                className="h-6 px-2"
              >
                <ChevronUp className="w-3 h-3" />
              </Button>
            </div>
            <OrderRouterFlow />
            <ExchangeComparison />
          </div>
        )}

        {/* Toggle button when panel is hidden */}
        {!showRouterPanel && (
          <div className="flex justify-center">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowRouterPanel(true)}
              className="h-6 px-3 gap-1.5 text-xs"
            >
              <ChevronDown className="w-3 h-3" />
              Show Order Router
            </Button>
          </div>
        )}

        {/* Order Blotter */}
        <div className={showRouterPanel ? 'h-[30%]' : 'h-[30%]'}>
          <OrderBlotter />
        </div>
      </div>

      {/* Right column - 35% */}
      <div className="col-span-4 flex flex-col gap-2">
        {/* Order Entry */}
        <div className="h-[35%]">
          <TradeTicket />
        </div>

        {/* Order Book */}
        <div className="h-[40%]">
          {showAggregatedBook ? (
            <div className="h-full relative">
              <div className="absolute top-3 right-3 z-10">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAggregatedBook(false)}
                  className="h-6 px-2 text-[10px]"
                >
                  Single Exchange
                </Button>
              </div>
              <AggregatedDOM
                bids={mockAggregatedOrderBook.bids}
                asks={mockAggregatedOrderBook.asks}
                lastPrice={67231.0}
                gbboIndices={{ bidIndex: 0, askIndex: 0 }}
              />
            </div>
          ) : (
            <div className="h-full relative">
              <div className="absolute top-3 right-3 z-10">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAggregatedBook(true)}
                  className="h-6 px-2 text-[10px]"
                >
                  Aggregated
                </Button>
              </div>
              <OrderBook bids={mockOrderBookBids} asks={mockOrderBookAsks} lastPrice={67234.5} />
            </div>
          )}
        </div>

        {/* Time & Sales */}
        <div className="h-[25%]">
          <TimeSales sales={mockTimeSales} />
        </div>
      </div>
    </div>
  )
}
