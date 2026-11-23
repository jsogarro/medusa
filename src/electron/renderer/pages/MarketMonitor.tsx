import { useState, memo } from 'react'
import { Card } from '../components/ui/card'
import { Input } from '../components/ui/input'
import { formatPrice, formatPercent, formatVolume } from '../lib/utils'
import { LineChart, Line, ResponsiveContainer } from 'recharts'
import { LinkColor, useSymbolLinkStore } from '../stores/symbolLink'

interface MarketSymbol {
  symbol: string
  lastPrice: number
  change: number
  changePct: number
  volume: number
  vwap: number
  bid: number
  ask: number
  spread: number
  sparkline: number[]
}

// Mock market data
const mockMarketData: MarketSymbol[] = [
  {
    symbol: 'BTCUSD',
    lastPrice: 67234.5,
    change: 345.2,
    changePct: 0.0052,
    volume: 12500,
    vwap: 67100.3,
    bid: 67230,
    ask: 67238,
    spread: 8,
    sparkline: Array.from({ length: 50 }, (_, i) => 67000 + Math.sin(i / 5) * 500 + Math.random() * 200)
  },
  {
    symbol: 'ETHUSD',
    lastPrice: 3215.8,
    change: -12.4,
    changePct: -0.0038,
    volume: 45300,
    vwap: 3220.1,
    bid: 3214,
    ask: 3217,
    spread: 3,
    sparkline: Array.from({ length: 50 }, (_, i) => 3200 + Math.sin(i / 5) * 30 + Math.random() * 20)
  },
  {
    symbol: 'SOLUSD',
    lastPrice: 145.3,
    change: 2.8,
    changePct: 0.0196,
    volume: 78400,
    vwap: 144.9,
    bid: 145.2,
    ask: 145.4,
    spread: 0.2,
    sparkline: Array.from({ length: 50 }, (_, i) => 143 + Math.sin(i / 5) * 3 + Math.random() * 2)
  },
  {
    symbol: 'ADAUSD',
    lastPrice: 0.452,
    change: -0.008,
    changePct: -0.0174,
    volume: 125000,
    vwap: 0.455,
    bid: 0.451,
    ask: 0.453,
    spread: 0.002,
    sparkline: Array.from({ length: 50 }, (_, i) => 0.45 + Math.sin(i / 5) * 0.01 + Math.random() * 0.005)
  },
  {
    symbol: 'AVAXUSD',
    lastPrice: 28.45,
    change: 1.2,
    changePct: 0.044,
    volume: 34200,
    vwap: 28.1,
    bid: 28.43,
    ask: 28.47,
    spread: 0.04,
    sparkline: Array.from({ length: 50 }, (_, i) => 28 + Math.sin(i / 5) * 0.8 + Math.random() * 0.3)
  },
  {
    symbol: 'DOTUSD',
    lastPrice: 6.82,
    change: -0.15,
    changePct: -0.0215,
    volume: 56700,
    vwap: 6.85,
    bid: 6.81,
    ask: 6.83,
    spread: 0.02,
    sparkline: Array.from({ length: 50 }, (_, i) => 6.8 + Math.sin(i / 5) * 0.15 + Math.random() * 0.1)
  },
  {
    symbol: 'LINKUSD',
    lastPrice: 15.34,
    change: 0.45,
    changePct: 0.0302,
    volume: 28900,
    vwap: 15.2,
    bid: 15.32,
    ask: 15.36,
    spread: 0.04,
    sparkline: Array.from({ length: 50 }, (_, i) => 15.2 + Math.sin(i / 5) * 0.3 + Math.random() * 0.15)
  },
  {
    symbol: 'UNIUSD',
    lastPrice: 7.89,
    change: 0.23,
    changePct: 0.03,
    volume: 45600,
    vwap: 7.85,
    bid: 7.88,
    ask: 7.90,
    spread: 0.02,
    sparkline: Array.from({ length: 50 }, (_, i) => 7.8 + Math.sin(i / 5) * 0.2 + Math.random() * 0.1)
  },
  {
    symbol: 'AAVEUSD',
    lastPrice: 92.45,
    change: -1.8,
    changePct: -0.019,
    volume: 12300,
    vwap: 92.8,
    bid: 92.4,
    ask: 92.5,
    spread: 0.1,
    sparkline: Array.from({ length: 50 }, (_, i) => 92 + Math.sin(i / 5) * 2 + Math.random() * 1)
  },
  {
    symbol: 'MATICUSD',
    lastPrice: 0.785,
    change: 0.012,
    changePct: 0.0155,
    volume: 234000,
    vwap: 0.782,
    bid: 0.784,
    ask: 0.786,
    spread: 0.002,
    sparkline: Array.from({ length: 50 }, (_, i) => 0.78 + Math.sin(i / 5) * 0.015 + Math.random() * 0.008)
  },
  {
    symbol: 'OPUSD',
    lastPrice: 2.34,
    change: 0.08,
    changePct: 0.0354,
    volume: 67800,
    vwap: 2.32,
    bid: 2.33,
    ask: 2.35,
    spread: 0.02,
    sparkline: Array.from({ length: 50 }, (_, i) => 2.3 + Math.sin(i / 5) * 0.08 + Math.random() * 0.04)
  },
  {
    symbol: 'ARBUSD',
    lastPrice: 1.23,
    change: -0.02,
    changePct: -0.016,
    volume: 89400,
    vwap: 1.24,
    bid: 1.22,
    ask: 1.24,
    spread: 0.02,
    sparkline: Array.from({ length: 50 }, (_, i) => 1.23 + Math.sin(i / 5) * 0.03 + Math.random() * 0.015)
  },
  {
    symbol: 'XRPUSD',
    lastPrice: 0.524,
    change: 0.003,
    changePct: 0.0057,
    volume: 456000,
    vwap: 0.522,
    bid: 0.523,
    ask: 0.525,
    spread: 0.002,
    sparkline: Array.from({ length: 50 }, (_, i) => 0.52 + Math.sin(i / 5) * 0.008 + Math.random() * 0.004)
  },
  {
    symbol: 'DOGEUSD',
    lastPrice: 0.089,
    change: 0.002,
    changePct: 0.023,
    volume: 1234000,
    vwap: 0.088,
    bid: 0.088,
    ask: 0.090,
    spread: 0.002,
    sparkline: Array.from({ length: 50 }, (_, i) => 0.088 + Math.sin(i / 5) * 0.002 + Math.random() * 0.001)
  },
  {
    symbol: 'SHIBUSD',
    lastPrice: 0.000012,
    change: -0.0000003,
    changePct: -0.024,
    volume: 5678000,
    vwap: 0.0000123,
    bid: 0.0000119,
    ask: 0.0000121,
    spread: 0.0000002,
    sparkline: Array.from({ length: 50 }, (_, i) => 0.000012 + Math.sin(i / 5) * 0.0000005 + Math.random() * 0.0000002)
  }
]

interface MarketMonitorProps {
  linkColor?: LinkColor
}

export const MarketMonitor = memo(function MarketMonitor({ linkColor = 'none' }: MarketMonitorProps) {
  const [searchTerm, setSearchTerm] = useState('')
  const [sortConfig, setSortConfig] = useState<{ key: keyof MarketSymbol; direction: 'asc' | 'desc' }>({
    key: 'symbol',
    direction: 'asc'
  })
  const setSymbol = useSymbolLinkStore((state) => state.setSymbol)

  const filteredData = mockMarketData.filter((item) =>
    item.symbol.toLowerCase().includes(searchTerm.toLowerCase())
  )

  const sortedData = [...filteredData].sort((a, b) => {
    const aValue = a[sortConfig.key]
    const bValue = b[sortConfig.key]

    if (Array.isArray(aValue) || Array.isArray(bValue)) return 0

    if (typeof aValue === 'number' && typeof bValue === 'number') {
      return sortConfig.direction === 'asc' ? aValue - bValue : bValue - aValue
    }

    return 0
  })

  const handleSort = (key: keyof MarketSymbol) => {
    setSortConfig({
      key,
      direction: sortConfig.key === key && sortConfig.direction === 'asc' ? 'desc' : 'asc'
    })
  }

  const handleSymbolClick = (symbol: string) => {
    if (linkColor !== 'none') {
      // Broadcast symbol change to all linked widgets
      setSymbol(linkColor, symbol, 'bitstamp')
    }
  }

  return (
    <div className="h-full flex flex-col p-2 gap-2">
      <Card className="p-3">
        <Input
          placeholder="Search symbols..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="max-w-md text-xs h-7"
        />
      </Card>

      <Card className="flex-1 overflow-hidden p-3">
        <div className="h-full overflow-auto">
          <table className="w-full text-xs font-mono">
            <thead className="sticky top-0 bg-card border-b border-border">
              <tr className="text-muted-foreground text-[10px]">
                <th className="text-left p-1.5 font-medium cursor-pointer" onClick={() => handleSort('symbol')}>
                  SYMBOL
                </th>
                <th className="text-right p-1.5 font-medium cursor-pointer" onClick={() => handleSort('lastPrice')}>
                  LAST
                </th>
                <th className="text-right p-1.5 font-medium cursor-pointer" onClick={() => handleSort('changePct')}>
                  CHANGE
                </th>
                <th className="text-right p-1.5 font-medium cursor-pointer" onClick={() => handleSort('volume')}>
                  VOLUME
                </th>
                <th className="text-right p-1.5 font-medium cursor-pointer" onClick={() => handleSort('vwap')}>
                  VWAP
                </th>
                <th className="text-right p-1.5 font-medium">BID</th>
                <th className="text-right p-1.5 font-medium">ASK</th>
                <th className="text-right p-1.5 font-medium">SPREAD</th>
                <th className="text-right p-1.5 font-medium">CHART</th>
              </tr>
            </thead>
            <tbody>
              {sortedData.map((item) => {
                const volumeSpike = item.volume > 100000

                return (
                  <tr
                    key={item.symbol}
                    onClick={() => handleSymbolClick(item.symbol)}
                    className={`border-b border-border/50 data-row hover:bg-card-hover cursor-pointer ${
                      volumeSpike ? 'bg-pending-yellow/10' : ''
                    } ${linkColor !== 'none' ? 'hover:bg-primary/10' : ''}`}
                  >
                    <td className="p-1.5 font-semibold">{item.symbol}</td>
                    <td className="p-1.5 text-right">{formatPrice(item.lastPrice, item.lastPrice < 1 ? 6 : 2)}</td>
                    <td
                      className={`p-1.5 text-right ${item.changePct >= 0 ? 'text-buy-green' : 'text-sell-red'}`}
                    >
                      {formatPercent(item.changePct)}
                    </td>
                    <td className="p-1.5 text-right">{formatVolume(item.volume)}</td>
                    <td className="p-1.5 text-right">{formatPrice(item.vwap, item.vwap < 1 ? 6 : 2)}</td>
                    <td className="p-1.5 text-right text-buy-green">{formatPrice(item.bid, item.bid < 1 ? 6 : 2)}</td>
                    <td className="p-1.5 text-right text-sell-red">{formatPrice(item.ask, item.ask < 1 ? 6 : 2)}</td>
                    <td className="p-1.5 text-right">{formatPrice(item.spread, item.spread < 0.01 ? 6 : 4)}</td>
                    <td className="p-1.5">
                      <ResponsiveContainer width={60} height={20}>
                        <LineChart data={item.sparkline.map((price) => ({ price }))}>
                          <Line
                            type="monotone"
                            dataKey="price"
                            stroke={item.changePct >= 0 ? '#00c853' : '#ff1744'}
                            strokeWidth={1}
                            dot={false}
                          />
                        </LineChart>
                      </ResponsiveContainer>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
})
