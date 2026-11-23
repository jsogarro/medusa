/ ============================================================================
/ pretrade.q - Pre-Trade Cost Estimation
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Pre-execution cost estimates
/   - Spread cost calculation
/   - Market impact estimation using orderbook depth
/   - Timing risk estimation from volatility
/ ----------------------------------------------------------------------------
/ Functions:
/   - estimateCost: Calculate total pre-trade cost estimate
/   - pretrade.estimateSpreadCost: Calculate bid-ask spread cost
/   - pretrade.estimateMarketImpact: Estimate slippage from orderbook depth
/   - pretrade.estimateTimingRisk: Estimate timing risk from recent volatility
/ ============================================================================

\d .tca

/ ============================================================================
/ SPREAD COST ESTIMATION
/ ============================================================================

/ Calculate spread cost as % of mid price
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return float - Spread cost in basis points
pretrade.estimateSpreadCost:{[exchange;pair]
  / Get current orderbook snapshot from risk module
  / Note: .risk.orderbook contains current bid/ask levels
  book:select from .risk.orderbook where exchange=exchange, sym=pair;

  / If no orderbook data, return null
  if[0 = count book; :0n];

  / Get best bid and ask
  bids:select from book where side=`bid;
  asks:select from book where side=`ask;

  if[(0 = count bids) or (0 = count asks); :0n];

  / Best bid = highest bid price, best ask = lowest ask price
  bestBid:exec max price from bids;
  bestAsk:exec min price from asks;

  / Calculate mid price
  mid:(bestBid + bestAsk) % 2;

  / Guard against zero mid
  if[mid = 0; :0n];

  / Spread cost in basis points = (spread / mid) * 10000
  spread:bestAsk - bestBid;
  10000f * spread % mid
 };

/ ============================================================================
/ MARKET IMPACT ESTIMATION
/ ============================================================================

/ Estimate market impact using orderbook depth
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - Order side (buy/sell)
/ @param qty long - Order quantity
/ @return float - Estimated impact in basis points
pretrade.estimateMarketImpact:{[exchange;pair;side;qty]
  / Use risk module's calcBookDepth function
  / Returns % of order that can be filled from available book depth
  depthPct:.risk.calcBookDepth[exchange;pair;side;qty];

  / If no depth data, use conservative estimate (5% impact)
  if[null depthPct; :5f];

  / Impact = inverse of depth
  / If 100% can be filled, impact = 0%
  / If 50% can be filled, impact = 50%
  impactPct:100f - depthPct;

  / Convert to basis points
  / Cap at 1000 bps (10%) for extreme cases
  1000f & impactPct * 100f
 };

/ ============================================================================
/ TIMING RISK ESTIMATION
/ ============================================================================

/ Estimate timing risk from recent volatility
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return float - Timing risk in basis points
pretrade.estimateTimingRisk:{[exchange;pair]
  / Get latest 1-minute benchmark volatility
  bench:.tca.benchmark.getLatestBenchmark[exchange;pair;`1min];

  / If no benchmark, use zero
  volatility:$[null bench`volatility; 0f; bench`volatility];

  / Timing risk = volatility * 100 (convert to bps)
  / Volatility is already in decimal form (e.g., 0.02 = 2%)
  volatility * 10000f
 };

/ ============================================================================
/ TOTAL COST ESTIMATION
/ ============================================================================

/ Estimate total pre-trade cost
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - Order side (buy/sell)
/ @param qty long - Order quantity
/ @return dict - Cost breakdown (spreadCostBps, impactBps, timingRiskBps, totalCostBps)
pretrade.estimateCost:{[exchange;pair;side;qty]
  / Calculate individual cost components
  spreadCost:pretrade.estimateSpreadCost[exchange;pair];
  impact:pretrade.estimateMarketImpact[exchange;pair;side;qty];
  timingRisk:pretrade.estimateTimingRisk[exchange;pair];

  / Handle nulls (use zero if component unavailable)
  spreadCost:$[null spreadCost; 0f; spreadCost];
  impact:$[null impact; 0f; impact];
  timingRisk:$[null timingRisk; 0f; timingRisk];

  / Total cost = spread + impact + timing risk
  totalCost:spreadCost + impact + timingRisk;

  / Build result dict
  result:`spreadCostBps`impactBps`timingRiskBps`totalCostBps!(
    spreadCost;
    impact;
    timingRisk;
    totalCost
  );

  / Insert into preTradeTCA table
  `.tca.preTradeTCA insert (
    .z.p;                    / time
    exchange;                / exchange
    pair;                    / pair
    side;                    / side
    qty;                     / qty
    spreadCost;              / estimatedSpreadBps
    impact;                  / estimatedImpactBps
    totalCost                / estimatedTotalBps
  );

  / Return breakdown
  result
 };

\d .

/ Export namespace
-1 "  TCA pre-trade module loaded: .tca.pretrade namespace";
