import { ComponentType } from 'react'
import {
  LineChart,
  List,
  Briefcase,
  Send,
  BarChart,
  Clock,
  TrendingUp,
  Shield,
  Eye,
  Cpu,
  Activity,
  GitBranch,
  Calculator,
  Layers,
  Mountain,
  DollarSign,
  Calendar
} from 'lucide-react'

import { WidgetType, WidgetMetadata } from './workspace-types'
import { LinkColor } from '../stores/symbolLink'

// Lazy-loaded widget components
import { AdvancedChart } from '../components/charts/AdvancedChart'
import { OrderBlotter } from '../components/orders/OrderBlotter'
import { PositionMonitor } from '../components/positions/PositionMonitor'
import { TradeTicket } from '../components/trade-ticket/TradeTicket'
import { OrderBook } from '../components/trading/OrderBook'
import { TimeSales } from '../components/trading/TimeSales'
import { PnLAnalytics } from '../pages/PnLAnalytics'
import { Risk } from '../pages/Risk'
import { MarketMonitor } from '../pages/MarketMonitor'
import { StrategyMonitor } from '../components/strategy/StrategyMonitor'
import { ExchangeStatus } from '../components/exchange/ExchangeStatus'
import { EquityCurve } from '../components/pnl/EquityCurve'
import { GreeksDashboard } from '../pages/GreeksDashboard'
import { YieldCurve } from '../pages/YieldCurve'
import { OptionsChain } from '../pages/OptionsChain'
import { PayoffDiagram } from '../pages/PayoffDiagram'
import { VolatilitySurface } from '../pages/VolatilitySurface'
import { BondLadder } from '../pages/BondLadder'
import { DurationDashboard } from '../pages/DurationDashboard'
import { VolumeAnalysis } from '../pages/VolumeAnalysis'
import { StrategyBuilder } from '../pages/StrategyBuilder'
import { useAssetClassStore } from '../stores/assetClass'

function AssetAwareChart({ linkColor }: { linkColor: LinkColor }) {
  const pair = useAssetClassStore((state) => state.symbol)
  const exchange = useAssetClassStore((state) => state.exchange)

  return <AdvancedChart pair={pair} exchange={exchange} linkColor={linkColor} />
}

export const WIDGET_REGISTRY: Record<
  WidgetType,
  {
    component: ComponentType<{ linkColor: LinkColor }>
    metadata: WidgetMetadata
  }
> = {
  chart: {
    component: AssetAwareChart,
    metadata: {
      title: 'Price Chart',
      icon: 'LineChart',
      supportsLinking: true
    }
  },
  orderBlotter: {
    component: () => <OrderBlotter />,
    metadata: {
      title: 'Orders',
      icon: 'List',
      supportsLinking: false
    }
  },
  positions: {
    component: () => <PositionMonitor />,
    metadata: {
      title: 'Positions',
      icon: 'Briefcase',
      supportsLinking: true
    }
  },
  tradeTicket: {
    component: ({ linkColor }: { linkColor: LinkColor }) => <TradeTicket linkColor={linkColor} />,
    metadata: {
      title: 'Trade Ticket',
      icon: 'Send',
      supportsLinking: true
    }
  },
  orderBook: {
    component: ({ linkColor }: { linkColor: LinkColor }) => (
      <OrderBook
        bids={[]}
        asks={[]}
        lastPrice={0}
        linkColor={linkColor}
      />
    ),
    metadata: {
      title: 'Order Book',
      icon: 'BarChart',
      supportsLinking: true
    }
  },
  timeSales: {
    component: ({ linkColor }: { linkColor: LinkColor }) => <TimeSales sales={[]} linkColor={linkColor} />,
    metadata: {
      title: 'Time & Sales',
      icon: 'Clock',
      supportsLinking: true
    }
  },
  pnl: {
    component: () => <PnLAnalytics />,
    metadata: {
      title: 'P&L',
      icon: 'TrendingUp',
      supportsLinking: false
    }
  },
  risk: {
    component: () => <Risk />,
    metadata: {
      title: 'Risk',
      icon: 'Shield',
      supportsLinking: false
    }
  },
  watchlist: {
    component: ({ linkColor }: { linkColor: LinkColor }) => <MarketMonitor linkColor={linkColor} />,
    metadata: {
      title: 'Watchlist',
      icon: 'Eye',
      supportsLinking: true
    }
  },
  strategy: {
    component: () => <StrategyMonitor />,
    metadata: {
      title: 'Strategies',
      icon: 'Cpu',
      supportsLinking: false
    }
  },
  exchange: {
    component: () => <ExchangeStatus />,
    metadata: {
      title: 'Exchanges',
      icon: 'Activity',
      supportsLinking: false
    }
  },
  equity: {
    component: () => <EquityCurve />,
    metadata: {
      title: 'Equity Curve',
      icon: 'TrendingUp',
      supportsLinking: false
    }
  },
  greeks: {
    component: () => <GreeksDashboard />,
    metadata: {
      title: 'Greeks',
      icon: 'Calculator',
      supportsLinking: false
    }
  },
  yieldCurve: {
    component: () => <YieldCurve />,
    metadata: {
      title: 'Yield Curve',
      icon: 'GitBranch',
      supportsLinking: false
    }
  },
  optionsChain: {
    component: ({ linkColor }: { linkColor: LinkColor }) => <OptionsChain linkColor={linkColor} />,
    metadata: {
      title: 'Options Chain',
      icon: 'Layers',
      supportsLinking: true
    }
  },
  payoffDiagram: {
    component: () => <PayoffDiagram />,
    metadata: {
      title: 'Payoff Diagram',
      icon: 'TrendingUp',
      supportsLinking: false
    }
  },
  volatilitySurface: {
    component: () => <VolatilitySurface />,
    metadata: {
      title: 'Vol Surface',
      icon: 'Mountain',
      supportsLinking: false
    }
  },
  bondLadder: {
    component: () => <BondLadder />,
    metadata: {
      title: 'Bond Ladder',
      icon: 'Calendar',
      supportsLinking: false
    }
  },
  durationDashboard: {
    component: () => <DurationDashboard />,
    metadata: {
      title: 'Duration',
      icon: 'Clock',
      supportsLinking: false
    }
  },
  volumeAnalysis: {
    component: () => <VolumeAnalysis />,
    metadata: {
      title: 'Volume Analysis',
      icon: 'BarChart',
      supportsLinking: false
    }
  },
  strategyBuilder: {
    component: () => <StrategyBuilder />,
    metadata: {
      title: 'Strategy Builder',
      icon: 'Cpu',
      supportsLinking: false
    }
  }
}

// Helper to get icon component
export function getIconComponent(iconName: string) {
  const icons: Record<string, ComponentType<{ className?: string }>> = {
    LineChart,
    List,
    Briefcase,
    Send,
    BarChart,
    Clock,
    TrendingUp,
    Shield,
    Eye,
    Cpu,
    Activity,
    GitBranch,
    Calculator,
    Layers,
    Mountain,
    DollarSign,
    Calendar
  }
  return icons[iconName] || LineChart
}
