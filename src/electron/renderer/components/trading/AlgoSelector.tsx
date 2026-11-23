import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../ui/select'
import { Input } from '../ui/input'
import { Label } from '../ui/label'
import { Card, CardContent } from '../ui/card'

export type AlgoType = 'direct' | 'vwap' | 'twap' | 'iceberg'

export interface AlgoParams {
  type: AlgoType
  vwap?: {
    participationRate: number // 5-25%
    duration: number // minutes
  }
  twap?: {
    duration: number // minutes
    sliceInterval: number // seconds
  }
  iceberg?: {
    displayQty: number // % of total
    totalQty: number
  }
}

interface AlgoSelectorProps {
  value: AlgoParams
  onChange: (params: AlgoParams) => void
}

export function AlgoSelector({ value, onChange }: AlgoSelectorProps) {
  const handleTypeChange = (type: AlgoType) => {
    onChange({
      type,
      vwap: type === 'vwap' ? { participationRate: 10, duration: 30 } : undefined,
      twap: type === 'twap' ? { duration: 30, sliceInterval: 60 } : undefined,
      iceberg: type === 'iceberg' ? { displayQty: 10, totalQty: 0 } : undefined
    })
  }

  return (
    <Card className="border-muted/40">
      <CardContent className="pt-4 space-y-3">
        <div>
          <Label className="text-xs text-muted-foreground">Execution Mode</Label>
          <Select value={value.type} onValueChange={(v) => handleTypeChange(v as AlgoType)}>
            <SelectTrigger className="h-8 mt-1">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="direct">Direct (Market/Limit)</SelectItem>
              <SelectItem value="vwap">VWAP</SelectItem>
              <SelectItem value="twap">TWAP</SelectItem>
              <SelectItem value="iceberg">Iceberg</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {value.type === 'vwap' && value.vwap && (
          <>
            <div>
              <Label className="text-xs text-muted-foreground">
                Participation Rate ({value.vwap.participationRate}%)
              </Label>
              <input
                type="range"
                min="5"
                max="25"
                step="1"
                value={value.vwap.participationRate}
                onChange={(e) =>
                  onChange({
                    ...value,
                    vwap: { ...value.vwap!, participationRate: parseInt(e.target.value) }
                  })
                }
                className="w-full h-1.5 mt-2 bg-muted rounded-lg appearance-none cursor-pointer accent-primary"
                aria-label="VWAP participation rate slider"
              />
            </div>
            <div>
              <Label className="text-xs text-muted-foreground">Duration (minutes)</Label>
              <Input
                type="number"
                min="1"
                max="1440"
                value={value.vwap.duration}
                onChange={(e) =>
                  onChange({
                    ...value,
                    vwap: { ...value.vwap!, duration: parseInt(e.target.value) || 30 }
                  })
                }
                className="h-8 mt-1 font-mono"
              />
            </div>
          </>
        )}

        {value.type === 'twap' && value.twap && (
          <>
            <div>
              <Label className="text-xs text-muted-foreground">Duration (minutes)</Label>
              <Input
                type="number"
                min="1"
                max="1440"
                value={value.twap.duration}
                onChange={(e) =>
                  onChange({
                    ...value,
                    twap: { ...value.twap!, duration: parseInt(e.target.value) || 30 }
                  })
                }
                className="h-8 mt-1 font-mono"
              />
            </div>
            <div>
              <Label className="text-xs text-muted-foreground">Slice Interval (seconds)</Label>
              <Input
                type="number"
                min="10"
                max="600"
                step="10"
                value={value.twap.sliceInterval}
                onChange={(e) =>
                  onChange({
                    ...value,
                    twap: { ...value.twap!, sliceInterval: parseInt(e.target.value) || 60 }
                  })
                }
                className="h-8 mt-1 font-mono"
              />
            </div>
          </>
        )}

        {value.type === 'iceberg' && value.iceberg && (
          <>
            <div>
              <Label className="text-xs text-muted-foreground">Total Quantity</Label>
              <Input
                type="number"
                min="0"
                step="0.0001"
                value={value.iceberg.totalQty}
                onChange={(e) =>
                  onChange({
                    ...value,
                    iceberg: { ...value.iceberg!, totalQty: parseFloat(e.target.value) || 0 }
                  })
                }
                className="h-8 mt-1 font-mono"
              />
            </div>
            <div>
              <Label className="text-xs text-muted-foreground">
                Display Quantity ({value.iceberg.displayQty}%)
              </Label>
              <input
                type="range"
                min="1"
                max="50"
                step="1"
                value={value.iceberg.displayQty}
                onChange={(e) =>
                  onChange({
                    ...value,
                    iceberg: { ...value.iceberg!, displayQty: parseInt(e.target.value) }
                  })
                }
                className="w-full h-1.5 mt-2 bg-muted rounded-lg appearance-none cursor-pointer accent-primary"
                aria-label="Iceberg display quantity slider"
              />
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
