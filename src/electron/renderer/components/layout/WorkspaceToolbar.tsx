import { useState } from 'react'
import { Plus, Save, FolderOpen, Download, Upload } from 'lucide-react'
import { Button } from '../ui/button'
import { useWorkspaceStore } from '../../stores/workspace'
import { PRESET_LAYOUTS } from '../../lib/preset-layouts'
import { WIDGET_REGISTRY } from '../../lib/widget-registry'
import { WidgetType } from '../../lib/workspace-types'

export function WorkspaceToolbar() {
  const [showLayoutMenu, setShowLayoutMenu] = useState(false)
  const [showAddWidget, setShowAddWidget] = useState(false)
  const [showSaveDialog, setShowSaveDialog] = useState(false)
  const [layoutName, setLayoutName] = useState('')

  const { currentLayout, loadLayout, saveLayout, savedLayouts, exportLayout, importLayout } =
    useWorkspaceStore()

  const handleLoadPreset = (name: string) => {
    loadLayout(name)
    setShowLayoutMenu(false)
  }

  const handleSaveLayout = () => {
    if (layoutName.trim()) {
      saveLayout(layoutName.trim())
      setLayoutName('')
      setShowSaveDialog(false)
    }
  }

  const handleExport = () => {
    const json = exportLayout()
    const blob = new Blob([json], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `medusa-layout-${currentLayout.name || 'custom'}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleImport = () => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = '.json'
    input.onchange = (e) => {
      const file = (e.target as HTMLInputElement).files?.[0]
      if (file) {
        file.text().then((json) => {
          try {
            importLayout(json)
          } catch (err) {
            alert('Failed to import layout: invalid JSON')
          }
        })
      }
    }
    input.click()
  }

  const handleAddWidget = (widgetType: WidgetType) => {
    const widgetId = `${widgetType}-${Date.now()}`
    const newConfig = {
      id: widgetId,
      type: widgetType,
      linkColor: 'none' as const
    }

    useWorkspaceStore.getState().addWidget(widgetId, newConfig)

    // Update mosaic tree to add widget (simplified: add as new tile)
    const { currentLayout, setMosaicTree } = useWorkspaceStore.getState()
    if (!currentLayout.mosaicTree) {
      setMosaicTree(widgetId)
    } else {
      // Split the first tile horizontally to add new widget
      setMosaicTree({
        direction: 'column',
        first: currentLayout.mosaicTree,
        second: widgetId,
        splitPercentage: 70
      })
    }

    setShowAddWidget(false)
  }

  return (
    <div className="h-10 bg-card border-b border-border px-4 flex items-center justify-between">
      <div className="flex items-center gap-2">
        <span className="text-xs font-medium text-muted-foreground">
          Workspace: {currentLayout.name || 'Custom'}
        </span>
      </div>

      <div className="flex items-center gap-2">
        {/* Add Widget */}
        <div className="relative">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowAddWidget(!showAddWidget)}
            className="h-7 gap-1.5 text-xs"
          >
            <Plus className="w-3 h-3" />
            Add Widget
          </Button>

          {showAddWidget && (
            <div className="absolute top-full right-0 mt-1 w-48 bg-card border border-border rounded shadow-lg p-1 z-50 max-h-96 overflow-y-auto">
              {Object.entries(WIDGET_REGISTRY).map(([type, { metadata }]) => (
                <button
                  key={type}
                  onClick={() => handleAddWidget(type as WidgetType)}
                  className="w-full text-left px-3 py-2 rounded hover:bg-muted transition-colors text-xs flex items-center gap-2"
                >
                  <span className="text-foreground">{metadata.title}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Load Layout */}
        <div className="relative">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowLayoutMenu(!showLayoutMenu)}
            className="h-7 gap-1.5 text-xs"
          >
            <FolderOpen className="w-3 h-3" />
            Load
          </Button>

          {showLayoutMenu && (
            <div className="absolute top-full right-0 mt-1 w-48 bg-card border border-border rounded shadow-lg p-1 z-50">
              <div className="px-2 py-1 text-[10px] font-semibold text-muted-foreground uppercase">
                Presets
              </div>
              {Object.keys(PRESET_LAYOUTS).map((name) => (
                <button
                  key={name}
                  onClick={() => handleLoadPreset(name)}
                  className="w-full text-left px-3 py-2 rounded hover:bg-muted transition-colors text-xs"
                >
                  <span className="text-foreground capitalize">{name}</span>
                </button>
              ))}

              {Object.keys(savedLayouts).length > 0 && (
                <>
                  <div className="my-1 border-t border-border" />
                  <div className="px-2 py-1 text-[10px] font-semibold text-muted-foreground uppercase">
                    Saved
                  </div>
                  {Object.keys(savedLayouts).map((name) => (
                    <button
                      key={name}
                      onClick={() => handleLoadPreset(name)}
                      className="w-full text-left px-3 py-2 rounded hover:bg-muted transition-colors text-xs"
                    >
                      <span className="text-foreground">{name}</span>
                    </button>
                  ))}
                </>
              )}
            </div>
          )}
        </div>

        {/* Save Layout */}
        <div className="relative">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowSaveDialog(!showSaveDialog)}
            className="h-7 gap-1.5 text-xs"
          >
            <Save className="w-3 h-3" />
            Save
          </Button>

          {showSaveDialog && (
            <div className="absolute top-full right-0 mt-1 w-64 bg-card border border-border rounded shadow-lg p-3 z-50">
              <label className="block text-xs font-medium text-foreground mb-2">
                Layout Name
              </label>
              <input
                type="text"
                value={layoutName}
                onChange={(e) => setLayoutName(e.target.value)}
                placeholder="My Custom Layout"
                className="w-full px-2 py-1.5 text-xs bg-background border border-border rounded focus:outline-none focus:ring-1 focus:ring-primary"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') handleSaveLayout()
                  if (e.key === 'Escape') setShowSaveDialog(false)
                }}
              />
              <div className="flex gap-2 mt-2">
                <Button size="sm" onClick={handleSaveLayout} className="flex-1 h-7 text-xs">
                  Save
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowSaveDialog(false)}
                  className="flex-1 h-7 text-xs"
                >
                  Cancel
                </Button>
              </div>
            </div>
          )}
        </div>

        {/* Export/Import */}
        <Button
          variant="ghost"
          size="sm"
          onClick={handleExport}
          className="h-7 w-7 p-0"
          title="Export layout"
        >
          <Download className="w-3 h-3" />
        </Button>

        <Button
          variant="ghost"
          size="sm"
          onClick={handleImport}
          className="h-7 w-7 p-0"
          title="Import layout"
        >
          <Upload className="w-3 h-3" />
        </Button>
      </div>
    </div>
  )
}
