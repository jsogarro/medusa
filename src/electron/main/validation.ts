const SAFE_SYMBOL = /^[A-Za-z0-9_]+$/
const MAX_STRING_LENGTH = 256

export function validateSymbol(value: string, fieldName: string): string {
  if (typeof value !== 'string' || !SAFE_SYMBOL.test(value)) {
    throw new Error(`Invalid ${fieldName}: "${value}" — only alphanumeric and underscore allowed`)
  }
  if (value.length > MAX_STRING_LENGTH) {
    throw new Error(`Invalid ${fieldName}: exceeds max length of ${MAX_STRING_LENGTH}`)
  }
  return value
}

const SAFE_PAIR = /^[A-Za-z0-9_/]+$/
const PRICE_SCALE = 1_000_000
const VOLUME_SCALE = 1_000_000
// 1e9 * 1e6 stays below Number.MAX_SAFE_INTEGER, so fixed-point values are exact.
const MAX_VALUE = 1e9

function validatePair(value: unknown): string {
  if (typeof value !== 'string' || !SAFE_PAIR.test(value) || value.length > MAX_STRING_LENGTH) {
    throw new Error(`Invalid pair: "${value}" — only alphanumeric, underscore and "/" allowed`)
  }
  return value
}

/** Strict positive number -> fixed-point long. No string/null/array coercion. */
function toFixedPositive(value: unknown, fieldName: string, scale: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > MAX_VALUE) {
    throw new Error(`Invalid ${fieldName}: must be a number in (0, ${MAX_VALUE}], got ${String(value)}`)
  }
  const fixed = Math.round(value * scale)
  if (fixed <= 0) {
    throw new Error(`Invalid ${fieldName}: ${value} rounds to zero at 6 decimal places`)
  }
  // Tolerate binary-float noise (0.1 + 0.2) but never round a real digit away (0.0000015).
  if (Math.abs(value * scale - fixed) > fixed * 1e-12 + 1e-9) {
    throw new Error(`Invalid ${fieldName}: ${value} has more than 6 decimal places`)
  }
  return fixed
}

export interface ValidatedOrder {
  exchange: string
  pair: string
  strategy: string
  side: 'buy' | 'sell'
  orderType: 'market' | 'limit' | 'stop_loss'
  /** 6-dp fixed-point long; null for market orders */
  price: number | null
  /** 6-dp fixed-point long */
  quantity: number
}

export function validateOrder(obj: unknown): ValidatedOrder {
  if (typeof obj !== 'object' || obj === null) {
    throw new Error('Invalid order: expected an object')
  }
  const o = obj as Record<string, unknown>
  const exchange = validateSymbol(String(o.exchange ?? ''), 'exchange')
  const pair = validatePair(o.pair)
  const strategy = validateSymbol(String(o.strategy ?? ''), 'strategy')
  const side = String(o.side ?? '')
  if (side !== 'buy' && side !== 'sell') {
    throw new Error(`Invalid side: "${side}" — must be "buy" or "sell"`)
  }
  const rawType = String(o.orderType ?? '')
  if (!['market', 'limit', 'stop', 'stop_loss'].includes(rawType)) {
    throw new Error(`Invalid orderType: "${rawType}" — must be market, limit, or stop`)
  }
  const orderType = rawType === 'stop' ? 'stop_loss' : (rawType as 'market' | 'limit' | 'stop_loss')
  const price = orderType === 'market' ? null : toFixedPositive(o.price, 'price', PRICE_SCALE)
  const quantity = toFixedPositive(o.quantity, 'quantity', VOLUME_SCALE)
  return { exchange, pair, side, orderType, price, quantity, strategy }
}

export interface RiskVerdict {
  ok: boolean
  reason?: string
}

/** `.risk.validateOrder` returns (1b;`) on pass and (0b;`reason;dict) on reject. Anything else fails closed. */
export function parseRiskVerdict(result: unknown): RiskVerdict {
  if (Array.isArray(result) && result[0] === true) {
    return { ok: true }
  }
  const reason = Array.isArray(result) && result[0] === false && typeof result[1] === 'string' ? result[1] : undefined
  return { ok: false, reason: reason || 'unexpected risk verdict' }
}

export interface KdbEndpoint {
  host: string
  port: number
}

const LOOPBACK_HOSTS = ['localhost', '127.0.0.1', '::1']

/** Loopback is always allowed; remote kdb+ hosts must be listed in MEDUSA_KDB_ALLOWED_HOSTS (comma separated). */
export function defaultAllowedHosts(): string[] {
  const extra = (process.env.MEDUSA_KDB_ALLOWED_HOSTS ?? '').split(',').map((h) => h.trim()).filter(Boolean)
  return [...LOOPBACK_HOSTS, ...extra]
}

function validateEndpoint(value: unknown, name: string, allowedHosts: string[]): KdbEndpoint {
  if (typeof value !== 'object' || value === null) {
    throw new Error(`Invalid kdb config: ${name} must be an object`)
  }
  const { host, port } = value as Record<string, unknown>
  if (typeof host !== 'string' || !allowedHosts.includes(host)) {
    throw new Error(`Invalid ${name} host: "${String(host)}" is not an allowed kdb+ host`)
  }
  if (typeof port !== 'number' || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`Invalid ${name} port: ${String(port)}`)
  }
  return { host, port }
}

export function validateKdbConfig(
  cfg: unknown,
  allowedHosts: string[] = defaultAllowedHosts()
): { tp: KdbEndpoint; rdb: KdbEndpoint } {
  if (typeof cfg !== 'object' || cfg === null) {
    throw new Error('Invalid kdb config: expected an object')
  }
  const c = cfg as Record<string, unknown>
  return {
    tp: validateEndpoint(c.tp, 'tp', allowedHosts),
    rdb: validateEndpoint(c.rdb, 'rdb', allowedHosts)
  }
}
