import { MosaicNode } from 'react-mosaic-component'
import { LinkColor } from '../stores/symbolLink'

export type WidgetType =
  | 'chart'
  | 'orderBlotter'
  | 'positions'
  | 'tradeTicket'
  | 'orderBook'
  | 'timeSales'
  | 'pnl'
  | 'risk'
  | 'watchlist'
  | 'strategy'
  | 'exchange'
  | 'equity'
  | 'greeks'
  | 'yieldCurve'
  | 'optionsChain'
  | 'payoffDiagram'
  | 'volatilitySurface'
  | 'bondLadder'
  | 'durationDashboard'
  | 'volumeAnalysis'
  | 'strategyBuilder'

export interface WidgetConfig {
  id: string
  type: WidgetType
  linkColor: LinkColor
}

export interface WorkspaceLayout {
  name: string
  mosaicTree: MosaicNode<string> | null
  widgets: Record<string, WidgetConfig>
}

export interface WidgetMetadata {
  title: string
  icon: string // lucide-react icon name
  supportsLinking: boolean
}
