import type { OptionQuote, OptionPosition, PortfolioGreeks } from './types'

// Generate realistic IV smile (higher IV at OTM strikes)
function calculateIV(strike: number, atmStrike: number, baseIV: number): number {
  const moneyness = strike / atmStrike
  const skew = Math.abs(moneyness - 1.0) * 0.15 // 15% skew
  return baseIV + skew
}

// Black-Scholes approximation for delta (simplified)
function calculateDelta(strike: number, spotPrice: number, type: 'call' | 'put'): number {
  const moneyness = spotPrice / strike
  if (type === 'call') {
    if (moneyness >= 1.1) return 0.95 // Deep ITM
    if (moneyness >= 1.05) return 0.75
    if (moneyness >= 0.95) return 0.50 // ATM
    if (moneyness >= 0.90) return 0.25
    return 0.05 // Deep OTM
  } else {
    if (moneyness <= 0.9) return -0.95 // Deep ITM
    if (moneyness <= 0.95) return -0.75
    if (moneyness <= 1.05) return -0.50 // ATM
    if (moneyness <= 1.10) return -0.25
    return -0.05 // Deep OTM
  }
}

// Generate options chain for AAPL at $155
export function generateOptionsChain(
  _symbol: string = 'AAPL',
  spotPrice: number = 155,
  _expiry: string = '2026-06-16'
): OptionQuote[] {
  const chain: OptionQuote[] = []
  const strikes = []

  // Generate strikes from 140 to 170 in $2.50 increments
  for (let strike = 140; strike <= 170; strike += 2.5) {
    strikes.push(strike)
  }

  const atmStrike = strikes.reduce((prev, curr) =>
    Math.abs(curr - spotPrice) < Math.abs(prev - spotPrice) ? curr : prev
  )
  const baseIV = 0.28 // 28% base IV

  strikes.forEach((strike) => {
    const isATM = strike === atmStrike
    const isITMCall = spotPrice > strike
    const isITMPut = spotPrice < strike

    const callIV = calculateIV(strike, atmStrike, baseIV)
    const putIV = calculateIV(strike, atmStrike, baseIV + 0.02) // Put skew

    const callDelta = calculateDelta(strike, spotPrice, 'call')
    const putDelta = calculateDelta(strike, spotPrice, 'put')

    // Intrinsic value
    const callIntrinsic = Math.max(0, spotPrice - strike)
    const putIntrinsic = Math.max(0, strike - spotPrice)

    // Time value (simplified)
    const callTimeValue = callIV * Math.sqrt(45 / 365) * strike * 0.5
    const putTimeValue = putIV * Math.sqrt(45 / 365) * strike * 0.5

    const callMid = callIntrinsic + callTimeValue
    const putMid = putIntrinsic + putTimeValue

    // Bid-ask spread (wider for OTM)
    const spreadPct = isATM ? 0.02 : 0.05
    const callSpread = callMid * spreadPct
    const putSpread = putMid * spreadPct

    // Volume and OI (higher at ATM and near-the-money)
    const moneynessFactor = Math.exp(-Math.pow((strike - atmStrike) / 10, 2))
    const callVol = Math.floor(500 + moneynessFactor * 4500)
    const putVol = Math.floor(400 + moneynessFactor * 3600)
    const callOI = Math.floor(callVol * (2 + Math.random() * 3))
    const putOI = Math.floor(putVol * (2 + Math.random() * 3))

    chain.push({
      strike,
      callBid: Math.max(0.01, callMid - callSpread / 2),
      callAsk: callMid + callSpread / 2,
      callVol,
      callOI,
      callDelta,
      callIV,
      putBid: Math.max(0.01, putMid - putSpread / 2),
      putAsk: putMid + putSpread / 2,
      putVol,
      putOI,
      putDelta,
      putIV,
      isATM,
      isITMCall,
      isITMPut
    })
  })

  return chain
}

// Mock options positions (5 positions showing an Iron Condor)
export const mockOptionPositions: OptionPosition[] = [
  {
    symbol: 'AAPL',
    strike: 150,
    expiry: '2026-06-16',
    type: 'put',
    quantity: -10, // Short
    avgPrice: 2.45,
    delta: 7.5, // -0.75 * -10
    gamma: -0.15,
    theta: 12.5,
    vega: -8.2,
    unrealizedPnL: 350
  },
  {
    symbol: 'AAPL',
    strike: 145,
    expiry: '2026-06-16',
    type: 'put',
    quantity: 10, // Long
    avgPrice: 1.20,
    delta: -5.0, // -0.50 * 10
    gamma: 0.12,
    theta: -8.0,
    vega: 6.5,
    unrealizedPnL: -120
  },
  {
    symbol: 'AAPL',
    strike: 165,
    expiry: '2026-06-16',
    type: 'call',
    quantity: -10, // Short
    avgPrice: 2.80,
    delta: -7.5, // 0.75 * -10
    gamma: -0.15,
    theta: 13.2,
    vega: -8.5,
    unrealizedPnL: 420
  },
  {
    symbol: 'AAPL',
    strike: 170,
    expiry: '2026-06-16',
    type: 'call',
    quantity: 10, // Long
    avgPrice: 1.10,
    delta: 5.0, // 0.50 * 10
    gamma: 0.12,
    theta: -7.5,
    vega: 6.8,
    unrealizedPnL: -95
  },
  {
    symbol: 'SPY',
    strike: 520,
    expiry: '2026-07-21',
    type: 'call',
    quantity: 5,
    avgPrice: 8.50,
    delta: 2.5,
    gamma: 0.08,
    theta: -4.2,
    vega: 3.5,
    unrealizedPnL: 225
  }
]

// Mock portfolio Greeks
export const mockPortfolioGreeks: PortfolioGreeks = {
  totalDelta: 0.0, // Delta-neutral
  totalGamma: -0.03,
  totalTheta: 5.8, // Positive theta (time decay working for us)
  totalVega: -0.2, // Slightly short vega
  deltaLimit: 100,
  gammaLimit: 0.5,
  thetaLimit: 50,
  vegaLimit: 10,
  history: Array.from({ length: 24 }, (_, i) => ({
    time: Date.now() - (24 - i) * 3600000, // Last 24 hours
    delta: (Math.random() - 0.5) * 20, // Random walk around 0
    vega: -0.2 + (Math.random() - 0.5) * 0.4
  }))
}

// Payoff diagram data for Iron Condor
export interface PayoffData {
  underlyingPrice: number;
  payoffAtExpiry: number;
  currentPnL: number;
}

export function generateIronCondorPayoff(
  spotPrice: number = 155,
  shortPutStrike: number = 150,
  longPutStrike: number = 145,
  shortCallStrike: number = 165,
  longCallStrike: number = 170,
  quantity: number = 10
): PayoffData[] {
  const data: PayoffData[] = []

  // Current option values (simplified)
  const currentCredit = (2.45 + 2.80 - 1.20 - 1.10) * quantity * 100

  // Generate payoff from 130 to 180
  for (let price = 130; price <= 180; price += 0.5) {
    let payoffAtExpiry = 0

    // Short put at 150
    if (price < shortPutStrike) {
      payoffAtExpiry -= (shortPutStrike - price) * quantity * 100
    }

    // Long put at 145
    if (price < longPutStrike) {
      payoffAtExpiry += (longPutStrike - price) * quantity * 100
    }

    // Short call at 165
    if (price > shortCallStrike) {
      payoffAtExpiry -= (price - shortCallStrike) * quantity * 100
    }

    // Long call at 170
    if (price > longCallStrike) {
      payoffAtExpiry += (price - longCallStrike) * quantity * 100
    }

    // Add premium collected
    payoffAtExpiry += currentCredit

    // Current P&L (simplified - uses delta approximation)
    const priceDiff = price - spotPrice
    const currentPnL = currentCredit + priceDiff * 0 // Delta-neutral, so small effect

    data.push({
      underlyingPrice: price,
      payoffAtExpiry,
      currentPnL
    })
  }

  return data
}

export const mockPayoffData = generateIronCondorPayoff()

// Calculate key metrics for Iron Condor
export const mockPayoffMetrics = {
  maxProfit: 2950, // Premium collected
  maxLoss: -2050, // Wing width - premium
  breakevens: [147.05, 167.95],
  probabilityOfProfit: 0.68,
  strategy: 'Iron Condor',
  legs: [
    { strike: 150, type: 'put', position: 'short', quantity: 10 },
    { strike: 145, type: 'put', position: 'long', quantity: 10 },
    { strike: 165, type: 'call', position: 'short', quantity: 10 },
    { strike: 170, type: 'call', position: 'long', quantity: 10 }
  ]
}

// Volatility Surface Data
export interface VolSurfacePoint {
  strike: number
  moneyness: number
  dte: number
  iv: number
}

export function generateVolSurfaceData(): VolSurfacePoint[] {
  const data: VolSurfacePoint[] = []
  const spotPrice = 155
  const baseIV = 0.28

  // 4 expiries
  const expiries = [
    { dte: 7, label: '1W' },
    { dte: 30, label: '1M' },
    { dte: 60, label: '2M' },
    { dte: 90, label: '3M' }
  ]

  // 10 strikes per expiry (85% to 115% moneyness)
  expiries.forEach(exp => {
    for (let moneyness = 0.85; moneyness <= 1.15; moneyness += 0.03) {
      const strike = spotPrice * moneyness

      // IV smile: higher IV at OTM strikes, term structure: higher IV at short DTE
      const skew = Math.abs(moneyness - 1.0) * 0.12
      const termPremium = Math.exp(-exp.dte / 60) * 0.05
      const iv = baseIV + skew + termPremium

      data.push({
        strike,
        moneyness,
        dte: exp.dte,
        iv
      })
    }
  })

  return data
}

// Skew Metrics
export interface SkewMetrics {
  atmIV: number
  putSkew: number
  callSkew: number
  riskReversal25d: number
  butterfly25d: number
}

export function generateSkewMetrics(): SkewMetrics {
  return {
    atmIV: 0.28,
    putSkew: 0.035, // 25Δ put IV - ATM IV
    callSkew: 0.025, // ATM IV - 25Δ call IV
    riskReversal25d: -0.010, // 25Δ call IV - 25Δ put IV (negative = put skew)
    butterfly25d: 0.030 // (25Δ put IV + 25Δ call IV) / 2 - ATM IV
  }
}

// Strategy Templates
export interface StrategyTemplate {
  name: string
  description: string
  legs: Array<{
    strike: number
    type: 'call' | 'put'
    position: 'long' | 'short'
    quantity: number
  }>
}

export function generateStrategyTemplates(spotPrice: number = 155): StrategyTemplate[] {
  return [
    {
      name: 'Iron Condor',
      description: 'Sell OTM put spread + OTM call spread',
      legs: [
        { strike: spotPrice - 5, type: 'put', position: 'short', quantity: 1 },
        { strike: spotPrice - 10, type: 'put', position: 'long', quantity: 1 },
        { strike: spotPrice + 10, type: 'call', position: 'short', quantity: 1 },
        { strike: spotPrice + 15, type: 'call', position: 'long', quantity: 1 }
      ]
    },
    {
      name: 'Bull Call Spread',
      description: 'Buy ITM call + sell OTM call',
      legs: [
        { strike: spotPrice - 5, type: 'call', position: 'long', quantity: 1 },
        { strike: spotPrice + 5, type: 'call', position: 'short', quantity: 1 }
      ]
    },
    {
      name: 'Bear Put Spread',
      description: 'Buy ITM put + sell OTM put',
      legs: [
        { strike: spotPrice + 5, type: 'put', position: 'long', quantity: 1 },
        { strike: spotPrice - 5, type: 'put', position: 'short', quantity: 1 }
      ]
    },
    {
      name: 'Long Straddle',
      description: 'Buy ATM call + ATM put',
      legs: [
        { strike: spotPrice, type: 'call', position: 'long', quantity: 1 },
        { strike: spotPrice, type: 'put', position: 'long', quantity: 1 }
      ]
    },
    {
      name: 'Butterfly',
      description: 'Buy 1 ITM, sell 2 ATM, buy 1 OTM (same type)',
      legs: [
        { strike: spotPrice - 10, type: 'call', position: 'long', quantity: 1 },
        { strike: spotPrice, type: 'call', position: 'short', quantity: 2 },
        { strike: spotPrice + 10, type: 'call', position: 'long', quantity: 1 }
      ]
    }
  ]
}
