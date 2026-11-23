/ Book Module Initialization
/ Loads all book modules and sets up subscriptions

\d .book

/ Load all book modules
loadModules:{[]
  -1 "Loading book modules...";

  / Load schema first
  system "l src/q/book/schema.q";

  / Load aggregator
  system "l src/q/book/aggregator.q";

  / Load GBBO utilities
  system "l src/q/book/gbbo.q";

  / Load router
  system "l src/q/book/router.q";

  / Initialize exchange fees
  .book.initFees[];

  -1 "Book modules loaded successfully";
 };

/ Subscribe to orderbook updates from tickerplant
/ When .u.upd is called with orderbook data, re-aggregate
setupSubscription:{[]
  / Check if .u namespace exists (tickerplant environment)
  if[not `u in key `.;
    -1 "WARNING: .u namespace not found. Orderbook subscription not active.";
    :()
  ];

  / Override .u.upd for orderbook table
  / Store original handler if it exists
  if[`upd in key .u; .book.originalUpd:.u.upd];

  / Define new handler
  .u.upd:{[tbl;data]
    / Call original handler if it exists
    if[`originalUpd in key .book; .book.originalUpd[tbl;data]];

    / If orderbook update, re-aggregate affected pairs
    if[tbl=`orderbook;
      / Extract unique pairs from update
      pairs:distinct data[;`sym];

      / Re-aggregate each affected pair
      {.book.aggregate[x]} each pairs;
    ];
  };

  -1 "Orderbook subscription active";
 };

/ Initialize book module
init:{[]
  -1 "Initializing book module...";

  / Load all modules
  loadModules[];

  / Set up tickerplant subscription
  setupSubscription[];

  -1 "Book module initialized";
 };

-1 "  Book init loaded: .book.init[]";

\d .
