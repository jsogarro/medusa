/ Open orders tracking with caching
/ Load order: 10 - orders.q (depends on harness.q)

\d .engine

/ Open orders cache (keyed table)
orders.cache:([orderId:`symbol$()] exchange:`symbol$(); strategyId:`symbol$(); side:`symbol$(); price:`float$(); volume:`float$(); status:`symbol$(); filled:`float$(); placedAt:`timestamp$(); lastUpdate:`timestamp$())

/ Cache TTL in milliseconds
orders.cacheTTL:2000

/ Fetch open orders from harness
/ @param harness dict - harness state
/ @param strategyId symbol - strategy identifier
/ @return table - open orders
orders.fetch:{[harness;strategyId]
  / Get all open orders from harness
  allOrders:harness.getOpenOrders[harness];

  / Filter by strategy if strategyId column exists
  / For now, assume all orders belong to querying strategy
  allOrders
 }

/ Get cached orders for strategy
/ @param strategyId symbol - strategy identifier
/ @return table - cached orders
orders.getCached:{[strategyId]
  select from orders.cache where strategyId=strategyId
 }

/ Update order status
/ @param orderId symbol - order identifier
/ @param status symbol - new status (open, filled, cancelled)
/ @param filled float - filled volume
orders.updateStatus:{[orderId;status;filled]
  / Update cache
  update status:status, filled:filled, lastUpdate:.z.p from `orders.cache where orderId=orderId;

  / Log update
  if[.engine.config.baseSchema[`enableLogging];
    -1"[ORDERS] Updated order ",string[orderId]," status: ",string status;
  ];
 }

/ Remove order from cache
/ @param orderId symbol - order identifier
orders.remove:{[orderId]
  orders.cache:delete from orders.cache where orderId=orderId;

  / Log removal
  if[.engine.config.baseSchema[`enableLogging];
    -1"[ORDERS] Removed order from cache: ",string orderId;
  ];
 }

/ Get open orders for strategy (with cache)
/ @param harness dict - harness state
/ @param strategyId symbol - strategy identifier
/ @return table - open orders
orders.get:{[harness;strategyId]
  / Check if cache is fresh
  if[count orders.cache;
    cached:orders.getCached[strategyId];
    if[count cached;
      / Check cache age
      newestUpdate:exec max lastUpdate from cached;
      age:.z.p - newestUpdate;
      if[age < orders.cacheTTL;
        / Cache is fresh, return it
        :cached;
      ];
    ];
  ];

  / Cache miss or stale - fetch from harness
  freshOrders:orders.fetch[harness;strategyId];

  / Update cache
  if[count freshOrders;
    / Convert to cache format
    {[sid;ord]
      newRow:(enlist ord[`orderId])!enlist(ord[`exchange];sid;ord[`side];ord[`price];ord[`volume];ord[`status];ord[`filled];ord[`placedAt];.z.p);
      orders.cache,:newRow;
    }[strategyId] each freshOrders;
  ];

  freshOrders
 }

/ Clear orders cache
orders.clearCache:{
  orders.cache:0#orders.cache;
  -1"[ORDERS] Cache cleared";
 }

/ Refresh cache by removing stale entries
orders.refreshCache:{
  cutoff:.z.p - orders.cacheTTL;
  orders.cache:select from orders.cache where lastUpdate > cutoff;

  / Log refresh
  -1"[ORDERS] Cache refreshed, ",string[count orders.cache]," entries retained";
 }

/ Get cache statistics
/ @return dict - cache statistics
orders.stats:{
  `count`exchanges`strategies`oldestEntry!(
    count orders.cache;
    count exec distinct exchange from orders.cache;
    count exec distinct strategyId from orders.cache;
    exec min lastUpdate from orders.cache
  )
 }

\d .
