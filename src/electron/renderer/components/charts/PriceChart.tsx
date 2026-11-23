import { useEffect, useRef, useState } from 'react'
import { createChart, ColorType, IChartApi, ISeriesApi, Time } from 'lightweight-charts'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { generateMockCandles } from '../../lib/mock-data'

interface PriceChartProps {
  pair: string
  exchange: string
}

export function PriceChart({ pair, exchange }: PriceChartProps) {
  const chartContainerRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<IChartApi | null>(null)
  const candlestickSeriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!chartContainerRef.current) return

    // Create chart
    const chart = createChart(chartContainerRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: '#141419' },
        textColor: '#fafafa'
      },
      grid: {
        vertLines: { color: '#26262a' },
        horzLines: { color: '#26262a' }
      },
      width: chartContainerRef.current.clientWidth,
      height: 400,
      timeScale: { timeVisible: true, secondsVisible: false }
    })

    const candlestickSeries = chart.addCandlestickSeries({
      upColor: '#16a34a',
      downColor: '#ef4444',
      borderUpColor: '#16a34a',
      borderDownColor: '#ef4444',
      wickUpColor: '#16a34a',
      wickDownColor: '#ef4444'
    })

    chartRef.current = chart
    candlestickSeriesRef.current = candlestickSeries

    // Resize handler
    const handleResize = () => {
      if (chartContainerRef.current && chartRef.current) {
        chartRef.current.applyOptions({
          width: chartContainerRef.current.clientWidth
        })
      }
    }
    window.addEventListener('resize', handleResize)

    // Load historical data
    loadChartData()

    return () => {
      window.removeEventListener('resize', handleResize)
      chart.remove()
    }
  }, [pair, exchange])

  const loadChartData = async () => {
    try {
      setLoading(true)

      if (!window.kdb) {
        // Use mock data when kdb+ is not available
        console.log('[PriceChart] Using mock candles for', pair, exchange)
        const mockCandles = generateMockCandles()
        if (candlestickSeriesRef.current) {
          const data = mockCandles.map((bar) => ({
            time: bar.time as Time,
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close
          }))
          candlestickSeriesRef.current.setData(data)
        }
        setLoading(false)
        return
      }

      // Load from kdb+ when available
      const result = await window.kdb.getCandles(exchange, pair, '1m')

      if (result.success && candlestickSeriesRef.current) {
        const data = result.data.map((bar: any) => ({
          time: new Date(bar.time).getTime() / 1000,
          open: bar.open,
          high: bar.high,
          low: bar.low,
          close: bar.close
        }))
        candlestickSeriesRef.current.setData(data)
      }
    } catch (error) {
      console.error('Failed to load chart data:', error)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card className="h-full">
      <CardHeader className="pb-3">
        <CardTitle className="text-base">
          {pair} - {exchange.toUpperCase()}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {loading && <div className="text-sm text-muted-foreground">Loading chart...</div>}
        <div ref={chartContainerRef} />
      </CardContent>
    </Card>
  )
}
