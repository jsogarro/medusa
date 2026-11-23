import { useEffect, useState } from 'react'
import { AppLayout } from './components/layout/AppLayout'
import { WorkspaceManager } from './components/layout/WorkspaceManager'
import { WorkspaceToolbar } from './components/layout/WorkspaceToolbar'
import { PopOutContainer } from './components/layout/PopOutContainer'
import { Tab } from './components/layout/TabNav'
import { Dashboard } from './pages/Dashboard'
import { Orders } from './pages/Orders'
import { TCADashboard } from './pages/TCADashboard'
import { Portfolio } from './pages/Portfolio'
import { PnLAnalytics } from './pages/PnLAnalytics'
import { Research } from './pages/Research'
import { StrategyBuilder } from './pages/StrategyBuilder'
import { AlgoWorkstation } from './pages/AlgoWorkstation'
import { MarketMonitor } from './pages/MarketMonitor'
import { VolumeAnalysis } from './pages/VolumeAnalysis'
import { Options } from './pages/Options'
import { Bonds } from './pages/Bonds'
import { RiskDashboard } from './pages/RiskDashboard'
import { Settings } from './pages/Settings'
import { useMockData } from './lib/use-mock-data'
import { WidgetType } from './lib/workspace-types'
import { LinkColor } from './stores/symbolLink'
import './styles/globals.css'

export function App() {
  const [activeTab, setActiveTab] = useState<Tab>('dashboard')
  const [isPopOut, setIsPopOut] = useState(false)
  const [popOutWidget, setPopOutWidget] = useState<{
    widgetType: WidgetType
    linkColor: LinkColor
  } | null>(null)

  // Populate stores with mock data when kdb+ is not available
  useMockData()

  // Check if running as pop-out window
  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search)
    const widgetType = urlParams.get('widgetType') as WidgetType | null
    const linkColor = (urlParams.get('linked') || 'none') as LinkColor

    if (widgetType) {
      setIsPopOut(true)
      setPopOutWidget({ widgetType, linkColor })
    }
  }, [])

  useEffect(() => {
    // Connect to kdb+ on app mount
    const connectToKdb = async () => {
      // Load config from localStorage or use defaults
      const savedConfig = localStorage.getItem('kdb-config')
      const config = savedConfig
        ? JSON.parse(savedConfig)
        : {
            tp: { host: 'localhost', port: 5010 },
            rdb: { host: 'localhost', port: 5011 }
          }

      if (!window.kdb) {
        console.warn('[App] window.kdb not available — running outside Electron')
        return
      }

      const result = await window.kdb.connect(config)
      if (result.success) {
        console.log('[App] Connected to kdb+')
      } else {
        console.error('[App] Failed to connect to kdb+:', result.error)
      }
    }

    connectToKdb()

    // Keyboard shortcuts
    const handleKeyDown = (e: KeyboardEvent) => {
      // Emergency stop: Ctrl+Shift+E
      if (e.ctrlKey && e.shiftKey && e.key === 'E') {
        e.preventDefault()
        if (window.kdb && confirm('EMERGENCY STOP: Cancel all orders and close positions?')) {
          window.kdb.emergencyStop()
        }
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  // Render pop-out window mode
  if (isPopOut && popOutWidget) {
    return (
      <PopOutContainer
        widgetType={popOutWidget.widgetType}
        linkColor={popOutWidget.linkColor}
      />
    )
  }

  const renderPage = () => {
    switch (activeTab) {
      case 'dashboard':
        return <Dashboard />
      case 'trading':
        return <WorkspaceLayout />
      case 'orders':
        return <Orders />
      case 'tca':
        return <TCADashboard />
      case 'portfolio':
        return <Portfolio />
      case 'options':
        return <Options />
      case 'pnl':
        return <PnLAnalytics />
      case 'research':
        return <Research />
      case 'builder':
        return <StrategyBuilder />
      case 'ide':
        return <AlgoWorkstation />
      case 'market':
        return <MarketMonitor />
      case 'volume':
        return <VolumeAnalysis />
      case 'bonds':
        return <Bonds />
      case 'risk':
        return <RiskDashboard />
      case 'settings':
        return <Settings />
      default:
        return <Dashboard />
    }
  }

  return (
    <AppLayout activeTab={activeTab} onTabChange={setActiveTab}>
      {renderPage()}
    </AppLayout>
  )
}

// Workspace layout wrapper (for Trading tab)
function WorkspaceLayout() {
  return (
    <div className="h-full flex flex-col">
      <WorkspaceToolbar />
      <div className="flex-1 overflow-hidden">
        <WorkspaceManager />
      </div>
    </div>
  )
}
