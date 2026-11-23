import type {
  YieldCurveSnapshot,
  SpreadMetric,
  RateChange,
  DurationMetrics,
  KeyRateDuration,
  RateScenario,
  BondHolding,
  MaturityBucket,
  CashFlow
} from './types'

// Standard Treasury tenors in years
const TENORS = [
  { label: '1M', years: 1/12 },
  { label: '3M', years: 3/12 },
  { label: '6M', years: 6/12 },
  { label: '1Y', years: 1 },
  { label: '2Y', years: 2 },
  { label: '3Y', years: 3 },
  { label: '5Y', years: 5 },
  { label: '7Y', years: 7 },
  { label: '10Y', years: 10 },
  { label: '20Y', years: 20 },
  { label: '30Y', years: 30 }
]

export function generateYieldCurves(): YieldCurveSnapshot[] {
  // Current curve (slightly inverted short end, steepening long end)
  const currentRates = [5.35, 5.28, 5.15, 4.85, 4.20, 4.10, 4.05, 4.15, 4.25, 4.45, 4.50]

  // 1 week ago (flatter)
  const oneWeekAgoRates = [5.25, 5.20, 5.10, 4.80, 4.25, 4.18, 4.12, 4.18, 4.22, 4.38, 4.42]

  // 1 month ago (more inverted)
  const oneMonthAgoRates = [5.45, 5.40, 5.30, 5.00, 4.50, 4.35, 4.20, 4.22, 4.28, 4.42, 4.48]

  // 1 year ago (significantly more inverted)
  const oneYearAgoRates = [5.55, 5.50, 5.42, 5.20, 4.85, 4.65, 4.40, 4.38, 4.35, 4.45, 4.55]

  return [
    {
      label: 'Current',
      color: '#ff6b35', // orange
      points: TENORS.map((t, i) => ({
        tenor: t.label,
        maturity: t.years,
        rate: currentRates[i]
      }))
    },
    {
      label: '1 Week Ago',
      color: '#94a3b8', // muted gray
      points: TENORS.map((t, i) => ({
        tenor: t.label,
        maturity: t.years,
        rate: oneWeekAgoRates[i]
      }))
    },
    {
      label: '1 Month Ago',
      color: '#64748b', // darker gray
      points: TENORS.map((t, i) => ({
        tenor: t.label,
        maturity: t.years,
        rate: oneMonthAgoRates[i]
      }))
    },
    {
      label: '1 Year Ago',
      color: '#3b82f6', // blue
      points: TENORS.map((t, i) => ({
        tenor: t.label,
        maturity: t.years,
        rate: oneYearAgoRates[i]
      }))
    }
  ]
}

export function generateSpreadMetrics(): SpreadMetric[] {
  return [
    { name: '2s10s', value: 5, change1D: -2 },
    { name: '2s30s', value: 30, change1D: 3 },
    { name: '10s30s', value: 25, change1D: 5 },
    { name: '5s30s', value: 45, change1D: 8 },
    { name: '2s5s', value: -15, change1D: -5 }
  ]
}

export function generateRateChanges(): RateChange[] {
  const currentRates = [5.35, 5.28, 5.15, 4.85, 4.20, 4.10, 4.05, 4.15, 4.25, 4.45, 4.50]

  return TENORS.map((t, i) => ({
    tenor: t.label,
    currentRate: currentRates[i],
    change1D: (Math.random() - 0.5) * 0.10,
    change1W: (Math.random() - 0.5) * 0.20,
    change1M: (Math.random() - 0.3) * 0.35
  }))
}

export function generateDurationMetrics(): DurationMetrics {
  return {
    modifiedDuration: 5.2,
    dv01: 13200,
    convexity: 32.5
  }
}

export function generateKeyRateDurations(): KeyRateDuration[] {
  return [
    { tenor: '1Y', dv01: 850 },
    { tenor: '2Y', dv01: 2100 },
    { tenor: '3Y', dv01: 1800 },
    { tenor: '5Y', dv01: 3200 },
    { tenor: '7Y', dv01: 2400 },
    { tenor: '10Y', dv01: 1900 },
    { tenor: '20Y', dv01: 600 },
    { tenor: '30Y', dv01: 350 }
  ]
}

export function generateRateScenarios(): RateScenario[] {
  return [
    {
      name: '+100bp Parallel',
      description: 'All rates up 100bp',
      pnlImpact: -68000
    },
    {
      name: '-100bp Parallel',
      description: 'All rates down 100bp',
      pnlImpact: 72000
    },
    {
      name: '+50bp Steepener',
      description: 'Short end +25bp, long end +75bp',
      pnlImpact: -15000
    },
    {
      name: 'Bull Flattener',
      description: 'Short end -75bp, long end -25bp',
      pnlImpact: 8500
    },
    {
      name: '2s10s +50bp',
      description: '10Y up 50bp vs 2Y',
      pnlImpact: -12000
    }
  ]
}

export function generateBondHoldings(): BondHolding[] {
  return [
    {
      cusip: '912828ZG5',
      maturity: '2026-05-15',
      coupon: 4.125,
      ytm: 4.85,
      faceValue: 1000000,
      marketValue: 985000,
      duration: 1.8
    },
    {
      cusip: '912828YX2',
      maturity: '2027-11-15',
      coupon: 3.875,
      ytm: 4.20,
      faceValue: 1500000,
      marketValue: 1465000,
      duration: 3.2
    },
    {
      cusip: '912828ZA8',
      maturity: '2029-02-15',
      coupon: 4.000,
      ytm: 4.10,
      faceValue: 2000000,
      marketValue: 1980000,
      duration: 4.5
    },
    {
      cusip: '912828W87',
      maturity: '2031-08-15',
      coupon: 3.625,
      ytm: 4.05,
      faceValue: 1800000,
      marketValue: 1725000,
      duration: 6.8
    },
    {
      cusip: '912810TM0',
      maturity: '2033-11-15',
      coupon: 3.500,
      ytm: 4.25,
      faceValue: 1200000,
      marketValue: 1135000,
      duration: 8.2
    },
    {
      cusip: '912810SD1',
      maturity: '2043-08-15',
      coupon: 3.750,
      ytm: 4.45,
      faceValue: 800000,
      marketValue: 755000,
      duration: 14.5
    }
  ]
}

export function generateMaturityBuckets(): MaturityBucket[] {
  const holdings = generateBondHoldings()

  // Group by maturity year
  const buckets: Record<number, BondHolding[]> = {}

  holdings.forEach(h => {
    const year = new Date(h.maturity).getFullYear()
    if (!buckets[year]) buckets[year] = []
    buckets[year].push(h)
  })

  return Object.entries(buckets).map(([year, bonds]) => ({
    year: parseInt(year),
    notional: bonds.reduce((sum, b) => sum + b.faceValue, 0),
    holdings: bonds
  })).sort((a, b) => a.year - b.year)
}

export function generateCashFlows(): CashFlow[] {
  const holdings = generateBondHoldings()
  const flows: CashFlow[] = []
  const today = new Date('2026-04-25')

  holdings.forEach(h => {
    const maturity = new Date(h.maturity)

    // Add semi-annual coupon payments for next 6 months
    const couponAmount = (h.faceValue * h.coupon / 100) / 2

    // Assume coupon dates are May 15 and Nov 15 for all bonds
    const nextCoupons = []
    if (today < new Date('2026-05-15')) {
      nextCoupons.push(new Date('2026-05-15'))
    }
    if (today < new Date('2026-11-15')) {
      nextCoupons.push(new Date('2026-11-15'))
    }

    nextCoupons.forEach(date => {
      if (date <= maturity) {
        flows.push({
          date: date.toISOString().split('T')[0],
          type: 'coupon',
          cusip: h.cusip,
          amount: couponAmount
        })
      }
    })

    // Add maturity payment if within 6 months
    const sixMonthsOut = new Date(today)
    sixMonthsOut.setMonth(sixMonthsOut.getMonth() + 6)

    if (maturity <= sixMonthsOut) {
      flows.push({
        date: h.maturity,
        type: 'maturity',
        cusip: h.cusip,
        amount: h.faceValue + couponAmount
      })
    }
  })

  return flows.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
}
