import { useState } from 'react'
import { OptionsChain } from './OptionsChain'
import { GreeksDashboard } from './GreeksDashboard'
import { PayoffDiagram } from './PayoffDiagram'
import { VolatilitySurface } from './VolatilitySurface'
import { OptionsStrategyBuilder } from './OptionsStrategyBuilder'

type OptionsSubTab = 'chain' | 'greeks' | 'payoff' | 'vol-surface' | 'builder'

export function Options() {
  const [activeSubTab, setActiveSubTab] = useState<OptionsSubTab>('chain')

  const subTabs: { id: OptionsSubTab; label: string }[] = [
    { id: 'chain', label: 'Chain' },
    { id: 'greeks', label: 'Greeks' },
    { id: 'payoff', label: 'Payoff' },
    { id: 'vol-surface', label: 'Vol Surface' },
    { id: 'builder', label: 'Builder' }
  ]

  const renderSubPage = () => {
    switch (activeSubTab) {
      case 'chain':
        return <OptionsChain />
      case 'greeks':
        return <GreeksDashboard />
      case 'payoff':
        return <PayoffDiagram />
      case 'vol-surface':
        return <VolatilitySurface />
      case 'builder':
        return <OptionsStrategyBuilder />
      default:
        return <OptionsChain />
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Sub-tab navigation */}
      <div className="border-b border-border bg-card px-6 flex items-center gap-1">
        {subTabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveSubTab(tab.id)}
            className={`
              relative px-4 py-2 text-xs font-medium transition-colors
              ${
                activeSubTab === tab.id
                  ? 'text-foreground'
                  : 'text-muted-foreground hover:text-foreground'
              }
            `}
          >
            {tab.label}
            {activeSubTab === tab.id && (
              <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-primary" />
            )}
          </button>
        ))}
      </div>

      {/* Sub-page content */}
      <div className="flex-1 overflow-auto">{renderSubPage()}</div>
    </div>
  )
}
