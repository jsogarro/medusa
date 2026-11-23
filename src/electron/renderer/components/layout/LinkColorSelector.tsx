import { memo, useMemo } from 'react'
import { LinkColor } from '../../stores/symbolLink'

interface LinkColorSelectorProps {
  color: LinkColor
  onChange: (color: LinkColor) => void
}

const LINK_COLORS: { value: LinkColor; label: string; className: string }[] = [
  { value: 'none', label: 'Unlinked', className: 'bg-muted' },
  { value: 'red', label: 'Red', className: 'bg-red-500' },
  { value: 'blue', label: 'Blue', className: 'bg-blue-500' },
  { value: 'green', label: 'Green', className: 'bg-green-500' },
  { value: 'yellow', label: 'Yellow', className: 'bg-yellow-500' }
]

export const LinkColorSelector = memo(function LinkColorSelector({ color, onChange }: LinkColorSelectorProps) {
  const currentColor = useMemo(() => LINK_COLORS.find((c) => c.value === color) || LINK_COLORS[0], [color])

  return (
    <div className="relative group">
      {/* Current color indicator */}
      <button
        className="h-5 w-5 rounded-full flex items-center justify-center border border-border hover:border-foreground transition-colors"
        title={`Link group: ${currentColor.label}`}
      >
        <div className={`h-2.5 w-2.5 rounded-full ${currentColor.className}`} />
      </button>

      {/* Dropdown menu on hover */}
      <div className="absolute top-full left-0 mt-1 hidden group-hover:block z-50">
        <div className="bg-card border border-border rounded shadow-lg p-1 flex flex-col gap-0.5">
          {LINK_COLORS.map((linkColor) => (
            <button
              key={linkColor.value}
              onClick={() => onChange(linkColor.value)}
              className="flex items-center gap-2 px-2 py-1 rounded hover:bg-muted transition-colors text-xs"
            >
              <div className={`h-2.5 w-2.5 rounded-full ${linkColor.className}`} />
              <span className="text-foreground whitespace-nowrap">{linkColor.label}</span>
              {color === linkColor.value && (
                <span className="text-primary text-xs">✓</span>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
})
