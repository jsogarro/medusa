import { Card } from '../ui/card'
import type { MonthlyReturn } from '../../lib/tearsheet-data'

interface MonthlyReturnsHeatmapProps {
  monthlyReturns: MonthlyReturn[]
}

export function MonthlyReturnsHeatmap({ monthlyReturns }: MonthlyReturnsHeatmapProps) {
  // Organize data by year
  const yearMap = new Map<number, Map<number, number>>()

  monthlyReturns.forEach(({ year, month, return: ret }) => {
    if (!yearMap.has(year)) {
      yearMap.set(year, new Map())
    }
    yearMap.get(year)!.set(month, ret)
  })

  const years = Array.from(yearMap.keys()).sort()
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

  // Color function based on return magnitude
  const getColor = (ret: number): string => {
    if (ret > 0.05) return '#00c853' // Strong green
    if (ret > 0.02) return '#4caf50' // Green
    if (ret > 0) return '#81c784' // Light green
    if (ret > -0.02) return '#ffb74d' // Light orange
    if (ret > -0.05) return '#ff5252' // Red
    return '#d32f2f' // Strong red
  }

  return (
    <Card className="p-3">
      <h3 className="text-xs font-semibold text-muted-foreground mb-3">MONTHLY RETURNS HEATMAP</h3>
      <div
        className="overflow-x-auto"
        role="img"
        aria-label="Monthly returns heatmap"
        aria-description="Color-coded table showing monthly portfolio returns by year, with green indicating positive returns and red indicating negative returns"
      >
        <table className="w-full text-[10px] font-mono">
          <thead>
            <tr>
              <th className="text-left p-1 text-muted-foreground">Year</th>
              {months.map((month) => (
                <th key={month} className="text-center p-1 text-muted-foreground">
                  {month}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {years.map((year) => (
              <tr key={year}>
                <td className="p-1 text-muted-foreground font-semibold">{year}</td>
                {months.map((_, monthIdx) => {
                  const monthNum = monthIdx + 1
                  const ret = yearMap.get(year)?.get(monthNum)
                  return (
                    <td
                      key={monthNum}
                      className="text-center p-1 rounded"
                      style={{
                        backgroundColor: ret !== undefined ? getColor(ret) : 'transparent',
                        color: ret !== undefined && Math.abs(ret) > 0.01 ? '#000' : 'inherit'
                      }}
                    >
                      {ret !== undefined ? `${(ret * 100).toFixed(1)}` : '-'}
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  )
}
