import { TabNav, Tab } from './TabNav'
import { SymbolBar } from './SymbolBar'
import { GBBOStrip } from '../trading/GBBOStrip'
import { MockModeBanner } from './MockModeBanner'
import { mockGBBOData } from '../../lib/mock-data'

interface AppLayoutProps {
  children: React.ReactNode
  activeTab: Tab
  onTabChange: (tab: Tab) => void
}

export function AppLayout({ children, activeTab, onTabChange }: AppLayoutProps) {
  // Mock symbol bar data
  const symbolBarData = {
    pair: 'BTCUSD',
    lastPrice: 67234.50,
    change: 345.20,
    changePct: 0.0052,
    bid: 67230,
    ask: 67238,
    volume: 12500,
    high24h: 67890,
    low24h: 66100
  }

  return (
    <div className="h-screen flex flex-col overflow-hidden bg-background">
      {/* Mock mode banner (always visible when active) */}
      <MockModeBanner />

      <TabNav activeTab={activeTab} onTabChange={onTabChange} />
      <SymbolBar {...symbolBarData} />
      <GBBOStrip data={mockGBBOData} />
      <main className="flex-1 overflow-hidden">
        {children}
      </main>
    </div>
  )
}
