import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatPrice(price: number, decimals: number = 2): string {
  return price.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  })
}

export function formatPnL(pnl: number): string {
  const sign = pnl >= 0 ? '+' : ''
  return `${sign}$${formatPrice(Math.abs(pnl), 2)}`
}

export function formatPercent(pct: number): string {
  const sign = pct >= 0 ? '+' : ''
  return `${sign}${(pct * 100).toFixed(2)}%`
}

export function formatVolume(vol: number): string {
  if (vol >= 1_000_000) {
    return `${(vol / 1_000_000).toFixed(1)}M`
  } else if (vol >= 1_000) {
    return `${(vol / 1_000).toFixed(1)}K`
  } else {
    return vol.toFixed(0)
  }
}

export function formatTimestamp(date: Date): string {
  const hours = date.getHours().toString().padStart(2, '0')
  const minutes = date.getMinutes().toString().padStart(2, '0')
  const seconds = date.getSeconds().toString().padStart(2, '0')
  return `${hours}:${minutes}:${seconds}`
}
