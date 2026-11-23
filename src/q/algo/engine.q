/ ============================================================================
/ engine.q - Execution Algorithm Engine Orchestrator
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Algo order lifecycle management (submit, pause, cancel, resume)
/   - Child order tracking and parent update on fills
/   - Timer-based slicing scheduler
/   - Progress tracking and reporting
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - schema.q (algo tables)
/   - risk/validate.q (pre-trade validation)
/   - exchange/coordinator.q (order placement)
/ ----------------------------------------------------------------------------
/ Functions:
/   - submit: Submit new algo order
/   - pause: Pause active algo order
/   - resume: Resume paused algo order
/   - cancel: Cancel algo order
/   - onChildFill: Handle child order fill event
/   - engine.scheduleSlicing: Register algo order for periodic slicing
/   - timerHandler: Process slicing for all active algos
/ ============================================================================

\d .algo

// ============================================================================
// STATE
// ============================================================================

/ Algo order ID counter (atomic)
engine.algoOrderIdCounter:0;

/ Child order ID counter (atomic)
engine.childOrderIdCounter:0;

/ Active algo orders scheduled for slicing (set of algoOrderId)
engine.activeSchedule:();

/ Last slice time per algo order (dict: algoOrderId -> timestamp)
engine.lastSliceTime:()!();

/ Timer interval in milliseconds (1 second)
engine.TIMER_INTERVAL:1000;

/ Timer enabled flag
engine.timerEnabled:0b;

// ============================================================================
// INITIALIZATION
// ============================================================================

/ Initialize algo engine
/ @return boolean - Success status
engine.init:{[]
  / Reset state
  engine.algoOrderIdCounter::0;
  engine.childOrderIdCounter::0;
  engine.activeSchedule::();
  engine.lastSliceTime::()!();
  engine.timerEnabled::0b;

  -1 "  Algo engine initialized";

  1b
 };

// ============================================================================
/ ALGO ORDER SUBMISSION
// ============================================================================

/ Submit new algo order
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @param qty long - Target quantity (fixed precision)
/ @param algo symbol - Algorithm type (`vwap`twap`iceberg)
/ @param params dict - Algorithm parameters
/ @return symbol - algoOrderId
engine.submit:{[exchange;pair;side;qty;algo;params]
  / Validate inputs
  if[not .qg.isValidExchange[exchange];
    '"Invalid exchange: ",string exchange];
  if[not side in `buy`sell;
    '"Invalid side: ",string side];
  if[not .qg.isPositiveAmount[qty];
    '"Quantity must be positive"];
  if[not .algo.isValidAlgoType[algo];
    '"Invalid algo type: ",string algo];

  / Generate algoOrderId
  engine.algoOrderIdCounter+:1;
  algoOrderId:`$"ALGO_",string[engine.algoOrderIdCounter],"_",string[exchange],"_",string[pair];

  / Determine benchmark type (default to arrival price)
  benchmark:$[`benchmark in key params; params`benchmark; `arrival];

  / Capture arrival price (current best price from orderbook)
  arrivalPrice:engine.captureArrivalPrice[exchange;pair;side];

  / Set benchmark price
  benchmarkPrice:$[benchmark=`arrival; arrivalPrice; 0Nj];  / VWAP calculated later

  / Determine end time
  endTime:$[`endTime in key params;
    params`endTime;
    0Np  / No time limit
  ];

  / Insert into algoOrder table
  `.algo.algoOrder upsert (
    algoOrderId;
    exchange;
    pair;
    side;
    qty;
    0j;                                      / filledQty
    algo;
    params;
    benchmark;
    benchmarkPrice;
    `active;
    .z.p;                                    / startTime
    endTime;
    .z.p;                                    / createdAt
    0Np                                      / completedAt
  );

  / Record arrival benchmark if applicable
  if[benchmark=`arrival;
    engine.recordBenchmark[exchange;pair;`arrival;arrivalPrice;0j];
  ];

  / Schedule for slicing
  engine.scheduleSlicing[algoOrderId];

  / Log submission
  -1 "  [ALGO] Submitted ",string[algo]," order ",string[algoOrderId],
     " for ",string[qty]," ",string[pair]," on ",string exchange;

  algoOrderId
 };

// ============================================================================
/ ALGO ORDER LIFECYCLE
// ============================================================================

/ Pause algo order (stop slicing but keep children open)
/ @param algoOrderId symbol - Algo order ID
/ @return boolean - Success status
engine.pause:{[aoid]
  / Check if exists and active
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; '"Algo order not found: ",string aoid];
  if[not ord[`status]=`active; '"Algo order not active: ",string aoid];

  / Update status
  update status:`paused from `.algo.algoOrder where algoOrderId=aoid;

  / Remove from schedule
  engine.activeSchedule::engine.activeSchedule except enlist aoid;

  / Log
  -1 "  [ALGO] Paused algo order ",string aoid;

  1b
 };

/ Resume paused algo order
/ @param algoOrderId symbol - Algo order ID
/ @return boolean - Success status
engine.resume:{[aoid]
  / Check if exists and paused
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; '"Algo order not found: ",string aoid];
  if[not ord[`status]=`paused; '"Algo order not paused: ",string aoid];

  / Update status
  update status:`active from `.algo.algoOrder where algoOrderId=aoid;

  / Re-schedule
  engine.scheduleSlicing[aoid];

  / Log
  -1 "  [ALGO] Resumed algo order ",string aoid;

  1b
 };

/ Cancel algo order (cancel all child orders, mark completed)
/ @param algoOrderId symbol - Algo order ID
/ @return boolean - Success status
engine.cancel:{[aoid]
  / Check if exists
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; '"Algo order not found: ",string aoid];

  / Cancel all pending child orders
  children:select from `.algo.childOrder where algoOrderId=aoid, status in `pending`open;

  {[childOrd]
    / Attempt to cancel via exchange coordinator
    @[.exchange.coordinator.cancelOrder; (childOrd`exchange; childOrd`childOrderId); {
      -1 "  [ALGO] Failed to cancel child order: ",x;
    }];

    / Update child status locally
    update status:`cancelled from `.algo.childOrder where childOrderId=childOrd`childOrderId;
  } each children;

  / Update parent status
  update status:`cancelled, completedAt:.z.p from `.algo.algoOrder where algoOrderId=aoid;

  / Remove from schedule
  engine.activeSchedule::engine.activeSchedule except enlist aoid;

  / Log
  -1 "  [ALGO] Cancelled algo order ",string[aoid],
     " (",string[count children]," child orders cancelled)";

  1b
 };

// ============================================================================
/ CHILD ORDER MANAGEMENT
// ============================================================================

/ Handle child order fill event
/ @param childOrderId symbol - Child order ID
/ @param filledQty long - Filled quantity (fixed precision)
/ @param avgFillPrice long - Average fill price
/ @return boolean - Success status
engine.onChildFill:{[coid;filledQty;avgFillPrice]
  coid:$[0<type coid; first coid; coid];
  filledQty:$[0<type filledQty; first filledQty; filledQty];
  avgFillPrice:$[0<type avgFillPrice; first avgFillPrice; avgFillPrice];

  / Get child order
  childOrd:.algo.childOrder[coid];
  if[null childOrd`algoOrderId; '"Child order not found: ",string coid];

  / Update child order
  `.algo.childOrder upsert (
    coid;
    childOrd`algoOrderId;
    childOrd`exchange;
    childOrd`pair;
    childOrd`side;
    childOrd`orderType;
    childOrd`price;
    childOrd`quantity;
    filledQty;
    `filled;
    childOrd`submitTime;
    .z.p;
    avgFillPrice
  );

  / Get parent algo order
  parentId:childOrd`algoOrderId;
  parentOrd:.algo.algoOrder[parentId];
  if[null parentOrd`exchange; :0b];  / Parent not found (should not happen)

  / Update parent filled quantity
  newFilledQty:parentOrd[`filledQty] + filledQty;
  isComplete:newFilledQty >= parentOrd`targetQty;
  newStatus:$[isComplete; `completed; parentOrd`status];
  newCompletedAt:$[isComplete; .z.p; parentOrd`completedAt];

  `.algo.algoOrder upsert (
    parentId;
    parentOrd`exchange;
    parentOrd`pair;
    parentOrd`side;
    parentOrd`targetQty;
    newFilledQty;
    parentOrd`algo;
    parentOrd`algoParams;
    parentOrd`benchmark;
    parentOrd`benchmarkPrice;
    newStatus;
    parentOrd`startTime;
    parentOrd`endTime;
    parentOrd`createdAt;
    newCompletedAt
  );

  / Check if parent is complete
  if[isComplete;
    / Remove from schedule
    engine.activeSchedule::engine.activeSchedule except enlist parentId;

    / Log completion
    -1 "  [ALGO] Algo order ",string[parentId]," completed (",
       string[newFilledQty]," filled)";
  ];

  / Publish progress update
  engine.publishProgress[parentId];

  1b
 };

/ Generate next child order ID
engine.nextChildOrderId:{[algoOrderId]
  engine.childOrderIdCounter+:1;
  `$"CHILD_",string[engine.childOrderIdCounter],"_",string algoOrderId
 };

/ Submit child order via exchange coordinator
/ @param algoOrderId symbol - Parent algo order ID
/ @param orderType symbol - `market or `limit
/ @param price long - Order price (null for market)
/ @param quantity long - Order quantity
/ @return symbol - childOrderId
engine.submitChildOrder:{[aoid;orderType;price;quantity]
  / Get parent order
  parentOrd:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count parentOrd; '"Parent algo order not found"];

  / Generate childOrderId
  childOrderId:engine.nextChildOrderId[aoid];

  / Risk check via .risk.validateOrder
  riskResult:.risk.validateOrder[`algo; parentOrd`pair; parentOrd`exchange; parentOrd`side; quantity; price];
  if[not riskResult 0;
    / Risk check failed - log and skip this slice
    -1 "  [ALGO] Risk check failed for child order ",string[childOrderId],": ",string riskResult 1;
    :`;  / Return null symbol
  ];

  / Submit order via coordinator
  result:.exchange.coordinator.placeOrder[
    parentOrd`exchange;
    parentOrd`pair;
    orderType;
    parentOrd`side;
    price;
    quantity
  ];

  / Insert into childOrder table
  `.algo.childOrder upsert (
    childOrderId;
    aoid;
    parentOrd`exchange;
    parentOrd`pair;
    parentOrd`side;
    orderType;
    price;
    quantity;
    0j;                                      / filledQty
    `pending;                                / status
    .z.p;                                    / submitTime
    0Np;                                     / fillTime
    0Nj                                      / avgFillPrice
  );

  / Log
  -1 "  [ALGO] Submitted child order ",string[childOrderId],
     " (",string[quantity]," @ ",string[price],")";

  childOrderId
 };

// ============================================================================
/ SLICING SCHEDULER
// ============================================================================

/ Schedule algo order for periodic slicing
/ @param algoOrderId symbol - Algo order ID
engine.scheduleSlicing:{[aoid]
  / Add to active schedule (unique)
  engine.activeSchedule::distinct engine.activeSchedule,enlist aoid;

  / Initialize last slice time
  engine.lastSliceTime[aoid]:.z.p;

  / Enable timer if not already enabled
  if[not engine.timerEnabled;
    engine.enableTimer[];
  ];
 };

/ Enable timer handler
engine.enableTimer:{[]
  / Set timer to call timerHandler every engine.TIMER_INTERVAL ms
  .z.ts:{[] .algo.engine.timerHandler[]};
  system "t ",string engine.TIMER_INTERVAL;
  engine.timerEnabled::1b;

  -1 "  [ALGO] Timer enabled (interval: ",string[engine.TIMER_INTERVAL]," ms)";
 };

/ Disable timer handler
engine.disableTimer:{[]
  system "t 0";
  engine.timerEnabled::0b;

  -1 "  [ALGO] Timer disabled";
 };

/ Timer handler - called periodically to slice active algo orders
engine.timerHandler:{[]
  / Process each active algo order
  {[aoid]
    / Get algo order
    ord:first select from `.algo.algoOrder where algoOrderId=aoid;
    if[0=count ord; :()];  / Order not found (skip)

    / Skip if not active
    if[not ord[`status]=`active; :()];

    / Check if end time reached
    if[(not null ord`endTime) and .z.p >= ord`endTime;
      / Time limit reached - mark as completed
      update status:`completed, completedAt:.z.p from `.algo.algoOrder where algoOrderId=aoid;
      engine.activeSchedule::engine.activeSchedule except enlist aoid;
      -1 "  [ALGO] Algo order ",string[aoid]," time limit reached";
      :();
    ];

    / Delegate to algo-specific slice function
    algo:ord`algo;
    sliceFunc:$[
      algo=`vwap; .algo.vwap.slice;
      algo=`twap; .algo.twap.slice;
      algo=`iceberg; .algo.iceberg.slice;
      {'"Unknown algo type: ",string x}[algo]
    ];

    / Execute slice (protected)
    @[sliceFunc; aoid; {
      -1 "  [ALGO] Error slicing order: ",x;
    }];

  } each engine.activeSchedule;

  / Disable timer if no active orders
  if[0=count engine.activeSchedule;
    engine.disableTimer[];
  ];
 };

// ============================================================================
/ BENCHMARK TRACKING
// ============================================================================

/ Capture arrival price from orderbook
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @return long - Arrival price
engine.captureArrivalPrice:{[exchange;pair;side]
  / Get current orderbook (this assumes orderbook table exists in .exchange or .tick)
  / For now, return a dummy price (replace with actual orderbook query in production)
  / TODO: Integrate with real orderbook table when available
  50000000000j  / Dummy price: $50,000.00
 };

/ Record benchmark price
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param benchmarkType symbol - Benchmark type
/ @param price long - Benchmark price
/ @param volume long - Volume (for VWAP)
engine.recordBenchmark:{[exchange;pair;benchmarkType;price;volume]
  `.algo.executionBenchmark upsert (.z.p;exchange;pair;benchmarkType;price;volume);
 };

// ============================================================================
/ PROGRESS REPORTING
// ============================================================================

/ Publish progress update (via tickerplant if available)
/ @param algoOrderId symbol - Algo order ID
engine.publishProgress:{[aoid]
  / Get algo order
  ord:first select from `.algo.algoOrder where algoOrderId=aoid;
  if[0=count ord; :()];

  / Calculate average fill price from child orders
  children:select from `.algo.childOrder where algoOrderId=aoid, status=`filled;
  childAvgFillPrice:children`avgFillPrice;
  avgFillPrice:$[0=count children;
    0Nj;
    last childAvgFillPrice
  ];

  / Build progress message
  msg:(aoid; ord`filledQty; ord`targetQty; avgFillPrice);

  / Publish to tickerplant (if .u.pub exists)
  if[not ()~key `.u.pub;
    .u.pub[`algoProgress; msg];
  ];
 };

\d .

/ Export namespace
-1 "  Algo engine loaded: .algo.engine with submit, pause, cancel, onChildFill, timerHandler";
