import { Toggle } from '../ui/toggle'
import { Button } from '../ui/button'

export type Timeframe = '1m' | '5m' | '15m' | '1h' | '4h' | '1D'

interface ChartToolbarProps {
  timeframe: Timeframe
  onTimeframeChange: (timeframe: Timeframe) => void
  showSMA: boolean
  onToggleSMA: () => void
  showBB: boolean
  onToggleBB: () => void
  showVolume: boolean
  onToggleVolume: () => void
  crosshairData: {
    open: number
    high: number
    low: number
    close: number
    volume: number
  } | null
}

export function ChartToolbar({
  timeframe,
  onTimeframeChange,
  showSMA,
  onToggleSMA,
  showBB,
  onToggleBB,
  showVolume,
  onToggleVolume,
  crosshairData
}: ChartToolbarProps) {
  const timeframes: Timeframe[] = ['1m', '5m', '15m', '1h', '4h', '1D']

  return (
    <div className="flex items-center justify-between px-3 py-2 border-b border-border bg-card/50">
      {/* Timeframe buttons */}
      <div className="flex items-center gap-1">
        {timeframes.map((tf) => (
          <Button
            key={tf}
            variant={timeframe === tf ? 'default' : 'ghost'}
            size="sm"
            onClick={() => onTimeframeChange(tf)}
            className={`h-6 px-2 text-xs font-mono ${
              timeframe === tf ? 'bg-primary text-primary-foreground' : ''
            }`}
          >
            {tf}
          </Button>
        ))}
      </div>

      {/* Indicator toggles */}
      <div className="flex items-center gap-2">
        <Toggle
          pressed={showSMA}
          onPressedChange={onToggleSMA}
          size="sm"
          className="h-6 px-2 text-xs data-[state=on]:bg-primary data-[state=on]:text-primary-foreground"
        >
          SMA
        </Toggle>
        <Toggle
          pressed={showBB}
          onPressedChange={onToggleBB}
          size="sm"
          className="h-6 px-2 text-xs data-[state=on]:bg-primary data-[state=on]:text-primary-foreground"
        >
          BB
        </Toggle>
        <Toggle
          pressed={showVolume}
          onPressedChange={onToggleVolume}
          size="sm"
          className="h-6 px-2 text-xs data-[state=on]:bg-primary data-[state=on]:text-primary-foreground"
        >
          VOL
        </Toggle>
      </div>

      {/* Crosshair info */}
      {crosshairData && (
        <div className="flex items-center gap-3 text-xs font-mono">
          <span className="text-muted-foreground">O:</span>
          <span>{crosshairData.open.toFixed(2)}</span>
          <span className="text-muted-foreground">H:</span>
          <span>{crosshairData.high.toFixed(2)}</span>
          <span className="text-muted-foreground">L:</span>
          <span>{crosshairData.low.toFixed(2)}</span>
          <span className="text-muted-foreground">C:</span>
          <span>{crosshairData.close.toFixed(2)}</span>
          <span className="text-muted-foreground">V:</span>
          <span>{crosshairData.volume.toFixed(2)}</span>
        </div>
      )}
    </div>
  )
}
