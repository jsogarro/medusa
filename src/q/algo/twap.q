/ ============================================================================
/ twap.q - Time-Weighted Average Price (TWAP) Algorithm
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - TWAP execution algorithm
/   - Equal-sized slices at regular intervals
/   - Time-based distribution of order quantity
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Divide remaining time into equal intervals
/   - Submit equal-sized slices at each interval
/   - Adjust slice size dynamically based on time remaining
/   - Handle early completion gracefully
/ ----------------------------------------------------------------------------
/ Default Parameters:
/   - sliceInterval: 60 (seconds between slices)
/   - orderType: `limit (can be `market for aggressive execution)
/   - priceOffset: 0j (offset from best price in fixed precision)
/   - endTime: required (algorithm end time)
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
twap.DEFAULT_PARAMS:`sliceInterval`orderType`priceOffset!(60; `limit; 0j);

/ Minimum slice size (1.0 units in fixed precision)
twap.MIN_SLICE_SIZE:1000000j;

// ============================================================================
/ TWAP SLICE FUNCTION
// ============================================================================

/ Execute TWAP slice for algo order
/ @param algoOrderId symbol - Algo order ID
twap.slice:{[aoid]
  / Get algo order
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; :()];  / Order not found (skip)

  / Skip if completed or cancelled
  if[ord[`status] in `completed`cancelled; :()];

  / Check if endTime is set (required for TWAP)
  if[null ord`endTime;
    -1 "  [TWAP] Error: endTime not set for algo order ",string aoid;
    :();
  ];

  / Merge default params with user params
  params:twap.DEFAULT_PARAMS,ord`algoParams;

  / Calculate time remaining (in seconds)
  timeRemainingNs:ord[`endTime] - .z.p;
  if[timeRemainingNs <= 0;
    / Time expired - mark as completed
    update status:`completed, completedAt:.z.p from `.algo.algoOrder where algoOrderId=aoid;
    -1 "  [TWAP] Time limit reached for ",string aoid;
    :();
  ];

  timeRemainingSec:timeRemainingNs % 1000000000;  / Convert ns to seconds

  / Calculate remaining quantity
  remainingQty:ord[`targetQty] - ord`filledQty;
  if[remainingQty <= 0; :()];  / Nothing left to fill

  / Calculate number of slices remaining
  sliceInterval:params`sliceInterval;
  slicesRemaining:ceiling timeRemainingSec % sliceInterval;
  if[slicesRemaining <= 0; slicesRemaining:1];  / At least 1 slice

  / Calculate slice size (equal distribution)
  sliceSize:floor remainingQty % slicesRemaining;

  / Ensure minimum slice size
  if[sliceSize < twap.MIN_SLICE_SIZE;
    / If remaining qty is too small to slice, submit all at once
    sliceSize:remainingQty;
  ];

  / Cap at remaining quantity
  sliceSize:sliceSize & remainingQty;

  / Get best price from orderbook
  bestPrice:twap.getBestPrice[ord`exchange; ord`pair; ord`side];

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
  if[sliceSize < twap.MIN_SLICE_SIZE; :()];  / Re-check minimum

  / Submit child order
  childOrderId:.algo.engine.submitChildOrder[aoid; params`orderType; orderPrice; sliceSize];

  / Log slice
  if[not null childOrderId;
    -1 "  [TWAP] Sliced ",string[sliceSize]," for ",string[aoid],
       " (",string[slicesRemaining]," slices remaining, ",
       string[timeRemainingSec]," sec left)";
  ];
 };

// ============================================================================
/ HELPER FUNCTIONS
// ============================================================================

/ Get best price from orderbook
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @return long - Best bid (for buy) or best ask (for sell)
twap.getBestPrice:{[exchange;pair;side]
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
-1 "  TWAP algorithm loaded: .algo.twap.slice";
