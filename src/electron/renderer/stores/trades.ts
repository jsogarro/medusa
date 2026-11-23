import { create } from 'zustand'
import type { Trade } from '../lib/types'

interface TradesState {
  trades: Trade[]
  addTrade: (trade: Trade) => void
  setTrades: (trades: Trade[]) => void
}

export const useTradesStore = create<TradesState>((set) => ({
  trades: [],
  addTrade: (trade) =>
    set((state) => ({
      trades: [trade, ...state.trades]
    })),
  setTrades: (trades) => set({ trades })
}))
