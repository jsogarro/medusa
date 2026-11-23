import { useCallback, useEffect } from 'react'
import { Mosaic, MosaicWindow, MosaicNode, MosaicBranch } from 'react-mosaic-component'
import 'react-mosaic-component/react-mosaic-component.css'
import { useWorkspaceStore } from '../../stores/workspace'
import { WidgetToolbar } from './WidgetToolbar'
import { WIDGET_REGISTRY } from '../../lib/widget-registry'
import './workspace.css'

export function WorkspaceManager() {
  // Granular selector - only subscribe to what we need
  const currentLayout = useWorkspaceStore((state) => state.currentLayout)
  const setMosaicTree = useWorkspaceStore((state) => state.setMosaicTree)
  const removeWidget = useWorkspaceStore((state) => state.removeWidget)
  const persistCurrentLayout = useWorkspaceStore((state) => state.persistCurrentLayout)

  useEffect(() => {
    persistCurrentLayout()
  }, [currentLayout, persistCurrentLayout])

  const handleChange = useCallback((newTree: MosaicNode<string> | null) => {
    setMosaicTree(newTree)
  }, [setMosaicTree])

  const handleClose = useCallback((widgetId: string) => {
    removeWidget(widgetId)
  }, [removeWidget])

  // Memoize renderTile to prevent recreation on every mosaic change
  const renderTile = useCallback((id: string, path: MosaicBranch[]) => {
    const widgetConfig = currentLayout.widgets[id]
    if (!widgetConfig) {
      return <div className="p-4 text-muted-foreground">Widget not found: {id}</div>
    }

    const { type, linkColor } = widgetConfig
    const widgetDef = WIDGET_REGISTRY[type]

    if (!widgetDef) {
      return <div className="p-4 text-muted-foreground">Unknown widget type: {type}</div>
    }

    const WidgetComponent = widgetDef.component

    return (
      <MosaicWindow
        path={path}
        createNode={() => 'new'}
        title=""
        renderToolbar={() => {
          return (
            <div
              className="flex items-center justify-between h-7 px-2 bg-card border-b border-border"
            >
              <span className="text-xs font-medium text-muted-foreground">
                {widgetDef.metadata.title}
              </span>
              <div className="flex items-center gap-2">
                <WidgetToolbar
                  widgetId={id}
                  widgetType={type}
                  linkColor={linkColor}
                  onClose={() => handleClose(id)}
                />
              </div>
            </div>
          )
        }}
      >
        <div className="h-full bg-background overflow-hidden">
          <WidgetComponent linkColor={linkColor} />
        </div>
      </MosaicWindow>
    )
  }, [currentLayout.widgets, handleClose])

  return (
    <div className="h-full bg-background">
      <Mosaic<string>
        renderTile={renderTile}
        value={currentLayout.mosaicTree}
        onChange={handleChange}
        className="medusa-mosaic"
      />
    </div>
  )
}
