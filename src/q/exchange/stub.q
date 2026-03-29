/ ============================================================================
/ stub.q - Stubbed Exchange Implementation
/ ============================================================================
/
/ Provides:
/   - Complete in-memory simulated exchange for testing
/   - Synthetic orderbook generation with configurable parameters
/   - Order matching engine with realistic fill simulation
/   - Balance tracking with holds for open orders
/   - Configurable latency and slippage models
/
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/   - base.q (order states and validation)
/   - registry.q (registration)
/
/ State Tables:
/   - .exchange.stub.balances: Currency balances
/   - .exchange.stub.holds: Reserved balances for open orders
/   - .exchange.stub.orders: In-memory order book
/   - .exchange.stub.fills: Trade fills
/
/ Functions:
/   - init: Initialize stub with configuration
/   - placeOrder: Submit and match order
/   - cancelOrder: Cancel open order
/   - getBalance: Get currency balance
/   - getOrderbook: Get synthetic orderbook
/   - getOpenOrders: Get open orders
/   - getPosition: Get position (stub)
/ ============================================================================

\d .exchange.stub

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Stub exchange configuration
config:`symbol`tickSize`minQty`maxQty`feeRate`latencyMs!(`;0.01;0.001;1000.0;0.001;10);

/ Orderbook generation parameters
obParams:`midPrice`spread`depth`volatility`tickSize!(100.0;0.02;10;0.001;0.01);

// ============================================================================
// STATE TABLES
// ============================================================================

/ Balances: currency -> amount
balances:()!();

/ Holds: currency -> held amount
holds:()!();

/ Orders table
ordersSchema:([]
  orderId:`long$();
  pair:`symbol$();
  orderType:`symbol$();
  side:`symbol$();
  price:`long$();
  quantity:`long$();
  filled:`long$();
  status:`symbol$();
  timestamp:`timestamp$()
 );
orders:ordersSchema;

/ Fills table
fillsSchema:([]
  fillId:`long$();
  orderId:`long$();
  price:`long$();
  quantity:`long$();
  fee:`long$();
  timestamp:`timestamp$()
 );
fills:fillsSchema;

/ Next order ID
nextOrderId:1j;

/ Next fill ID
nextFillId:1j;

/ Random seed for deterministic orderbook generation
seed:42;

// ============================================================================
// INITIALIZATION
// ============================================================================

/ Initialize stub exchange
/ @param cfg dict - Configuration overrides (optional)
/ @return dict - Configuration
init:{[cfg]
  / Apply configuration overrides
  if[count cfg;
    config,:cfg
  ];

  / Initialize state
  balances::()!();
  holds::()!();
  orders::ordersSchema;
  fills::fillsSchema;
  nextOrderId::1j;
  nextFillId::1j;

  / Log initialization
  -1 "  Stub exchange initialized";

  config
 };

/ Set starting balances
/ @param balancesDict dict - Currency -> amount
setBalances:{[balancesDict]
  balances::balancesDict;
  holds::balancesDict!count[balancesDict]#0.0;
 };

/ Set orderbook parameters
/ @param params dict - Orderbook generation parameters
setOBParams:{[params]
  obParams,:params;
 };

// ============================================================================
// BALANCE OPERATIONS
// ============================================================================

/ Get total balance
/ @param currency symbol - Currency code
/ @return float - Total balance
getTotalBalance:{[currency]
  $[currency in key balances; balances[currency]; 0.0]
 };

/ Get available balance (total - holds)
/ @param currency symbol - Currency code
/ @return float - Available balance
getAvailableBalance:{[currency]
  total:getTotalBalance[currency];
  hold:$[currency in key holds; holds[currency]; 0.0];
  total - hold
 };

/ Place hold on balance
/ @param currency symbol - Currency code
/ @param amount float - Amount to hold
placeHold:{[currency;amount]
  available:getAvailableBalance[currency];
  if[amount > available;
    '"Insufficient available balance"
  ];

  / Initialize hold if doesn't exist
  if[not currency in key holds;
    holds[currency]:0.0
  ];

  holds[currency]+:amount;
 };

/ Release hold on balance
/ @param currency symbol - Currency code
/ @param amount float - Amount to release
releaseHold:{[currency;amount]
  if[not currency in key holds;
    '"No holds for currency"
  ];

  current:holds[currency];
  if[amount > current;
    '"Cannot release more than held"
  ];

  holds[currency]-:amount;
 };

/ Update balance (add or subtract)
/ @param currency symbol - Currency code
/ @param delta float - Amount to add (positive) or subtract (negative)
updateBalance:{[currency;delta]
  / Initialize balance if doesn't exist
  if[not currency in key balances;
    balances[currency]:0.0
  ];

  newBalance:balances[currency] + delta;
  if[newBalance < 0.0;
    '"Balance cannot go negative"
  ];

  balances[currency]:newBalance;
 };

// ============================================================================
// SYNTHETIC ORDERBOOK GENERATION
// ============================================================================

/ Generate price levels around mid
/ @param mid float - Mid price
/ @param spread float - Bid-ask spread (fraction)
/ @param depth long - Number of levels per side
/ @param tick float - Tick size
/ @return dict - Bid and ask price arrays
genPriceLevels:{[mid;spread;depth;tick]
  half:mid * (spread % 2.0);
  bidMid:mid - half;
  askMid:mid + half;

  / Geometric spacing (tighter near top)
  ratios:1.0 + (til depth) * 0.001;

  bidPrices:reverse tick * floor (bidMid * reverse ratios) % tick;
  askPrices:tick * ceiling (askMid * ratios) % tick;

  `bid`ask!(bidPrices;askPrices)
 };

/ Generate realistic quantities (exponential distribution)
/ @param n long - Number of levels
/ @param minQty float - Minimum quantity
/ @param maxQty float - Maximum quantity
/ @return float[] - Quantities
genQuantities:{[n;minQty;maxQty]
  / Use seed for deterministic results
  seed+::1;
  .Q.srand seed;

  / Exponential distribution
  vals:n?1.0;
  exp:neg log 1.0 - vals;
  / Scale to range
  scaled:minQty + (exp % max exp) * (maxQty - minQty);
  scaled
 };

/ Generate synthetic orderbook
/ @return table - Orderbook with bid/ask levels
genOrderbook:{[]
  levels:genPriceLevels[
    obParams`midPrice;
    obParams`spread;
    obParams`depth;
    obParams`tickSize
  ];

  n:obParams`depth;
  bidQty:genQuantities[n;config`minQty;config`maxQty];
  askQty:genQuantities[n;config`minQty;config`maxQty];

  / Build orderbook table
  ob:([]
    side:n#`bid,n#`ask;
    price:levels[`bid],levels[`ask];
    quantity:bidQty,askQty;
    timestamp:2*n#.z.p
  );

  / Sort: bids descending, asks ascending
  bidOB:`price xdesc select from ob where side=`bid;
  askOB:`price xasc select from ob where side=`ask;

  bidOB,askOB
 };

// ============================================================================
// ORDER MATCHING ENGINE
// ============================================================================

/ Submit order and attempt to match
/ @param pair symbol - Trading pair
/ @param orderType symbol - Order type
/ @param side symbol - Buy or sell
/ @param price long - Order price (null for market)
/ @param quantity long - Order quantity
/ @return dict - Order response
submitOrder:{[pair;orderType;side;price;quantity]
  / Validate order parameters
  .exchange.validateOrderParams[orderType;side;price;quantity];

  / Assign order ID
  oid:nextOrderId;
  nextOrderId+::1;

  / Extract currencies from pair (assume XXXYYY format)
  pairStr:string pair;
  baseCurrency:`$3#pairStr;
  quoteCurrency:`$-3#pairStr;

  / Place hold for buy orders (need quote currency)
  if[side=`buy;
    required:$[orderType=`market;
      quantity * obParams`midPrice * 1.1;  / Market orders: use mid + buffer
      quantity * .qg.fromPrice[price]
    ];
    placeHold[quoteCurrency;required]
  ];

  / Place hold for sell orders (need base currency)
  if[side=`sell;
    placeHold[baseCurrency;.qg.fromVolume[quantity]]
  ];

  / Create order record
  `orders insert (oid;pair;orderType;side;price;quantity;0j;`pending;.z.p);

  / Update status to open
  update status:`open from `orders where orderId=oid;

  / Attempt to match
  matchResult:matchOrder[oid;baseCurrency;quoteCurrency];

  / Get final order state
  ord:first select from orders where orderId=oid;

  / Return order response
  `orderId`pair`orderType`side`price`quantity`filled`status`timestamp!(
    oid;pair;orderType;side;price;quantity;ord`filled;ord`status;ord`timestamp
  )
 };

/ Match order against synthetic orderbook
/ @param orderId long - Order ID
/ @param baseCurrency symbol - Base currency
/ @param quoteCurrency symbol - Quote currency
/ @return dict - Match result
matchOrder:{[orderId;baseCurrency;quoteCurrency]
  ord:first select from orders where orderId=orderId;
  if[0 = count ord; '"Order not found"];
  if[not ord[`status] in `open`partially_filled; :()];

  / Get current orderbook
  ob:genOrderbook[];

  / Filter by opposing side
  oppSide:`buy`sell (`sell`buy)?ord`side;
  levels:select from ob where side=oppSide;

  / Match logic
  remaining:.qg.fromVolume[ord[`quantity] - ord[`filled]];
  totalFilled:0.0;

  / Iterate through price levels
  i:0;
  while[(remaining > 0.0) and (i < count levels)];
    level:levels i;

    / Check price matching - handle null price for market orders
    orderPrice:$[null ord`price; 0n; .qg.fromPrice[ord`price]];
    matchable:$[ord[`orderType]=`market;
      1b;  / Market orders always match
      $[ord[`side]=`buy;
        level[`price] <= orderPrice;
        level[`price] >= orderPrice
      ]
    ];

    if[not matchable; break];

    / Calculate fill quantity
    fillQty:min[remaining;level`quantity];
    fillPrice:level`price;

    / Record fill
    fillId:nextFillId;
    nextFillId+::1;

    fee:fillQty * fillPrice * config`feeRate;
    `fills insert (fillId;orderId;fillPrice;fillQty;fee;.z.p);

    / Update balances
    if[ord[`side]=`buy;
      / Buy: release quote hold, add base, deduct quote + fee
      releaseHold[quoteCurrency;fillQty * fillPrice];
      updateBalance[baseCurrency;fillQty];
      updateBalance[quoteCurrency;neg (fillQty * fillPrice + fee)]
    ];

    if[ord[`side]=`sell;
      / Sell: release base hold, deduct base, add quote - fee
      releaseHold[baseCurrency;fillQty];
      updateBalance[baseCurrency;neg fillQty];
      updateBalance[quoteCurrency;fillQty * fillPrice - fee]
    ];

    / Update remaining and filled
    remaining-:fillQty;
    totalFilled+:fillQty;
    i+:1;
  ];

  / Update order status and filled quantity
  newFilled:ord[`filled] + .qg.toVolume[totalFilled];
  newStatus:$[
    remaining = 0.0; `filled;
    totalFilled > 0.0; `partially_filled;
    `open
  ];

  update filled:newFilled, status:newStatus from `orders where orderId=orderId;

  `filled`remaining!(newFilled;.qg.toVolume[remaining])
 };

/ Cancel order
/ @param orderId long - Order ID
/ @return dict - Cancelled order
cancelOrder:{[orderId]
  ord:first select from orders where orderId=orderId;
  if[0 = count ord; '"Order not found"];
  if[not ord[`status] in `open`partially_filled;
    '"Cannot cancel order in status: ",string ord`status
  ];

  / Extract currencies from pair
  pairStr:string ord`pair;
  baseCurrency:`$3#pairStr;
  quoteCurrency:`$-3#pairStr;

  / Calculate remaining quantity
  remaining:.qg.fromVolume[ord[`quantity] - ord[`filled]];

  / Release holds - handle null price for market orders
  if[ord[`side]=`buy;
    / For market orders, estimate hold based on mid price
    holdAmount:$[null ord`price;
      remaining * obParams`midPrice;
      remaining * .qg.fromPrice[ord`price]
    ];
    releaseHold[quoteCurrency;holdAmount]
  ];

  if[ord[`side]=`sell;
    releaseHold[baseCurrency;remaining]
  ];

  / Update status
  update status:`cancelled from `orders where orderId=orderId;

  `orderId`status!(orderId;`cancelled)
 };

// ============================================================================
// EXCHANGE API IMPLEMENTATION
// ============================================================================

/ Place order (exchange interface)
placeOrder:{[pair;orderType;side;price;quantity]
  submitOrder[pair;orderType;side;price;quantity]
 };

/ Cancel order (exchange interface)
cancel:{[orderId]
  cancelOrder[orderId]
 };

/ Get balance (exchange interface)
getBalance:{[currency]
  total:getTotalBalance[currency];
  available:getAvailableBalance[currency];
  reserved:$[currency in key holds; holds[currency]; 0.0];

  `currency`total`available`reserved!(currency;total;available;reserved)
 };

/ Get orderbook (exchange interface)
getOrderbook:{[pair]
  genOrderbook[]
 };

/ Get open orders (exchange interface)
getOpenOrders:{[pair]
  select from orders where pair=pair, status in `open`partially_filled
 };

/ Get position (exchange interface - stub returns empty)
getPosition:{[pair]
  `pair`size`side!(pair;0j;`)
 };

// ============================================================================
// REGISTRATION
// ============================================================================

/ Register stub exchange implementation
registerStub:{[]
  / Create implementation dict
  impl:`placeOrder`cancelOrder`getBalance`getOrderbook`getOpenOrders`getPosition!(
    placeOrder;
    cancel;
    getBalance;
    getOrderbook;
    getOpenOrders;
    getPosition
  );

  / Register with registry
  .exchange.registry.register[`stub;impl];
 };

\d .

/ Export namespace
-1 "  Stub exchange loaded: .exchange.stub namespace";
