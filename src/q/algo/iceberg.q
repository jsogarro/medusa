/ ============================================================================
/ iceberg.q - Iceberg Order Algorithm
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Iceberg execution algorithm
/   - Displays only a fraction of total order size
/   - Automatically replenishes displayed quantity on fills
/   - Randomizes display size to avoid detection
/ ----------------------------------------------------------------------------
/ Strategy:
/   - Show only displayQty at a time on the order book
/   - When displayed slice fills, submit next slice immediately
/   - Optionally randomize display quantity ±20% to avoid pattern detection
/   - Use limit orders at best price or with slight offset
/ ----------------------------------------------------------------------------
/ Default Parameters:
/   - displayQty: 10000000j (10.0 units - display quantity per slice)
/   - randomize: 1b (randomize display quantity ±20%)
/   - orderType: `limit
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
iceberg.DEFAULT_PARAMS:`displayQty`randomize`orderType`priceOffset!(10000000j; 1b; `limit; 0j);

/ Randomization range (±20%)
iceberg.RANDOMIZE_FACTOR:0.20;

/ Minimum slice size (0.1 units in fixed precision)
iceberg.MIN_SLICE_SIZE:100000j;

// ============================================================================
/ ICEBERG SLICE FUNCTION
// ============================================================================

/ Execute Iceberg slice for algo order
/ @param algoOrderId symbol - Algo order ID
iceberg.slice:{[aoid]
  / Get algo order
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; :()];  / Order not found (skip)

  / Skip if completed or cancelled
  if[ord[`status] in `completed`cancelled; :()];

  / Merge default params with user params
  params:iceberg.DEFAULT_PARAMS,ord`algoParams;

  / Calculate remaining quantity
  remainingQty:ord[`targetQty] - ord`filledQty;
  if[remainingQty <= 0; :()];  / Nothing left to fill

  / Check if there are already pending/open child orders
  / Iceberg only submits new slice when previous slice is filled
  children:0!.algo.childOrder;
  pendingChildren:children where (children`algoOrderId)=aoid;
  pendingChildren:pendingChildren where (pendingChildren`status) in `pending`open`partially_filled;

  if[(count pendingChildren) > 0;
    / Still have active child orders - wait for fill
    :();
  ];

  / Calculate display quantity (base)
  displayQty:params`displayQty;

  / Apply randomization if enabled
  if[params`randomize;
    / CORRECTED: Use continuous uniform random, not boolean
    / Random factor in [-0.20, +0.20] → display qty varies ±20%
    randomFactor:iceberg.RANDOMIZE_FACTOR * ((2.0 * (first 1?1.0)) - 1.0);
    displayQty:floor displayQty * 1.0 + randomFactor;
  ];

  / Ensure minimum slice size
  if[displayQty < iceberg.MIN_SLICE_SIZE; displayQty:iceberg.MIN_SLICE_SIZE];

  / Cap at remaining quantity
  sliceSize:displayQty & remainingQty;

  / Get best price from orderbook
  bestPrice:iceberg.getBestPrice[ord`exchange; ord`pair; ord`side];

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
  if[sliceSize < iceberg.MIN_SLICE_SIZE; :()];  / Re-check minimum

  / Submit child order
  childOrderId:.algo.engine.submitChildOrder[aoid; params`orderType; orderPrice; sliceSize];

  / Log slice
  if[not null childOrderId;
    -1 "  [ICEBERG] Displayed ",string[sliceSize]," for ",string[aoid],
       " (remaining: ",string[remainingQty],")";
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
iceberg.getBestPrice:{[exchange;pair;side]
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
-1 "  Iceberg algorithm loaded: .algo.iceberg.slice";
