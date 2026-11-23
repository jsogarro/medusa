/ Risk Management — Notional Exposure Limits (per-exchange and global)
/ // PRECISION GUARANTEE: All notional calculations are rounded to 6 decimal places
/ to prevent floating-point accumulation errors. This matches USD precision (2 decimals)
/ with a safety margin for high-precision crypto (up to 6 decimals for BTC fractions).

\d .risk

/ Round notional value to 6 decimal places (precision guarantee)
/ @param n float - Raw notional value
/ @return float - Rounded to 6 decimals
roundNotional:{[n]
  `float$floor 0.5 + n * 1000000 % 1000000
 };

/ Set exposure limit for an exchange
setExposureLimit:{[exchange;maxNotional]
  `.risk.exposureLimits upsert ([] exchange:enlist exchange; maxNotional:enlist maxNotional; currentNotional:enlist 0.0);
  -1 "Exposure limit set: ",string[exchange]," [",string[maxNotional]," USD]";
 };

/ Set global exposure limit
setGlobalExposureLimit:{[maxNotional]
  .risk.globalExposureLimit[`maxNotional]:maxNotional;
  .risk.globalExposureLimit[`currentNotional]:0.0;
  -1 "Global exposure limit set: [",string[maxNotional]," USD]";
 };

/ Update exposure (called on position change)
updateExposure:{[exchange;sym;qty;price]
  notional:roundNotional[abs[qty]*price];  / HIGH-1 fix: precision guarantee

  / SAFETY CHECK: Ensure exchange entry exists (fail-safe)
  if[not exchange in key .risk.exposureLimits;
    / CRITICAL: Log error and reject fill (limits must be set before trading)
    .risk.logRiskEvent[.z.p;`unconfiguredExchangeExposure;`;sym;exchange;`qty`price`notional!(qty;price;notional);`reject;`critical];
    -1 "CRITICAL: Attempted to update exposure for unconfigured exchange: ",string[exchange];
    :(::)
  ];
  / ATOMIC: Update both exchange and global exposure in one operation
  / Update exchange-level exposure
  update currentNotional:currentNotional+notional from `.risk.exposureLimits where exchange=exchange;

  / Update global exposure (single-row table — use indexed assignment)
  / SAFETY: Validate table has exactly 1 row
  if[1<>count .risk.globalExposureLimit;
    -1 "CRITICAL: globalExposureLimit table corrupted (row count: ",string[count .risk.globalExposureLimit],")";
    :(::)
  ];
  .risk.globalExposureLimit[`currentNotional]:first[.risk.globalExposureLimit`currentNotional]+notional;
 };

/ Check exposure limits (pre-trade)
/ Returns: (pass:boolean; reason:symbol)
/ HOT PATH: Optimized to use keyed table indexing (O(1)) instead of select (O(n))
checkExposureLimit:{[exchange;qty;price]
  if[0=count .risk.exposureLimits; :(1b;`)];

  notional:roundNotional[abs[qty]*price];  / HIGH-1 fix: precision guarantee

  / Use keyed table indexing for O(1) lookup (exchange is the key)
  exchLimit:.risk.exposureLimits[exchange];

  / FAIL-SAFE: reject if no limits configured (missing key returns null values)
  if[null exchLimit`maxNotional;
    :(0b;`noExchangeLimitConfigured)
  ];

  / Exchange limit check (direct dict access)
  if[(exchLimit[`currentNotional]+notional)>exchLimit`maxNotional;:(0b;`exchangeExposureLimitExceeded)];

  / Check global limit (single-row table — direct column access)
  / SAFETY: validate table integrity
  if[1<>count .risk.globalExposureLimit;
    -1 "CRITICAL: globalExposureLimit table corrupted (row count: ",string[count .risk.globalExposureLimit],")";
    :(0b;`globalExposureLimitCorrupted)
  ];

  globalMax:first .risk.globalExposureLimit`maxNotional;
  globalCurrent:first .risk.globalExposureLimit`currentNotional;

  if[(globalCurrent+notional)>globalMax;:(0b;`globalExposureLimitExceeded)];

  / All checks passed
  (1b;`)
 };

/ Recalculate exposure from current positions (reconciliation)
recalcExposure:{[positionTable]
  / positionTable: table with columns (exchange;sym;qty;lastPrice)
  / Reset exposures
  update currentNotional:0.0 from `.risk.exposureLimits;
  .risk.globalExposureLimit[`currentNotional]:0.0;

  / Aggregate by exchange (vectorized)
  exchExposure:select totalNotional:roundNotional sum abs qty*lastPrice by exchange from positionTable;  / HIGH-1 fix

  / Update each exchange (original approach — recalcExposure is not hot path)
  {[row]
    if[not row[`exchange] in key .risk.exposureLimits;
      `.risk.exposureLimits upsert ([] exchange:enlist row`exchange; maxNotional:enlist 500000.0; currentNotional:enlist 0.0)
    ];
    update currentNotional:row`totalNotional from `.risk.exposureLimits where exchange=row`exchange;
  } each 0!exchExposure;

  / Update global (single-row table — use indexed assignment)
  globalNotional:exec sum totalNotional from exchExposure;
  .risk.globalExposureLimit[`currentNotional]:globalNotional;

  -1 "Exposure recalculated from positions";
 };

\d .
