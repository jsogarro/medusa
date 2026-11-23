import * as q from 'node-q'
import Long from 'long'

/** Explicit q symbol. A bare JS string would be sent as a char list, which q functions taking symbols reject. */
export const sym = (value: string) => q.symbol(value)

/** Explicit q long; null serialises as the null long (0Nj). */
export const fixedLong = (value: number | null) => q.long(value === null ? (null as never) : (Long.fromNumber(value) as never))
