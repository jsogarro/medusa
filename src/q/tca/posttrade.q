/ ============================================================================
/ posttrade.q - Post-Trade Execution Analysis
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Post-execution TCA report generation
/   - Slippage calculation vs multiple benchmarks
/   - Market impact measurement
/   - Execution cost breakdown
/ ----------------------------------------------------------------------------
/ Functions:
/   - generateReport: Create TCA report for completed order
/   - posttrade.calculateSlippage: Calculate slippage vs benchmark in bps
/   - posttrade.calculateMarketImpact: Measure price movement after execution
/   - getReport: Retrieve TCA report by ID
/ ============================================================================

\d .tca

/ ============================================================================
/ REPORT ID COUNTER
/ ============================================================================

/ Atomic report ID counter
posttrade.reportIdCounter:0j;

/ ============================================================================
/ SLIPPAGE CALCULATION
/ ============================================================================

/ Calculate slippage in basis points
/ @param fillPx long - Average fill price
/ @param benchmarkPx long - Benchmark price
/ @param side symbol - Order side (buy/sell)
/ @return float - Slippage in basis points
posttrade.calculateSlippage:{[fillPx;benchmarkPx;side]
  / Guard against null or zero benchmark
  if[(null benchmarkPx) or (benchmarkPx = 0j); :0n];

  / Slippage calculation depends on side
  / Buy: positive slippage = paid more than benchmark (bad)
  / Sell: positive slippage = received less than benchmark (bad)
  slippage:$[side=`buy;
    / Buy: (fillPx - benchmark) / benchmark
    fillPx - benchmarkPx;
    / Sell: (benchmark - fillPx) / benchmark
    benchmarkPx - fillPx
  ];

  / Convert to basis points: (slippage / benchmark) * 10000
  10000f * slippage % benchmarkPx
 };

/ ============================================================================
/ MARKET IMPACT MEASUREMENT
/ ============================================================================

/ Measure market impact (price movement after execution)
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - Order side
/ @param lastFillTime timestamp - Time of last fill
/ @param lastFillPx long - Price of last fill
/ @return float - Market impact in basis points
posttrade.calculateMarketImpact:{[exchange;pair;side;lastFillTime;lastFillPx]
  / Look for trades 1 minute after last fill
  impactWindow:lastFillTime + 60000000000j; / +1 minute

  / Get trades in impact window
  impactTrades:select from .qg.trade
    where exchange_name=exchange,
          volume_currency=first pair,
          price_currency=last pair,
          time_created within (lastFillTime;impactWindow);

  / If no trades in window, use latest benchmark
  if[0 = count impactTrades;
    bench:.tca.benchmark.getBenchmark[exchange;pair;`1min;impactWindow];
    impactPx:bench`vwap;

    / If no benchmark either, return null
    if[null impactPx; :0n];
  ];

  / If trades exist, use first trade price as impact price
  if[count impactTrades;
    impactPx:exec first price from impactTrades;
  ];

  / Calculate impact same way as slippage
  / Buy: if price increased after our buy, we moved the market up (bad)
  / Sell: if price decreased after our sell, we moved the market down (bad)
  impact:$[side=`buy;
    impactPx - lastFillPx;
    lastFillPx - impactPx
  ];

  / Convert to basis points
  10000f * impact % lastFillPx
 };

/ ============================================================================
/ TCA REPORT GENERATION
/ ============================================================================

/ Generate TCA report for completed order
/ @param orderId long - Order ID
/ @return long - Report ID
posttrade.generateReport:{[orderId]
  / Get order details
  ord:.qg.getOrder[orderId];

  / Validate order exists and is filled
  if[0 = count ord; '"Order not found"];
  if[not ord[`status] in `filled`partially_filled; '"Order not completed"];

  / Get all fills for this order
  orderFills:.qg.getTradesForOrder[orderId];

  / If no fills, cannot generate report
  if[0 = count orderFills; '"No fills found for order"];

  / Calculate volume-weighted average fill price
  fillPrices:orderFills`price;
  fillVolumes:orderFills`volume;
  avgFillPx:`long$(sum fillPrices * fillVolumes) % sum fillVolumes;

  / Get arrival price (price at order submission)
  / Use first trade price closest to order creation time
  / Construct pair symbol from volume_currency + price_currency
  pair:`$string[ord`volume_currency],string ord`price_currency;

  arrivalTrades:select from .qg.trade
    where exchange_name=ord`exchange_name,
          volume_currency=ord`volume_currency,
          price_currency=ord`price_currency,
          time_created <= ord`time_created;

  / Get most recent trade before order submission
  arrivalPx:$[count arrivalTrades;
    exec last price from arrivalTrades;
    / If no trades, use order price
    ord`price
  ];

  / Get execution window
  submitTime:ord`time_created;
  completeTime:exec last time_created from orderFills;
  executionTime:completeTime - submitTime;

  / Get benchmarks for execution window
  benchmarks:.tca.benchmark.getBenchmarksForWindow[
    ord`exchange_name;
    pair;
    `1min;
    submitTime;
    completeTime
  ];

  / Calculate slippages
  side:$[ord[`order_type]=`buy; `buy; `sell];  / Infer side from order type
  arrivalSlippage:posttrade.calculateSlippage[avgFillPx;arrivalPx;side];
  vwapSlippage:posttrade.calculateSlippage[avgFillPx;benchmarks`vwap;side];

  / Calculate market impact
  lastFillTime:exec last time_created from orderFills;
  lastFillPx:exec last price from orderFills;
  marketImpact:posttrade.calculateMarketImpact[
    ord`exchange_name;
    pair;
    side;
    lastFillTime;
    lastFillPx
  ];

  / Get spread cost at submission (from pre-trade estimate)
  / Find most recent pre-trade estimate for this order
  preTradeEstimates:select from .tca.preTradeTCA
    where exchange=ord`exchange_name,
          pair=pair,
          time <= submitTime;

  spreadCost:$[count preTradeEstimates;
    exec last estimatedSpreadBps from preTradeEstimates;
    0f
  ];

  / Total cost = arrival slippage + market impact + spread
  totalCost:arrivalSlippage + marketImpact + spreadCost;

  / Generate report ID
  posttrade.reportIdCounter+::1j;
  reportId:posttrade.reportIdCounter;

  / Insert report
  `.tca.tcaReport insert (
    reportId;                / reportId
    orderId;                 / orderId
    ord`exchange_name;       / exchange
    pair;                    / pair
    side;                    / side
    ord`volume;              / targetQty
    ord`filled_volume;       / filledQty
    avgFillPx;               / avgFillPx
    arrivalPx;               / arrivalPx
    benchmarks`vwap;         / vwapBenchmark
    benchmarks`twap;         / twapBenchmark
    arrivalSlippage;         / arrivalSlippageBps
    vwapSlippage;            / vwapSlippageBps
    marketImpact;            / marketImpactBps
    spreadCost;              / spreadCostBps
    totalCost;               / totalCostBps
    executionTime;           / executionTime
    submitTime;              / submitTime
    completeTime             / completeTime
  );

  / Publish report via tickerplant (if available)
  / Check if .u.pub is defined (tickerplant might not be running in tests)
  if[not ()~key `.u.pub;
    .u.pub[`tcaReport; reportId];
  ];

  -1 "  TCA report generated: reportId=",string[reportId]," orderId=",string[orderId],
     " totalCost=",string[totalCost]," bps";

  reportId
 };

/ ============================================================================
/ QUERY FUNCTIONS
/ ============================================================================

/ Get TCA report by ID
/ @param reportId long - Report ID
/ @return dict - TCA report
posttrade.getReport:{[reportId]
  first select from .tca.tcaReport where reportId=reportId
 };

/ Get all reports for an order
/ @param orderId long - Order ID
/ @return table - All TCA reports for order
posttrade.getReportsForOrder:{[orderId]
  select from .tca.tcaReport where orderId=orderId
 };

/ Get recent reports
/ @param n long - Number of reports
/ @return table - N most recent reports
posttrade.getRecentReports:{[n]
  idx:n sublist idesc exec reportId from .tca.tcaReport;
  .tca.tcaReport idx
 };

\d .

/ Export namespace
-1 "  TCA post-trade module loaded: .tca.posttrade namespace";
