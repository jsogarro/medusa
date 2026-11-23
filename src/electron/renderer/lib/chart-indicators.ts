import type { Candlestick } from './types'

export interface IndicatorDataPoint {
  time: number
  value: number
}

export interface BollingerBandsDataPoint {
  time: number
  upper: number
  middle: number
  lower: number
}

/**
 * Calculate Simple Moving Average (SMA)
 * @param candles - Array of candlesticks
 * @param period - Number of periods for the moving average
 * @returns Array of {time, value} data points
 */
export function calculateSMA(candles: Candlestick[], period: number): IndicatorDataPoint[] {
  if (candles.length < period) return []

  const smaData: IndicatorDataPoint[] = []

  for (let i = period - 1; i < candles.length; i++) {
    let sum = 0
    for (let j = 0; j < period; j++) {
      sum += candles[i - j].close
    }
    const sma = sum / period

    smaData.push({
      time: candles[i].time,
      value: sma
    })
  }

  return smaData
}

/**
 * Calculate Exponential Moving Average (EMA)
 * @param candles - Array of candlesticks
 * @param period - Number of periods for the moving average
 * @returns Array of {time, value} data points
 */
export function calculateEMA(candles: Candlestick[], period: number): IndicatorDataPoint[] {
  if (candles.length < period) return []

  const emaData: IndicatorDataPoint[] = []
  const multiplier = 2 / (period + 1)

  // Start with SMA for the first value
  let ema = 0
  for (let i = 0; i < period; i++) {
    ema += candles[i].close
  }
  ema = ema / period

  emaData.push({
    time: candles[period - 1].time,
    value: ema
  })

  // Calculate EMA for remaining values
  for (let i = period; i < candles.length; i++) {
    ema = (candles[i].close - ema) * multiplier + ema
    emaData.push({
      time: candles[i].time,
      value: ema
    })
  }

  return emaData
}

/**
 * Calculate Bollinger Bands
 * @param candles - Array of candlesticks
 * @param period - Number of periods for the moving average
 * @param stdDev - Number of standard deviations for the bands
 * @returns Array of {time, upper, middle, lower} data points
 */
export function calculateBollingerBands(
  candles: Candlestick[],
  period: number,
  stdDev: number
): BollingerBandsDataPoint[] {
  if (candles.length < period) return []

  const bbData: BollingerBandsDataPoint[] = []

  for (let i = period - 1; i < candles.length; i++) {
    // Calculate SMA (middle band)
    let sum = 0
    for (let j = 0; j < period; j++) {
      sum += candles[i - j].close
    }
    const sma = sum / period

    // Calculate standard deviation
    let variance = 0
    for (let j = 0; j < period; j++) {
      const diff = candles[i - j].close - sma
      variance += diff * diff
    }
    const standardDeviation = Math.sqrt(variance / period)

    // Calculate upper and lower bands
    const upper = sma + stdDev * standardDeviation
    const lower = sma - stdDev * standardDeviation

    bbData.push({
      time: candles[i].time,
      upper,
      middle: sma,
      lower
    })
  }

  return bbData
}
