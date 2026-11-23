/ Risk Management — Concentration Limits
/ Per-exchange and per-asset concentration limits as % of portfolio
/ Performance: <10μs per check

\d .risk

/ Initialize concentration limits with default thresholds
initConcentrationLimits:{[]
  / Clear existing limits
  delete from `.risk.exchangeConcentration;
  delete from `.risk.assetConcentration;
  delete from `.risk.portfolioValue;
  delete from `.risk.concentrationEvents;

  / Default exchange concentration limits (% of total portfolio)
  / Tier 1 exchanges: 40% max, Tier 2: 25% max
  `.risk.exchangeConcentration upsert ([]
    exchange:`binance`coinbase`kraken;
    maxPct:40 40 25f;
    currentValue:0 0 0f;
    currentPct:0 0 0f;
    tier:1 1 2i
  );

  / Default asset concentration limits (% of total portfolio)
  / BTC/ETH: 25% max each, Alts: 10% max each
  `.risk.assetConcentration upsert ([]
    sym:`BTCUSD`ETHUSD;
    maxPct:25 25f;
    currentValue:0 0f;
    currentPct:0 0f
  );

  / Initialize portfolio value tracker (single-row table)
  `.risk.portfolioValue set ([]
    totalValue:enlist 0.0;
    lastUpdate:enlist .z.p
  );

  -1 "Concentration limits initialized: ",string[count .risk.exchangeConcentration]," exchanges, ",string[count .risk.assetConcentration]," assets";
 };

/ Check exchange concentration limit (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <10μs per check
checkExchangeConcentration:{[exchange;qty;price]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.portfolioValue;
    -1 "CRITICAL: portfolioValue table corrupted (row count: ",string[count .risk.portfolioValue],")";
    :(0b;`portfolioValueCorrupted;`exchange!exchange)
  ];

  / Calculate notional value of this order (use .money for precision)
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Get current portfolio value
  totalValue:first .risk.portfolioValue`totalValue;

  / Handle zero portfolio value case (startup)
  if[totalValue = 0.0; :(1b;`;()!())];

  / FAIL-SAFE: reject if no limits configured for this exchange
  if[not exchange in key .risk.exchangeConcentration;
    :(0b;`noExchangeConcentrationConfigured;`exchange!exchange)
  ];

  / Use keyed table indexing for O(1) lookup
  limit:.risk.exchangeConcentration[exchange];

  / Calculate new concentration percentage
  newValue:limit[`currentValue] + notional;
  newPct:100.0 * newValue % totalValue;

  / Check against limit
  if[newPct > limit`maxPct;
    / Log event
    `.risk.concentrationEvents insert (.z.p;`exchange;exchange;`;`rejected;limit`currentPct;newPct;limit`maxPct);
    :(0b;`exchangeConcentrationExceeded;`exchange`current`new`max!(exchange;limit`currentPct;newPct;limit`maxPct))
  ];

  / All checks passed
  (1b;`;()!())
 };

/ Check asset concentration limit (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <10μs per check
checkAssetConcentration:{[sym;qty;price]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.portfolioValue;
    -1 "CRITICAL: portfolioValue table corrupted (row count: ",string[count .risk.portfolioValue],")";
    :(0b;`portfolioValueCorrupted;`sym!sym)
  ];

  / Calculate notional value of this order (use .money for precision)
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Get current portfolio value
  totalValue:first .risk.portfolioValue`totalValue;

  / Handle zero portfolio value case (startup)
  if[totalValue = 0.0; :(1b;`;()!())];

  / Get asset limit if it exists (some assets may not have explicit limits)
  if[not sym in key .risk.assetConcentration;
    / No explicit limit for this asset — use default 10% for alts
    defaultLimit:10.0;
    currentValue:0.0;
    currentPct:0.0;
    newValue:notional;
    newPct:100.0 * newValue % totalValue;
    if[newPct > defaultLimit;
      `.risk.concentrationEvents insert (.z.p;`asset;`;sym;`rejected;currentPct;newPct;defaultLimit);
      :(0b;`assetConcentrationExceeded;`sym`current`new`max!(sym;currentPct;newPct;defaultLimit))
    ];
    :(1b;`;()!())
  ];

  / Use keyed table indexing for O(1) lookup
  limit:.risk.assetConcentration[sym];

  / Calculate new concentration percentage
  newValue:limit[`currentValue] + notional;
  newPct:100.0 * newValue % totalValue;

  / Check against limit
  if[newPct > limit`maxPct;
    / Log event
    `.risk.concentrationEvents insert (.z.p;`asset;`;sym;`rejected;limit`currentPct;newPct;limit`maxPct);
    :(0b;`assetConcentrationExceeded;`sym`current`new`max!(sym;limit`currentPct;newPct;limit`maxPct))
  ];

  / All checks passed
  (1b;`;()!())
 };

/ Update concentration after fill (post-fill)
updateConcentration:{[exchange;sym;qty;price]
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Update exchange concentration
  if[exchange in key .risk.exchangeConcentration;
    update currentValue:currentValue+notional from `.risk.exchangeConcentration where exchange=exchange;
  ];

  / Update asset concentration
  if[sym in key .risk.assetConcentration;
    update currentValue:currentValue+notional from `.risk.assetConcentration where sym=sym;
  ];

  / Recalculate percentages
  recalcConcentration[];

  / Log event
  `.risk.concentrationEvents insert (.z.p;`updated;exchange;sym;`accepted;0.0;0.0;0.0);
 };

/ Update portfolio total value (called periodically or on major events)
updatePortfolioValue:{[newTotalValue]
  / ROBUSTNESS: Validate input is finite
  if[(null newTotalValue) or (newTotalValue~0w) or (newTotalValue~-0w);
    -1 "CRITICAL: Invalid portfolio value received: ",string[newTotalValue];
    :(::)
  ];

  .risk.portfolioValue[`totalValue]:newTotalValue;
  .risk.portfolioValue[`lastUpdate]:.z.p;

  / Recalculate all concentration percentages
  recalcConcentration[];

  -1 "Portfolio value updated: ",string[newTotalValue]," USD";
 };

/ Recalculate all concentration percentages (internal helper)
recalcConcentration:{[]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.portfolioValue;
    -1 "CRITICAL: portfolioValue table corrupted (row count: ",string[count .risk.portfolioValue],")";
    :(::)
  ];

  totalValue:first .risk.portfolioValue`totalValue;

  / Avoid division by zero
  if[totalValue = 0.0;
    / Reset all percentages to zero
    update currentPct:0.0 from `.risk.exchangeConcentration;
    update currentPct:0.0 from `.risk.assetConcentration;
    :(::)
  ];

  / Recalculate exchange concentrations (vectorized)
  update currentPct:100.0 * currentValue % totalValue from `.risk.exchangeConcentration;

  / Recalculate asset concentrations (vectorized)
  update currentPct:100.0 * currentValue % totalValue from `.risk.assetConcentration;
 };

/ Get concentration status for monitoring
getConcentrationStatus:{[]
  `exchanges`assets`portfolio`recentEvents!(
    select from .risk.exchangeConcentration;
    select from .risk.assetConcentration;
    first select from .risk.portfolioValue;
    select from .risk.concentrationEvents where time>.z.p-01:00:00
  )
 };

\d .
