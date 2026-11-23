import { Card, CardContent } from '../ui/card'
import { Check, X, ChevronRight } from 'lucide-react'

interface OrderRouterFlowProps {
  signal?: {
    strategy: string
    side: 'buy' | 'sell'
    quantity: number
    pair: string
  }
  riskChecks?: {
    passed: number
    total: number
  }
  selectedExchange?: {
    name: string
    reason: string
  }
  route?: {
    status: 'routed' | 'pending' | 'failed'
  }
  execution?: {
    status: 'filled' | 'partial' | 'rejected'
    fillPrice?: number
  }
}

export function OrderRouterFlow({
  signal = {
    strategy: 'simpleArb',
    side: 'buy',
    quantity: 0.5,
    pair: 'BTCUSD'
  },
  riskChecks = {
    passed: 11,
    total: 11
  },
  selectedExchange = {
    name: 'Binance',
    reason: 'best ask'
  },
  route = {
    status: 'routed'
  },
  execution = {
    status: 'filled',
    fillPrice: 67231
  }
}: OrderRouterFlowProps) {
  const stages = [
    {
      name: 'Signal',
      status: 'success',
      detail: `${signal.strategy} ${signal.side.toUpperCase()} ${signal.quantity} ${signal.pair}`
    },
    {
      name: 'Risk Check',
      status: riskChecks.passed === riskChecks.total ? 'success' : 'failed',
      detail: `${riskChecks.passed}/${riskChecks.total} checks passed`
    },
    {
      name: 'Exchange Select',
      status: selectedExchange ? 'success' : 'pending',
      detail: selectedExchange ? `${selectedExchange.name} (${selectedExchange.reason})` : 'Evaluating...'
    },
    {
      name: 'Route',
      status: route.status === 'routed' ? 'success' : route.status === 'pending' ? 'pending' : 'failed',
      detail: route.status === 'routed' ? 'Order routed' : route.status === 'pending' ? 'Routing...' : 'Route failed'
    },
    {
      name: 'Execute',
      status: execution.status === 'filled' ? 'success' : execution.status === 'partial' ? 'pending' : 'failed',
      detail: execution.status === 'filled'
        ? `Filled at $${execution.fillPrice?.toLocaleString()}`
        : execution.status === 'partial'
        ? 'Partially filled'
        : 'Rejected'
    }
  ]

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center gap-2">
          {stages.map((stage, idx) => (
            <div key={stage.name} className="flex items-center gap-2 flex-1">
              {/* Stage card */}
              <div
                className={`
                  flex-1 p-3 rounded border
                  ${stage.status === 'success' ? 'border-buy-green/30 bg-buy-green/5' : ''}
                  ${stage.status === 'failed' ? 'border-sell-red/30 bg-sell-red/5' : ''}
                  ${stage.status === 'pending' ? 'border-border bg-card' : ''}
                `}
              >
                <div className="flex items-center gap-2 mb-1">
                  <div className="text-xs font-semibold text-foreground">{stage.name}</div>
                  {stage.status === 'success' && (
                    <Check className="w-3.5 h-3.5 text-buy-green" />
                  )}
                  {stage.status === 'failed' && (
                    <X className="w-3.5 h-3.5 text-sell-red" />
                  )}
                </div>
                <div className="text-xs text-muted-foreground">{stage.detail}</div>
              </div>

              {/* Arrow connector */}
              {idx < stages.length - 1 && (
                <ChevronRight className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
