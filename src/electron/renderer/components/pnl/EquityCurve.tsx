import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { generateMockEquityCurve } from '../../lib/mock-data'

// Generate realistic equity curve data - in production this would come from kdb+
const data = generateMockEquityCurve()

export function EquityCurve() {
  return (
    <div
      className="h-32"
      role="img"
      aria-label="Portfolio equity curve"
      aria-description="Time series chart showing portfolio value over time with area shading"
    >
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data}>
          <defs>
            <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="hsl(142 76% 36%)" stopOpacity={0.3} />
              <stop offset="95%" stopColor="hsl(142 76% 36%)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis dataKey="time" hide />
          <YAxis hide domain={['dataMin', 'dataMax']} />
          <Tooltip
            contentStyle={{
              backgroundColor: 'hsl(240 10% 8%)',
              border: '1px solid hsl(240 3.7% 15.9%)',
              borderRadius: '6px'
            }}
            labelStyle={{ color: 'hsl(0 0% 98%)' }}
          />
          <Area
            type="monotone"
            dataKey="equity"
            stroke="hsl(142 76% 36%)"
            fillOpacity={1}
            fill="url(#equityGradient)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}
