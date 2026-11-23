/ ============================================================================
/ alpaca.q - Alpaca Markets Exchange Implementation
/ ============================================================================
/ // Provides:
/   - Alpaca exchange registration with stub implementation
/   - Equity trading interface (placeOrder, cancelOrder, etc.)
/   - Balance and position tracking for equities
/   - Integration with Rust connector (future)
/ // Dependencies:
/   - base.q (exchange interface)
/   - registry.q (exchange implementation registry)
/   - types.q (validation)
/ // Asset Class: Equity (US stocks)
/ Trading Hours: 9:30-16:00 ET (regular), 4:00-9:30 and 16:00-20:00 (extended)
/ // Functions:
/   - placeOrder: Place equity order (stub)
/   - cancelOrder: Cancel order (stub)
/   - getBalance: Get cash balance (stub)
/   - getOrderbook: Get orderbook snapshot (stub)
/   - getOpenOrders: Get open orders (stub)
/   - getPosition: Get equity position (stub)
/   - registerAlpaca: Register Alpaca with exchange registry
/ ============================================================================

\d .exchange.alpaca

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Asset class for this exchange
ASSET_CLASS:`equity;

/ Exchange name
EXCHANGE_NAME:`alpaca;

/ Commission (Alpaca is commission-free for stocks)
COMMISSION:0.0;

/ Supported order types for equities
SUPPORTED_ORDER_TYPES:`market`limit`stop_loss`take_profit;

/ Slippage model parameters (basis points)
SLIPPAGE_BP:2.0;  / 2 basis points average slippage

// ============================================================================
// STUB STATE TABLES (in-memory simulation)
// ============================================================================

/ Orders table (stub - simulated orders)
orders:([]
  orderId:`symbol$();
  pair:`symbol$();
  orderType:`symbol$();
  side:`symbol$();
  price:`long$();
  quantity:`long$();
  filled:`long$();
  status:`symbol$();
  timestamp:`timestamp$()
 );

/ Positions table (stub - simulated positions)
positions:([pair:`symbol$()]
  quantity:`long$();
  avgEntryPrice:`long$();
  marketValue:`long$();
  unrealizedPnL:`long$();
  side:`symbol$();
  marginUsed:`long$()
 );

/ Cash balance (stub)
cashBalance:100000.0;  / $100k default paper trading balance

/ Next order ID counter
nextOrderId:1j;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/ Generate order ID
genOrderId:{[]
  oid:`$"ALP_",string[nextOrderId];
  nextOrderId+::1;
  oid
 };

/ Log stub operation
logStub:{[operation;params]
  -1 "  [ALPACA STUB] ",operation," - ",(-3!params);
 };

// ============================================================================
// EXCHANGE API IMPLEMENTATION (STUBS)
// ============================================================================

/ Place order (stub implementation)
/ @param pair symbol - Trading pair (e.g., `AAPL)
/ @param orderType symbol - Order type
/ @param side symbol - Buy or sell
/ @param price long - Order price (null for market)
/ @param quantity long - Order quantity
/ @return dict - Order response
placeOrder:{[pair;orderType;side;price;quantity]
  / Validate order parameters
  .exchange.validateOrderParams[orderType;side;price;quantity];

  / Validate asset class
  if[not .schema.isEquity[pair];
    '"Alpaca only supports equity symbols"];

  / Check market hours (only for regular session)
  if[not .exchange.calendar.isMarketOpen[];
    -1 "  [ALPACA STUB] Warning: Market is closed. Order will be queued.";
  ];

  / Generate order ID
  oid:genOrderId[];

  / Create order record
  `orders insert (oid;pair;orderType;side;price;quantity;0j;`pending;.z.p);

  / Update status to open (simulate immediate acceptance)
  update status:`open from `orders where orderId=oid;

  / Log operation
  logStub["placeOrder";`pair`orderType`side`price`quantity!(pair;orderType;side;price;quantity)];

  / Return order response
  `orderId`pair`orderType`side`price`quantity`filled`status`timestamp`exchange!(
    oid;pair;orderType;side;price;quantity;0j;`open;.z.p;EXCHANGE_NAME
  )
 };

/ Cancel order (stub implementation)
/ @param orderId long - Order ID
/ @return dict - Cancellation response
cancelOrder:{[orderId]
  / Check order exists
  ord:first select from orders where orderId=orderId;
  if[0 = count ord;
    '"Order not found: ",string orderId];

  / Check order is cancellable
  if[not ord[`status] in `open`partially_filled;
    '"Cannot cancel order in status: ",string ord`status];

  / Update status
  update status:`cancelled from `orders where orderId=orderId;

  / Log operation
  logStub["cancelOrder";`orderId!orderId];

  / Return response
  `orderId`status!(orderId;`cancelled)
 };

/ Get balance (stub implementation)
/ @param currency symbol - Currency code (should be `USD for Alpaca)
/ @return dict - Balance dict with amount, available, reserved
getBalance:{[currency]
  / Validate currency
  if[not currency in `USD`CASH;
    '"Alpaca only supports USD cash balance"];

  / Calculate reserved (sum of open buy order notional)
  reserved:exec sum quantity*price from orders where status in `open`partially_filled, side=`buy;
  reserved:$[null reserved;0.0;reserved];

  / Log operation
  logStub["getBalance";`currency!currency];

  / Return balance
  `currency`amount`available`reserved!(currency;cashBalance;cashBalance-reserved;reserved)
 };

/ Get orderbook snapshot (stub implementation)
/ @param pair symbol - Trading pair
/ @return table - Orderbook with bids and asks
getOrderbook:{[pair]
  / Validate asset class
  if[not .schema.isEquity[pair];
    '"Alpaca only supports equity symbols"];

  / Log operation
  logStub["getOrderbook";`pair!pair];

  / Return stub orderbook (5 levels, mock data)
  midPrice:100.0;
  spread:0.02;
  ([]
    side:5#`bid,5#`ask;
    price:midPrice*(1.0-spread%2.0)*1.0 1.0005 1.001 1.0015 1.002,
          midPrice*(1.0+spread%2.0)*1.0 1.0005 1.001 1.0015 1.002;
    quantity:10#100 200 150 300 250;
    timestamp:10#.z.p
  )
 };

/ Get open orders (stub implementation)
/ @param pair symbol - Trading pair
/ @return table - Open orders
getOpenOrders:{[pair]
  / Log operation
  logStub["getOpenOrders";`pair!pair];

  / Return open orders for pair
  select from orders where pair=pair, status in `open`partially_filled
 };

/ Get position (stub implementation)
/ @param pair symbol - Trading pair
/ @return dict - Position dict with quantity, avgEntryPrice, etc.
getPosition:{[pair]
  / Log operation
  logStub["getPosition";`pair!pair];

  / Check if position exists
  if[not pair in key positions;
    :` pair`quantity`avgEntryPrice`marketValue`unrealizedPnL`side`marginUsed!(
      pair;0j;0j;0j;0j;`;0j
    )
  ];

  / Return position
  pos:positions[pair];
  `pair`quantity`avgEntryPrice`marketValue`unrealizedPnL`side`marginUsed!(
    pair;pos`quantity;pos`avgEntryPrice;pos`marketValue;pos`unrealizedPnL;pos`side;pos`marginUsed
  )
 };

// ============================================================================
// REGISTRATION
// ============================================================================

/ Register Alpaca exchange implementation
registerAlpaca:{[]
  / Create implementation dict
  impl:`placeOrder`cancelOrder`getBalance`getOrderbook`getOpenOrders`getPosition!(
    placeOrder;
    cancelOrder;
    getBalance;
    getOrderbook;
    getOpenOrders;
    getPosition
  );

  / Register with registry
  .exchange.registry.register[EXCHANGE_NAME;impl];

  / Log registration
  -1 "  Alpaca exchange registered (asset class: equity, commission: $0)";
 };

\d .

/ Export namespace
-1 "  Alpaca exchange loaded: .exchange.alpaca namespace with stub implementation";
