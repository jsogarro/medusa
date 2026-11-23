import { VolumeProfile } from '../components/volume/VolumeProfile'
import { VwapChart } from '../components/volume/VwapChart'
import { VolumeSpikeDetector } from '../components/volume/VolumeSpikeDetector'
import { CumulativeVolumeDelta } from '../components/volume/CumulativeVolumeDelta'
import { OrderFlowImbalance } from '../components/volume/OrderFlowImbalance'

export function VolumeAnalysis() {
  return (
    <div className="h-full grid grid-cols-2 grid-rows-[40%_30%_30%] gap-2 p-2" role="main" aria-label="Volume Analysis Dashboard">
      {/* Top row: Volume Profile and VWAP Chart (40%) */}
      <div className="col-span-1">
        <VolumeProfile />
      </div>
      <div className="col-span-1">
        <VwapChart />
      </div>

      {/* Middle row: Volume Spike Detector (30%, full width) */}
      <div className="col-span-2">
        <VolumeSpikeDetector />
      </div>

      {/* Bottom row: CVD Chart and Order Flow Imbalance (30%) */}
      <div className="col-span-1">
        <CumulativeVolumeDelta />
      </div>
      <div className="col-span-1">
        <OrderFlowImbalance />
      </div>
    </div>
  )
}
