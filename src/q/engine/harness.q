/ Execution harness for exchange interaction
/ Load order: 4 - harness.q (depends on types.q)

\d .engine

/ Harness state schema
harness.state:`exchanges`mode`dryRunOrders`nextOrderId!()

/ Initialize harness with exchange connections
/ @param exchanges list of symbols - exchange identifiers
/ @param mode symbol - `live or `dryrun
/ @return dict - initialized harness
harness.init:{[exchanges;mode]
  / Validate mode
  if[not mode in types.validModes;
    '"Invalid mode: ",string mode];

  / In dry-run mode, create mock exchange connections
  / In live mode, would connect to real exchanges (not implemented here)
  exchangeConns:exchanges!count[exchanges]#enlist (::);

  / Initialize dry-run orders table
  dryRunOrders:([]
    orderId:`symbol$();
    exchange:`symbol$();
    side:`symbol$();
    price:`float$();
    volume:`float$();
    status:`symbol$();
    placedAt:`timestamp$();
    filled:`float$()
  );

  `exchanges`mode`dryRunOrders`nextOrderId!(
    exchangeConns;
    mode;
    dryRunOrders;
    1  / start order IDs at 1
  )
 }

/ Get orderbook for an exchange (mock in dry-run)
/ @param harness dict - harness state
/ @param exchange symbol - exchange identifier
/ @return table - orderbook (bids and asks)
harness.getOrderbook:{[harness;exchange]
  / Check exchange exists in harness
  if[not exchange in key harness[`exchanges];
    '"Unknown exchange: ",string exchange];

  / In dry-run mode, generate mock orderbook
  if[harness[`mode]~`dryrun;
    :harness.mockOrderbook[exchange];
  ];

  / In live mode, would query real exchange
  / For now, return mock even in live mode
  harness.mockOrderbook[exchange]
 }

/ Generate mock orderbook (helper)
/ @param exchange symbol - exchange identifier
/ @return dict - orderbook with bids and asks
harness.mockOrderbook:{[exchange]
  / Generate realistic-looking orderbook
  midPrice:50000.0 + 1000.0 * rand 1.0;  / BTC/USD around 50k-51k
  spread:10.0;

  / Generate 10 bid levels
  bids:([]
    price:midPrice - spread + neg 10?50.0;
    volume:10?100.0
  );
  bids:`price xdesc bids;

  / Generate 10 ask levels
  asks:([]
    price:midPrice + spread + 10?50.0;
    volume:10?100.0
  );
  asks:`price xasc asks;

  `bids`asks!(bids;asks)
 }

/ Place order (simulated in dry-run)
/ @param harness dict - harness state
/ @param exchange symbol - exchange identifier
/ @param side symbol - `buy or `sell
/ @param price float - order price
/ @param volume float - order volume
/ @return (dict; symbol) - (updated harness, orderId)
harness.placeOrder:{[harness;exchange;side;price;volume]
  / Validate exchange
  if[not exchange in key harness[`exchanges];
    '"Unknown exchange: ",string exchange];

  / Validate side
  if[not side in `buy`sell;
    '"Invalid side: ",string side];

  / Generate order ID
  orderId:`$"order_",string harness[`nextOrderId];
  harness[`nextOrderId]:harness[`nextOrderId]+1;

  / In dry-run mode, add to mock orders table
  if[harness[`mode]~`dryrun;
    newOrder:(orderId;exchange;side;price;volume;`open;.z.p;0.0);
    harness[`dryRunOrders],:flip `orderId`exchange`side`price`volume`status`placedAt`filled!newOrder;
  ];

  / In live mode, would submit to real exchange
  / For now, mock it

  (harness;orderId)
 }

/ Cancel order
/ @param harness dict - harness state
/ @param orderId symbol - order identifier
/ @return dict - updated harness
harness.cancelOrder:{[harness;orderId]
  / In dry-run mode, update mock orders table
  if[harness[`mode]~`dryrun;
    harness[`dryRunOrders]:update status:`cancelled where orderId=orderId from harness[`dryRunOrders];
  ];

  / In live mode, would cancel on real exchange

  harness
 }

/ Get all open orders
/ @param harness dict - harness state
/ @return table - open orders
harness.getOpenOrders:{[harness]
  / In dry-run mode, query mock orders table
  if[harness[`mode]~`dryrun;
    :select from harness[`dryRunOrders] where status=`open;
  ];

  / In live mode, would query real exchanges
  / For now, return empty table
  ([]orderId:();exchange:();side:();price:();volume:();status:();placedAt:();filled:())
 }

/ Shutdown harness and disconnect exchanges
/ @param harness dict - harness state
/ @return dict - shutdown harness
harness.shutdown:{[harness]
  / In live mode, would disconnect from exchanges
  / In dry-run mode, just clear state

  harness[`exchanges]:()!();
  harness[`dryRunOrders]:0#harness[`dryRunOrders];

  harness
 }

\d .
