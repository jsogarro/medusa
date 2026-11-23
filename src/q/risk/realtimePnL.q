/ Real-Time P&L Monitoring
/ Tracks P&L across all dimensions with alert thresholds

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ P&L Tables
/ ═══════════════════════════════════════════════════════════════════

/ Real-time P&L state (single-row table, updated continuously)
intradayPnL:([]
  totalPnL:`float$();
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  dayOpenPnL:`float$();
  dayChangePnL:`float$();
  dayChangePct:`float$();
  lastUpdate:`timestamp$()
 );

/ P&L by strategy (keyed table)
pnlByStrategyRT:([strategy:`symbol$()]
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  totalPnL:`float$();
  tradeCount:`int$();
  winCount:`int$();
  lossCount:`int$();
  winRate:`float$();
  lastUpdate:`timestamp$()
 );

/ P&L by exchange (keyed table)
pnlByExchangeRT:([exchange:`symbol$()]
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  totalPnL:`float$();
  tradeCount:`int$();
  lastUpdate:`timestamp$()
 );

/ P&L by asset (keyed table)
pnlByAssetRT:([sym:`symbol$()]
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  totalPnL:`float$();
  tradeCount:`int$();
  lastUpdate:`timestamp$()
 );

/ P&L alert thresholds (keyed by severity)
pnlAlertThresholds:([severity:`symbol$()]
  lossPct:`float$();
  lossAbsolute:`float$();
  breached:`boolean$();
  breachTime:`timestamp$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

initRealtimePnL:{[]
  / Initialize P&L state to zero
  `.risk.intradayPnL set ([] totalPnL:enlist 0.0; realizedPnL:enlist 0.0; unrealizedPnL:enlist 0.0;
                             dayOpenPnL:enlist 0.0; dayChangePnL:enlist 0.0; dayChangePct:enlist 0.0;
                             lastUpdate:enlist .z.p);

  / Clear aggregated tables
  delete from `.risk.pnlByStrategyRT;
  delete from `.risk.pnlByExchangeRT;
  delete from `.risk.pnlByAssetRT;

  / Set default alert thresholds
  delete from `.risk.pnlAlertThresholds;
  `.risk.pnlAlertThresholds upsert (`warn; 2.0; 5000.0; 0b; 0Np);
  `.risk.pnlAlertThresholds upsert (`halt; 5.0; 15000.0; 0b; 0Np);

  -1 "  Real-time P&L initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ P&L Calculation (FIFO accounting)
/ ═══════════════════════════════════════════════════════════════════

/ Calculate realized P&L for a fill using FIFO accounting
/ Returns: realized P&L (float)
calculateRealizedPnL:{[strategy;sym;side;qty;price]
  / Get current position
  pos:first select from .schema.position where strategy=strategy, sym=sym;

  / If no position exists, this is an opening trade (realized P&L = 0)
  if[()~pos; :0.0];

  currentQty:pos`quantity;
  avgEntry:pos`avgEntryPrice;

  / If opening position (same sign as side), no realized P&L
  if[currentQty * $[side=`buy;1;-1] >= 0; :0.0];

  / Closing or reducing position — calculate realized P&L
  / FIFO: realized on the quantity being closed
  closedQty:min[qty; abs currentQty];
  exitPrice:price;
  entryPrice:avgEntry;

  / P&L = (exitPrice - entryPrice) * closedQty * direction
  pnl:$[side=`buy; (exitPrice - entryPrice) * closedQty; (entryPrice - exitPrice) * closedQty];
  pnl
 };

/ ═══════════════════════════════════════════════════════════════════
/ Update Functions (called from onFillEnhanced)
/ ═══════════════════════════════════════════════════════════════════

/ Update strategy-level P&L aggregation
updateStrategyPnLRT:{[strat;realizedPnL;unrealizedPnL]
  rows:0!.risk.pnlByStrategyRT;

  if[not strat in rows`strategy;
    / Initialize new strategy
    rows,:enlist `strategy`realizedPnL`unrealizedPnL`totalPnL`tradeCount`winCount`lossCount`winRate`lastUpdate!(strat;0.0;0.0;0.0;0i;0i;0i;0.0;.z.p);
  ];

  existing:first select from rows where strategy=strat;

  / Update realized and total
  newRealized:existing[`realizedPnL] + realizedPnL;
  newTotal:newRealized + existing[`unrealizedPnL];
  newTradeCount:existing[`tradeCount] + 1i;

  / Update win/loss counts
  newWinCount:existing[`winCount] + $[realizedPnL > 0; 1i; 0i];
  newLossCount:existing[`lossCount] + $[realizedPnL < 0; 1i; 0i];
  newWinRate:$[newTradeCount > 0; 100.0 * newWinCount % newTradeCount; 0.0];

  rows:update realizedPnL:newRealized, unrealizedPnL:existing`unrealizedPnL, totalPnL:newTotal,
              tradeCount:newTradeCount, winCount:newWinCount, lossCount:newLossCount,
              winRate:newWinRate, lastUpdate:.z.p from rows where strategy=strat;
  `.risk.pnlByStrategyRT set `strategy xkey rows;
 };

/ Update exchange-level P&L aggregation
updateExchangePnLRT:{[exch;realizedPnL;unrealizedPnL]
  rows:0!.risk.pnlByExchangeRT;

  if[not exch in rows`exchange;
    rows,:enlist `exchange`realizedPnL`unrealizedPnL`totalPnL`tradeCount`lastUpdate!(exch;0.0;0.0;0.0;0i;.z.p);
  ];

  existing:first select from rows where exchange=exch;

  / Update
  newRealized:existing[`realizedPnL] + realizedPnL;
  newTotal:newRealized + existing[`unrealizedPnL];
  newTradeCount:existing[`tradeCount] + 1i;

  rows:update realizedPnL:newRealized, unrealizedPnL:existing`unrealizedPnL, totalPnL:newTotal,
              tradeCount:newTradeCount, lastUpdate:.z.p from rows where exchange=exch;
  `.risk.pnlByExchangeRT set `exchange xkey rows;
 };

/ Update asset-level P&L aggregation
updateAssetPnLRT:{[asset;realizedPnL;unrealizedPnL]
  rows:0!.risk.pnlByAssetRT;

  if[not asset in rows`sym;
    rows,:enlist `sym`realizedPnL`unrealizedPnL`totalPnL`tradeCount`lastUpdate!(asset;0.0;0.0;0.0;0i;.z.p);
  ];

  existing:first select from rows where sym=asset;

  / Update
  newRealized:existing[`realizedPnL] + realizedPnL;
  newTotal:newRealized + existing[`unrealizedPnL];
  newTradeCount:existing[`tradeCount] + 1i;

  rows:update realizedPnL:newRealized, unrealizedPnL:existing`unrealizedPnL, totalPnL:newTotal,
              tradeCount:newTradeCount, lastUpdate:.z.p from rows where sym=asset;
  `.risk.pnlByAssetRT set `sym xkey rows;
 };

/ ═══════════════════════════════════════════════════════════════════
/ P&L Updates (called from validate.q onFillEnhanced)
/ ═══════════════════════════════════════════════════════════════════

/ Update P&L on fill
updatePnLOnFill:{[strategy;exchange;sym;side;qty;price]
  / Calculate realized P&L for this fill
  realizedPnL:calculateRealizedPnL[strategy;sym;side;qty;price];

  / Update aggregations
  updateStrategyPnLRT[strategy;realizedPnL;0.0];
  updateExchangePnLRT[exchange;realizedPnL;0.0];
  updateAssetPnLRT[sym;realizedPnL;0.0];

  / Update total realized P&L
  currentRealized:first .risk.intradayPnL`realizedPnL;
  .risk.intradayPnL[`realizedPnL]:currentRealized + realizedPnL;
  .risk.intradayPnL[`totalPnL]:(first .risk.intradayPnL`realizedPnL) + first .risk.intradayPnL`unrealizedPnL;
  .risk.intradayPnL[`lastUpdate]:.z.p;

  / Recalc day change
  recalcDayChange[];

  / Check alert thresholds
  checkPnLAlerts[];
 };

/ Recalculate day change metrics
recalcDayChange:{[]
  totalPnL:first .risk.intradayPnL`totalPnL;
  dayOpen:first .risk.intradayPnL`dayOpenPnL;
  dayChange:totalPnL - dayOpen;
  dayChangePct:$[dayOpen <> 0.0; 100.0 * dayChange % dayOpen; 0.0];

  .risk.intradayPnL[`dayChangePnL]:dayChange;
  .risk.intradayPnL[`dayChangePct]:dayChangePct;
 };

/ ═══════════════════════════════════════════════════════════════════
/ Alert Threshold Checking
/ ═══════════════════════════════════════════════════════════════════

/ Check P&L alert thresholds
checkPnLAlerts:{[]
  currentPnL:first .risk.intradayPnL`totalPnL;
  dayOpen:first .risk.intradayPnL`dayOpenPnL;
  dayChange:currentPnL - dayOpen;
  dayChangePct:$[dayOpen <> 0.0; 100.0 * dayChange % dayOpen; 0.0];

  / Check warn threshold
  warnThreshold:first select from .risk.pnlAlertThresholds where severity=`warn;
  if[not ()~warnThreshold;
    warnLossPct:warnThreshold`lossPct;
    warnLossAbs:warnThreshold`lossAbsolute;
    if[(abs[dayChangePct] > warnLossPct) or (abs[dayChange] > warnLossAbs);
      if[not first warnThreshold`breached;
        / Log alert
        .risk.logRiskEvent[.z.p;`pnlWarnThreshold;`;`;`;`loss`pct!(dayChange;dayChangePct);`warn;`warning];
        / Update breached flag
        update breached:1b, breachTime:.z.p from `.risk.pnlAlertThresholds where severity=`warn;
      ];
    ];
  ];

  / Check halt threshold
  haltThreshold:first select from .risk.pnlAlertThresholds where severity=`halt;
  if[not ()~haltThreshold;
    haltLossPct:haltThreshold`lossPct;
    haltLossAbs:haltThreshold`lossAbsolute;
    if[(abs[dayChangePct] > haltLossPct) or (abs[dayChange] > haltLossAbs);
      if[not first haltThreshold`breached;
        / Log critical alert
        .risk.logRiskEvent[.z.p;`pnlHaltThreshold;`;`;`;`loss`pct!(dayChange;dayChangePct);`halt;`critical];
        / Update breached flag
        update breached:1b, breachTime:.z.p from `.risk.pnlAlertThresholds where severity=`halt;
        / Trigger emergency stop
        .risk.activateEmergencyStop[`pnlHaltBreach;`system];
      ];
    ];
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Query Functions (for UI)
/ ═══════════════════════════════════════════════════════════════════

/ Get P&L by strategy
pnl.byStrategy:{[]
  select from .risk.pnlByStrategyRT
 };

/ Get P&L by exchange
pnl.byExchange:{[]
  select from .risk.pnlByExchangeRT
 };

/ Get P&L by asset
pnl.byAsset:{[]
  select from .risk.pnlByAssetRT
 };

/ Get intraday P&L summary
pnl.intraday:{[]
  first select from .risk.intradayPnL
 };

\d .
