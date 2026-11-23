/ ============================================================================
/ vwap.q - Volume-Weighted Average Price (VWAP) Algorithm
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - VWAP execution algorithm
/   - Participation-rate based slicing
/   - Dynamic slice sizing based on recent market volume
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Monitor recent market volume (configurable lookback window)
/   - Slice size = participation_rate × recent_volume
/   - Cap slice at remaining quantity
/   - Submit limit orders at best price (or market orders if aggressive)
/ ----------------------------------------------------------------------------
/ Default Parameters:
/   - participation: 0.10 (10% of recent volume)
/   - lookbackWindow: 60000 (1 minute in milliseconds)
/   - orderType: `limit (can be `market for aggressive execution)
/   - priceOffset: 0j (offset from best price in fixed precision)
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - engine.q (submitChildOrder, onChildFill)
/   - schema.q (algoOrder, childOrder)
/ ============================================================================

\d .algo

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Default parameters
vwap.DEFAULT_PARAMS:`participation`lookbackWindow`orderType`priceOffset!(0.10; 60000; `limit; 0j);

// ============================================================================
/ VWAP SLICE FUNCTION
// ============================================================================

/ Execute VWAP slice for algo order
/ @param algoOrderId symbol - Algo order ID
vwap.slice:{[aoid]
  / Get algo order
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; :()];  / Order not found (skip)

  / Skip if completed or cancelled
  if[ord[`status] in `completed`cancelled; :()];

  / Merge default params with user params
  params:vwap.DEFAULT_PARAMS,ord`algoParams;

  / Calculate remaining quantity
  remainingQty:ord[`targetQty] - ord`filledQty;
  if[remainingQty <= 0; :()];  / Nothing left to fill

  / Get recent market volume
  recentVolume:vwap.getRecentVolume[ord`exchange; ord`pair; params`lookbackWindow];

  / Calculate slice size (participation rate × recent volume)
  sliceSize:floor params[`participation] * recentVolume;

  / Cap at remaining quantity
  sliceSize:sliceSize & remainingQty;

  / Skip if slice size too small (< 1 unit in fixed precision)
  if[sliceSize < 1000000; :()];  / Skip if < 1.0 units

  / Get best price from orderbook
  bestPrice:vwap.getBestPrice[ord`exchange; ord`pair; ord`side];

  / Apply price offset (for limit orders)
  orderPrice:$[params[`orderType]=`limit;
    bestPrice + params`priceOffset;
    0Nj  / null for market orders
  ];

  / CRITICAL: Re-read parent order state immediately before submission
  / to prevent race condition (child fill could arrive between read and submit)
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  remainingQty:ord[`targetQty] - ord`filledQty;
  sliceSize:sliceSize & remainingQty;  / Re-cap at latest remaining
  if[sliceSize < 1000000; :()];  / Re-check minimum

  / Submit child order
  childOrderId:.algo.engine.submitChildOrder[aoid; params`orderType; orderPrice; sliceSize];

  / Log slice
  if[not null childOrderId;
    -1 "  [VWAP] Sliced ",string[sliceSize]," for ",string[aoid],
       " (recent volume: ",string[recentVolume],")";
  ];
 };

// ============================================================================
/ HELPER FUNCTIONS
// ============================================================================

/ Get recent market volume for pair
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param lookbackMs long - Lookback window in milliseconds
/ @return long - Total volume in lookback period (fixed precision)
vwap.getRecentVolume:{[exchange;pair;lookbackMs]
  / Calculate cutoff time
  cutoff:.z.p - lookbackMs * 1000000;  / Convert ms to nanoseconds

  / Query trade table for recent volume (assumes .tick.trade or .qg.trade exists)
  / TODO: Replace with actual trade table query when integrated with tick
  / For now, return a dummy volume
  100000000j  / Dummy: 100.0 units of recent volume
 };

/ Get best price from orderbook
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @return long - Best bid (for buy) or best ask (for sell)
vwap.getBestPrice:{[exchange;pair;side]
  / Query orderbook table (assumes .tick.orderbook or .exchange.orderbook exists)
  / TODO: Replace with actual orderbook query when integrated
  / For now, return a dummy price
  $[side=`buy;
    49990000000j;  / Best ask: $49,990.00
    50010000000j   / Best bid: $50,010.00
  ]
 };

\d .

/ Export namespace
-1 "  VWAP algorithm loaded: .algo.vwap.slice";
