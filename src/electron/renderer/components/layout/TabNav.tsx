import { AlertTriangle } from 'lucide-react'
import { Button } from '../ui/button'
import { runEmergencyStop } from '../../lib/kdb-actions'
import { useExchangesStore } from '../../stores/exchanges'

export type Tab = 'dashboard' | 'trading' | 'orders' | 'tca' | 'portfolio' | 'options' | 'pnl' | 'research' | 'builder' | 'ide' | 'market' | 'volume' | 'bonds' | 'risk' | 'settings'

interface TabNavProps {
  activeTab: Tab
  onTabChange: (tab: Tab) => void
}

export function TabNav({ activeTab, onTabChange }: TabNavProps) {
  const exchanges = useExchangesStore((state) => state.exchanges)

  const handleEmergencyStop = () => {
    if (confirm('EMERGENCY STOP: This will cancel all orders and close all positions. Continue?')) {
      void runEmergencyStop(window.kdb).then((r) => alert(r.message))
    }
  }

  const tabs: { id: Tab; label: string }[] = [
    { id: 'dashboard', label: 'Dashboard' },
    { id: 'trading', label: 'Trading' },
    { id: 'orders', label: 'Orders' },
    { id: 'tca', label: 'TCA' },
    { id: 'portfolio', label: 'Portfolio' },
    { id: 'options', label: 'Options' },
    { id: 'pnl', label: 'P&L' },
    { id: 'research', label: 'Research' },
    { id: 'builder', label: 'Builder' },
    { id: 'ide', label: 'IDE' },
    { id: 'market', label: 'Market' },
    { id: 'volume', label: 'Volume' },
    { id: 'bonds', label: 'Bonds' },
    { id: 'risk', label: 'Risk' },
    { id: 'settings', label: 'Settings' }
  ]

  return (
    <div className="h-10 border-b border-border bg-card px-4 flex items-center justify-between">
      <div className="flex items-center gap-6">
        <span className="text-sm font-semibold text-muted-foreground">MEDUSA</span>
        <div className="flex items-center gap-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`
                relative px-3 py-1.5 text-xs font-medium transition-colors
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
      </div>
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          {exchanges.map((ex) => (
            <div
              key={ex.exchange}
              className="flex items-center gap-1"
              title={`${ex.exchange}: ${ex.connected ? 'Connected' : 'Disconnected'} (${ex.latency}ms)`}
            >
              <div
                className={`w-1.5 h-1.5 rounded-full ${
                  ex.connected ? 'bg-buy-green' : 'bg-sell-red'
                }`}
              />
              <span className="text-[10px] text-muted-foreground uppercase">
                {ex.exchange}
              </span>
            </div>
          ))}
        </div>
        <Button
          variant="destructive"
          size="sm"
          onClick={handleEmergencyStop}
          className="h-6 gap-1.5 text-xs px-2"
        >
          <AlertTriangle className="w-3 h-3" />
          STOP
        </Button>
      </div>
    </div>
  )
}
