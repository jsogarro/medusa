/ ============================================================================
/ stub.q - Stubbed Exchange Implementation
/ ============================================================================
/ // Provides:
/   - Complete in-memory simulated exchange for testing
/   - Synthetic orderbook generation with configurable parameters
/   - Order matching engine with realistic fill simulation
/   - Balance tracking with stub.holds for open stub.orders
/   - Configurable latency and slippage models
/ // Dependencies:
/   - types.q (validation, constants, ID generator)
/   - base.q (order states and validation)
/   - registry.q (registration)
/ // State Tables:
/   - .exchange.stub.stub.balances: Currency stub.balances
/   - .exchange.stub.stub.holds: Reserved stub.balances for open stub.orders
/   - .exchange.stub.stub.orders: In-memory order book
/   - .exchange.stub.stub.fills: Trade stub.fills
/ // Functions:
/   - stub.init: Initialize stub with configuration
/   - stub.placeOrder: Submit and match order
/   - stub.cancelOrder: Cancel open order
/   - stub.getBalance: Get currency balance
/   - stub.getOrderbook: Get synthetic orderbook
/   - stub.getOpenOrders: Get open stub.orders
/   - stub.getPosition: Get position (stub)
/ ============================================================================

\d .exchange

// ============================================================================
// CONFIGURATION
// ============================================================================

/ Stub exchange configuration
stub.defaultConfig:`symbol`tickSize`minQty`maxQty`feeRate`latencyMs!(`;0.01;0.001;1000.0;0.001;10);
stub.config:stub.defaultConfig;

/ Orderbook generation parameters
stub.defaultOBParams:`midPrice`spread`depth`volatility`tickSize!(100.0;0.02;10;0.001;0.01);
stub.obParams:stub.defaultOBParams;

// ============================================================================
// STATE TABLES
// ============================================================================

/ Balances: currency -> amount
stub.balances:()!();

/ Holds: currency -> held amount
stub.holds:()!();

/ Orders table
stub.ordersSchema:([]
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
stub.orders:stub.ordersSchema;

/ Fills table
stub.fillsSchema:([]
  fillId:`long$();
  orderId:`long$();
  price:`float$();
  quantity:`float$();
  fee:`float$();
  timestamp:`timestamp$()
 );
stub.fills:stub.fillsSchema;

/ Next order ID
stub.nextOrderId:1j;

/ Next fill ID
stub.nextFillId:1j;

/ Random stub.seed for deterministic orderbook generation
stub.seed:42;

// ============================================================================
// INITIALIZATION
// ============================================================================

/ Initialize stub exchange
/ @param cfg dict - Configuration overrides (optional)
/ @return dict - Configuration
stub.init:{[cfg]
  stub.config::stub.defaultConfig;
  stub.obParams::stub.defaultOBParams;

  / Apply configuration overrides
  if[count cfg;
    stub.config,:cfg
  ];

  / Initialize state
  stub.balances::()!();
  stub.holds::()!();
  stub.orders::stub.ordersSchema;
  stub.fills::stub.fillsSchema;
  stub.nextOrderId::1j;
  stub.nextFillId::1j;

  / Log initialization
  -1 "  Stub exchange initialized";

  stub.config
 };

/ Set starting stub.balances
/ @param balancesDict dict - Currency -> amount
stub.setBalances:{[balancesDict]
  stub.balances::balancesDict;
  stub.holds::(key balancesDict)!count[balancesDict]#0.0;
 };

/ Set orderbook parameters
/ @param params dict - Orderbook generation parameters
stub.setOBParams:{[params]
  stub.obParams,:params;
 };

// ============================================================================
// BALANCE OPERATIONS
// ============================================================================

/ Get total balance
/ @param currency symbol - Currency code
/ @return float - Total balance
stub.getTotalBalance:{[currency]
  $[currency in key stub.balances; stub.balances[currency]; 0.0]
 };

/ Get available balance (total - stub.holds)
/ @param currency symbol - Currency code
/ @return float - Available balance
stub.getAvailableBalance:{[currency]
  total:stub.getTotalBalance[currency];
  hold:$[currency in key stub.holds; stub.holds[currency]; 0.0];
  total - hold
 };

/ Place hold on balance
/ @param currency symbol - Currency code
/ @param amount float - Amount to hold
stub.placeHold:{[currency;amount]
  available:stub.getAvailableBalance[currency];
  if[amount > available;
    '"Insufficient available balance"
  ];

  / Initialize hold if doesn't exist
  if[not currency in key stub.holds;
    stub.holds::stub.holds,enlist[currency]!enlist 0.0
  ];

  stub.holds::stub.holds,enlist[currency]!enlist stub.holds[currency]+amount;
 };

/ Release hold on balance
/ @param currency symbol - Currency code
/ @param amount float - Amount to release
stub.releaseHold:{[currency;amount]
  if[not currency in key stub.holds;
    '"No stub.holds for currency"
  ];

  current:stub.holds[currency];
  if[amount > current;
    '"Cannot release more than held"
  ];

  stub.holds::stub.holds,enlist[currency]!enlist current-amount;
 };

/ Update balance (add or subtract)
/ @param currency symbol - Currency code
/ @param delta float - Amount to add (positive) or subtract (negative)
stub.updateBalance:{[currency;delta]
  / Initialize balance if doesn't exist
  if[not currency in key stub.balances;
    stub.balances::stub.balances,enlist[currency]!enlist 0.0
  ];

  newBalance:stub.balances[currency] + delta;
  if[newBalance < 0.0;
    '"Balance cannot go negative"
  ];

  stub.balances::stub.balances,enlist[currency]!enlist newBalance;
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
stub.genPriceLevels:{[mid;spread;depth;tick]
  half:mid * (spread % 2.0);
  bidMid:mid - half;
  askMid:mid + half;

  / Geometric spacing (tighter near top)
  ratioVals:1.0 + (til depth) * 0.001;

  bidPrices:reverse tick * floor (bidMid * reverse ratioVals) % tick;
  askPrices:tick * ceiling (askMid * ratioVals) % tick;

  `bid`ask!(bidPrices;askPrices)
 };

/ Generate realistic quantities (exponential distribution)
/ @param n long - Number of levels
/ @param minQty float - Minimum quantity
/ @param maxQty float - Maximum quantity
/ @return float[] - Quantities
stub.genQuantities:{[n;minQty;maxQty]
  / Use stub.seed for deterministic results
  stub.seed+::1;

  / Exponential distribution
  vals:n?1.0;
  expVals:neg log 1.0 - vals;
  / Scale to range
  scaled:minQty + (expVals % max expVals) * (maxQty - minQty);
  scaled
 };

/ Generate synthetic orderbook
/ @return table - Orderbook with bid/ask levels
stub.genOrderbook:{[]
  levels:stub.genPriceLevels[
    stub.obParams`midPrice;
    stub.obParams`spread;
    stub.obParams`depth;
    stub.obParams`tickSize
  ];

  n:stub.obParams`depth;
  bidQty:stub.genQuantities[n;stub.config`minQty;stub.config`maxQty];
  askQty:stub.genQuantities[n;stub.config`minQty;stub.config`maxQty];

  / Build orderbook table
  ob:([]
    side:(n#`bid),(n#`ask);
    price:levels[`bid],levels[`ask];
    quantity:bidQty,askQty;
    timestamp:(2*n)#.z.p
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
stub.submitOrder:{[pair;orderType;side;price;quantity]
  / Validate order parameters
  .exchange.validateOrderParams[orderType;side;price;quantity];

  / Assign order ID
  oid:stub.nextOrderId;
  stub.nextOrderId+::1;

  / Extract currencies from pair (assume XXXYYY format)
  pairStr:string pair;
  baseCurrency:`$3#pairStr;
  quoteCurrency:`$-3#pairStr;

  / Place hold for buy stub.orders (need quote currency)
  if[side=`buy;
    required:$[orderType=`market;
      (.qg.fromVolume[quantity]) * (stub.obParams`midPrice) * 1.1;  / Market stub.orders: use mid + buffer
      (.qg.fromVolume[quantity]) * .qg.fromPrice[price]
    ];
    stub.placeHold[quoteCurrency;required]
  ];

  / Place hold for sell stub.orders (need base currency)
  if[side=`sell;
    stub.placeHold[baseCurrency;.qg.fromVolume[quantity]]
  ];

  / Create order record
  stub.orders::stub.orders,enlist `orderId`pair`orderType`side`price`quantity`filled`status`timestamp!(
    oid;pair;orderType;side;price;quantity;0j;`pending;.z.p
  );

  / Update status to open
  stub.orders::update status:`open from stub.orders where orderId=oid;

  / Attempt to match
  matchResult:stub.matchOrder[oid;baseCurrency;quoteCurrency];

  / Get final order state
  ord:first select from stub.orders where orderId=oid;

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
stub.matchOrder:{[orderId;baseCurrency;quoteCurrency]
  ord:first select from stub.orders where orderId=orderId;
  if[0 = count ord; '"Order not found"];
  if[not ord[`status] in `open`partially_filled; :()];

  / Get current orderbook
  ob:stub.genOrderbook[];

  / Filter by opposing side
  oppSide:$[ord[`side]=`buy; `ask; `bid];
  levels:select from ob where side=oppSide;

  / Match logic
  remaining:.qg.fromVolume[ord[`quantity] - ord[`filled]];
  totalFilled:0.0;

  / Iterate through price levels
  i:0;
  while[(remaining > 0.0) and (i < count levels);
    level:levels i;

    / Check price matching - handle null price for market stub.orders
    orderPrice:$[null ord`price; 0n; .qg.fromPrice[ord`price]];
    matchable:$[ord[`orderType]=`market;
      1b;  / Market stub.orders always match
      $[ord[`side]=`buy;
        level[`price] <= orderPrice;
        level[`price] >= orderPrice
      ]
    ];

    if[not matchable; i:count levels; ];

    if[matchable;
      / Calculate fill quantity
      fillQty:remaining & level`quantity;
      fillPrice:level`price;

      / Record fill
      fillId:stub.nextFillId;
      stub.nextFillId+::1;

      fee:fillQty * fillPrice * (stub.config`feeRate);
      stub.fills::stub.fills,enlist `fillId`orderId`price`quantity`fee`timestamp!(
        fillId;orderId;fillPrice;fillQty;fee;.z.p
      );

      / Update stub.balances
      if[ord[`side]=`buy;
        / Buy: release quote hold, add base, deduct quote + fee
        stub.releaseHold[quoteCurrency;fillQty * fillPrice];
        stub.updateBalance[baseCurrency;fillQty];
        stub.updateBalance[quoteCurrency;neg (fillQty * fillPrice + fee)]
      ];

      if[ord[`side]=`sell;
        / Sell: release base hold, deduct base, add quote - fee
        stub.releaseHold[baseCurrency;fillQty];
        stub.updateBalance[baseCurrency;neg fillQty];
        stub.updateBalance[quoteCurrency;fillQty * fillPrice - fee]
      ];

      / Update remaining and filled
      remaining-:fillQty;
      totalFilled+:fillQty;
      i+:1;
    ];
  ];

  / Update order status and filled quantity
  newFilled:ord[`filled] + .qg.toVolume[totalFilled];
  newStatus:$[
    remaining = 0.0; `filled;
    totalFilled > 0.0; `partially_filled;
    `open
  ];

  stub.orders::update filled:newFilled, status:newStatus from stub.orders where orderId=orderId;

  `filled`remaining!(newFilled;.qg.toVolume[remaining])
 };

/ Cancel order
/ @param orderId long - Order ID
/ @return dict - Cancelled order
stub.cancelOrder:{[orderId]
  ord:first select from stub.orders where orderId=orderId;
  if[0 = count ord; '"Order not found"];
  if[not ord[`status] in `open`partially_filled;
    '"Cannot stub.cancel order in status: ",string ord`status
  ];

  / Extract currencies from pair
  pairStr:string ord`pair;
  baseCurrency:`$3#pairStr;
  quoteCurrency:`$-3#pairStr;

  / Calculate remaining quantity
  remaining:.qg.fromVolume[ord[`quantity] - ord[`filled]];

  / Release stub.holds - handle null price for market stub.orders
  if[ord[`side]=`buy;
    / For market stub.orders, estimate hold based on mid price
    holdAmount:$[null ord`price;
      remaining * (stub.obParams`midPrice);
      remaining * .qg.fromPrice[ord`price]
    ];
    stub.releaseHold[quoteCurrency;holdAmount]
  ];

  if[ord[`side]=`sell;
    stub.releaseHold[baseCurrency;remaining]
  ];

  / Update status
  stub.orders::update status:`cancelled from stub.orders where orderId=orderId;

  `orderId`status!(orderId;`cancelled)
 };

// ============================================================================
// EXCHANGE API IMPLEMENTATION
// ============================================================================

/ Place order (exchange interface)
stub.placeOrder:{[pair;orderType;side;price;quantity]
  stub.submitOrder[pair;orderType;side;price;quantity]
 };

/ Cancel order (exchange interface)
stub.cancel:{[orderId]
  stub.cancelOrder[orderId]
 };

/ Get balance (exchange interface)
stub.getBalance:{[currency]
  total:stub.getTotalBalance[currency];
  available:stub.getAvailableBalance[currency];
  reserved:$[currency in key stub.holds; stub.holds[currency]; 0.0];

  `currency`total`available`reserved!(currency;total;available;reserved)
 };

/ Get orderbook (exchange interface)
stub.getOrderbook:{[pair]
  stub.genOrderbook[]
 };

/ Get open stub.orders (exchange interface)
stub.getOpenOrders:{[p]
  select from stub.orders where pair=p, status in `open`partially_filled
 };

/ Get position (exchange interface - stub returns empty)
stub.getPosition:{[pair]
  `pair`size`side!(pair;0j;`)
 };

// ============================================================================
// REGISTRATION
// ============================================================================

/ Register stub exchange implementation
stub.registerStub:{[]
  / Create implementation dict
  impl:`stub.placeOrder`stub.cancelOrder`stub.getBalance`stub.getOrderbook`stub.getOpenOrders`stub.getPosition!(
    stub.placeOrder;
    stub.cancel;
    stub.getBalance;
    stub.getOrderbook;
    stub.getOpenOrders;
    stub.getPosition
  );

  / Register with registry
  .exchange.registry.register[`stub;impl];
 };

\d .

/ Export namespace
-1 "  Stub exchange loaded: .exchange.stub namespace";
