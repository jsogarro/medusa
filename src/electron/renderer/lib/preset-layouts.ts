import { WorkspaceLayout } from './workspace-types'

export const PRESET_LAYOUTS: Record<string, WorkspaceLayout> = {
  trading: {
    name: 'Trading',
    mosaicTree: {
      direction: 'row',
      first: {
        direction: 'column',
        first: 'chart-1',
        second: 'orderBlotter-1',
        splitPercentage: 60
      },
      second: {
        direction: 'column',
        first: 'tradeTicket-1',
        second: {
          direction: 'column',
          first: 'orderBook-1',
          second: 'timeSales-1',
          splitPercentage: 60
        },
        splitPercentage: 30
      },
      splitPercentage: 65
    },
    widgets: {
      'chart-1': { id: 'chart-1', type: 'chart', linkColor: 'blue' },
      'orderBlotter-1': { id: 'orderBlotter-1', type: 'orderBlotter', linkColor: 'none' },
      'tradeTicket-1': { id: 'tradeTicket-1', type: 'tradeTicket', linkColor: 'blue' },
      'orderBook-1': { id: 'orderBook-1', type: 'orderBook', linkColor: 'blue' },
      'timeSales-1': { id: 'timeSales-1', type: 'timeSales', linkColor: 'blue' }
    }
  },

  portfolio: {
    name: 'Portfolio',
    mosaicTree: {
      direction: 'row',
      first: {
        direction: 'column',
        first: 'positions-1',
        second: 'pnl-1',
        splitPercentage: 50
      },
      second: {
        direction: 'column',
        first: 'risk-1',
        second: 'strategy-1',
        splitPercentage: 50
      },
      splitPercentage: 50
    },
    widgets: {
      'positions-1': { id: 'positions-1', type: 'positions', linkColor: 'green' },
      'pnl-1': { id: 'pnl-1', type: 'pnl', linkColor: 'none' },
      'risk-1': { id: 'risk-1', type: 'risk', linkColor: 'none' },
      'strategy-1': { id: 'strategy-1', type: 'strategy', linkColor: 'none' }
    }
  },

  research: {
    name: 'Research',
    mosaicTree: {
      direction: 'row',
      first: {
        direction: 'column',
        first: 'chart-1',
        second: 'watchlist-1',
        splitPercentage: 60
      },
      second: {
        direction: 'column',
        first: 'equity-1',
        second: 'volumeAnalysis-1',
        splitPercentage: 50
      },
      splitPercentage: 65
    },
    widgets: {
      'chart-1': { id: 'chart-1', type: 'chart', linkColor: 'red' },
      'watchlist-1': { id: 'watchlist-1', type: 'watchlist', linkColor: 'red' },
      'equity-1': { id: 'equity-1', type: 'equity', linkColor: 'none' },
      'volumeAnalysis-1': { id: 'volumeAnalysis-1', type: 'volumeAnalysis', linkColor: 'none' }
    }
  },

  options: {
    name: 'Options',
    mosaicTree: {
      direction: 'row',
      first: {
        direction: 'column',
        first: 'optionsChain-1',
        second: 'greeks-1',
        splitPercentage: 60
      },
      second: {
        direction: 'column',
        first: 'payoffDiagram-1',
        second: 'volatilitySurface-1',
        splitPercentage: 50
      },
      splitPercentage: 55
    },
    widgets: {
      'optionsChain-1': { id: 'optionsChain-1', type: 'optionsChain', linkColor: 'yellow' },
      'greeks-1': { id: 'greeks-1', type: 'greeks', linkColor: 'none' },
      'payoffDiagram-1': { id: 'payoffDiagram-1', type: 'payoffDiagram', linkColor: 'none' },
      'volatilitySurface-1': { id: 'volatilitySurface-1', type: 'volatilitySurface', linkColor: 'none' }
    }
  }
}
