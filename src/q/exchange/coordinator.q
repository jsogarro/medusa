/ ============================================================================
/ coordinator.q - Exchange Coordinator for Multi-Exchange Orchestration
/ ============================================================================
/
/ Provides:
/   - Multi-exchange connection management
/   - Order routing across exchanges
/   - Balance management and fund allocation
/   - Cross-exchange position aggregation
/   - Exchange health monitoring
/
/ Dependencies:
/   - base.q (exchange interface)
/   - registry.q (exchange implementation registry)
/
/ Functions:
/   - init: Initialize coordinator
/   - connect: Connect to exchange
/   - disconnect: Disconnect from exchange
/   - placeOrder: Place order with routing
/   - cancelOrder: Cancel order
/   - getBalance: Get balance across exchanges
/   - getAllBalances: Get balances for all exchanges
/   - getPosition: Get position across exchanges
/   - getAllPositions: Get positions across all exchanges
/   - getHealthStatus: Get exchange health status
/ ============================================================================

\d .exchange.coordinator

// ============================================================================
// STATE TABLES
// ============================================================================

/ Exchange connections (keyed by exchange)
connections:([exchange:`symbol$()]
  connected:`boolean$();
  lastHeartbeat:`timestamp$();
  errorCount:`long$();
  lastError:()
 );

/ Balance cache (keyed by exchange and currency)
balances:([exchange:`symbol$(); currency:`symbol$()]
  amount:`float$();
  available:`float$();
  reserved:`float$();
  lastUpdate:`timestamp$()
 );

/ Position cache (keyed by exchange and pair)
positions:([exchange:`symbol$(); pair:`symbol$()]
  quantity:`float$();
  avgPrice:`float$();
  unrealizedPnL:`float$();
  lastUpdate:`timestamp$()
 );

/ Order routing state (keyed by order ID)
orderRouting:([orderId:`symbol$()]
  exchange:`symbol$();
  routedAt:`timestamp$();
  status:`symbol$()
 );

/ Coordinator mode (dryrun or live)
coordinatorMode:`dryrun;

/ Atomic order ID counter
orderIdCounter:0;

// ============================================================================
/ CONFIGURATION
// ============================================================================

/ Cache TTL in milliseconds
balanceCacheTTL:5000;
positionCacheTTL:5000;

/ Health check interval in milliseconds
healthCheckInterval:10000;

/ Maximum error count before marking exchange unhealthy
maxErrorCount:5;

// ============================================================================
/ INITIALIZATION
// ============================================================================

/ Initialize coordinator
/ @return boolean - Success status
init:{[]
  / Clear all state
  connections::0#connections;
  balances::0#balances;
  positions::0#positions;
  orderRouting::0#orderRouting;
  coordinatorMode::`dryrun;
  orderIdCounter::0;

  / Log initialization
  -1 "  Exchange coordinator initialized (mode: dryrun)";

  1b
 };

/ Set coordinator mode (dryrun or live)
/ @param mode symbol - Mode to set (`dryrun or `live)
/ @return boolean - Success status
setMode:{[mode]
  if[not mode in `dryrun`live;
    '"Invalid mode. Must be `dryrun or `live"];

  coordinatorMode::mode;
  -1 "  Coordinator mode set to: ",string mode;

  1b
 };

// ============================================================================
/ CONNECTION MANAGEMENT
// ============================================================================

/ Connect to exchange
/ @param exchangeName symbol - Exchange name
/ @return boolean - Success status
connect:{[exchangeName]
  / Validate exchange is registered
  if[not .exchange.registry.isRegistered[exchangeName];
    '"Exchange not registered: ",string exchangeName];

  / Check if already connected
  if[exchangeName in key connections;
    if[connections[exchangeName;`connected];
      -1 "  Exchange already connected: ",string exchangeName;
      :1b;
    ];
  ];

  / Add to connections table
  newRow:(enlist exchangeName)!(1b;.z.p;0j;());
  connections,:newRow;

  / Initialize balances for this exchange
  / (Will be populated on first getBalance call)

  / Log connection
  -1 "  Connected to exchange: ",string exchangeName;

  1b
 };

/ Disconnect from exchange
/ @param exchangeName symbol - Exchange name
/ @return boolean - Success status
disconnect:{[exchangeName]
  / Remove from connections
  connections::delete exchangeName from connections;

  / Clear cached data for this exchange
  balances::delete from balances where exchange=exchangeName;
  positions::delete from positions where exchange=exchangeName;

  / Log disconnection
  -1 "  Disconnected from exchange: ",string exchangeName;

  1b
 };

/ Check if exchange is connected
/ @param exchangeName symbol - Exchange name
/ @return boolean - True if connected
isConnected:{[exchangeName]
  (exchangeName in key connections) and connections[exchangeName;`connected]
 };

// ============================================================================
/ ORDER ROUTING
// ============================================================================

/ Place order with routing
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param orderType symbol - Order type
/ @param side symbol - Buy or sell
/ @param price long - Order price (null for market)
/ @param quantity long - Order quantity
/ @return dict - Order response
placeOrder:{[exchangeName;pair;orderType;side;price;quantity]
  / Validate exchange connection
  if[not isConnected[exchangeName];
    '"Exchange not connected: ",string exchangeName];

  / Input validation
  if[not null price; if[price <= 0; '"Invalid price: must be > 0"]];
  if[quantity <= 0; '"Invalid quantity: must be > 0"];
  if[not side in `buy`sell; '"Invalid side: must be `buy or `sell"];
  if[null pair; '"Invalid pair: pair cannot be null"];

  / Generate orderId using atomic counter
  orderIdCounter+:1;
  orderId:`$"ORD_",string[orderIdCounter],"_",string[exchangeName];

  / Check for duplicate order (race condition prevention)
  if[orderId in key orderRouting;
    '"Duplicate order detected: ",string orderId];

  / Record routing as pending BEFORE placement
  orderRouting[orderId]:(exchangeName;.z.p;`pending);

  / Check mode - in dryrun mode, simulate order placement
  result:$[coordinatorMode=`dryrun;
    [
      / Dry-run mode: simulate order placement
      -1 "  [DRY-RUN] Simulating order placement: ",string orderId;
      `orderId`status`exchange`pair`side`price`quantity!(orderId;`simulated;exchangeName;pair;side;price;quantity)
    ];
    [
      / Live mode: delegate to exchange implementation
      .exchange.placeOrder[exchangeName;pair;orderType;side;price;quantity]
    ]
  ];

  / Update routing status to open
  if[`orderId in key result;
    orderRouting[result`orderId;`status]:`open;
  ];

  / Invalidate balance cache for this exchange after order placement
  / Delete balance cache entries for all currencies on this exchange
  balances::delete from balances where exchange=exchangeName;

  / Update health (successful operation)
  updateHealth[exchangeName;1b];

  result
 };

/ Cancel order
/ @param exchangeName symbol - Exchange name
/ @param orderId long - Order ID
/ @return dict - Cancellation response
cancelOrder:{[exchangeName;orderId]
  / Validate exchange connection
  if[not isConnected[exchangeName];
    '"Exchange not connected: ",string exchangeName];

  / Delegate to exchange implementation
  result:.exchange.cancelOrder[exchangeName;orderId];

  / Update routing status
  if[orderId in key orderRouting;
    orderRouting[orderId;`status]:`cancelled;
  ];

  / Update health
  updateHealth[exchangeName;1b];

  result
 };

// ============================================================================
/ BALANCE MANAGEMENT
// ============================================================================

/ Get balance for currency on exchange
/ @param exchangeName symbol - Exchange name
/ @param currency symbol - Currency code
/ @return dict - Balance dict with amount, available, reserved
getBalance:{[exchangeName;currency]
  / Check cache first
  cacheKey:(exchangeName;currency);

  if[cacheKey in key balances;
    cached:balances[cacheKey];
    / Check if cache is fresh
    age:.z.p - cached`lastUpdate;
    if[age < balanceCacheTTL;
      :cached;
    ];
  ];

  / Cache miss or stale - query exchange
  balance:@[.exchange.getBalance;(exchangeName;currency);{
    -1 "  Error getting balance: ",x;
    updateHealth[exchangeName;0b];
    `amount`available`reserved`error!(0.0;0.0;0.0;x)
  }];

  / Update health if successful
  if[not `error in key balance;
    updateHealth[exchangeName;1b];

    / Update cache using proper keyed table upsert
    balance[`lastUpdate]:.z.p;
    balances[cacheKey]:(balance`amount;balance`available;balance`reserved;balance`lastUpdate);
  ];

  balance
 };

/ Get all balances for exchange
/ @param exchangeName symbol - Exchange name
/ @return table - Balances for all currencies
getAllBalances:{[exchangeName]
  / Validate connection
  if[not isConnected[exchangeName];
    '"Exchange not connected: ",string exchangeName];

  / Get all balances from cache for this exchange
  select from balances where exchange=exchangeName
 };

/ Refresh balance cache for exchange
/ @param exchangeName symbol - Exchange name
/ @param currency symbol - Currency code
/ @return dict - Updated balance
refreshBalance:{[exchangeName;currency]
  / Force cache refresh by deleting entry
  balances::delete from balances where exchange=exchangeName, currency=currency;

  / Fetch fresh balance
  getBalance[exchangeName;currency]
 };

// ============================================================================
/ POSITION AGGREGATION
// ============================================================================

/ Get position for pair on exchange
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return dict - Position dict
getPosition:{[exchangeName;pair]
  / Check cache first
  cacheKey:(exchangeName;pair);

  if[cacheKey in key positions;
    cached:positions[cacheKey];
    / Check if cache is fresh
    age:.z.p - cached`lastUpdate;
    if[age < positionCacheTTL;
      :cached;
    ];
  ];

  / Cache miss or stale - query exchange
  position:@[.exchange.getPosition;(exchangeName;pair);{
    -1 "  Error getting position: ",x;
    updateHealth[exchangeName;0b];
    `quantity`avgPrice`unrealizedPnL`error!(0.0;0.0;0.0;x)
  }];

  / Update health if successful
  if[not `error in key position;
    updateHealth[exchangeName;1b];

    / Update cache using proper keyed table upsert
    position[`lastUpdate]:.z.p;
    positions[cacheKey]:(position`quantity;position`avgPrice;position`unrealizedPnL;position`lastUpdate);
  ];

  position
 };

/ Get all positions across exchanges for a pair
/ @param pair symbol - Trading pair
/ @return table - Positions across all connected exchanges
getAllPositions:{[pair]
  / Get positions from all connected exchanges
  connectedExchanges:exec exchange from connections where connected;

  / Query each exchange
  positions:raze {[pair;ex]
    pos:getPosition[ex;pair];
    if[not `error in key pos;
      enlist `exchange`pair`quantity`avgPrice`unrealizedPnL!(ex;pair;pos`quantity;pos`avgPrice;pos`unrealizedPnL)
    ]
  }[pair] each connectedExchanges;

  / Return as table
  flip positions
 };

/ Calculate aggregate position across all exchanges
/ @param pair symbol - Trading pair
/ @return dict - Aggregated position
getAggregatePosition:{[pair]
  / Get all positions
  allPositions:getAllPositions[pair];

  / Calculate aggregate
  if[0=count allPositions;
    :`quantity`avgPrice`unrealizedPnL!(0.0;0.0;0.0)
  ];

  / Sum quantities
  totalQuantity:sum exec quantity from allPositions;

  / Weighted average price (corrected for mixed long/short positions)
  if[totalQuantity=0;
    :`quantity`avgPrice`unrealizedPnL!(0.0;0.0;0.0)
  ];

  / Separate long and short positions
  longPositions:select from allPositions where quantity > 0;
  shortPositions:select from allPositions where quantity < 0;

  / Calculate weighted average for the net direction
  weightedAvg:$[
    totalQuantity > 0;
    / Net long: use long positions' weighted avg
    sum[exec quantity*avgPrice from longPositions] % sum[exec quantity from longPositions];
    totalQuantity < 0;
    / Net short: use short positions' weighted avg
    sum[exec quantity*avgPrice from shortPositions] % sum[exec quantity from shortPositions];
    / Flat
    0.0
  ];

  totalPnL:sum exec unrealizedPnL from allPositions;

  `quantity`avgPrice`unrealizedPnL!(totalQuantity;weightedAvg;totalPnL)
 };

// ============================================================================
/ HEALTH MONITORING
// ============================================================================

/ Update exchange health status
/ @param exchangeName symbol - Exchange name
/ @param success boolean - Whether operation succeeded
updateHealth:{[exchangeName;success]
  / Update last heartbeat
  connections[exchangeName;`lastHeartbeat]:.z.p;

  / Update error count
  if[success;
    / Reset error count on success
    connections[exchangeName;`errorCount]:0j;
    connections[exchangeName;`lastError]:();
  ];

  if[not success;
    / Increment error count
    currentErrors:connections[exchangeName;`errorCount];
    connections[exchangeName;`errorCount]:currentErrors+1;
    connections[exchangeName;`lastError]:.z.p;

    / Mark as disconnected if error threshold exceeded
    if[currentErrors >= maxErrorCount;
      connections[exchangeName;`connected]:0b;
      -1 "  Exchange marked unhealthy due to errors: ",string exchangeName;
    ];
  ];
 };

/ Get health status for exchange
/ @param exchangeName symbol - Exchange name
/ @return dict - Health status
getHealthStatus:{[exchangeName]
  if[not exchangeName in key connections;
    :`status`error!(`unknown;"Exchange not in connections table")
  ];

  conn:connections[exchangeName];

  / Check connection status
  if[not conn`connected;
    :`status`errorCount`lastError!(`disconnected;conn`errorCount;conn`lastError)
  ];

  / Check heartbeat age
  age:.z.p - conn`lastHeartbeat;
  isStale:age > healthCheckInterval;

  `status`errorCount`lastHeartbeat`age`stale!(
    $[isStale;`stale;`healthy];
    conn`errorCount;
    conn`lastHeartbeat;
    age;
    isStale
  )
 };

/ Get health status for all exchanges
/ @return table - Health status for all connected exchanges
getAllHealthStatus:{[]
  {[ex]
    status:getHealthStatus[ex];
    status[`exchange]:ex;
    status
  } each exec exchange from connections
 };

\d .

/ Export namespace
-1 "  Exchange coordinator loaded: .exchange.coordinator namespace";
