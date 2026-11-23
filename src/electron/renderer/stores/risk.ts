import { create } from 'zustand'
import type { RiskMetrics } from '../lib/types'

interface RiskState {
  metrics: RiskMetrics
  updateMetrics: (metrics: Partial<RiskMetrics>) => void
  setMetrics: (metrics: RiskMetrics) => void
}

const defaultMetrics: RiskMetrics = {
  positionLimitUtilization: {},
  exposureUtilization: {},
  drawdownCurrent: 0,
  drawdownMax: 0,
  dailyVolumeUsed: 0,
  dailyVolumeLimit: 1000000
}

export const useRiskStore = create<RiskState>((set) => ({
  metrics: defaultMetrics,
  updateMetrics: (updates) =>
    set((state) => ({
      metrics: { ...state.metrics, ...updates }
    })),
  setMetrics: (metrics) => set({ metrics })
}))
