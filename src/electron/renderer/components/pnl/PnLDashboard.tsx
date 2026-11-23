import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { EquityCurve } from './EquityCurve'
import { DrawdownGauge } from './DrawdownGauge'
import { useRiskStore } from '../../stores/risk'

export function PnLDashboard() {
  const metrics = useRiskStore((state) => state.metrics)

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">P&L</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <EquityCurve />
        <DrawdownGauge current={metrics.drawdownCurrent} max={metrics.drawdownMax} />
      </CardContent>
    </Card>
  )
}
