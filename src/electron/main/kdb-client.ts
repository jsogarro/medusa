import { EventEmitter } from 'events'
import * as q from 'node-q'

export interface KdbConfig {
  host: string
  port: number
}

export class KdbClient extends EventEmitter {
  private connection: q.Connection | null = null
  private config: KdbConfig
  private reconnectTimeout: NodeJS.Timeout | null = null
  private reconnectAttempts = 0
  private readonly MAX_RECONNECT_DELAY = 60000
  private shouldReconnect = true

  constructor(config: KdbConfig) {
    super()
    this.config = config
  }

  async connect(): Promise<void> {
    if (this.connection) {
      return
    }

    this.shouldReconnect = true

    try {
      const connection = await new Promise<q.Connection>((resolve, reject) => {
        q.connect(
          {
            host: this.config.host,
            port: this.config.port
          },
          (error, value) => {
            if (error) {
              reject(error)
              return
            }

            if (!value) {
              reject(new Error('node-q connected without returning a connection'))
              return
            }

            resolve(value)
          }
        )
      })

      this.connection = connection

      this.reconnectAttempts = 0
      this.emit('connected')
      console.log(`[KDB] Connected to ${this.config.host}:${this.config.port}`)

      connection.addListener('close', () => {
        this.connection = null
        this.emit('disconnected')
        if (this.shouldReconnect) {
          this.scheduleReconnect()
        }
      })

      connection.addListener('error', (err: Error) => {
        this.emit('error', err)
        console.error('[KDB] Error:', err)
      })

      connection.addListener('upd', (table: string, ...data: any[]) => {
        this.emit('update', table, data.length <= 1 ? data[0] : data)
      })
    } catch (error) {
      this.emit('error', error)
      if (this.shouldReconnect) {
        this.scheduleReconnect()
      }
      throw error
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimeout) return

    // Exponential backoff with jitter
    const delay = Math.min(
      5000 * Math.pow(2, this.reconnectAttempts),
      this.MAX_RECONNECT_DELAY
    ) + Math.random() * 1000

    console.log(`[KDB] Scheduling reconnect in ${Math.round(delay)}ms (attempt ${this.reconnectAttempts + 1})`)
    this.reconnectTimeout = setTimeout(() => {
      this.reconnectTimeout = null
      this.reconnectAttempts++
      this.connect().catch(() => {})
    }, delay)
  }

  async subscribe(table: string): Promise<void> {
    if (!this.connection) {
      throw new Error('Not connected to kdb+')
    }

    const query = `.u.sub[\`${table};\`]`
    await new Promise<void>((resolve, reject) => {
      this.connection!.ks(query, (error) => {
        if (error) {
          reject(error)
          return
        }
        resolve()
      })
    })
    console.log(`[KDB] Subscribed to ${table}`)
  }

  /**
   * Execute a q expression (no user input — safe for hardcoded queries only).
   */
  async query<T = any>(qExpr: string): Promise<T>

  /**
   * Call a q function with parameterized arguments (safe for user input).
   * Uses node-q's k(func, arg1, arg2, ...) to avoid injection.
   */
  async query<T = any>(func: string, args: any[]): Promise<T>

  async query<T = any>(funcOrExpr: string, args?: any[]): Promise<T> {
    if (!this.connection) {
      throw new Error('Not connected to kdb+')
    }

    return await new Promise<T>((resolve, reject) => {
      const callback = (error: Error | undefined, result: T | undefined) => {
        if (error) {
          reject(error)
          return
        }
        resolve(result as T)
      }

      if (args !== undefined) {
        // Parameterized call: k(func, arg1, arg2, ..., callback)
        this.connection!.k(funcOrExpr, ...args, callback)
      } else {
        // Direct expression (only use with hardcoded strings)
        this.connection!.k(funcOrExpr, callback)
      }
    })
  }

  async disconnect(): Promise<void> {
    this.shouldReconnect = false

    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout)
      this.reconnectTimeout = null
    }

    if (this.connection) {
      const connection = this.connection
      this.connection = null
      await new Promise<void>((resolve) => {
        connection.close(() => {
          resolve()
        })
      })
      console.log('[KDB] Disconnected')
    }
  }

  isConnected(): boolean {
    return this.connection !== null
  }
}
