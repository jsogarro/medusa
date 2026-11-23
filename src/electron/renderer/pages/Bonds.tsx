import { useState } from 'react'
import { YieldCurve } from './YieldCurve'
import { DurationDashboard } from './DurationDashboard'
import { BondLadder } from './BondLadder'
import { CashFlowCalendar } from './CashFlowCalendar'
import { ScenarioAnalysis } from './ScenarioAnalysis'

type BondTab = 'curve' | 'duration' | 'ladder' | 'cashflow' | 'scenarios'

export function Bonds() {
  const [activeTab, setActiveTab] = useState<BondTab>('curve')

  const bondTabs: { id: BondTab; label: string }[] = [
    { id: 'curve', label: 'Curve' },
    { id: 'duration', label: 'Duration' },
    { id: 'ladder', label: 'Ladder' },
    { id: 'cashflow', label: 'Cash Flow' },
    { id: 'scenarios', label: 'Scenarios' }
  ]

  return (
    <div className="h-full flex flex-col">
      {/* Sub-navigation */}
      <div className="h-8 border-b border-border bg-card px-4 flex items-center gap-1">
        {bondTabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`
              relative px-3 py-1 text-xs font-medium transition-colors
              ${
                activeTab === tab.id
                  ? 'text-foreground'
                  : 'text-muted-foreground hover:text-foreground'
              }
            `}
          >
            {tab.label}
            {activeTab === tab.id && (
              <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-primary" />
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'curve' && <YieldCurve />}
        {activeTab === 'duration' && <DurationDashboard />}
        {activeTab === 'ladder' && <BondLadder />}
        {activeTab === 'cashflow' && <CashFlowCalendar />}
        {activeTab === 'scenarios' && <ScenarioAnalysis />}
      </div>
    </div>
  )
}
