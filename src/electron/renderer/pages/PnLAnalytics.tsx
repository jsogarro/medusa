import { useState } from 'react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../components/ui/tabs'
import { generateTearsheetData } from '../lib/tearsheet-data'
import { ReturnsSummary } from '../components/tearsheet/ReturnsSummary'
import { MonthlyReturnsHeatmap } from '../components/tearsheet/MonthlyReturnsHeatmap'
import { AnnualReturnsBar } from '../components/tearsheet/AnnualReturnsBar'
import { ReturnDistribution } from '../components/tearsheet/ReturnDistribution'
import { DrawdownAnalysis } from '../components/tearsheet/DrawdownAnalysis'
import { RiskMetricsGrid } from '../components/tearsheet/RiskMetricsGrid'
import { RollingStats } from '../components/tearsheet/RollingStats'
import { ExposureAnalysis } from '../components/tearsheet/ExposureAnalysis'
import { RoundTripAnalysis } from '../components/tearsheet/RoundTripAnalysis'

export function PnLAnalytics() {
  // Generate comprehensive tearsheet data (500 days, 200 trades)
  const [tearsheet] = useState(() => generateTearsheetData(500, 200))

  return (
    <div className="h-full flex flex-col p-2 overflow-hidden">
      <Tabs defaultValue="returns" className="flex-1 flex flex-col overflow-hidden">
        <TabsList className="grid grid-cols-6 w-full mb-2">
          <TabsTrigger value="returns" className="text-xs">
            Returns
          </TabsTrigger>
          <TabsTrigger value="drawdowns" className="text-xs">
            Drawdowns
          </TabsTrigger>
          <TabsTrigger value="metrics" className="text-xs">
            Metrics
          </TabsTrigger>
          <TabsTrigger value="rolling" className="text-xs">
            Rolling
          </TabsTrigger>
          <TabsTrigger value="exposure" className="text-xs">
            Exposure
          </TabsTrigger>
          <TabsTrigger value="roundtrips" className="text-xs">
            Round Trips
          </TabsTrigger>
        </TabsList>

        {/* Returns Tab */}
        <TabsContent value="returns" className="flex-1 overflow-y-auto space-y-2">
          <ReturnsSummary dailyReturns={tearsheet.dailyReturns} />
          <MonthlyReturnsHeatmap monthlyReturns={tearsheet.monthlyReturns} />
          <AnnualReturnsBar annualReturns={tearsheet.annualReturns} />
          <ReturnDistribution dailyReturns={tearsheet.dailyReturns} />
        </TabsContent>

        {/* Drawdowns Tab */}
        <TabsContent value="drawdowns" className="flex-1 overflow-y-auto">
          <DrawdownAnalysis underwater={tearsheet.drawdowns.underwater} periods={tearsheet.drawdowns.periods} />
        </TabsContent>

        {/* Metrics Tab */}
        <TabsContent value="metrics" className="flex-1 overflow-y-auto">
          <RiskMetricsGrid metrics={tearsheet.metrics} />
        </TabsContent>

        {/* Rolling Tab */}
        <TabsContent value="rolling" className="flex-1 overflow-y-auto">
          <RollingStats rollingMetrics={tearsheet.rollingMetrics} />
        </TabsContent>

        {/* Exposure Tab */}
        <TabsContent value="exposure" className="flex-1 overflow-y-auto">
          <ExposureAnalysis exposure={tearsheet.exposure} />
        </TabsContent>

        {/* Round Trips Tab */}
        <TabsContent value="roundtrips" className="flex-1 overflow-y-auto">
          <RoundTripAnalysis roundTrips={tearsheet.roundTrips} />
        </TabsContent>
      </Tabs>
    </div>
  )
}
