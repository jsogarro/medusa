/ Risk Management — Order Size and Daily Volume Limits

\d .risk

/ Reset daily volume counters (run at start of day or auto-detect new day)
resetDailyVolume:{[]
  update dailyVolume:0j,lastResetDate:.z.d from `.risk.orderSizeLimits;
  .risk.globalOrderSizeLimits[`dailyVolume]:0j;
  .risk.globalOrderSizeLimits[`lastResetDate]:.z.d;
  -1 "Daily volume counters reset";
 };

/ Set order size limits for a strategy
setOrderSizeLimit:{[strategy;maxOrderQty;maxDailyVolume]
  `.risk.orderSizeLimits upsert ([] strategy:enlist strategy; minOrderQty:enlist maxOrderQty; maxOrderQty:enlist maxDailyVolume; maxDailyVolume:enlist 0Wj; dailyVolume:enlist 0j; lastResetDate:enlist .z.d);
  -1 "Order size limit set: ",string[strategy]," [min:",string[maxOrderQty],", max:",string[maxDailyVolume],"]";
 };

/ Set global order size limits
setGlobalOrderSizeLimit:{[minQty;maxQty]
  globalOrderSizeLimits::update minOrderQty:minQty, maxOrderQty:maxQty, maxDailyVolume:0Wj, dailyVolume:0j, lastResetDate:.z.d from globalOrderSizeLimits;
  -1 "Global order size limit set: [min:",string[minQty],", max:",string[maxQty],"]";
 };

/ Update daily volume (called on fill)
updateDailyVolume:{[strategy;qty]
  / ATOMIC auto-reset if new day (consolidated to prevent race condition)
  if[.z.d>first .risk.globalOrderSizeLimits`lastResetDate;
    / Lock: perform atomic reset once
    resetDailyVolume[]
  ];

  / SAFETY CHECK: Ensure strategy entry exists (fail-safe)
  if[not strategy in key .risk.orderSizeLimits;
    / CRITICAL: Log error and reject fill (limits must be set before trading)
    .risk.logRiskEvent[.z.p;`unconfiguredStrategyOrderLimit;strategy;`;`;`qty!qty;`reject;`critical];
    -1 "CRITICAL: Attempted to update volume for unconfigured strategy: ",string[strategy];
    :(::)
  ];
  / ATOMIC update strategy-level volume using upsert
  `.risk.orderSizeLimits upsert update dailyVolume:dailyVolume+qty from .risk.orderSizeLimits where strategy=strategy;

  / Update global volume (single-row table — use indexed assignment)
  .risk.globalOrderSizeLimits[`dailyVolume]:first[.risk.globalOrderSizeLimits`dailyVolume]+qty;
 };

/ Check order size limits (pre-trade)
/ Returns: (pass:boolean; reason:symbol)
/ HOT PATH: Optimized to use keyed table indexing (O(1)) instead of select (O(n))
checkOrderSizeLimit:{[strategy;qty]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.globalOrderSizeLimits;
    -1 "CRITICAL: globalOrderSizeLimits table corrupted (row count: ",string[count .risk.globalOrderSizeLimits],")";
    :(0b;`globalOrderLimitCorrupted)
  ];

  / ATOMIC auto-reset if new day (deduplicated from updateDailyVolume)
  if[.z.d>first .risk.globalOrderSizeLimits`lastResetDate;
    resetDailyVolume[]
  ];

  / Use keyed table indexing for O(1) lookup (strategy is the key)
  stratLimits:.risk.orderSizeLimits[strategy];

  / FAIL-SAFE: reject if no limits configured (missing key returns null values)
  if[null stratLimits`maxOrderQty;
    :(0b;`noStrategyOrderLimitConfigured)
  ];

  / Strategy limit checks (direct dict access)
  if[qty<stratLimits`minOrderQty;:(0b;`belowMinOrderSize)];
  if[qty>stratLimits`maxOrderQty;:(0b;`aboveMaxOrderSize)];
  if[(stratLimits[`dailyVolume]+qty)>stratLimits`maxDailyVolume;:(0b;`strategyDailyVolumeExceeded)];

  / Check global limits (single-row table — direct column access)
  globalMinLimit:first .risk.globalOrderSizeLimits`minOrderQty;
  globalQtyLimit:first .risk.globalOrderSizeLimits`maxOrderQty;
  globalDailyLimit:first .risk.globalOrderSizeLimits`maxDailyVolume;
  globalDailyVol:first .risk.globalOrderSizeLimits`dailyVolume;

  if[qty<globalMinLimit;:(0b;`belowMinOrderSize)];
  if[qty>globalQtyLimit;:(0b;`aboveMaxOrderSize)];
  if[(globalDailyVol+qty)>globalDailyLimit;:(0b;`globalDailyVolumeExceeded)];

  / All checks passed
  (1b;`)
 };

\d .
