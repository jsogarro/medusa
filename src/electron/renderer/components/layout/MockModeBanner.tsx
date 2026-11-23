/**
 * MockModeBanner.tsx - Warning banner for mock data mode
 *
 * Displays a persistent warning when the app is running with mock data
 * (i.e., not connected to kdb+). This prevents users from thinking
 * they're trading with real data when they're not.
 */

import { useState, useEffect } from 'react'

export function MockModeBanner() {
  const [isMockMode, setIsMockMode] = useState(true)

  useEffect(() => {
    // Check if window.kdb is available
    // If window.kdb exists and is functional, we're connected to real kdb+
    const checkKdbConnection = () => {
      if (typeof window !== 'undefined' && window.kdb) {
        // Assume connected if kdb API exists
        setIsMockMode(false)
      } else {
        setIsMockMode(true)
      }
    }

    checkKdbConnection()

    // Re-check periodically in case connection status changes
    const interval = setInterval(checkKdbConnection, 5000)

    return () => clearInterval(interval)
  }, [])

  if (!isMockMode) return null

  return (
    <div className="shrink-0 bg-yellow-500 text-black px-4 py-2 text-center font-semibold">
      ⚠️ MOCK DATA MODE — Orders are simulated, not real
      <span className="ml-4 text-sm">(Connect to kdb+ for live trading)</span>
    </div>
  )
}
