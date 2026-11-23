import { memo, useCallback } from 'react'
import { X, Maximize2 } from 'lucide-react'
import { LinkColor, loadWindowBounds } from '../../stores/symbolLink'
import { useWorkspaceStore } from '../../stores/workspace'
import { WIDGET_REGISTRY } from '../../lib/widget-registry'
import { WidgetType } from '../../lib/workspace-types'
import { LinkColorSelector } from './LinkColorSelector'

interface WidgetToolbarProps {
  widgetId: string
  widgetType: WidgetType
  linkColor: LinkColor
  onClose: () => void
}

export const WidgetToolbar = memo(function WidgetToolbar({ widgetId, widgetType, linkColor, onClose }: WidgetToolbarProps) {
  const updateWidget = useWorkspaceStore((state) => state.updateWidget)
  const widgetDef = WIDGET_REGISTRY[widgetType]

  const handlePopOut = useCallback(() => {
    if (window.popOutWidget) {
      const savedBounds = loadWindowBounds(widgetId)
      window.popOutWidget(widgetId, {
        title: widgetDef.metadata.title,
        linkGroup: linkColor,
        widgetType,
        bounds: savedBounds
      })
    } else {
      console.warn('[WidgetToolbar] Pop-out API not available')
    }
  }, [widgetId, widgetDef.metadata.title, linkColor, widgetType])

  const handleLinkColorChange = useCallback((newColor: LinkColor) => {
    updateWidget(widgetId, { linkColor: newColor })
  }, [updateWidget, widgetId])

  return (
    <div className="flex items-center gap-2">
      {/* Link color selector (only for widgets that support linking) */}
      {widgetDef.metadata.supportsLinking && (
        <LinkColorSelector color={linkColor} onChange={handleLinkColorChange} />
      )}

      {/* Pop-out button */}
      <button
        onClick={handlePopOut}
        className="h-5 w-5 flex items-center justify-center rounded hover:bg-muted/50 transition-colors"
        title="Pop out to new window"
      >
        <Maximize2 className="w-3 h-3 text-muted-foreground hover:text-foreground" />
      </button>

      {/* Close button */}
      <button
        onClick={onClose}
        className="h-5 w-5 flex items-center justify-center rounded hover:bg-destructive/20 transition-colors"
        title="Close widget"
      >
        <X className="w-3 h-3 text-muted-foreground hover:text-destructive" />
      </button>
    </div>
  )
})
