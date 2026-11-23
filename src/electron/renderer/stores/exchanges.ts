import { create } from 'zustand'
import type { ExchangeStatus } from '../lib/types'

interface ExchangesState {
  exchanges: ExchangeStatus[]
  updateExchange: (exchange: string, updates: Partial<ExchangeStatus>) => void
  setExchanges: (exchanges: ExchangeStatus[]) => void
}

export const useExchangesStore = create<ExchangesState>((set) => ({
  exchanges: [],
  updateExchange: (exchange, updates) =>
    set((state) => ({
      exchanges: state.exchanges.map((ex) =>
        ex.exchange === exchange ? { ...ex, ...updates } : ex
      )
    })),
  setExchanges: (exchanges) => set({ exchanges })
}))
