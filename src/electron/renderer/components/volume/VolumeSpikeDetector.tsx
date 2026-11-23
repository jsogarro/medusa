import { Card } from '../ui/card'
import { mockVolumeSpikes } from '../../lib/mock-data'
import { formatTimestamp, formatPrice } from '../../lib/utils'

export function VolumeSpikeDetector() {
  return (
    <Card className="p-3 flex flex-col h-full">
      <h3 className="text-xs font-semibold text-muted-foreground mb-2">VOLUME SPIKE DETECTOR (24H)</h3>
      <div className="flex-1 overflow-y-auto">
        <table className="w-full text-xs font-mono">
          <thead className="sticky top-0 bg-card border-b border-border">
            <tr className="text-muted-foreground text-[10px]">
              <th className="text-left p-1.5 font-medium">TIME</th>
              <th className="text-left p-1.5 font-medium">SYMBOL</th>
              <th className="text-right p-1.5 font-medium">VOLUME</th>
              <th className="text-right p-1.5 font-medium">AVG VOL</th>
              <th className="text-right p-1.5 font-medium">SPIKE</th>
              <th className="text-right p-1.5 font-medium">PRICE</th>
              <th className="text-center p-1.5 font-medium">DIR</th>
            </tr>
          </thead>
          <tbody>
            {mockVolumeSpikes.map((spike, idx) => {
              const isHighSpike = spike.spikeRatio >= 5
              const isMediumSpike = spike.spikeRatio >= 3 && spike.spikeRatio < 5

              return (
                <tr
                  key={idx}
                  className={`border-b border-border/50 data-row hover:bg-card-hover ${
                    isHighSpike ? 'bg-sell-red/10' : isMediumSpike ? 'bg-pending-yellow/10' : ''
                  }`}
                >
                  <td className="p-1.5">{formatTimestamp(spike.time)}</td>
                  <td className="p-1.5">{spike.symbol}</td>
                  <td className="p-1.5 text-right">{spike.volume.toLocaleString()}</td>
                  <td className="p-1.5 text-right">{spike.avgVolume.toLocaleString()}</td>
                  <td className={`p-1.5 text-right font-semibold ${
                    isHighSpike ? 'text-sell-red' : isMediumSpike ? 'text-pending-yellow' : 'text-chart-orange'
                  }`}>
                    {spike.spikeRatio.toFixed(2)}x
                  </td>
                  <td className="p-1.5 text-right">{formatPrice(spike.price, 2)}</td>
                  <td className={`p-1.5 text-center ${
                    spike.direction === 'buy' ? 'text-buy-green' : 'text-sell-red'
                  }`}>
                    {spike.direction === 'buy' ? '↑' : '↓'}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <div className="mt-2 flex items-center gap-4 text-[10px] text-muted-foreground font-mono">
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-sell-red/30 border border-sell-red" />
          <span>&gt;5x spike</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-2 h-2 bg-pending-yellow/30 border border-pending-yellow" />
          <span>3-5x spike</span>
        </div>
      </div>
    </Card>
  )
}
