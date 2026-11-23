import { create } from 'zustand'

export type TradingAssetClass = 'crypto' | 'equity' | 'option'

export interface AssetClassConfig {
  label: string
  defaultExchange: string
  defaultSymbol: string
  accountLabel: string
  symbolLabel: string
  quantityLabel: string
  quantityStep: string
  supportedOrderTypes: Array<'market' | 'limit'>
}

export const ASSET_CLASS_CONFIG: Record<TradingAssetClass, AssetClassConfig> = {
  crypto: {
    label: 'Crypto',
    defaultExchange: 'bitstamp',
    defaultSymbol: 'BTCUSD',
    accountLabel: 'Multi-exchange',
    symbolLabel: 'Pair',
    quantityLabel: 'Quantity',
    quantityStep: '0.0001',
    supportedOrderTypes: ['market', 'limit']
  },
  equity: {
    label: 'Equity',
    defaultExchange: 'alpaca',
    defaultSymbol: 'AAPL',
    accountLabel: 'Alpaca Paper',
    symbolLabel: 'Symbol',
    quantityLabel: 'Shares',
    quantityStep: '1',
    supportedOrderTypes: ['market', 'limit']
  },
  option: {
    label: 'Options',
    defaultExchange: 'alpaca',
    defaultSymbol: 'AAPL250117C00150000',
    accountLabel: 'Alpaca Options',
    symbolLabel: 'Contract',
    quantityLabel: 'Contracts',
    quantityStep: '1',
    supportedOrderTypes: ['limit']
  }
}

const STORAGE_KEY = 'medusa-trading-asset-context'

interface AssetContextSnapshot {
  assetClass: TradingAssetClass
  symbol: string
  exchange: string
}

interface AssetClassState extends AssetContextSnapshot {
  setAssetClass: (assetClass: TradingAssetClass) => void
  setSymbol: (symbol: string) => void
  setExchange: (exchange: string) => void
  setContext: (assetClass: TradingAssetClass, symbol: string, exchange: string) => void
}

function inferAssetClass(symbol: string): TradingAssetClass {
  if (/^[A-Z]{1,5}\d{6}[CP]\d{8}$/.test(symbol)) return 'option'
  if (/^[A-Z]{1,5}$/.test(symbol)) return 'equity'
  return 'crypto'
}

export function inferTradingAssetClass(symbol: string): TradingAssetClass {
  return inferAssetClass(symbol.toUpperCase())
}

function loadSnapshot(): AssetContextSnapshot {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      const parsed = JSON.parse(saved) as Partial<AssetContextSnapshot>
      if (parsed.assetClass && parsed.assetClass in ASSET_CLASS_CONFIG) {
        const config = ASSET_CLASS_CONFIG[parsed.assetClass]
        return {
          assetClass: parsed.assetClass,
          symbol: parsed.symbol || config.defaultSymbol,
          exchange: parsed.exchange || config.defaultExchange
        }
      }
    }
  } catch (err) {
    console.error('[AssetClass] Failed to load asset context:', err)
  }

  const config = ASSET_CLASS_CONFIG.crypto
  return {
    assetClass: 'crypto',
    symbol: config.defaultSymbol,
    exchange: config.defaultExchange
  }
}

function persistSnapshot(snapshot: AssetContextSnapshot) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  } catch (err) {
    console.error('[AssetClass] Failed to persist asset context:', err)
  }
}

export const useAssetClassStore = create<AssetClassState>((set) => ({
  ...loadSnapshot(),

  setAssetClass: (assetClass) => {
    const config = ASSET_CLASS_CONFIG[assetClass]
    const snapshot = {
      assetClass,
      symbol: config.defaultSymbol,
      exchange: config.defaultExchange
    }
    persistSnapshot(snapshot)
    set(snapshot)
  },

  setSymbol: (symbol) => {
    const normalized = symbol.toUpperCase()
    set((state) => {
      const snapshot = {
        assetClass: state.assetClass,
        symbol: normalized,
        exchange: state.exchange
      }
      persistSnapshot(snapshot)
      return { symbol: normalized }
    })
  },

  setExchange: (exchange) => {
    const normalized = exchange.toLowerCase()
    set((state) => {
      const snapshot = {
        assetClass: state.assetClass,
        symbol: state.symbol,
        exchange: normalized
      }
      persistSnapshot(snapshot)
      return { exchange: normalized }
    })
  },

  setContext: (assetClass, symbol, exchange) => {
    const snapshot = {
      assetClass,
      symbol: symbol.toUpperCase(),
      exchange: exchange.toLowerCase()
    }
    persistSnapshot(snapshot)
    set(snapshot)
  }
}))
