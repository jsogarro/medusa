import { create } from 'zustand'
import type { Strategy } from '../lib/types'

interface StrategiesState {
  strategies: Strategy[]
  updateStrategy: (name: string, updates: Partial<Strategy>) => void
  setStrategies: (strategies: Strategy[]) => void
}

export const useStrategiesStore = create<StrategiesState>((set) => ({
  strategies: [],
  updateStrategy: (name, updates) =>
    set((state) => ({
      strategies: state.strategies.map((s) =>
        s.name === name ? { ...s, ...updates } : s
      )
    })),
  setStrategies: (strategies) => set({ strategies })
}))
