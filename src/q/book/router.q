/ Smart Order Routing
/ Routes orders to best exchange considering price and fees

\d .book

/ Exchange fee rates (hardcoded for now, could be loaded from config)
/ fee_rate is a percentage (e.g., 0.1 = 0.1%)
exchangeFees:([exchange:`symbol$()]
  makerFee:`float$();
  takerFee:`float$()
 );

/ Initialize default fee structure
initFees:{[]
  `.book.exchangeFees set 0#.book.exchangeFees;
  `.book.exchangeFees upsert ([exchange:`binance`coinbase`kraken]
    makerFee:0.1 0.4 0.16;
    takerFee:0.1 0.6 0.26
  );
  -1 "Exchange fees initialized";
 };

/ Get fee rate for exchange
/ @param exchange symbol - Exchange name
/ @param isMaker boolean - True if maker order, false if taker
/ @return float - Fee rate as percentage
getFeeRate:{[exchange;isMaker]
  / Default to 0.2% if exchange not found
  if[not exchange in key .book.exchangeFees; :0.2];

  feeType:$[isMaker; `makerFee; `takerFee];
  .book.exchangeFees[exchange;feeType]
 };

/ Calculate effective price after fees
/ @param price float - Base price
/ @param side symbol - `buy or `sell
/ @param feeRate float - Fee rate as percentage
/ @return float - Effective price including fees
calcEffectivePrice:{[price;side;feeRate]
  / For buy orders: effective price = ask + (ask × fee_rate / 100)
  / For sell orders: effective price = bid - (bid × fee_rate / 100)
  feeMultiplier:feeRate % 100.0;

  $[side=`buy;
    price * (1.0 + feeMultiplier);
    price * (1.0 - feeMultiplier)
  ]
 };

/ Route order to best exchange based on price and fees
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @param qty float - Order quantity
/ @return symbol - Best exchange name or ` if no liquidity
routeToBestExchange:{[pair;side;qty]
  / Get aggregated book for this pair/side
  bookSide:$[side=`buy; `ask; `bid]; / Buy lifts asks, sell hits bids
  book:0!select from .book.aggregatedBook where pair=pair, side=bookSide;

  / If no book data, return null
  if[0=count book; :`];

  / Evaluate each exchange's own top quote rather than only the global best level.
  candidates:raze {[book;i]
    row:book i;
    exchanges:row`exchanges;
    ([] exchange:exchanges;
        size:row`exchangeSizes;
        price:(count exchanges)#row`price;
        level:(count exchanges)#row`level)
  }[book] each til count book;

  / Build table of exchanges with sufficient liquidity.
  candidates:select from candidates where size >= qty;

  / If no single exchange has enough liquidity, return ` (caller should use split routing)
  if[0=count candidates; :`];

  / Calculate effective price for each candidate (assume taker order)
  candidates:update feeRate:.book.getFeeRate'[exchange;0b] from candidates;
  candidates:update effectivePrice:{[s;p;f].book.calcEffectivePrice[p;s;f]}[side]'[price;feeRate] from candidates;

  / For buy: pick lowest effective price
  / For sell: pick highest effective price
  sorted:$[side=`buy;
    `effectivePrice xasc candidates;
    `effectivePrice xdesc candidates
  ];

  / Return best exchange
  first exec exchange from sorted
 };

/ Split order across multiple exchanges
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @param qty float - Total order quantity
/ @return table - Table of (exchange; qty) pairs
routeSplit:{[pair;side;qty]
  bookSide:$[side=`buy; `ask; `bid];
  book:`level xasc select from .book.aggregatedBook where pair=pair, side=bookSide;
  $[0=count book;
    0#([] exchange:`symbol$(); qty:`float$());
    select sum qty by exchange from .book.fillFromBook[book;qty]
  ]
 };

/ Helper function to fill order from book
/ @param book table - Sorted aggregated book (keyed)
/ @param qty float - Order quantity
/ @return table - Fills with (exchange; qty; price)
fillFromBook:{[book;qty]
  / Unkey book for easier indexing
  unkeyed:0!book;

  state:`remainingQty`fills`i`used!(
    qty;
    0#([] exchange:`symbol$(); qty:`float$(); price:`float$());
    0;
    `symbol$()
  );

  / Process each level
  state:{[s;levelIdx;unkeyed]
    if[s[`remainingQty] <= 0.0; :s]; / Early exit if filled

    levelRow:unkeyed levelIdx;
    levelPrice:levelRow`price;
    exchanges:levelRow`exchanges;
    sizes:levelRow`exchangeSizes;

    / Process each exchange at this level
    j:0;
    while[(s[`remainingQty] > 0.0) and (j < count exchanges);
      exchange:exchanges j;
      if[not exchange in s`used;
        availableSize:sizes j;
        fillQty:s[`remainingQty] & availableSize;
        s[`fills],:enlist `exchange`qty`price!(exchange; fillQty; levelPrice);
        s[`remainingQty]-:fillQty;
        s[`used],:exchange;
      ];
      j+:1;
    ];

    s
  }[;; unkeyed]/[state; til count unkeyed];

  if[state[`remainingQty] > 0.0;
    -1 "WARNING: routeSplit could not fill full order. Remaining: ",string state`remainingQty;
  ];

  state`fills
 };

/ Route order (wrapper that tries single exchange first, then split if needed)
/ @param pair symbol - Trading pair
/ @param side symbol - `buy or `sell
/ @param qty float - Order quantity
/ @return dict - Routing decision with `type`exchange`qty or `type`splits
route:{[pair;side;qty]
  / Try single exchange first
  bestExchange:routeToBestExchange[pair;side;qty];

  / If single exchange can handle it, return simple routing
  if[not null bestExchange;
    :`type`exchange`qty!(`single;bestExchange;qty)
  ];

  / Otherwise, use split routing
  splits:routeSplit[pair;side;qty];

  / If split routing failed, return error
  if[0=count splits;
    :`type`error!(`failed;"Insufficient liquidity across all exchanges")
  ];

  `type`splits!(`split;splits)
 };

-1 "  Router loaded: routeToBestExchange[], routeSplit[], route[], initFees[]";

\d .
