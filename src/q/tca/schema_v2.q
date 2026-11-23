/ TCA Schema - Simplified version

\d .tca

/ Benchmark table (unkeyed for simplicity)
tcaBenchmark:([]
  time:`timestamp$();exchange:`symbol$();pair:`symbol$();interval:`symbol$();
  arrivalPx:`long$();vwap:`long$();twap:`long$();closePx:`long$();volume:`long$();volatility:`float$()
 )

/ Pre-trade TCA table
preTradeTCA:([]
  time:`timestamp$();exchange:`symbol$();pair:`symbol$();side:`symbol$();qty:`long$();
  estimatedSpreadBps:`float$();estimatedImpactBps:`float$();estimatedTotalBps:`float$()
 )

/ TCA Report table
tcaReport:([]
  reportId:`long$();orderId:`long$();exchange:`symbol$();pair:`symbol$();side:`symbol$();
  targetQty:`long$();filledQty:`long$();avgFillPx:`long$();arrivalPx:`long$();
  vwapBenchmark:`long$();twapBenchmark:`long$();
  arrivalSlippageBps:`float$();vwapSlippageBps:`float$();marketImpactBps:`float$();
  spreadCostBps:`float$();totalCostBps:`float$();
  executionTime:`long$();submitTime:`timestamp$();completeTime:`timestamp$()
 )

/ Apply primary key after creation
`reportId xkey `tcaReport

\d .

-1 "  TCA schema v2 loaded: tcaBenchmark, preTradeTCA, tcaReport";
