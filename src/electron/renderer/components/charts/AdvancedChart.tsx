import { useEffect, useRef, useState, memo } from 'react'
import {
  createChart,
  ColorType,
  IChartApi,
  ISeriesApi,
  Time,
  MouseEventParams
} from 'lightweight-charts'
import { Card, CardHeader, CardTitle, CardContent } from '../ui/card'
import { ChartToolbar, Timeframe } from './ChartToolbar'
import { generateMockCandles } from '../../lib/mock-data'
import { calculateSMA, calculateBollingerBands } from '../../lib/chart-indicators'

import { LinkColor, useSymbolLinkStore } from '../../stores/symbolLink'

interface AdvancedChartProps {
  pair?: string
  exchange?: string
  linkColor?: LinkColor
}

export const AdvancedChart = memo(function AdvancedChart({ pair: propPair, exchange: propExchange, linkColor = 'none' }: AdvancedChartProps) {
  // Use linked symbol if linkColor is set, otherwise use props
  const linkedSymbol = useSymbolLinkStore((state) =>
    linkColor !== 'none' ? state.groups[linkColor]?.symbol : undefined
  )
  const linkedExchange = useSymbolLinkStore((state) =>
    linkColor !== 'none' ? state.groups[linkColor]?.exchange : undefined
  )

  const pair = linkColor !== 'none' ? (linkedSymbol || propPair || 'BTCUSD') : (propPair || 'BTCUSD')
  const exchange = linkColor !== 'none' ? (linkedExchange || propExchange || 'bitstamp') : (propExchange || 'bitstamp')
  const chartContainerRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<IChartApi | null>(null)
  const candlestickSeriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null)
  const volumeSeriesRef = useRef<ISeriesApi<'Histogram'> | null>(null)
  const sma20SeriesRef = useRef<ISeriesApi<'Line'> | null>(null)
  const sma50SeriesRef = useRef<ISeriesApi<'Line'> | null>(null)
  const sma200SeriesRef = useRef<ISeriesApi<'Line'> | null>(null)
  const bbUpperSeriesRef = useRef<ISeriesApi<'Line'> | null>(null)
  const bbMiddleSeriesRef = useRef<ISeriesApi<'Line'> | null>(null)
  const bbLowerSeriesRef = useRef<ISeriesApi<'Line'> | null>(null)

  const [timeframe, setTimeframe] = useState<Timeframe>('1m')
  const [showSMA, setShowSMA] = useState(true)
  const [showBB, setShowBB] = useState(false)
  const [showVolume, setShowVolume] = useState(true)
  const [loading, setLoading] = useState(true)
  const [crosshairData, setCrosshairData] = useState<{
    open: number
    high: number
    low: number
    close: number
    volume: number
  } | null>(null)

  // Create chart once on mount
  useEffect(() => {
    if (!chartContainerRef.current) return

    // Create main chart
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
      timeScale: { timeVisible: true, secondsVisible: false },
      crosshair: {
        mode: 1 // Normal crosshair mode
      }
    })

    // Add candlestick series
    const candlestickSeries = chart.addCandlestickSeries({
      upColor: '#16a34a',
      downColor: '#ef4444',
      borderUpColor: '#16a34a',
      borderDownColor: '#ef4444',
      wickUpColor: '#16a34a',
      wickDownColor: '#ef4444'
    })

    // Add volume series (histogram)
    const volumeSeries = chart.addHistogramSeries({
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume'
    })

    // Configure volume price scale
    chart.priceScale('volume').applyOptions({
      scaleMargins: {
        top: 0.8,
        bottom: 0
      }
    })

    // Add SMA series
    const sma20Series = chart.addLineSeries({
      color: '#ff6b35',
      lineWidth: 1,
      title: 'SMA 20'
    })
    const sma50Series = chart.addLineSeries({
      color: '#448aff',
      lineWidth: 1,
      title: 'SMA 50'
    })
    const sma200Series = chart.addLineSeries({
      color: '#ffffff',
      lineWidth: 1,
      title: 'SMA 200'
    })

    // Add Bollinger Bands series
    const bbUpperSeries = chart.addLineSeries({
      color: '#6b6b80',
      lineWidth: 1,
      lineStyle: 2, // Dashed
      title: 'BB Upper'
    })
    const bbMiddleSeries = chart.addLineSeries({
      color: '#6b6b80',
      lineWidth: 1,
      title: 'BB Middle'
    })
    const bbLowerSeries = chart.addLineSeries({
      color: '#6b6b80',
      lineWidth: 1,
      lineStyle: 2, // Dashed
      title: 'BB Lower'
    })

    chartRef.current = chart
    candlestickSeriesRef.current = candlestickSeries
    volumeSeriesRef.current = volumeSeries
    sma20SeriesRef.current = sma20Series
    sma50SeriesRef.current = sma50Series
    sma200SeriesRef.current = sma200Series
    bbUpperSeriesRef.current = bbUpperSeries
    bbMiddleSeriesRef.current = bbMiddleSeries
    bbLowerSeriesRef.current = bbLowerSeries

    // Subscribe to crosshair move
    chart.subscribeCrosshairMove((param: MouseEventParams) => {
      if (param.time && param.seriesData.size > 0) {
        const candleData = param.seriesData.get(candlestickSeries) as any
        const volumeData = param.seriesData.get(volumeSeries) as any
        if (candleData && volumeData) {
          setCrosshairData({
            open: candleData.open,
            high: candleData.high,
            low: candleData.low,
            close: candleData.close,
            volume: volumeData.value
          })
        }
      } else {
        setCrosshairData(null)
      }
    })

    // Resize handler
    const handleResize = () => {
      if (chartContainerRef.current && chartRef.current) {
        chartRef.current.applyOptions({
          width: chartContainerRef.current.clientWidth
        })
      }
    }
    window.addEventListener('resize', handleResize)

    return () => {
      window.removeEventListener('resize', handleResize)
      chart.remove()
    }
  }, []) // Only create chart once

  // Load data when pair/exchange/timeframe changes
  useEffect(() => {
    loadChartData()
  }, [pair, exchange, timeframe])

  // Update indicator visibility
  useEffect(() => {
    if (!chartRef.current) return

    if (sma20SeriesRef.current) {
      sma20SeriesRef.current.applyOptions({ visible: showSMA })
    }
    if (sma50SeriesRef.current) {
      sma50SeriesRef.current.applyOptions({ visible: showSMA })
    }
    if (sma200SeriesRef.current) {
      sma200SeriesRef.current.applyOptions({ visible: showSMA })
    }
    if (bbUpperSeriesRef.current) {
      bbUpperSeriesRef.current.applyOptions({ visible: showBB })
    }
    if (bbMiddleSeriesRef.current) {
      bbMiddleSeriesRef.current.applyOptions({ visible: showBB })
    }
    if (bbLowerSeriesRef.current) {
      bbLowerSeriesRef.current.applyOptions({ visible: showBB })
    }
    if (volumeSeriesRef.current) {
      volumeSeriesRef.current.applyOptions({ visible: showVolume })
    }
  }, [showSMA, showBB, showVolume])

  const loadChartData = async () => {
    try {
      setLoading(true)

      // Use mock data
      const mockCandles = generateMockCandles()

      if (!candlestickSeriesRef.current || !volumeSeriesRef.current) return

      // Set candlestick data
      const candleData = mockCandles.map((bar) => ({
        time: bar.time as Time,
        open: bar.open,
        high: bar.high,
        low: bar.low,
        close: bar.close
      }))
      candlestickSeriesRef.current.setData(candleData)

      // Set volume data (green for up bars, red for down bars)
      const volumeData = mockCandles.map((bar) => ({
        time: bar.time as Time,
        value: bar.volume,
        color: bar.close >= bar.open ? '#16a34a80' : '#ef444480' // 50% opacity
      }))
      volumeSeriesRef.current.setData(volumeData)

      // Calculate and set SMA data
      const sma20Data = calculateSMA(mockCandles, 20).map((point) => ({
        time: point.time as Time,
        value: point.value
      }))
      const sma50Data = calculateSMA(mockCandles, 50).map((point) => ({
        time: point.time as Time,
        value: point.value
      }))
      const sma200Data = calculateSMA(mockCandles, 200).map((point) => ({
        time: point.time as Time,
        value: point.value
      }))

      if (sma20SeriesRef.current) sma20SeriesRef.current.setData(sma20Data)
      if (sma50SeriesRef.current) sma50SeriesRef.current.setData(sma50Data)
      if (sma200SeriesRef.current) sma200SeriesRef.current.setData(sma200Data)

      // Calculate and set Bollinger Bands data
      const bbData = calculateBollingerBands(mockCandles, 20, 2)
      const bbUpperData = bbData.map((point) => ({
        time: point.time as Time,
        value: point.upper
      }))
      const bbMiddleData = bbData.map((point) => ({
        time: point.time as Time,
        value: point.middle
      }))
      const bbLowerData = bbData.map((point) => ({
        time: point.time as Time,
        value: point.lower
      }))

      if (bbUpperSeriesRef.current) bbUpperSeriesRef.current.setData(bbUpperData)
      if (bbMiddleSeriesRef.current) bbMiddleSeriesRef.current.setData(bbMiddleData)
      if (bbLowerSeriesRef.current) bbLowerSeriesRef.current.setData(bbLowerData)

      setLoading(false)
    } catch (error) {
      console.error('Failed to load chart data:', error)
      setLoading(false)
    }
  }

  return (
    <Card className="h-full flex flex-col">
      <CardHeader className="pb-2 px-0 pt-0">
        <div className="px-3 pt-3 pb-2">
          <CardTitle className="text-base">
            {pair} - {exchange.toUpperCase()}
          </CardTitle>
        </div>
        <ChartToolbar
          timeframe={timeframe}
          onTimeframeChange={setTimeframe}
          showSMA={showSMA}
          onToggleSMA={() => setShowSMA(!showSMA)}
          showBB={showBB}
          onToggleBB={() => setShowBB(!showBB)}
          showVolume={showVolume}
          onToggleVolume={() => setShowVolume(!showVolume)}
          crosshairData={crosshairData}
        />
      </CardHeader>
      <CardContent className="flex-1 p-0">
        {loading && <div className="text-sm text-muted-foreground px-3">Loading chart...</div>}
        <div
          ref={chartContainerRef}
          className="w-full h-full"
          role="img"
          aria-label="Price chart with candlesticks and technical indicators"
          aria-description={`Interactive price chart for ${pair} on ${exchange} showing candlestick patterns, volume, and technical indicators including SMA and Bollinger Bands`}
        />
      </CardContent>
    </Card>
  )
})
