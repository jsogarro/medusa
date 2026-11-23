import { useState, memo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { generateOptionsChain } from '../lib/options-mock-data'
import { formatPrice } from '../lib/utils'
import { LinkColor } from '../stores/symbolLink'

interface OptionsChainProps {
  linkColor?: LinkColor
}

export const OptionsChain = memo(function OptionsChain({ linkColor = 'none' }: OptionsChainProps) {
  // NOTE: In production, linkColor would be used to load options for the linked underlying symbol
  // @ts-ignore - linkColor for future implementation
  const _linkColor = linkColor
  const [selectedExpiry, setSelectedExpiry] = useState('2026-06-16')
  const [symbol] = useState('AAPL')
  const spotPrice = 155

  const expiries = [
    { label: 'Jun 16', value: '2026-06-16' },
    { label: 'Jul 21', value: '2026-07-21' },
    { label: 'Aug 18', value: '2026-08-18' },
    { label: 'Sep 15', value: '2026-09-15' }
  ]

  const chain = generateOptionsChain(symbol, spotPrice, selectedExpiry)

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">{symbol} Options Chain</h1>
          <p className="text-sm text-muted-foreground">
            Spot: ${formatPrice(spotPrice)}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {expiries.map((exp) => (
            <button
              key={exp.value}
              onClick={() => setSelectedExpiry(exp.value)}
              className={`
                px-3 py-1.5 text-xs font-medium rounded transition-colors
                ${
                  selectedExpiry === exp.value
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-card text-muted-foreground hover:text-foreground border border-border'
                }
              `}
            >
              {exp.label}
            </button>
          ))}
        </div>
      </div>

      {/* Options Chain Table */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            {selectedExpiry} Expiration
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Bid</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Ask</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Vol</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">OI</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Δ</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">IV</th>
                  <th className="text-center py-2 px-4 font-semibold bg-muted">Strike</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Δ</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">IV</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">OI</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Vol</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Ask</th>
                  <th className="text-right py-2 px-3 font-medium text-muted-foreground">Bid</th>
                </tr>
              </thead>
              <tbody className="font-mono">
                {chain.map((row) => (
                  <tr
                    key={row.strike}
                    className={`
                      border-b border-border/50 transition-colors hover:bg-muted/50
                      ${row.isATM ? 'bg-primary/10 border-primary/30' : ''}
                    `}
                  >
                    {/* CALLS */}
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {formatPrice(row.callBid)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {formatPrice(row.callAsk)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.callVol.toLocaleString()}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.callOI.toLocaleString()}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.callDelta.toFixed(2)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMCall ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {(row.callIV * 100).toFixed(1)}%
                    </td>

                    {/* STRIKE */}
                    <td
                      className={`
                        text-center py-1.5 px-4 font-semibold
                        ${row.isATM ? 'bg-primary text-primary-foreground' : 'bg-muted'}
                      `}
                    >
                      {formatPrice(row.strike)}
                    </td>

                    {/* PUTS */}
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.putDelta.toFixed(2)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {(row.putIV * 100).toFixed(1)}%
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.putOI.toLocaleString()}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {row.putVol.toLocaleString()}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {formatPrice(row.putAsk)}
                    </td>
                    <td
                      className={`text-right py-1.5 px-3 ${
                        row.isITMPut ? 'bg-buy-green/10' : 'bg-muted/30'
                      }`}
                    >
                      {formatPrice(row.putBid)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  )
})
