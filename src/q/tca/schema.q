/ TCA Schema - Simplified version

\d .tca

/ Benchmark table (unkeyed for simplicity)
tcaBenchmarkSchema:([]
  time:`timestamp$();exchange:`symbol$();pair:`symbol$();interval:`symbol$();
  arrivalPx:`long$();vwap:`long$();twap:`long$();closePx:`long$();volume:`long$();volatility:`float$()
 )

/ Pre-trade TCA table
preTradeTCASchema:([]
  time:`timestamp$();exchange:`symbol$();pair:`symbol$();side:`symbol$();qty:`long$();
  estimatedSpreadBps:`float$();estimatedImpactBps:`float$();estimatedTotalBps:`float$()
 )

/ TCA Report table
tcaReportSchema:([]
  reportId:`long$();orderId:`long$();exchange:`symbol$();pair:`symbol$();side:`symbol$();
  targetQty:`long$();filledQty:`long$();avgFillPx:`long$();arrivalPx:`long$();
  vwapBenchmark:`long$();twapBenchmark:`long$();
  arrivalSlippageBps:`float$();vwapSlippageBps:`float$();marketImpactBps:`float$();
  spreadCostBps:`float$();totalCostBps:`float$();
  executionTime:`timespan$();submitTime:`timestamp$();completeTime:`timestamp$()
 )

initTCASchema:{[]
  tcaBenchmark::tcaBenchmarkSchema;
  preTradeTCA::preTradeTCASchema;
  tcaReport::`reportId xkey tcaReportSchema;
  if[`posttrade in key `.tca;
    if[`reportIdCounter in key .tca.posttrade;
      .tca.posttrade.reportIdCounter:0j
    ]
  ];
  1b
 };

initTCASchema[];

\d .

-1 "  TCA schema v2 loaded: tcaBenchmark, preTradeTCA, tcaReport";
