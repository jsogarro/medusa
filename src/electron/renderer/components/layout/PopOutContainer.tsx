import { useEffect, useState, memo } from 'react'
import { WIDGET_REGISTRY } from '../../lib/widget-registry'
import { WidgetType } from '../../lib/workspace-types'
import { LinkColor } from '../../stores/symbolLink'

interface PopOutContainerProps {
  widgetType: WidgetType
  linkColor: LinkColor
}

export const PopOutContainer = memo(function PopOutContainer({ widgetType, linkColor }: PopOutContainerProps) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  const widgetDef = WIDGET_REGISTRY[widgetType]

  if (!widgetDef) {
    return (
      <div className="h-screen flex items-center justify-center bg-background text-muted-foreground">
        Unknown widget type: {widgetType}
      </div>
    )
  }

  const WidgetComponent = widgetDef.component

  if (!mounted) {
    return null
  }

  return (
    <div className="h-screen bg-background p-2">
      <div className="h-full border border-border rounded overflow-hidden">
        <WidgetComponent linkColor={linkColor} />
      </div>
    </div>
  )
})
