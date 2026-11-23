/**
 * Settings Page
 *
 * SECURITY: API keys are NEVER stored in localStorage or React state.
 * - All API keys are stored server-side in environment variables or secure credential stores
 * - UI only displays last 4 characters for verification (e.g., "sk_***abc")
 * - When user "sets" an API key, it's sent directly to backend via IPC and never cached in frontend
 *
 * TODO (Production): Integrate with OS keychain (macOS Keychain, Windows Credential Manager)
 */

import { useState } from 'react'
import { Card } from '../components/ui/card'
import { Input } from '../components/ui/input'
import { Button } from '../components/ui/button'
import { mockSettings } from '../lib/mock-data'
import type { Settings as SettingsType } from '../lib/types'

type SettingsSection = 'connections' | 'exchanges' | 'risk' | 'display' | 'paper'

export function Settings() {
  const [activeSection, setActiveSection] = useState<SettingsSection>('connections')
  // NOTE: mockSettings contains masked keys only (last 4 chars). Real keys are never in frontend state.
  const [settings, setSettings] = useState<SettingsType>(mockSettings)

  const sections = [
    { id: 'connections' as const, label: 'Connection Settings' },
    { id: 'exchanges' as const, label: 'Exchange Configuration' },
    { id: 'risk' as const, label: 'Risk Limits' },
    { id: 'display' as const, label: 'Display Preferences' },
    { id: 'paper' as const, label: 'Paper Trading' }
  ]

  const testConnection = async (service: 'tp' | 'rdb' | 'hdb') => {
    alert(`Testing connection to ${service.toUpperCase()}...`)
    // In real implementation, would call window.kdb.testConnection()
  }

  const reconnect = () => {
    alert('Reconnecting to all kdb+ services...')
    // In real implementation, would call window.kdb.reconnect()
  }

  return (
    <div className="h-full flex gap-2 p-2">
      {/* Left sidebar navigation */}
      <div className="w-56 flex flex-col gap-1">
        {sections.map((section) => (
          <button
            key={section.id}
            onClick={() => setActiveSection(section.id)}
            className={`
              px-3 py-2 text-xs font-medium text-left rounded transition-colors
              ${
                activeSection === section.id
                  ? 'bg-card text-foreground border border-border'
                  : 'text-muted-foreground hover:bg-card/50'
              }
            `}
          >
            {section.label}
          </button>
        ))}
      </div>

      {/* Right content area */}
      <div className="flex-1 overflow-y-auto">
        <Card className="p-4">
          {activeSection === 'connections' && (
            <div className="space-y-4">
              <h2 className="text-sm font-semibold mb-4">kdb+ Connection Settings</h2>

              {/* Tickerplant */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <label className="text-xs font-medium text-muted-foreground w-24">Tickerplant</label>
                  <div
                    className={`w-2 h-2 rounded-full ${
                      settings.connections.tp.connected ? 'bg-buy-green' : 'bg-sell-red'
                    }`}
                  />
                  <span className="text-xs font-mono">
                    {settings.connections.tp.connected ? 'Connected' : 'Disconnected'}
                  </span>
                </div>
                <div className="flex gap-2">
                  <Input
                    type="text"
                    value={settings.connections.tp.host}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          tp: { ...settings.connections.tp, host: e.target.value }
                        }
                      })
                    }
                    placeholder="Host"
                    className="h-8 text-xs font-mono flex-1"
                  />
                  <Input
                    type="number"
                    value={settings.connections.tp.port}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          tp: { ...settings.connections.tp, port: parseInt(e.target.value) }
                        }
                      })
                    }
                    placeholder="Port"
                    className="h-8 text-xs font-mono w-24"
                  />
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => testConnection('tp')}
                    className="h-8 text-xs"
                  >
                    Test
                  </Button>
                </div>
              </div>

              {/* RDB */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <label className="text-xs font-medium text-muted-foreground w-24">RDB</label>
                  <div
                    className={`w-2 h-2 rounded-full ${
                      settings.connections.rdb.connected ? 'bg-buy-green' : 'bg-sell-red'
                    }`}
                  />
                  <span className="text-xs font-mono">
                    {settings.connections.rdb.connected ? 'Connected' : 'Disconnected'}
                  </span>
                </div>
                <div className="flex gap-2">
                  <Input
                    type="text"
                    value={settings.connections.rdb.host}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          rdb: { ...settings.connections.rdb, host: e.target.value }
                        }
                      })
                    }
                    placeholder="Host"
                    className="h-8 text-xs font-mono flex-1"
                  />
                  <Input
                    type="number"
                    value={settings.connections.rdb.port}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          rdb: { ...settings.connections.rdb, port: parseInt(e.target.value) }
                        }
                      })
                    }
                    placeholder="Port"
                    className="h-8 text-xs font-mono w-24"
                  />
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => testConnection('rdb')}
                    className="h-8 text-xs"
                  >
                    Test
                  </Button>
                </div>
              </div>

              {/* HDB */}
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <label className="text-xs font-medium text-muted-foreground w-24">HDB</label>
                  <div
                    className={`w-2 h-2 rounded-full ${
                      settings.connections.hdb.connected ? 'bg-buy-green' : 'bg-sell-red'
                    }`}
                  />
                  <span className="text-xs font-mono">
                    {settings.connections.hdb.connected ? 'Connected' : 'Disconnected'}
                  </span>
                </div>
                <div className="flex gap-2">
                  <Input
                    type="text"
                    value={settings.connections.hdb.host}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          hdb: { ...settings.connections.hdb, host: e.target.value }
                        }
                      })
                    }
                    placeholder="Host"
                    className="h-8 text-xs font-mono flex-1"
                  />
                  <Input
                    type="number"
                    value={settings.connections.hdb.port}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        connections: {
                          ...settings.connections,
                          hdb: { ...settings.connections.hdb, port: parseInt(e.target.value) }
                        }
                      })
                    }
                    placeholder="Port"
                    className="h-8 text-xs font-mono w-24"
                  />
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => testConnection('hdb')}
                    className="h-8 text-xs"
                  >
                    Test
                  </Button>
                </div>
              </div>

              <div className="pt-2">
                <Button onClick={reconnect} className="h-8 text-xs">
                  Reconnect All
                </Button>
              </div>
            </div>
          )}

          {activeSection === 'exchanges' && (
            <div className="space-y-4">
              <h2 className="text-sm font-semibold mb-4">Exchange Configuration</h2>
              <table className="w-full text-xs font-mono">
                <thead className="border-b border-border">
                  <tr className="text-muted-foreground text-[10px]">
                    <th className="text-left p-2 font-medium">NAME</th>
                    <th className="text-center p-2 font-medium">ENABLED</th>
                    <th className="text-left p-2 font-medium">API KEY</th>
                    <th className="text-right p-2 font-medium">RATE LIMIT</th>
                    <th className="text-center p-2 font-medium">STATUS</th>
                  </tr>
                </thead>
                <tbody>
                  {settings.exchanges.map((exchange, idx) => (
                    <tr key={idx} className="border-b border-border/50 hover:bg-card-hover">
                      <td className="p-2">{exchange.name}</td>
                      <td className="p-2 text-center">
                        <input
                          type="checkbox"
                          checked={exchange.enabled}
                          onChange={(e) => {
                            const newExchanges = [...settings.exchanges]
                            newExchanges[idx].enabled = e.target.checked
                            setSettings({ ...settings, exchanges: newExchanges })
                          }}
                          className="w-4 h-4"
                        />
                      </td>
                      <td className="p-2 text-muted-foreground">{exchange.apiKey || 'Not set'}</td>
                      <td className="p-2 text-right">{exchange.rateLimit}/min</td>
                      <td className="p-2 text-center">
                        <div
                          className={`inline-block w-2 h-2 rounded-full ${
                            exchange.status === 'connected' ? 'bg-buy-green' : 'bg-sell-red'
                          }`}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div className="pt-2">
                <Button variant="secondary" className="h-8 text-xs">
                  Add Exchange
                </Button>
              </div>
            </div>
          )}

          {activeSection === 'risk' && (
            <div className="space-y-4">
              <h2 className="text-sm font-semibold mb-4">Risk Limits</h2>

              <div className="space-y-3">
                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Max Position Size per Strategy
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.maxPositionSize}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          maxPositionSize: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">USD</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Max Daily Volume
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.maxDailyVolume}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          maxDailyVolume: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">USD</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Max Drawdown
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.maxDrawdownPct}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          maxDrawdownPct: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">%</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Max Exposure per Exchange
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.maxExposurePerExchange}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          maxExposurePerExchange: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">USD</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Emergency Stop Threshold
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.emergencyStopThreshold}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          emergencyStopThreshold: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">% Loss</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Circuit Breaker: Consecutive Losses
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.circuitBreakerConsecutiveLosses}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          circuitBreakerConsecutiveLosses: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Circuit Breaker: Pause Duration
                  </label>
                  <Input
                    type="number"
                    value={settings.riskLimits.circuitBreakerPauseDuration}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        riskLimits: {
                          ...settings.riskLimits,
                          circuitBreakerPauseDuration: parseInt(e.target.value)
                        }
                      })
                    }
                    className="h-8 text-xs font-mono w-32"
                  />
                  <span className="text-xs text-muted-foreground">seconds</span>
                </div>
              </div>
            </div>
          )}

          {activeSection === 'display' && (
            <div className="space-y-4">
              <h2 className="text-sm font-semibold mb-4">Display Preferences</h2>

              <div className="space-y-3">
                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">Theme</label>
                  <select
                    value={settings.display.theme}
                    className="h-8 text-xs font-mono bg-background border border-input rounded-md px-2"
                    disabled
                  >
                    <option value="dark">Dark</option>
                  </select>
                  <span className="text-xs text-muted-foreground">(Light theme coming soon)</span>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Default Chart Timeframe
                  </label>
                  <select
                    value={settings.display.chartTimeframe}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        display: { ...settings.display, chartTimeframe: e.target.value }
                      })
                    }
                    className="h-8 text-xs font-mono bg-background border border-input rounded-md px-2"
                  >
                    <option value="1m">1 Minute</option>
                    <option value="5m">5 Minutes</option>
                    <option value="15m">15 Minutes</option>
                    <option value="1h">1 Hour</option>
                    <option value="4h">4 Hours</option>
                    <option value="1D">1 Day</option>
                  </select>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Number Format
                  </label>
                  <select
                    value={settings.display.numberFormat}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        display: { ...settings.display, numberFormat: e.target.value }
                      })
                    }
                    className="h-8 text-xs font-mono bg-background border border-input rounded-md px-2"
                  >
                    <option value="en-US">US (1,234.56)</option>
                    <option value="de-DE">EU (1.234,56)</option>
                  </select>
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Show Extended Hours
                  </label>
                  <input
                    type="checkbox"
                    checked={settings.display.showExtendedHours}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        display: { ...settings.display, showExtendedHours: e.target.checked }
                      })
                    }
                    className="w-4 h-4"
                  />
                </div>

                <div className="flex items-center gap-4">
                  <label className="text-xs font-medium text-muted-foreground w-48">
                    Enable Sound Alerts
                  </label>
                  <input
                    type="checkbox"
                    checked={settings.display.enableSoundAlerts}
                    onChange={(e) =>
                      setSettings({
                        ...settings,
                        display: { ...settings.display, enableSoundAlerts: e.target.checked }
                      })
                    }
                    className="w-4 h-4"
                  />
                </div>
              </div>
            </div>
          )}

          {activeSection === 'paper' && (
            <div className="space-y-4">
              <h2 className="text-sm font-semibold mb-4">Paper Trading Mode</h2>

              <div className="bg-card-hover border border-border rounded-md p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-sm font-semibold">Current Mode</div>
                    <div className="text-xs text-muted-foreground mt-1">
                      {settings.paperMode
                        ? 'Paper trading mode is active (no real money)'
                        : 'Live trading mode is active (real money at risk)'}
                    </div>
                  </div>
                  <div
                    className={`px-3 py-1.5 rounded font-mono text-xs font-semibold ${
                      settings.paperMode
                        ? 'bg-info-blue/20 text-info-blue'
                        : 'bg-sell-red/20 text-sell-red'
                    }`}
                  >
                    {settings.paperMode ? 'PAPER' : 'LIVE'}
                  </div>
                </div>

                <div className="pt-2">
                  <Button
                    variant={settings.paperMode ? 'destructive' : 'secondary'}
                    onClick={() => {
                      const confirmed = confirm(
                        settings.paperMode
                          ? 'WARNING: Switching to LIVE mode will execute real trades with real money. Continue?'
                          : 'Switching to PAPER mode will simulate trades without real money. Continue?'
                      )
                      if (confirmed) {
                        setSettings({ ...settings, paperMode: !settings.paperMode })
                      }
                    }}
                    className="h-8 text-xs"
                  >
                    {settings.paperMode ? 'Switch to LIVE Mode' : 'Switch to PAPER Mode'}
                  </Button>
                </div>
              </div>

              {settings.paperMode && (
                <div className="text-xs text-muted-foreground bg-info-blue/10 border border-info-blue/30 rounded-md p-3">
                  <strong>Paper Trading Active:</strong> All orders are simulated. No real money is
                  at risk. Use this mode to test strategies before going live.
                </div>
              )}

              {!settings.paperMode && (
                <div className="text-xs text-sell-red bg-sell-red/10 border border-sell-red/30 rounded-md p-3">
                  <strong>WARNING:</strong> Live trading mode is active. Real money is at risk.
                  Make sure you have tested your strategies thoroughly in paper mode first.
                </div>
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  )
}
