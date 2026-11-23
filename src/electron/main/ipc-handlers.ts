import { ipcMain, BrowserWindow, IpcMainInvokeEvent } from 'electron'
import { KdbClient, SAFE_TABLE } from './kdb-client'
import { IpcRateLimiter } from './ipc-rate-limiter'
import { isTrustedSender } from './security'
import { fixedLong, sym } from './q-types'
import {
  KdbEndpoint,
  parseRiskVerdict,
  validateKdbConfig,
  validateOrder,
  validateSymbol
} from './validation'

type KdbConfig = { tp: KdbEndpoint; rdb: KdbEndpoint }

let tpClient: KdbClient | null = null
let rdbClient: KdbClient | null = null
let currentConfig: KdbConfig | null = null
let removeTpUpdateForwarder: (() => void) | null = null

// Default budget, plus tighter per-channel budgets for state-changing calls.
// One limiter for the process lifetime: re-registering handlers must not refill budgets.
const rateLimiter = new IpcRateLimiter(100, 10, {
  'kdb:placeOrder': { capacity: 10, refillRate: 2 },
  'kdb:cancelOrder': { capacity: 20, refillRate: 5 },
  'kdb:strategyControl': { capacity: 20, refillRate: 5 },
  'kdb:connect': { capacity: 5, refillRate: 0.5 },
  'kdb:subscribe': { capacity: 50, refillRate: 5 },
  'window:popout': { capacity: 5, refillRate: 0.2 }
})

/** Consume one token for `channel`, throwing when its budget is spent. */
export function checkIpcLimit(channel: string): void {
  if (!rateLimiter.checkLimit(channel)) {
    throw new Error('Rate limit exceeded — too many requests. Please slow down.')
  }
}

const MAX_PAYLOAD_SIZE = 10 * 1024  // 10KB max payload (JSON stringified)

function validatePayloadSize(obj: unknown): void {
  const serialized = JSON.stringify(obj)
  if (serialized.length > MAX_PAYLOAD_SIZE) {
    throw new Error(`Payload too large: ${serialized.length} bytes exceeds max ${MAX_PAYLOAD_SIZE} bytes`)
  }
}

function sameEndpoint(a: KdbEndpoint, b: KdbEndpoint): boolean {
  return a.host === b.host && a.port === b.port
}

/**
 * Register an IPC handler that only serves the app's own renderer, converts thrown
 * errors into { success: false }, and can be registered again (macOS re-activate).
 */
function handle(channel: string, fn: (event: IpcMainInvokeEvent, ...args: any[]) => unknown): void {
  ipcMain.removeHandler(channel)
  ipcMain.handle(channel, async (event, ...args) => {
    try {
      if (!isTrustedSender(event as never)) {
        throw new Error('Untrusted sender')
      }
      return await fn(event, ...args)
    } catch (error: any) {
      return { success: false, error: error.message }
    }
  })
}

let connectQueue: Promise<unknown> = Promise.resolve()

async function connectClients(config: KdbConfig): Promise<{ success: true }> {
  if (
    currentConfig &&
    tpClient?.isConnected() &&
    rdbClient?.isConnected() &&
    sameEndpoint(currentConfig.tp, config.tp) &&
    sameEndpoint(currentConfig.rdb, config.rdb)
  ) {
    return { success: true }
  }
  checkIpcLimit('kdb:connect')

  try {
    await disconnectClients()

    const tp = new KdbClient(config.tp)
    tpClient = tp
    await tp.connect()
    attachTpUpdateForwarding(tp)

    const rdb = new KdbClient(config.rdb)
    rdbClient = rdb
    await rdb.connect()

    currentConfig = config
    return { success: true }
  } catch (error) {
    await disconnectClients()
    throw error
  }
}

export function setupIpcHandlers(): void {
  const limit = checkIpcLimit

  // Connect to kdb+ (TP and RDB). Idempotent for an unchanged config so a second
  // window cannot tear down the link the first one is using.
  handle('kdb:connect', (_event, rawConfig: unknown) => {
    const config = validateKdbConfig(rawConfig)
    // Run connects one at a time: a concurrent call otherwise tears down and replaces a client
    // that is still mid-connect, leaving it orphaned and reconnecting forever. Queued calls with
    // an unchanged config then hit the idempotent branch and share the first connection.
    const run = connectQueue.then(() => connectClients(config))
    connectQueue = run.catch(() => undefined)
    return run
  })

  // Subscribe to table updates (validated table name)
  handle('kdb:subscribe', async (_event, table: string) => {
    if (!tpClient) {
      throw new Error('Not connected to TP')
    }
    if (typeof table !== 'string' || !SAFE_TABLE.test(table)) {
      throw new Error(`Invalid table name: "${table}"`)
    }
    limit('kdb:subscribe')
    await tpClient.subscribe(table)
    return { success: true }
  })

  // Named query operations — NO raw q expression passthrough
  handle('kdb:cancelOrder', async (_event, orderId: string, exchange: string) => {
    if (!rdbClient) throw new Error('Not connected to RDB')
    validateSymbol(orderId, 'orderId')
    validateSymbol(exchange, 'exchange')
    limit('kdb:cancelOrder')
    const result = await rdbClient.query('.exchange.coordinator.cancelOrder', [sym(exchange), sym(orderId)])
    return { success: true, data: result }
  })

  handle('kdb:getOrders', async () => {
    if (!rdbClient) throw new Error('Not connected to RDB')
    return { success: true, data: await rdbClient.query(`select from orders`) }
  })

  handle('kdb:getPositions', async () => {
    if (!rdbClient) throw new Error('Not connected to RDB')
    return { success: true, data: await rdbClient.query(`select from positions`) }
  })

  // No q-side implementation exists for these yet; fail explicitly rather than call a missing function.
  handle('kdb:getRiskMetrics', async () => {
    throw new Error('not implemented')
  })

  handle('kdb:getCandles', async () => {
    throw new Error('not implemented')
  })

  handle('kdb:emergencyStop', async () => {
    if (!rdbClient) throw new Error('Not connected to RDB')
    const result = await rdbClient.query(`.risk.activateEmergencyStop[\`manual;\`ui]`)
    return { success: true, data: result }
  })

  handle('kdb:strategyControl', async (_event, name: string, action: string) => {
    if (!rdbClient) throw new Error('Not connected to RDB')
    validateSymbol(name, 'strategy name')
    if (!['pause', 'resume', 'stop'].includes(action)) {
      throw new Error(`Invalid action: "${action}" — must be pause, resume, or stop`)
    }
    limit('kdb:strategyControl')
    const funcMap: Record<string, string> = {
      pause: '.engine.strategy.pause',
      resume: '.engine.strategy.resume',
      stop: '.engine.strategy.stop',
    }
    const result = await rdbClient.query(funcMap[action], [sym(name)])
    return { success: true, data: result }
  })

  // Place order: pre-trade risk check, then the exchange coordinator (dry-run, rate limits, routing).
  handle('kdb:placeOrder', async (_event, orderData: unknown) => {
    validatePayloadSize(orderData)
    const order = validateOrder(orderData)
    if (!rdbClient) throw new Error('Not connected to RDB')
    limit('kdb:placeOrder')

    const verdict = parseRiskVerdict(await rdbClient.query('.risk.validateOrder', [
      sym(order.strategy), sym(order.pair), sym(order.exchange), sym(order.side),
      fixedLong(order.quantity), fixedLong(order.price)
    ]))
    if (!verdict.ok) {
      throw new Error(`Order rejected by risk module: ${verdict.reason}`)
    }

    const result = await rdbClient.query('.exchange.coordinator.placeOrder', [
      sym(order.exchange), sym(order.pair), sym(order.orderType), sym(order.side),
      fixedLong(order.price), fixedLong(order.quantity)
    ])
    if (typeof result !== 'object' || result === null || typeof (result as any).orderId !== 'string') {
      throw new Error('Order placement returned no order id')
    }
    const { orderId, status } = result as { orderId: string; status?: string }
    return { success: true, data: { orderId, status } }
  })

  // Setup kdb+ update forwarding (re-attaches an existing TP client when handlers are set up again)
  if (tpClient) attachTpUpdateForwarding(tpClient)

  // Health check endpoint
  handle('system:health', async () => ({
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
  }))
}

/** Updates go to every open window: pop-outs share this connection and never connect themselves. */
function attachTpUpdateForwarding(client: KdbClient): void {
  removeTpUpdateForwarder?.()

  const listener = (table: string, data: any) => {
    for (const win of BrowserWindow.getAllWindows()) {
      if (!win.isDestroyed()) win.webContents.send('kdb:update', { table, data })
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
  currentConfig = null

  await Promise.allSettled([
    currentTpClient?.disconnect(),
    currentRdbClient?.disconnect()
  ])
}
