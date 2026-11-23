import { Card } from '../ui/card'
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, ReferenceLine } from 'recharts'
import { mockOrderFlowData } from '../../lib/mock-data'

export function OrderFlowImbalance() {
  const { buyPressure, sellPressure, imbalance, history } = mockOrderFlowData

  return (
    <Card className="h-full p-3 flex flex-col">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2">ORDER FLOW IMBALANCE</h3>

      {/* Current Imbalance Bar */}
      <div className="mb-3">
        <div className="flex justify-between text-xs font-mono mb-1">
          <span className="text-sell-red">{sellPressure}% Sell</span>
          <span className="text-muted-foreground">{(imbalance * 100).toFixed(1)}% Net</span>
          <span className="text-buy-green">{buyPressure}% Buy</span>
        </div>
        <div className="h-6 flex rounded overflow-hidden">
          <div
            className="bg-sell-red flex items-center justify-center text-[10px] font-mono font-semibold"
            style={{ width: `${sellPressure}%` }}
          >
            {sellPressure > 20 && `${sellPressure}%`}
          </div>
          <div
            className="bg-buy-green flex items-center justify-center text-[10px] font-mono font-semibold"
            style={{ width: `${buyPressure}%` }}
          >
            {buyPressure > 20 && `${buyPressure}%`}
          </div>
        </div>
      </div>

      {/* Historical Imbalance Sparkline */}
      <div className="flex-1 min-h-0">
        <div className="text-[10px] text-muted-foreground mb-1">Historical Imbalance</div>
        <ResponsiveContainer width="100%" height="100%">
          <LineChart
            data={history}
            margin={{ top: 0, right: 0, left: 0, bottom: 0 }}
          >
            <XAxis dataKey="time" hide />
            <YAxis hide domain={[-0.3, 0.3]} />
            <ReferenceLine y={0} stroke="#26262a" strokeWidth={1} />
            <Line
              type="monotone"
              dataKey="imbalance"
              stroke="#ff9100"
              strokeWidth={1.5}
              dot={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-2 text-[10px] text-muted-foreground font-mono">
        Positive = buy pressure | Negative = sell pressure
      </div>
    </Card>
  )
}
