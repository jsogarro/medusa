/ ============================================================================
/ simpleMM.q - Simple Market Making Strategy
/ ============================================================================
/
/ Production market making strategy using the strategy engine framework.
/ Provides continuous liquidity on a single exchange by placing limit orders
/ on both sides of the orderbook. Uses the .strategy.mm library for quote
/ generation and position-responsive sizing.
/
/ Dependencies:
/   - engine/strategy.q (lifecycle framework)
/   - strategy/mm.q (market making library)
/   - exchange/base.q (exchange operations)
/
/ Lifecycle hooks implemented:
/   - configure: Validate and apply configuration
/   - setUp: Initialize state and exchange connections
/   - preTick: Cancel existing orders, fetch orderbook
/   - tick: Calculate quotes and place new orders
/   - postTick: Update metrics and check inventory
/   - isComplete: Never completes (runs indefinitely)
/   - tearDown: Cancel all orders and final reporting
/ ============================================================================

\d .strategy.simpleMM

// ============================================================================
/ CONFIGURATION
// ============================================================================

/ Configuration schema with defaults
defaultConfig:{[]
  `exchange`pair`spreadBps`baseOrderSize`maxPosition`minSpreadBps`maxSpreadBps`inventorySkewFactor`depth`enabled!(
    `; / exchange (required)
    `; / trading pair (required)
    10.0; / base spread in bps (0.1%)
    1.0; / base order size
    5.0; / max position
    5.0; / min spread bps
    100.0; / max spread bps
    0.1; / inventory skew factor (0.0-1.0)
    2.0; / orderbook depth for midpoint calculation
    1b / enabled flag
  )
 }

/ Validate configuration
/ @param cfg dict - configuration to validate
/ @return dict - validated config or throws error
validateConfig:{[cfg]
  / Required fields
  if[not `exchange in key cfg; '"Missing required config: exchange"];
  if[not `pair in key cfg; '"Missing required config: pair"];

  / Type validation
  if[not -11h = type cfg`exchange; '"exchange must be symbol"];
  if[not -11h = type cfg`pair; '"pair must be symbol"];

  / Business rules
  if[cfg[`spreadBps] < 1.0; '"spreadBps must be >= 1.0"];
  if[cfg[`baseOrderSize] < 0.01; '"baseOrderSize must be >= 0.01"];
  if[cfg[`baseOrderSize] > 1000.0; '"baseOrderSize must be <= 1000"];
  if[cfg[`maxPosition] < 0.1; '"maxPosition must be >= 0.1"];
  if[cfg[`maxPosition] > 10000.0; '"maxPosition must be <= 10000"];
  if[cfg[`baseOrderSize] > cfg[`maxPosition]; '"baseOrderSize must be <= maxPosition"];
  if[cfg[`minSpreadBps] <= 0.0; '"minSpreadBps must be positive"];
  if[cfg[`maxSpreadBps] <= cfg[`minSpreadBps]; '"maxSpreadBps must be > minSpreadBps"];
  if[(cfg[`inventorySkewFactor] < 0.0) or cfg[`inventorySkewFactor] > 1.0;
    '"inventorySkewFactor must be between 0.0 and 1.0"];

  cfg
 }

// ============================================================================
/ STATE MANAGEMENT
// ============================================================================

/ Initialize strategy-specific state
/ @param state dict - engine state
/ @return dict - state with simpleMM-specific fields
initState:{[state]
  / Add strategy-specific state fields
  state[`state;`position]:0.0; / Current inventory position
  state[`state;`openOrders]:(); / List of active order IDs
  state[`state;`quotesPlaced]:0; / Total quotes placed
  state[`state;`fillsReceived]:0; / Total fills received
  state[`state;`totalVolume]:0.0; / Total volume traded
  state[`state;`lastQuoteTime]:.z.p; / Last quote timestamp
  state[`state;`currentBidPrice]:0n; / Current bid price
  state[`state;`currentAskPrice]:0n; / Current ask price

  / Rate limiting state
  state[`state;`lastOrderTime]:0Np;   / Last order placement timestamp
  state[`state;`ordersThisMinute]:0;  / Order count in current minute
  state[`state;`minuteStartTime]:.z.p; / Start of current minute window

  state
 }

// ============================================================================
/ LIFECYCLE HOOKS
// ============================================================================

/ Configure hook - apply and validate configuration
/ @param state dict - strategy state
/ @param cfg dict - configuration to apply
/ @return dict - updated state
configure:{[state;cfg]
  / Merge with defaults
  fullConfig:defaultConfig[],$[99h=type cfg; cfg; ()!()];

  / Validate
  validatedConfig:validateConfig[fullConfig];

  / Apply
  state[`config]:validatedConfig;

  state
 }

/ Setup hook - one-time initialization
/ @param state dict - strategy state
/ @return dict - initialized state
setUp:{[state]
  / Initialize strategy-specific state
  state:initState[state];

  / Store exchange for harness
  state[`exchanges]:enlist state[`config;`exchange];

  / Log initialization
  -1 "[simpleMM] Strategy initialized";
  -1 "[simpleMM] Exchange: ", string state[`config;`exchange];
  -1 "[simpleMM] Trading pair: ", string state[`config;`pair];
  -1 "[simpleMM] Spread: ", string[state[`config;`spreadBps]], " bps";
  -1 "[simpleMM] Base order size: ", string state[`config;`baseOrderSize];

  state
 }

/ PreTick hook - pre-execution checks and order cancellation
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated state
preTick:{[state;ctx]
  / Only execute if enabled
  if[not state[`config;`enabled]; :state];

  / Cancel all existing orders (cancel-before-quote pattern)
  state:cancelAllOrders[state];

  state
 }

/ Tick hook - main strategy logic
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated state
tick:{[state;ctx]
  / Only execute if enabled
  if[not state[`config;`enabled]; :state];

  / Get configuration
  config:state`config;
  exchange:config`exchange;
  pair:config`pair;

  / Get orderbook from context
  orderbooks:ctx`orderbooks;
  if[not exchange in key orderbooks;
    -1 "[simpleMM] No orderbook available for ",string exchange;
    :state
  ];

  ob:orderbooks[exchange];

  / Orderbook staleness check - verify it has bids and asks
  bids:.strategy.mm.getBids[ob];
  asks:.strategy.mm.getAsks[ob];
  if[(0=count bids) or 0=count asks;
    -1 "[simpleMM] Orderbook stale or empty - skipping tick";
    :state
  ];

  / Calculate midpoint using weighted calculation
  mid:.strategy.mm.midpoint[ob;config`depth];
  if[null mid;
    -1 "[simpleMM] Unable to calculate midpoint - insufficient orderbook data";
    :state
  ];

  / Generate quote prices
  quote:.strategy.mm.generateQuote[mid;config`spreadBps;config`minSpreadBps;config`maxSpreadBps];
  if[any null (quote`bidPrice;quote`askPrice);
    -1 "[simpleMM] Unable to generate quote - invalid midpoint or spread";
    :state
  ];

  / Quote sanity check - verify bid < ask and both > 0
  if[(quote[`bidPrice] >= quote[`askPrice]) or (quote[`bidPrice] <= 0.0) or quote[`askPrice] <= 0.0;
    -1 "[simpleMM] Invalid quote generated - bid: ",string[quote`bidPrice]," ask: ",string[quote`askPrice];
    :state
  ];

  / Rate limiting checks
  currentTime:.z.p;

  / Check minimum interval since last order (1000ms for MM)
  if[not null state[`state;`lastOrderTime];
    timeSinceLastOrder:`long$(currentTime - state[`state;`lastOrderTime]) % 1000000;  / microseconds to milliseconds
    if[timeSinceLastOrder < 1000;
      / Skip tick silently - this is normal for MM
      :state
    ];
  ];

  / Check orders per minute limit (60 for MM)
  minuteElapsed:`long$(currentTime - state[`state;`minuteStartTime]) % 60000000000;  / nanoseconds to check if minute rolled over
  if[minuteElapsed >= 60000000000;
    / Reset counter for new minute
    state[`state;`ordersThisMinute]:0;
    state[`state;`minuteStartTime]:currentTime;
  ];

  if[state[`state;`ordersThisMinute] >= 60;
    -1 "[simpleMM] Rate limit: ",string[state[`state;`ordersThisMinute]]," orders this minute (max 60)";
    :state
  ];

  / Calculate order sizes with inventory skewing
  sizes:.strategy.mm.calculateOrderSizes[
    config`baseOrderSize;
    state[`state;`position];
    config`maxPosition;
    config`inventorySkewFactor;
    0.01 / min size
  ];

  / Place quotes
  state:placeQuotes[state;quote`bidPrice;quote`askPrice;sizes`bidSize;sizes`askSize];

  / Update rate limiting state after successful quote placement
  state[`state;`lastOrderTime]:currentTime;
  state[`state;`ordersThisMinute]+:1;

  state
 }

/ PostTick hook - post-execution updates
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated state
postTick:{[state;ctx]
  / Check position imbalance
  state:checkPositionImbalance[state];

  / Update last quote time
  state[`state;`lastQuoteTime]:.z.p;

  state
 }

/ IsComplete hook - termination check
/ @param state dict - strategy state
/ @return boolean - always false (runs indefinitely)
isComplete:{[state]
  0b / Never complete
 }

/ TearDown hook - cleanup
/ @param state dict - strategy state
/ @return dict - final state
tearDown:{[state]
  / Cancel all orders before stopping
  state:cancelAllOrders[state];

  / Log final statistics
  -1 "[simpleMM] Strategy stopping";
  -1 "[simpleMM] Total quotes placed: ", string state[`state;`quotesPlaced];
  -1 "[simpleMM] Total fills received: ", string state[`state;`fillsReceived];
  -1 "[simpleMM] Total volume traded: ", string state[`state;`totalVolume];
  -1 "[simpleMM] Final position: ", string state[`state;`position];

  state
 }

// ============================================================================
/ ORDER MANAGEMENT
// ============================================================================

/ Cancel all open orders
/ @param state dict - strategy state
/ @return dict - updated state
cancelAllOrders:{[state]
  / In dryrun mode, just clear the list
  if[state[`mode] = `dryrun;
    state[`state;`openOrders]:();
    :state
  ];

  / Live mode cancellation (placeholder - would integrate with exchange connector)
  / {[exchange;orderId] .exchange.cancelOrder[exchange;orderId]}[state[`config;`exchange]] each state[`state;`openOrders];

  / Clear open orders list
  state[`state;`openOrders]:();

  state
 }

/ Place bid and ask limit orders
/ @param state dict - strategy state
/ @param bidPrice float - bid price
/ @param askPrice float - ask price
/ @param bidSize float - bid size
/ @param askSize float - ask size
/ @return dict - updated state
placeQuotes:{[state;bidPrice;askPrice;bidSize;askSize]
  config:state`config;

  / In dryrun mode, just log
  if[state[`mode] = `dryrun;
    -1 "[simpleMM] DRYRUN: Placing quotes - bid: ",string[bidSize],"@",string[bidPrice]," ask: ",string[askSize],"@",string[askPrice];

    / Update state
    state[`state;`quotesPlaced]+:1;
    state[`state;`currentBidPrice]:bidPrice;
    state[`state;`currentAskPrice]:askPrice;

    :state
  ];

  / Live mode execution (placeholder - would integrate with exchange connector)
  / bidOrderId:.exchange.placeOrder[config`exchange;config`pair;`buy;`limit;bidSize;bidPrice];
  / askOrderId:.exchange.placeOrder[config`exchange;config`pair;`sell;`limit;askSize;askPrice];

  -1 "[simpleMM] LIVE: Order placement not yet implemented - requires exchange connector integration";

  / Update state
  state[`state;`quotesPlaced]+:1;
  state[`state;`currentBidPrice]:bidPrice;
  state[`state;`currentAskPrice]:askPrice;
  / state[`state;`openOrders]:(bidOrderId;askOrderId); / Would track real order IDs

  state
 }

// ============================================================================
/ POSITION MANAGEMENT
// ============================================================================

/ Check for position imbalance and log warnings
/ @param state dict - strategy state
/ @return dict - updated state
checkPositionImbalance:{[state]
  position:state[`state;`position];
  maxPosition:state[`config;`maxPosition];
  threshold:maxPosition * 0.8; / Warn at 80% of max

  if[abs[position] > threshold;
    -1 "[simpleMM] WARNING: Position imbalance - current: ",string[position]," max: ",string[maxPosition];

    / If position exceeds max, disable strategy
    if[abs[position] > maxPosition;
      -1 "[simpleMM] CRITICAL: Position limit exceeded - disabling strategy";
      state[`config;`enabled]:0b;
    ];
  ];

  state
 }

/ Handle fill event (callback from exchange)
/ @param state dict - strategy state
/ @param fillEvent dict - fill event details
/ @return dict - updated state
onFill:{[state;fillEvent]
  / fillEvent: `orderId`side`size`price`fee!...

  / Update position
  if[fillEvent[`side] = `buy;
    state[`state;`position]+:fillEvent`size;
  ];
  if[fillEvent[`side] = `sell;
    state[`state;`position]-:fillEvent`size;
  ];

  / Update metrics
  state[`state;`fillsReceived]+:1;
  state[`state;`totalVolume]+:fillEvent`size;

  / Log fill
  -1 "[simpleMM] Fill received: ",string[fillEvent`side]," ",string[fillEvent`size],"@",string[fillEvent`price];

  / Check position limits
  state:checkPositionImbalance[state];

  state
 }

// ============================================================================
/ STRATEGY FACTORY
// ============================================================================

/ Create new simpleMM strategy instance
/ @param id symbol - strategy ID
/ @param name string - strategy name
/ @param actor symbol - actor identifier
/ @param cfg dict - strategy configuration
/ @return dict - initialized strategy state
new:{[id;name;actor;cfg]
  / Define strategy functions
  fns:`configure`setUp`preTick`tick`postTick`isComplete`tearDown!(
    configure;
    setUp;
    preTick;
    tick;
    postTick;
    isComplete;
    tearDown
  );

  / Create strategy using engine
  state:.engine.strategy.new[id;name;actor;fns];

  / Configure
  state:.engine.strategy.configure[state;cfg];

  state
 }

\d .
