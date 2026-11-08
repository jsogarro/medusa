// Renderer-side helpers around window.kdb. Pure and testable: no React, no DOM.

export interface KdbResult {
  success: boolean
  error?: string
}

export interface KdbControls {
  emergencyStop: () => Promise<KdbResult>
  strategyControl: (name: string, action: 'pause' | 'resume' | 'stop') => Promise<KdbResult>
}

export interface ActionOutcome {
  ok: boolean
  message: string
}

const UNAVAILABLE = 'kdb+ bridge is not available'

/** The main process answers { success: false } instead of rejecting, so success must be read from the result. */
export async function runEmergencyStop(kdb: KdbControls | undefined): Promise<ActionOutcome> {
  if (!kdb) return { ok: false, message: `Emergency stop FAILED: ${UNAVAILABLE}` }
  try {
    const result = await kdb.emergencyStop()
    if (result?.success) return { ok: true, message: 'Emergency stop executed' }
    return { ok: false, message: `Emergency stop FAILED: ${result?.error ?? 'unknown error'}` }
  } catch (err) {
    return { ok: false, message: `Emergency stop FAILED: ${String(err)}` }
  }
}

export async function pauseAllStrategies(kdb: KdbControls | undefined, names: string[]): Promise<ActionOutcome> {
  if (!kdb) return { ok: false, message: `Pause all FAILED: ${UNAVAILABLE}` }
  const settled = await Promise.allSettled(names.map((n) => kdb.strategyControl(n, 'pause')))
  const failed = names.filter((_, i) => {
    const s = settled[i]
    return s.status === 'rejected' || !s.value?.success
  })
  if (failed.length === 0) return { ok: true, message: 'All strategies paused' }
  return { ok: false, message: `Failed to pause ${failed.length} of ${names.length} strategies: ${failed.join(', ')}` }
}

export interface KdbConfig {
  tp: { host: string; port: number }
  rdb: { host: string; port: number }
}

export const DEFAULT_KDB_CONFIG: KdbConfig = {
  tp: { host: 'localhost', port: 5010 },
  rdb: { host: 'localhost', port: 5011 }
}

const isEndpoint = (e: any) => typeof e?.host === 'string' && Number.isInteger(e?.port)

/** Parse the saved connection config; corrupt or malformed storage falls back to defaults instead of crashing the app. */
export function loadKdbConfig(raw: string | null): KdbConfig {
  if (!raw) return DEFAULT_KDB_CONFIG
  try {
    const parsed = JSON.parse(raw)
    return isEndpoint(parsed?.tp) && isEndpoint(parsed?.rdb) ? parsed : DEFAULT_KDB_CONFIG
  } catch {
    return DEFAULT_KDB_CONFIG
  }
}

/** A pop-out window is a secondary view; only the main window owns the kdb+ connection. */
export function isPopOutSearch(search: string): boolean {
  return new URLSearchParams(search).has('widgetType')
}

/** Runs at most one submission at a time; calls made while one is in flight are dropped. */
export function createSubmitGuard() {
  let inFlight = false
  return async <T>(fn: () => Promise<T>): Promise<T | undefined> => {
    if (inFlight) return undefined
    inFlight = true
    try {
      return await fn()
    } finally {
      inFlight = false
    }
  }
}
