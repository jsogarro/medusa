import { useEffect } from 'react'
import { routeUpdate } from '../lib/route-update'

// Check if kdb API is available (only in Electron, not in browser dev mode)
const isKdbAvailable = () => typeof window !== 'undefined' && window.kdb !== undefined

export function useKdbSubscription(table: string) {
  // Depends on `table` only: store objects change on every update and would resubscribe on each one.
  useEffect(() => {
    if (!isKdbAvailable()) {
      console.warn(`[KDB] window.kdb not available — skipping subscription to ${table}`)
      return
    }

    // Subscribe to kdb+ table updates
    window.kdb
      .subscribe(table)
      .then((result: { success: boolean; error?: string }) => {
        if (!result.success) console.warn(`[KDB] Failed to subscribe to ${table}:`, result.error)
      })
      .catch((err: unknown) => {
        console.warn(`[KDB] Failed to subscribe to ${table}:`, err)
      })

    const removeListener = window.kdb.onUpdate((tableName: string, data: any) => {
      if (tableName === table) routeUpdate(tableName, data)
    })

    return () => {
      removeListener()
    }
  }, [table])
}
