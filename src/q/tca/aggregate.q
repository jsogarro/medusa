/ ============================================================================
/ aggregate.q - TCA Aggregate Analytics
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Aggregate TCA statistics across dimensions
/   - Performance breakdown by strategy, exchange, time-of-day
/   - Summary statistics for TCA reporting
/ ----------------------------------------------------------------------------
/ Functions:
/   - byStrategy: Aggregate TCA by trading strategy
/   - byExchange: Aggregate TCA by exchange
/   - byHour: Aggregate TCA by hour of day
/   - summary: Overall TCA summary for date range
/ ============================================================================

\d .tca

/ ============================================================================
/ AGGREGATE BY STRATEGY
/ ============================================================================

/ Aggregate TCA metrics by strategy
/ @param startDate date - Start date
/ @param endDate date - End date
/ @return table - Average slippage and costs by strategy
aggregate.byStrategy:{[startDate;endDate]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;  / Include full end date

  / Get all reports in date range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / If no reports, return empty table
  if[0 = count reports; :0#reports];

  / Join with order table to get strategy (actor)
  / Note: Using .qg.order table to get actor field
  reportsWithStrategy:reports lj `orderId xkey select orderId:order_id, strategy:actor from .qg.order;

  / Aggregate by strategy
  select
    orderCount:count i,
    avgArrivalSlippageBps:avg arrivalSlippageBps,
    avgVwapSlippageBps:avg vwapSlippageBps,
    avgMarketImpactBps:avg marketImpactBps,
    avgSpreadCostBps:avg spreadCostBps,
    avgTotalCostBps:avg totalCostBps,
    medianTotalCostBps:med totalCostBps,
    maxTotalCostBps:max totalCostBps,
    minTotalCostBps:min totalCostBps,
    totalVolume:sum filledQty,
    avgExecutionTime:first executionTime
    by strategy
    from reportsWithStrategy
 };

/ ============================================================================
/ AGGREGATE BY EXCHANGE
/ ============================================================================

/ Aggregate TCA metrics by exchange
/ @param startDate date - Start date
/ @param endDate date - End date
/ @return table - Average slippage and costs by exchange
aggregate.byExchange:{[startDate;endDate]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / If no reports, return empty table
  if[0 = count reports; :0#reports];

  / Aggregate by exchange
  select
    orderCount:count i,
    avgArrivalSlippageBps:avg arrivalSlippageBps,
    avgVwapSlippageBps:avg vwapSlippageBps,
    avgMarketImpactBps:avg marketImpactBps,
    avgSpreadCostBps:avg spreadCostBps,
    avgTotalCostBps:avg totalCostBps,
    medianTotalCostBps:med totalCostBps,
    maxTotalCostBps:max totalCostBps,
    minTotalCostBps:min totalCostBps,
    totalVolume:sum filledQty,
    avgExecutionTime:first executionTime
    by exchange
    from reports
 };

/ ============================================================================
/ AGGREGATE BY HOUR OF DAY
/ ============================================================================

/ Aggregate TCA metrics by hour of day
/ @param startDate date - Start date
/ @param endDate date - End date
/ @return table - Average slippage and costs by hour
aggregate.byHour:{[startDate;endDate]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / If no reports, return empty table
  if[0 = count reports; :0#reports];

  / Extract hour from submitTime
  reportsWithHour:update hour:`int$`hh$submitTime from reports;

  / Aggregate by hour
  select
    orderCount:count i,
    avgArrivalSlippageBps:avg arrivalSlippageBps,
    avgVwapSlippageBps:avg vwapSlippageBps,
    avgMarketImpactBps:avg marketImpactBps,
    avgSpreadCostBps:avg spreadCostBps,
    avgTotalCostBps:avg totalCostBps,
    medianTotalCostBps:med totalCostBps,
    maxTotalCostBps:max totalCostBps,
    minTotalCostBps:min totalCostBps,
    totalVolume:sum filledQty,
    avgExecutionTime:first executionTime
    by hour
    from reportsWithHour
 };

/ ============================================================================
/ OVERALL SUMMARY
/ ============================================================================

/ Generate overall TCA summary for date range
/ @param startDate date - Start date
/ @param endDate date - End date
/ @return dict - Summary statistics
aggregate.summary:{[startDate;endDate]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / If no reports, return empty dict
  if[0 = count reports;
    :`totalOrders`avgArrivalSlippageBps`avgVwapSlippageBps`avgMarketImpactBps`avgSpreadCostBps`avgTotalCostBps`medianTotalCostBps`maxTotalCostBps`minTotalCostBps`totalVolume`avgExecutionTime!(0;0n;0n;0n;0n;0n;0n;0n;0n;0j;0Nn)
  ];

  / Calculate summary stats
  avgExecTime:exec first executionTime from reports;
  totalOrders:count reports;
  avgArrival:exec avg arrivalSlippageBps from reports;
  avgVwap:exec avg vwapSlippageBps from reports;
  avgImpact:exec avg marketImpactBps from reports;
  avgSpread:exec avg spreadCostBps from reports;
  avgTotal:exec avg totalCostBps from reports;
  medTotal:exec med totalCostBps from reports;
  maxTotal:exec max totalCostBps from reports;
  minTotal:exec min totalCostBps from reports;
  totalVolume:exec sum filledQty from reports;
  `totalOrders`avgArrivalSlippageBps`avgVwapSlippageBps`avgMarketImpactBps`avgSpreadCostBps`avgTotalCostBps`medianTotalCostBps`maxTotalCostBps`minTotalCostBps`totalVolume`avgExecutionTime!(
    totalOrders;
    avgArrival;
    avgVwap;
    avgImpact;
    avgSpread;
    avgTotal;
    medTotal;
    maxTotal;
    minTotal;
    totalVolume;
    avgExecTime
  )
 };

/ ============================================================================
/ PERFORMANCE BREAKDOWN
/ ============================================================================

/ Get performance breakdown by side (buy/sell)
/ @param startDate date - Start date
/ @param endDate date - End date
/ @return table - TCA metrics by side
aggregate.bySide:{[startDate;endDate]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / If no reports, return empty table
  if[0 = count reports; :0#reports];

  / Aggregate by side
  select
    orderCount:count i,
    avgArrivalSlippageBps:avg arrivalSlippageBps,
    avgVwapSlippageBps:avg vwapSlippageBps,
    avgMarketImpactBps:avg marketImpactBps,
    avgSpreadCostBps:avg spreadCostBps,
    avgTotalCostBps:avg totalCostBps,
    medianTotalCostBps:med totalCostBps,
    totalVolume:sum filledQty
    by side
    from reports
 };

/ Get worst performing orders (highest total cost)
/ @param startDate date - Start date
/ @param endDate date - End date
/ @param n long - Number of orders to return
/ @return table - Top N worst performing orders
aggregate.worstPerformers:{[startDate;endDate;n]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / Sort by total cost descending and take top N
  n sublist `totalCostBps xdesc reports
 };

/ Get best performing orders (lowest total cost)
/ @param startDate date - Start date
/ @param endDate date - End date
/ @param n long - Number of orders to return
/ @return table - Top N best performing orders
aggregate.bestPerformers:{[startDate;endDate;n]
  / Convert dates to timestamps
  startTime:`timestamp$startDate;
  endTime:`timestamp$endDate + 1;

  / Get reports in range
  reports:select from .tca.tcaReport
    where submitTime within (startTime;endTime);

  / Sort by total cost ascending and take top N
  n sublist `totalCostBps xasc reports
 };

\d .

/ Export namespace
-1 "  TCA aggregate module loaded: .tca.aggregate namespace";
