import { ipcMain, BrowserWindow } from 'electron'
import { KdbClient } from './kdb-client'
import { IpcRateLimiter } from './ipc-rate-limiter'

let tpClient: KdbClient | null = null
let rdbClient: KdbClient | null = null
let removeTpUpdateForwarder: (() => void) | null = null

// Initialize rate limiter (100 tokens capacity, 10 tokens/sec refill)
const rateLimiter = new IpcRateLimiter(100, 10)

// Input sanitization: only allow alphanumeric + underscore for symbols
const SAFE_SYMBOL = /^[A-Za-z0-9_]+$/
const SAFE_TABLE = /^[a-z][a-zA-Z0-9_.]*$/
const MAX_STRING_LENGTH = 256  // Limit to prevent payload bloat
const MAX_PAYLOAD_SIZE = 10 * 1024  // 10KB max payload (JSON stringified)

function validateSymbol(value: string, fieldName: string): string {
  if (typeof value !== 'string' || !SAFE_SYMBOL.test(value)) {
    throw new Error(`Invalid ${fieldName}: "${value}" — only alphanumeric and underscore allowed`)
  }
  if (value.length > MAX_STRING_LENGTH) {
    throw new Error(`Invalid ${fieldName}: exceeds max length of ${MAX_STRING_LENGTH}`)
  }
  return value
}

function validatePayloadSize(obj: unknown): void {
  const serialized = JSON.stringify(obj)
  if (serialized.length > MAX_PAYLOAD_SIZE) {
    throw new Error(`Payload too large: ${serialized.length} bytes exceeds max ${MAX_PAYLOAD_SIZE} bytes`)
  }
}

function validateNumber(value: unknown, fieldName: string): number {
  const num = Number(value)
  if (!Number.isFinite(num) || num < 0) {
    throw new Error(`Invalid ${fieldName}: must be a non-negative finite number, got ${value}`)
  }
  return num
}

interface PlaceOrderRequest {
  exchange: string
  pair: string
  side: 'buy' | 'sell'
  orderType: 'market' | 'limit' | 'stop'
  price: number
  quantity: number
  strategy: string
}

function validateOrder(obj: unknown): PlaceOrderRequest {
  if (typeof obj !== 'object' || obj === null) {
    throw new Error('Invalid order: expected an object')
  }
  const o = obj as Record<string, unknown>
  const exchange = validateSymbol(String(o.exchange ?? ''), 'exchange')
  const pair = validateSymbol(String(o.pair ?? ''), 'pair')
  const strategy = validateSymbol(String(o.strategy ?? ''), 'strategy')
  const side = String(o.side ?? '')
  if (side !== 'buy' && side !== 'sell') {
    throw new Error(`Invalid side: "${side}" — must be "buy" or "sell"`)
  }
  const orderType = String(o.orderType ?? '')
  if (!['market', 'limit', 'stop'].includes(orderType)) {
    throw new Error(`Invalid orderType: "${orderType}" — must be market, limit, or stop`)
  }
  const price = validateNumber(o.price, 'price')
  const quantity = validateNumber(o.quantity, 'quantity')
  if (quantity <= 0) {
    throw new Error('Invalid quantity: must be greater than 0')
  }
  return { exchange, pair, side: side as 'buy' | 'sell', orderType: orderType as 'market' | 'limit' | 'stop', price, quantity, strategy }
}

export function setupIpcHandlers(mainWindow: BrowserWindow): void {
  // Connect to kdb+ (TP and RDB)
  ipcMain.handle('kdb:connect', async (_event, config: { tp: { host: string; port: number }; rdb: { host: string; port: number } }) => {
    try {
      await disconnectClients()

      tpClient = new KdbClient(config.tp)
      await tpClient.connect()
      attachTpUpdateForwarding(mainWindow, tpClient)

      rdbClient = new KdbClient(config.rdb)
      await rdbClient.connect()

      return { success: true }
    } catch (error: any) {
      await disconnectClients()
      return { success: false, error: error.message }
    }
  })

  // Subscribe to table updates (validated table name)
  ipcMain.handle('kdb:subscribe', async (_event, table: string) => {
    try {
      if (!tpClient) {
        throw new Error('Not connected to TP')
      }
      if (typeof table !== 'string' || !SAFE_TABLE.test(table)) {
        throw new Error(`Invalid table name: "${table}"`)
      }
      await tpClient.subscribe(table)
      return { success: true }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  // Named query operations — NO raw q expression passthrough
  // Each operation is a pre-defined function with validated parameters
  ipcMain.handle('kdb:cancelOrder', async (_event, orderId: string) => {
    try {
      // Rate limit check
      if (!rateLimiter.checkLimit('kdb:cancelOrder')) {
        throw new Error('Rate limit exceeded — too many requests. Please slow down.')
      }

      if (!rdbClient) throw new Error('Not connected to RDB')
      validateSymbol(orderId, 'orderId')
      const result = await rdbClient.query(`.engine.order.cancel`, [orderId])
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:getOrders', async (_event) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      const result = await rdbClient.query(`select from orders`)
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:getPositions', async (_event) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      const result = await rdbClient.query(`select from positions`)
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:getRiskMetrics', async (_event) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      const result = await rdbClient.query(`.risk.getStatus[]`)
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:emergencyStop', async (_event) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      const result = await rdbClient.query(`.risk.activateEmergencyStop[\`manual;\`ui]`)
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:strategyControl', async (_event, name: string, action: string) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      validateSymbol(name, 'strategy name')
      if (!['pause', 'resume', 'stop'].includes(action)) {
        throw new Error(`Invalid action: "${action}" — must be pause, resume, or stop`)
      }
      const funcMap: Record<string, string> = {
        pause: '.engine.strategy.pause',
        resume: '.engine.strategy.resume',
        stop: '.engine.strategy.stop',
      }
      const result = await rdbClient.query(funcMap[action], [name])
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  ipcMain.handle('kdb:getCandles', async (_event, exchange: string, pair: string, timeframe: string) => {
    try {
      if (!rdbClient) throw new Error('Not connected to RDB')
      validateSymbol(exchange, 'exchange')
      validateSymbol(pair, 'pair')
      validateSymbol(timeframe, 'timeframe')
      // Use parameterized query — no string interpolation of user input
      const result = await rdbClient.query(`.medusa.getCandles`, [exchange, pair, timeframe])
      return { success: true, data: result }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  // Place order (validates via risk module first)
  ipcMain.handle('kdb:placeOrder', async (_event, orderData: unknown) => {
    try {
      // Rate limit check (FIRST — before any processing)
      if (!rateLimiter.checkLimit('kdb:placeOrder')) {
        throw new Error('Rate limit exceeded — too many requests. Please slow down.')
      }

      if (!rdbClient) {
        throw new Error('Not connected to RDB')
      }

      // Validate payload size first (prevent DoS via large payloads)
      validatePayloadSize(orderData)

      // Validate all order fields before touching kdb+
      const order = validateOrder(orderData)

      // Use parameterized function call — no string interpolation
      const riskCheck = await rdbClient.query(`.risk.validateOrder`, [
        order.strategy, order.pair, order.exchange, order.side, order.quantity, order.price
      ])

      if (!riskCheck) {
        throw new Error('Order rejected by risk module')
      }

      // Call the actual exchange coordinator function
      const orderId = await rdbClient.query(`.exchange.placeOrder`, [
        order.exchange, order.pair, order.orderType, order.side, order.price, order.quantity
      ])

      return { success: true, data: { orderId } }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })

  // Setup kdb+ update forwarding
  setupKdbUpdates(mainWindow)

  // Health check endpoint
  ipcMain.handle('system:health', async (_event) => {
    try {
      return {
        success: true,
        data: {
          timestamp: new Date().toISOString(),
          kdb: {
            tp: tpClient?.isConnected() ?? false,
            rdb: rdbClient?.isConnected() ?? false,
          },
          electron: {
            version: process.versions.electron,
            node: process.versions.node,
            uptime: process.uptime(),
            memory: process.memoryUsage(),
          },
          ui: {
            screens: 25,
            workspaceActive: true,
          }
        }
      }
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })
}

function setupKdbUpdates(mainWindow: BrowserWindow): void {
  if (tpClient) {
    attachTpUpdateForwarding(mainWindow, tpClient)
  }
}

function attachTpUpdateForwarding(mainWindow: BrowserWindow, client: KdbClient): void {
  removeTpUpdateForwarder?.()

  const listener = (table: string, data: any) => {
    if (!mainWindow.isDestroyed()) {
      mainWindow.webContents.send('kdb:update', { table, data })
    }
  }

  client.on('update', listener)
  removeTpUpdateForwarder = () => {
    client.removeListener('update', listener)
  }
}

async function disconnectClients(): Promise<void> {
  removeTpUpdateForwarder?.()
  removeTpUpdateForwarder = null

  const currentTpClient = tpClient
  const currentRdbClient = rdbClient
  tpClient = null
  rdbClient = null

  await Promise.allSettled([
    currentTpClient?.disconnect(),
    currentRdbClient?.disconnect()
  ])
}
