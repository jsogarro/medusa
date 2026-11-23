import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/card'
import { generateCashFlows } from '../lib/bond-mock-data'

export function CashFlowCalendar() {
  const cashFlows = useMemo(() => generateCashFlows(), [])

  // Group by month
  const flowsByMonth = useMemo(() => {
    const grouped: Record<string, typeof cashFlows> = {}
    cashFlows.forEach(flow => {
      const month = flow.date.substring(0, 7) // YYYY-MM
      if (!grouped[month]) grouped[month] = []
      grouped[month].push(flow)
    })
    return grouped
  }, [cashFlows])

  const months = useMemo(() => Object.keys(flowsByMonth).sort(), [flowsByMonth])

  // Calculate summaries
  const summaries = useMemo(() => {
    const calculateSummary = (monthCount: number) => {
      const cutoff = new Date()
      cutoff.setMonth(cutoff.getMonth() + monthCount)
      const relevant = cashFlows.filter(f => new Date(f.date) <= cutoff)
      return relevant.reduce((sum, f) => sum + f.amount, 0)
    }

    return {
      next3m: calculateSummary(3),
      next6m: calculateSummary(6),
      next12m: calculateSummary(12)
    }
  }, [cashFlows])

  const { next3m, next6m, next12m } = summaries

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">Cash Flow Calendar</h1>
        <p className="text-sm text-muted-foreground">
          Coupon and maturity payment schedule
        </p>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Next 3 Months
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-mono font-bold text-buy-green">
              ${next3m.toLocaleString()}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Next 6 Months
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-mono font-bold text-buy-green">
              ${next6m.toLocaleString()}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Next 12 Months
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-mono font-bold text-buy-green">
              ${next12m.toLocaleString()}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Calendar Grid */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium text-muted-foreground">
            Payment Schedule
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {months.map(month => {
              const flows = flowsByMonth[month]
              const monthTotal = flows.reduce((sum, f) => sum + f.amount, 0)
              const monthDate = new Date(month + '-01')
              const monthLabel = monthDate.toLocaleDateString('en-US', { year: 'numeric', month: 'long' })

              return (
                <div key={month} className="border border-border rounded-lg p-3 space-y-2">
                  <div className="flex items-center justify-between border-b border-border pb-2">
                    <h3 className="text-sm font-semibold">{monthLabel}</h3>
                    <p className="text-sm font-mono font-bold text-buy-green">
                      ${monthTotal.toLocaleString()}
                    </p>
                  </div>
                  <div className="space-y-1.5">
                    {flows.map((flow, idx) => {
                      const flowDate = new Date(flow.date)
                      const dayLabel = flowDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })

                      return (
                        <div
                          key={idx}
                          className={`flex items-center justify-between text-xs p-2 rounded ${
                            flow.type === 'coupon' ? 'bg-buy-green/10' : 'bg-primary/10'
                          }`}
                        >
                          <div className="flex items-center gap-2">
                            <span className="font-mono font-semibold">{dayLabel}</span>
                            <span
                              className={`px-2 py-0.5 rounded text-[10px] font-semibold uppercase ${
                                flow.type === 'coupon'
                                  ? 'bg-buy-green/20 text-buy-green'
                                  : 'bg-primary/20 text-primary'
                              }`}
                            >
                              {flow.type}
                            </span>
                            <span className="text-muted-foreground font-mono text-[10px]">
                              {flow.cusip}
                            </span>
                          </div>
                          <p className="font-mono font-semibold">
                            ${flow.amount.toLocaleString()}
                          </p>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
