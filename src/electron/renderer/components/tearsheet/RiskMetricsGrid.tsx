import { Card } from '../ui/card'

interface RiskMetricsGridProps {
  metrics: {
    annualReturn: number
    cumulativeReturn: number
    annualVolatility: number
    dailyVaR95: number
    sharpe: number
    sortino: number
    calmar: number
    omega: number
    maxDrawdown: number
    stability: number
    tailRatio: number
    skew: number
    kurtosis: number
    totalTrades: number
    winRate: number
    profitFactor: number
    avgWinLossRatio: number
    avgTradeDurationHours: number
  }
}

export function RiskMetricsGrid({ metrics }: RiskMetricsGridProps) {
  const MetricCard = ({ label, value }: { label: string; value: string }) => (
    <Card className="p-2">
      <div className="text-[9px] text-muted-foreground mb-1">{label}</div>
      <div className="text-sm font-bold font-mono">{value}</div>
    </Card>
  )

  return (
    <div className="space-y-3">
      {/* Returns */}
      <div>
        <h4 className="text-[10px] font-semibold text-muted-foreground mb-2">RETURNS</h4>
        <div className="grid grid-cols-4 gap-2">
          <MetricCard label="Annual Return" value={`${(metrics.annualReturn * 100).toFixed(1)}%`} />
          <MetricCard label="Cumulative Return" value={`${(metrics.cumulativeReturn * 100).toFixed(1)}%`} />
          <MetricCard label="Annual Volatility" value={`${(metrics.annualVolatility * 100).toFixed(1)}%`} />
          <MetricCard label="Daily VaR (95%)" value={`${(metrics.dailyVaR95 * 100).toFixed(1)}%`} />
        </div>
      </div>

      {/* Risk-Adjusted */}
      <div>
        <h4 className="text-[10px] font-semibold text-muted-foreground mb-2">RISK-ADJUSTED</h4>
        <div className="grid grid-cols-4 gap-2">
          <MetricCard label="Sharpe Ratio" value={metrics.sharpe.toFixed(2)} />
          <MetricCard label="Sortino Ratio" value={metrics.sortino.toFixed(2)} />
          <MetricCard label="Calmar Ratio" value={metrics.calmar.toFixed(2)} />
          <MetricCard label="Omega Ratio" value={metrics.omega.toFixed(2)} />
        </div>
      </div>

      {/* Tail Risk */}
      <div>
        <h4 className="text-[10px] font-semibold text-muted-foreground mb-2">TAIL RISK</h4>
        <div className="grid grid-cols-5 gap-2">
          <MetricCard label="Max Drawdown" value={`${(metrics.maxDrawdown * 100).toFixed(1)}%`} />
          <MetricCard label="Stability" value={metrics.stability.toFixed(2)} />
          <MetricCard label="Tail Ratio" value={metrics.tailRatio.toFixed(2)} />
          <MetricCard label="Skew" value={metrics.skew.toFixed(2)} />
          <MetricCard label="Kurtosis" value={metrics.kurtosis.toFixed(2)} />
        </div>
      </div>

      {/* Trading */}
      <div>
        <h4 className="text-[10px] font-semibold text-muted-foreground mb-2">TRADING</h4>
        <div className="grid grid-cols-5 gap-2">
          <MetricCard label="Total Trades" value={metrics.totalTrades.toString()} />
          <MetricCard label="Win Rate" value={`${(metrics.winRate * 100).toFixed(0)}%`} />
          <MetricCard label="Profit Factor" value={metrics.profitFactor.toFixed(2)} />
          <MetricCard label="Avg Win/Loss" value={metrics.avgWinLossRatio.toFixed(2)} />
          <MetricCard label="Avg Duration" value={`${metrics.avgTradeDurationHours.toFixed(1)}h`} />
        </div>
      </div>
    </div>
  )
}
