import { BadgeDollarSign, Bitcoin, Building2 } from 'lucide-react'
import { ASSET_CLASS_CONFIG, TradingAssetClass } from '../../stores/assetClass'
import { Button } from '../ui/button'

interface AssetClassSwitcherProps {
  value: TradingAssetClass
  onChange: (assetClass: TradingAssetClass) => void
}

const ASSET_CLASS_OPTIONS: Array<{
  value: TradingAssetClass
  icon: typeof Bitcoin
}> = [
  { value: 'crypto', icon: Bitcoin },
  { value: 'equity', icon: Building2 },
  { value: 'option', icon: BadgeDollarSign }
]

export function AssetClassSwitcher({ value, onChange }: AssetClassSwitcherProps) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">Asset Class</span>
        <span className="text-[10px] uppercase tracking-normal text-muted-foreground">
          {ASSET_CLASS_CONFIG[value].accountLabel}
        </span>
      </div>
      <div className="grid grid-cols-3 gap-1" role="group" aria-label="Asset class">
        {ASSET_CLASS_OPTIONS.map(({ value: optionValue, icon: Icon }) => {
          const selected = optionValue === value
          const label = ASSET_CLASS_CONFIG[optionValue].label

          return (
            <Button
              key={optionValue}
              type="button"
              variant={selected ? 'default' : 'outline'}
              size="sm"
              aria-label={`${label} asset class`}
              aria-pressed={selected}
              onClick={() => onChange(optionValue)}
              className="h-8 gap-1.5 px-2 text-[11px]"
            >
              <Icon className="h-3.5 w-3.5" />
              {label}
            </Button>
          )
        })}
      </div>
    </div>
  )
}

