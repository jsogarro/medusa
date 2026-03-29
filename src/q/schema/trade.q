/ ============================================================================
/ trade.q - Trade Execution Tracking
/ ============================================================================
/
/ Provides:
/   - Trade recording linked to orders
/   - Volume-weighted average price (VWAP) calculation
/   - Trade statistics and analytics
/   - Realized P&L calculation
/
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/   - order.q (FK: order_id)
/
/ Tables:
/   - trade: Executed trades (keyed by trade_id, FK to order_id)
/
/ Functions:
/   - Commands: createTrade, updateTrade
/   - Queries: getTrade, getTradesForOrder, getTradesByExchange, getTradesByType,
/              getRecentTrades, getTradesInRange
/   - Analytics: getTotalTradeVolume, getTotalFees, getVWAP, getTradeStats,
/                getRealizedPnL, getOrderTradeBreakdown
/ ============================================================================

\d .qg

// ============================================================================
// TRADE TABLE SCHEMA
// ============================================================================

tradeSchema:([]
  trade_id: `long$();                    / Unique trade ID (auto-increment, PK)
  unique_id: `guid$();                   / GUID for distributed systems
  exchange_name: `symbol$();             / Foreign key to Exchange.name
  exchange_trade_id: `symbol$();         / Exchange's trade ID
  order_id: `long$();                    / Foreign key to Order.order_id
  trade_type: `symbol$();                / Trade type (buy/sell)
  price: `long$();                       / Execution price (fixed precision)
  price_currency: `symbol$();            / Price currency
  volume: `long$();                      / Trade volume (fixed precision)
  volume_currency: `symbol$();           / Volume currency
  fee: `long$();                         / Trading fee (fixed precision)
  fee_currency: `symbol$();              / Fee currency
  time_created: `timestamp$();           / Trade execution timestamp
  time_updated: `timestamp$();           / Last update timestamp
  meta_data: ()                          / Dictionary of trade-specific metadata
 );

// Primary key: trade_id
// Foreign key: order_id
// Indices: exchange_name, order_id, time_created

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

initTradeTable:{[]
  trade::tradeSchema;

  / Create primary key
  `trade_id xkey `trade;
 };

// ============================================================================
// CRUD OPERATIONS - TRADE
// ============================================================================

// Record new trade
// Usage: .qg.createTrade[`coinbase; `EXCH_TRD_123; 42j; `buy; 1000000j; 50000000000j; `BTC; `USD; 25000j; `USD; ...]
createTrade:{[exchangeName; exchangeTradeId; orderId; tradeType;
               volume; price; volumeCurrency; priceCurrency;
               fee; feeCurrency; metaData]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not .qg.isValidTradeType[tradeType];
    '"Invalid trade type"];
  if[not .qg.isValidCurrency[volumeCurrency];
    '"Invalid volume currency"];
  if[not .qg.isValidCurrency[priceCurrency];
    '"Invalid price currency"];
  if[not .qg.isValidCurrency[feeCurrency];
    '"Invalid fee currency"];
  if[not .qg.isPositiveAmount[volume];
    '"Volume must be positive"];
  if[not .qg.isValidPrice[price];
    '"Invalid price"];

  / Validate order exists
  ord:first select from order where order_id=orderId;
  if[0 = count ord; '"Order not found"];

  / Generate new trade ID and GUID
  trdId:.qg.nextId[`trade];
  guid:.Q.w[];

  / Insert trade
  `trade insert (
    trdId;                               / trade_id
    guid;                                / unique_id
    exchangeName;                        / exchange_name
    exchangeTradeId;                     / exchange_trade_id
    orderId;                             / order_id
    tradeType;                           / trade_type
    price;                               / price
    priceCurrency;                       / price_currency
    volume;                              / volume
    volumeCurrency;                      / volume_currency
    fee;                                 / fee
    feeCurrency;                         / fee_currency
    .z.p;                                / time_created
    .z.p;                                / time_updated
    metaData                             / meta_data
  );

  / Update order filled volume
  currentFilled:ord[`filled_volume];
  newFilled:currentFilled + volume;
  .qg.updateOrderFill[orderId; newFilled];

  trdId
 };

// Update trade metadata
updateTrade:{[tradeId; metaData]
  update meta_data:metaData, time_updated:.z.p
    from `trade where trade_id=tradeId;

  tradeId
 };

// Get trade by ID
getTrade:{[tradeId]
  first select from trade where trade_id=tradeId
 };

// Get trades for order
getTradesForOrder:{[orderId]
  select from trade where order_id=orderId
 };

// Get trades by exchange
getTradesByExchange:{[exchangeName]
  select from trade where exchange_name=exchangeName
 };

// Get trades by type
getTradesByType:{[tradeType]
  select from trade where trade_type=tradeType
 };

// Get recent trades
getRecentTrades:{[n]
  idx:n sublist idesc exec time_created from trade;
  trade idx
 };

// Get trades in time range
getTradesInRange:{[startTime; endTime]
  select from trade where time_created within (startTime; endTime)
 };

// ============================================================================
// QUERY FUNCTIONS
// ============================================================================

// Calculate total volume traded
getTotalTradeVolume:{[exchangeName; currency; startTime; endTime]
  exec sum volume from trade
    where exchange_name=exchangeName,
          volume_currency=currency,
          time_created within (startTime; endTime)
 };

// Calculate total fees paid
getTotalFees:{[exchangeName; currency; startTime; endTime]
  exec sum fee from trade
    where exchange_name=exchangeName,
          fee_currency=currency,
          time_created within (startTime; endTime)
 };

// Get volume-weighted average price (VWAP) - Single-pass aggregation
getVWAP:{[exchangeName; volumeCurrency; priceCurrency; startTime; endTime]
  result:exec (sum price * volume) % sum volume from trade
    where exchange_name=exchangeName,
          volume_currency=volumeCurrency,
          price_currency=priceCurrency,
          time_created within (startTime; endTime);

  $[()~result; .qg.NULL_LONG; result]  / Return null if no trades
 };

// Get trade statistics for exchange
getTradeStats:{[exchangeName; startTime; endTime]
  trades:select from trade
    where exchange_name=exchangeName,
          time_created within (startTime; endTime);

  select
    currency:volume_currency,
    tradeCount:count i,
    totalVolume:sum volume,
    avgPrice:avg price,
    minPrice:min price,
    maxPrice:max price,
    totalFees:sum fee,
    buyCount:sum trade_type=`buy,
    sellCount:sum trade_type=`sell
    by volume_currency, price_currency
    from trades
 };

// Calculate realized P&L from paired buy/sell trades
getRealizedPnL:{[volumeCurrency; priceCurrency; startTime; endTime]
  / Get all trades in range
  trades:select from trade
    where volume_currency=volumeCurrency,
          price_currency=priceCurrency,
          time_created within (startTime; endTime);

  / Separate buys and sells
  buys:select from trades where trade_type=`buy;
  sells:select from trades where trade_type=`sell;

  / Calculate total cost and proceeds
  totalCost:exec sum (price * volume) + fee from buys;
  totalProceeds:exec sum (price * volume) - fee from sells;

  / Realized P&L
  totalProceeds - totalCost
 };

// Get trade breakdown by order
getOrderTradeBreakdown:{[orderId]
  trades:select from trade where order_id=orderId;

  select
    tradeCount:count i,
    totalVolume:sum volume,
    avgPrice:avg price,
    totalFees:sum fee,
    firstTrade:min time_created,
    lastTrade:max time_created
    from trades
 };

\d .

/ Export namespace
-1 "  Trade table loaded: trade with CRUD operations and analytics functions";
