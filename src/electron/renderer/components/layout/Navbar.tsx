import { AlertTriangle } from 'lucide-react'
import { Button } from '../ui/button'
import { runEmergencyStop } from '../../lib/kdb-actions'
import { useExchangesStore } from '../../stores/exchanges'

export function Navbar() {
  const exchanges = useExchangesStore((state) => state.exchanges)

  const handleEmergencyStop = () => {
    if (confirm('EMERGENCY STOP: This will cancel all orders and close all positions. Continue?')) {
      void runEmergencyStop(window.kdb).then((r) => alert(r.message))
    }
  }

  return (
    <div className="h-14 border-b border-border bg-card px-4 flex items-center justify-between">
      <div className="flex items-center gap-4">
        <h1 className="text-xl font-bold">Medusa Trading</h1>
        <div className="flex items-center gap-2">
          {exchanges.map((ex) => (
            <div
              key={ex.exchange}
              className="flex items-center gap-1.5"
              title={`${ex.exchange}: ${ex.connected ? 'Connected' : 'Disconnected'} (${ex.latency}ms)`}
            >
              <div
                className={`w-2 h-2 rounded-full ${
                  ex.connected ? 'bg-buy-green' : 'bg-sell-red'
                }`}
              />
              <span className="text-xs text-muted-foreground uppercase">
                {ex.exchange}
              </span>
            </div>
          ))}
        </div>
      </div>
      <Button
        variant="destructive"
        size="sm"
        onClick={handleEmergencyStop}
        className="gap-2"
      >
        <AlertTriangle className="w-4 h-4" />
        EMERGENCY STOP
      </Button>
    </div>
  )
}
