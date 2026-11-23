import { app, BrowserWindow, ipcMain } from 'electron'
import { join } from 'path'
import { setupIpcHandlers } from './ipc-handlers'

let mainWindow: BrowserWindow | null = null

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1920,
    height: 1080,
    backgroundColor: '#0a0a0a',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  })

  // Setup IPC handlers
  setupIpcHandlers(mainWindow)

  // Load URL based on environment
  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173')
    mainWindow.webContents.openDevTools()
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

// Pop-out window handler
ipcMain.handle('window:popout', (_event, widgetId: string, config: any) => {
  // Restore window bounds from config or use defaults
  const bounds = config.bounds || { x: undefined, y: undefined, width: 800, height: 600 }

  const popout = new BrowserWindow({
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height,
    title: config.title || 'Widget',
    backgroundColor: '#0a0a0a',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  })

  // Save window bounds on move/resize
  const saveWindowBounds = () => {
    if (!popout.isDestroyed()) {
      const bounds = popout.getBounds()
      popout.webContents.send('window:boundsChanged', widgetId, bounds)
    }
  }

  popout.on('move', saveWindowBounds)
  popout.on('resize', saveWindowBounds)

  // Cleanup on window close
  popout.on('closed', () => {
    popout.removeListener('move', saveWindowBounds)
    popout.removeListener('resize', saveWindowBounds)
  })

  // Load same renderer URL with widget query param
  const params = new URLSearchParams({
    widget: widgetId,
    widgetType: config.widgetType || 'chart',
    linked: config.linkGroup || 'none'
  })

  if (process.env.NODE_ENV === 'development') {
    popout.loadURL(`http://localhost:5173?${params.toString()}`)
    popout.webContents.openDevTools()
  } else {
    popout.loadFile(join(__dirname, '../renderer/index.html'), {
      query: Object.fromEntries(params.entries())
    })
  }

  return Promise.resolve()
})

// Symbol link cross-window IPC
ipcMain.on('symbolLink:changed', (_event, color: string, symbol: string, exchange: string) => {
  // Broadcast to ALL BrowserWindows
  BrowserWindow.getAllWindows().forEach((win) => {
    win.webContents.send('symbolLink:update', color, symbol, exchange)
  })
})

// App lifecycle
app.whenReady().then(() => {
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})
