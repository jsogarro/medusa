import { create } from 'zustand'
import type { Position } from '../lib/types'

interface PositionsState {
  positions: Position[]
  addPosition: (position: Position) => void
  updatePosition: (key: string, updates: Partial<Position>) => void
  setPositions: (positions: Position[]) => void
}

export const usePositionsStore = create<PositionsState>((set) => ({
  positions: [],
  addPosition: (position) =>
    set((state) => ({
      positions: [...state.positions, position]
    })),
  updatePosition: (key, updates) =>
    set((state) => ({
      positions: state.positions.map((p) => {
        const posKey = `${p.exchange}-${p.pair}`
        return posKey === key ? { ...p, ...updates } : p
      })
    })),
  setPositions: (positions) => set({ positions })
}))
