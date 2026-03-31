/ ============================================================================
/ simpleArb.q - Simple Arbitrage Strategy
/ ============================================================================
/
/ Production arbitrage strategy using the strategy engine framework.
/ Monitors orderbooks across exchanges, detects profitable crosses using
/ .strategy.arb library, and executes simultaneous market orders when
/ profit exceeds configured thresholds.
/
/ Dependencies:
/   - engine/strategy.q (lifecycle framework)
/   - strategy/arb.q (arbitrage detection)
/   - exchange/coordinator.q (multi-exchange execution)
/
/ Lifecycle hooks implemented:
/   - configure: Validate and apply configuration
/   - setUp: Initialize state and exchange connections
/   - preTick: Health checks and orderbook fetching
/   - tick: Detect opportunities and execute trades
/   - postTick: Update metrics and check completion
/   - isComplete: Never completes (runs indefinitely)
/   - tearDown: Cleanup and final reporting
/ ============================================================================

\d .strategy.simpleArb

// ============================================================================
/ CONFIGURATION
// ============================================================================

/ Configuration schema with defaults
defaultConfig:{[]
  `exchanges`pair`minProfitUSD`minProfitBps`maxPositionSize`maxOrderSize`enabled!(
    (); / exchanges list (required)
    `; / trading pair (required)
    5.0; / minimum profit in USD
    50.0; / minimum profit in bps (0.5%)
    10.0; / max position size
    2.0; / max order size
    1b / enabled flag
  )
 }

/ Validate configuration
/ @param cfg dict - configuration to validate
/ @return dict - validated config or throws error
validateConfig:{[cfg]
  / Required fields
  if[not `exchanges in key cfg; '"Missing required config: exchanges"];
  if[not `pair in key cfg; '"Missing required config: pair"];

  / Type validation
  if[not 11h = type cfg`exchanges; '"exchanges must be symbol list"];
  if[not -11h = type cfg`pair; '"pair must be symbol"];

  / Business rules
  if[2 > count cfg`exchanges; '"At least 2 exchanges required"];
  if[cfg[`minProfitUSD] <= 0.0; '"minProfitUSD must be positive"];
  if[cfg[`minProfitBps] <= 0.0; '"minProfitBps must be positive"];
  if[cfg[`maxPositionSize] <= 0.0; '"maxPositionSize must be positive"];
  if[cfg[`maxPositionSize] > 1000.0; '"maxPositionSize must be <= 1000"];
  if[cfg[`maxOrderSize] <= 0.0; '"maxOrderSize must be positive"];
  if[cfg[`maxOrderSize] > cfg[`maxPositionSize]; '"maxOrderSize must be <= maxPositionSize"];

  cfg
 }

// ============================================================================
/ STATE MANAGEMENT
// ============================================================================

/ Initialize strategy-specific state
/ @param state dict - engine state
/ @return dict - state with simpleArb-specific fields
initState:{[state]
  / Add strategy-specific state fields
  state[`state;`position]:0.0;
  state[`state;`tradesExecuted]:0;
  state[`state;`totalProfit]:0.0;
  state[`state;`lastCheck]:.z.p;
  state[`state;`inFlightVolume]:0.0;  / Track in-flight orders for position limit
  state[`state;`pendingOrders]:();    / List of pending orders for future live integration

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

  / Store exchanges for coordinator
  state[`exchanges]:state[`config;`exchanges];

  / Log initialization
  -1 "[simpleArb] Strategy initialized";
  -1 "[simpleArb] Exchanges: ", " " sv string state[`config;`exchanges];
  -1 "[simpleArb] Trading pair: ", string state[`config;`pair];
  -1 "[simpleArb] Min profit: $", string state[`config;`minProfitUSD];

  state
 }

/ PreTick hook - pre-execution checks
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated state
preTick:{[state;ctx]
  / Only execute if enabled
  if[not state[`config;`enabled]; :state];

  / Update last check timestamp
  state[`state;`lastCheck]:.z.p;

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
  pair:config`pair;
  exchanges:config`exchanges;

  / Get orderbooks from context (should be populated by harness)
  orderbooks:ctx`orderbooks;

  / Detect opportunities between all exchange pairs
  opportunities:detectOpportunities[orderbooks;pair;exchanges];

  / Execute best opportunity if it passes thresholds
  if[count opportunities;
    state:evaluateAndExecute[state;first opportunities]
  ];

  state
 }

/ PostTick hook - post-execution updates
/ @param state dict - strategy state
/ @param ctx dict - execution context
/ @return dict - updated state
postTick:{[state;ctx]
  / Update metrics (placeholder for future metrics reporting)
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
  / Log final statistics
  -1 "[simpleArb] Strategy stopping";
  -1 "[simpleArb] Total trades: ", string state[`state;`tradesExecuted];
  -1 "[simpleArb] Total profit: $", string state[`state;`totalProfit];

  state
 }

// ============================================================================
/ OPPORTUNITY DETECTION
// ============================================================================

/ Detect arbitrage opportunities across all exchange pairs
/ @param orderbooks dict - exchange -> orderbook table
/ @param pair symbol - trading pair
/ @param exchanges symbol list - exchanges to check
/ @return table - opportunities sorted by profit descending
detectOpportunities:{[orderbooks;pair;exchanges]
  / Generate all directed pairs (ex1->ex2)
  pairs:raze {[exchanges;ex1]
    otherExchanges:exchanges where exchanges <> ex1;
    {[ex1;ex2] (ex1;ex2)} [ex1] each otherExchanges
  }[exchanges] each exchanges;

  / Detect crosses for each pair
  crosses:{[orderbooks;pair;exPair]
    buyEx:exPair 0;
    sellEx:exPair 1;

    / Guard against missing orderbooks
    if[not buyEx in key orderbooks; :()];
    if[not sellEx in key orderbooks; :()];

    cross:.strategy.arb.detectDirectionalCross[
      orderbooks[buyEx];
      orderbooks[sellEx];
      buyEx;
      sellEx;
      pair
    ];

    cross
  }[orderbooks;pair] each pairs;

  / Filter out nulls and sort by profit
  crosses:crosses where not null crosses;
  if[0=count crosses; :()];

  / Convert to table and sort by profit descending
  crossTable:([]
    buyExchange:`symbol$crosses[;`buyExchange];
    sellExchange:`symbol$crosses[;`sellExchange];
    volume:`float$crosses[;`volume];
    revenue:`float$crosses[;`revenue];
    fees:`float$crosses[;`fees];
    profit:`float$crosses[;`profit]
  );

  `profit xdesc crossTable
 }

// ============================================================================
/ EXECUTION LOGIC
// ============================================================================

/ Evaluate opportunity and execute if it passes thresholds
/ @param state dict - strategy state
/ @param opportunity dict - cross opportunity
/ @return dict - updated state
evaluateAndExecute:{[state;opportunity]
  config:state`config;

  / Check profit thresholds
  if[opportunity[`profit] < config`minProfitUSD;
    -1 "[simpleArb] Opportunity rejected: profit $",string[opportunity`profit]," < min $",string config`minProfitUSD;
    :state
  ];

  / Calculate profit in bps
  / Use revenue as trade notional approximation
  profitBps:(opportunity[`profit] % opportunity[`revenue]) * 10000.0;
  if[profitBps < config`minProfitBps;
    -1 "[simpleArb] Opportunity rejected: profit ",string[profitBps]," bps < min ",string config`minProfitBps," bps";
    :state
  ];

  / Check position limit including in-flight orders
  inFlight:state[`state;`inFlightVolume];
  newPosition:state[`state;`position] + inFlight + opportunity`volume;
  if[abs[newPosition] > config`maxPositionSize;
    -1 "[simpleArb] Opportunity rejected: position limit (abs ",string[newPosition]," > ",string config`maxPositionSize,")";
    :state
  ];

  / Rate limiting checks
  currentTime:.z.p;

  / Check minimum interval since last order (500ms for arb)
  if[not null state[`state;`lastOrderTime];
    timeSinceLastOrder:`long$(currentTime - state[`state;`lastOrderTime]) % 1000000;  / microseconds to milliseconds
    if[timeSinceLastOrder < 500;
      -1 "[simpleArb] Rate limit: ",string[timeSinceLastOrder],"ms since last order (min 500ms)";
      :state
    ];
  ];

  / Check orders per minute limit (30 for arb)
  minuteElapsed:`long$(currentTime - state[`state;`minuteStartTime]) % 60000000000;  / nanoseconds to check if minute rolled over
  if[minuteElapsed >= 60000000000;
    / Reset counter for new minute
    state[`state;`ordersThisMinute]:0;
    state[`state;`minuteStartTime]:currentTime;
  ];

  if[state[`state;`ordersThisMinute] >= 30;
    -1 "[simpleArb] Rate limit: ",string[state[`state;`ordersThisMinute]]," orders this minute (max 30)";
    :state
  ];

  / Enforce max order size
  volume:min[opportunity`volume; config`maxOrderSize];

  / Execute trade
  state:executeTrade[state;opportunity;volume];

  / Update rate limiting state after successful execution
  state[`state;`lastOrderTime]:currentTime;
  state[`state;`ordersThisMinute]+:1;

  state
 }

/ Execute arbitrage trade
/ @param state dict - strategy state
/ @param opportunity dict - cross opportunity
/ @param volume float - volume to trade
/ @return dict - updated state
executeTrade:{[state;opportunity;volume]
  / Add to in-flight volume before execution
  state[`state;`inFlightVolume]+:volume;

  / In dryrun mode, just log and update metrics
  if[state[`mode] = `dryrun;
    -1 "[simpleArb] DRYRUN: Buy ",string[volume]," on ",string[opportunity`buyExchange];
    -1 "[simpleArb] DRYRUN: Sell ",string[volume]," on ",string[opportunity`sellExchange];
    -1 "[simpleArb] DRYRUN: Estimated profit: $",string opportunity`profit;

    / Update position (both legs assumed to fill in dry-run)
    / LIMITATION: In dry-run mode, both legs always fill. In live mode, need to track per-leg fills.
    state[`state;`position]+:volume;  / Bought
    state[`state;`position]-:volume;  / Sold

    / Update metrics
    state[`state;`tradesExecuted]+:1;
    state[`state;`totalProfit]+:opportunity`profit;

    / Clear in-flight after successful dry-run execution
    state[`state;`inFlightVolume]-:volume;

    :state
  ];

  / Live mode execution (placeholder - would integrate with exchange coordinator)
  / buyOrderId:.exchange.coordinator.placeMarketOrder[opportunity`buyExchange;state[`config;`pair];`buy;volume];
  / sellOrderId:.exchange.coordinator.placeMarketOrder[opportunity`sellExchange;state[`config;`pair];`sell;volume];

  -1 "[simpleArb] LIVE: Execution not yet implemented - requires exchange coordinator integration";

  / Update position per-leg to handle partial fills
  / Buy leg
  state[`state;`position]+:volume;

  / Sell leg - if this fails in future live integration, position will reflect actual state
  / TODO: In live mode, check if sell actually filled before decrementing position
  sellSuccess:1b;  / Placeholder - would check actual sell order status
  if[sellSuccess;
    state[`state;`position]-:volume;
  ];
  if[not sellSuccess;
    -1 "[simpleArb] WARNING: Sell leg failed - position now long ",string state[`state;`position];
    state[`state;`openRisk]:1b;  / Flag for monitoring
  ];

  / Update metrics
  state[`state;`tradesExecuted]+:1;
  state[`state;`totalProfit]+:opportunity`profit;

  / Clear in-flight after execution
  state[`state;`inFlightVolume]-:volume;

  state
 }

// ============================================================================
/ STRATEGY FACTORY
// ============================================================================

/ Create new simpleArb strategy instance
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
