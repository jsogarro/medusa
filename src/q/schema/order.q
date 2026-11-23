/ ============================================================================
/ order.q - Order Management
/ ============================================================================
/ /
/ Provides:
/   - Order lifecycle tracking (pending → open → filled)
/   - Order CRUD operations with auto-increment IDs
/   - Order queries by status, exchange, actor, time range
/   - Fill tracking and statistics
/ /
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/ /
/ Tables:
/   - order: Trading orders with metadata (keyed by order_id)
/ /
/ Functions:
/   - Commands: createOrder, updateOrderStatus, updateOrderFill, cancelOrder
/   - Queries: getOrder, getOrdersByStatus, getOrdersByExchange, getOpenOrders,
/              getOrdersByActor, getRecentOrders
/   - Analytics: getTotalVolume, getActorFillRate, getAvgExecutionTime
/ ============================================================================

\d .qg

// ============================================================================
// ORDER TABLE SCHEMA
// ============================================================================

orderSchema:([]
  order_id: `long$();                    / Unique order ID (auto-increment, PK)
  unique_id: `guid$();                   / GUID for distributed systems
  exchange_name: `symbol$();             / Foreign key to Exchange.name
  exchange_order_id: `symbol$();         / Exchange's order ID
  status: `symbol$();                    / Order status (pending/open/filled/etc.)
  order_type: `symbol$();                / Order type (market/limit/etc.)
  actor: `symbol$();                     / Strategy/actor that created order
  price: `long$();                       / Order price (fixed precision)
  price_currency: `symbol$();            / Price currency (e.g., USD)
  volume: `long$();                      / Order volume (fixed precision)
  volume_currency: `symbol$();           / Volume currency (e.g., BTC)
  filled_volume: `long$();               / Volume filled so far
  exchange_rate: `float$();              / Exchange rate at time of order
  fundamental_value: `long$();           / Fair value estimate (fixed precision)
  competitiveness: `float$();            / How competitive the price is (0-1)
  spread: `long$();                      / Spread at time of order (fixed precision)
  time_created: `timestamp$();           / Order creation time
  time_executed: `timestamp$();          / Order execution time (null if pending)
  time_updated: `timestamp$();           / Last update time
  meta_data: ()                          / Dictionary of order-specific metadata
 );

// Primary key: order_id
// Indices: exchange_name, status, time_created

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

initOrderTable:{[]
  order::orderSchema;
  .qg.publishTable[`order];
 };

// ============================================================================
// CRUD OPERATIONS - ORDER
// ============================================================================

// Create new order
// Usage: .qg.createOrder[`coinbase; `limit; `strategy1; `BTC; `USD; 1000000j; 50000000000j; ...]
createOrder:{[args]
  exchangeName:args 0;
  orderType:args 1;
  actor:args 2;
  volumeCurrency:args 3;
  priceCurrency:args 4;
  volume:args 5;
  price:args 6;
  fundamentalValue:args 7;
  competitiveness:args 8;
  spread:args 9;
  metaData:args 10;

  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not .qg.isValidOrderType[orderType];
    '"Invalid order type"];
  if[not .qg.isValidCurrency[volumeCurrency];
    '"Invalid volume currency"];
  if[not .qg.isValidCurrency[priceCurrency];
    '"Invalid price currency"];
  if[not .qg.isPositiveAmount[volume];
    '"Volume must be positive"];
  if[(orderType=`limit) and not .qg.isValidPrice[price];
    '"Limit orders require valid price"];

  / Generate new order ID and GUID
  ordId:.qg.nextId[`order];
  guid:first 1?0Ng;

  / Insert order
  order::order,enlist `order_id`unique_id`exchange_name`exchange_order_id`status`order_type`actor`price`price_currency`volume`volume_currency`filled_volume`exchange_rate`fundamental_value`competitiveness`spread`time_created`time_executed`time_updated`meta_data!(
    ordId;
    guid;
    exchangeName;
    `;
    `pending;
    orderType;
    actor;
    price;
    priceCurrency;
    volume;
    volumeCurrency;
    0j;
    1.0;
    fundamentalValue;
    competitiveness;
    spread;
    .z.p;
    .qg.NULL_TIMESTAMP;
    .z.p;
    metaData
  );
  .qg.publishTable[`order];

  ordId
 };

// Update order status
updateOrderStatus:{[orderId; newStatus; exchangeOrderId]
  / Validate status
  if[not .qg.isValidOrderStatus[newStatus];
    '"Invalid order status"];

  / Get current order
  ord:first select from order where order_id=orderId;
  if[0 = count ord; '"Order not found"];

  / Check valid status transition
  validTransitions:`pending`open`filled`cancelled`partially_filled`rejected`expired;
  if[not newStatus in validTransitions;
    '"Invalid status transition"];

  / Update order
  execTime:$[newStatus in `filled`partially_filled; .z.p; ord`time_executed];
  order::update status:newStatus,
    exchange_order_id:exchangeOrderId,
    time_executed:execTime,
    time_updated:.z.p
    from order where order_id=orderId;
  .qg.publishTable[`order];

  orderId
 };

// Update order fill
updateOrderFill:{[orderId; filledVolume]
  / Validate
  ord:first select from order where order_id=orderId;
  if[0 = count ord; '"Order not found"];
  if[filledVolume > ord[`volume];
    '"Filled volume cannot exceed order volume"];

  / Determine new status
  newStatus:$[
    filledVolume = ord[`volume]; `filled;
    filledVolume > 0j; `partially_filled;
    ord[`status]
  ];

  / Update order
  execTime:$[newStatus in `filled`partially_filled; .z.p; ord`time_executed];
  order::update filled_volume:filledVolume,
    status:newStatus,
    time_executed:execTime,
    time_updated:.z.p
    from order where order_id=orderId;
  .qg.publishTable[`order];

  orderId
 };

// Cancel order
cancelOrder:{[orderId]
  / Get order
  ord:first select from order where order_id=orderId;
  if[0 = count ord; '"Order not found"];

  / Check if cancellable
  if[ord[`status] in `filled`cancelled`rejected;
    '"Cannot cancel order in status: ", string ord[`status]];

  / Cancel
  order::update status:`cancelled, time_updated:.z.p
    from order where order_id=orderId;
  .qg.publishTable[`order];

  orderId
 };

// Get order by ID
getOrder:{[orderId]
  first select from order where order_id=orderId
 };

// Get orders by status
getOrdersByStatus:{[status]
  select from order where status=status
 };

// Get orders by exchange
getOrdersByExchange:{[exchangeName]
  select from order where exchange_name=exchangeName
 };

// Get open orders
getOpenOrders:{[]
  select from order where status in `pending`open`partially_filled
 };

// Get orders by actor/strategy
getOrdersByActor:{[actor]
  select from order where actor=actor
 };

// Get recent orders (last N)
getRecentOrders:{[n]
  idx:n sublist idesc exec time_created from order;
  order idx
 };

// ============================================================================
// QUERY FUNCTIONS
// ============================================================================

// Calculate total volume for exchange/currency pair
getTotalVolume:{[exchangeName; currency; startTime; endTime]
  exec sum volume from order
    where exchange_name=exchangeName,
          volume_currency=currency,
          time_created within (startTime; endTime),
          status=`filled
 };

// Get fill rate for actor/strategy
getActorFillRate:{[actor]
  stats:select
    totalOrders:count i,
    filledOrders:sum status=`filled,
    partialOrders:sum status=`partially_filled,
    totalVolume:sum volume,
    filledVolume:sum filled_volume
    from order where actor=actor;

  stats,(`fillRate`volumeFillRate)!(
    stats[`filledOrders] % stats[`totalOrders];
    stats[`filledVolume] % stats[`totalVolume]
  )
 };

// Get average execution time for filled orders
getAvgExecutionTime:{[exchangeName]
  exec avg time_executed - time_created
    from order
    where exchange_name=exchangeName, status=`filled
 };

\d .

/ Export namespace
-1 "  Order table loaded: order with CRUD operations and query functions";
