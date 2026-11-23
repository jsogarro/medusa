/ Risk Management — Pre-Trade Validation Pipeline
/ Unified validation function called before every order

\d .risk

/ Log a risk event
logRiskEvent:{[time;eventType;strategy;sym;exchange;details;action;severity]
  riskEvents::riskEvents,enlist `time`eventType`strategy`sym`exchange`details`action`severity!(
    time;eventType;strategy;sym;exchange;details;action;severity
  );
 };

/ Pre-trade risk validation (run before every order submission)
/ Returns: (pass:boolean; reason:symbol)
validateOrder:{[strategy;sym;exchange;side;qty;price]
  / Log validation attempt
  if[`log in key `.;
    .log.event[`INFO;`risk;`validateOrder;`strategy`sym`exchange`side`qty`price!(strategy;sym;exchange;side;qty;price)]
  ];
  isOpt:$[`schema in key `.; .schema.isOption[sym]; 0b];
  isEq:$[`schema in key `.; .schema.isEquity[sym]; 0b];

  / Check 0: Market hours (equity only)
  result:checkMarketHours[exchange;sym];
  if[not result 0;
    logRiskEvent[.z.p;`marketClosedBlock;strategy;sym;exchange;();`reject;`warning];
    if[`log in key `.; .log.event[`WARN;`risk;`orderRejected;`strategy`sym`reason!(strategy;sym;`marketClosed)]];
    :result];

  / Check 1: Emergency stop
  result:checkEmergencyStop[];
  if[not result 0;
    logRiskEvent[.z.p;`emergencyStopBlock;strategy;sym;exchange;();`reject;`critical];
    if[`log in key `.; .log.event[`CRITICAL;`risk;`orderRejected;`strategy`sym`reason!(strategy;sym;`emergencyStop)]];
    :result];

  / Check 2: Drawdown halt
  result:checkDrawdownHalt[];
  if[not result 0;
    logRiskEvent[.z.p;`drawdownBlock;strategy;sym;exchange;();`reject;`critical];
    :result];

  / Check 3: Circuit breaker
  result:checkCircuitBreaker[strategy];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction (avoid crash if result is 2-tuple)
    logRiskEvent[.z.p;`circuitBreakerBlock;strategy;sym;exchange;details;`reject;`critical];
    :result];

  / Check 4: Rate limiting
  if[0=count .risk.globalRateLimits; initRateLimits[]];
  result:checkRateLimit[exchange;sym];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction
    logRiskEvent[.z.p;`rateLimitViolation;strategy;sym;exchange;details;`reject;`warning];
    :result];

  / Check 5: Order size limits
  result:checkOrderSizeLimit[strategy;qty];
  if[not result 0;
    logRiskEvent[.z.p;`orderSizeViolation;strategy;sym;exchange;`qty`limit!(qty;result 1);`reject;`warning];
    :result];

  / Check 6: Position limits
  result:checkPositionLimit[strategy;sym;side;qty];
  if[not result 0;
    logRiskEvent[.z.p;`positionLimitBreach;strategy;sym;exchange;`side`qty`reason!(side;qty;result 1);`reject;`warning];
    :result];

  / Check 7: Exchange concentration
  result:checkExchangeConcentration[exchange;qty;price];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction
    logRiskEvent[.z.p;`exchangeConcentrationBreach;strategy;sym;exchange;details;`reject;`warning];
    :result];

  / Check 8: Asset concentration
  result:checkAssetConcentration[sym;qty;price];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction
    logRiskEvent[.z.p;`assetConcentrationBreach;strategy;sym;exchange;details;`reject;`warning];
    :result];

  / Check 9: Correlation limits
  result:checkCorrelationLimit[sym;qty;price];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction
    logRiskEvent[.z.p;`correlationLimitBreach;strategy;sym;exchange;details;`reject;`warning];
    :result];

  / Check 10: Exposure limits
  result:checkExposureLimit[exchange;qty;price];
  if[not result 0;
    logRiskEvent[.z.p;`exposureBreach;strategy;sym;exchange;`qty`price`notional!(qty;price;abs[qty]*price);`reject;`warning];
    :result];

  / Check 11: Market impact
  result:checkMarketImpact[exchange;sym;side;qty;price];
  if[not result 0;
    details:$[2<count result; result 2; ()];  / Safe extraction
    logRiskEvent[.z.p;`marketImpactBreach;strategy;sym;exchange;details;`reject;`warning];
    :result];

  / Check 12: Greeks limits (if option)
  if[isOpt;
    result:checkGreeksLimit[strategy;sym;side;qty];
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`greeksLimitBreach;strategy;sym;exchange;details;`reject;`warning];
      :result];
  ];

  / Check 13: Margin requirements (if option)
  if[isOpt;
    / Get available cash (from balance or marginSummary)
    cashAvail:first .risk.marginSummary`availableCash;
    newPosition:`contractId`side`qty`avgEntryPrice!(sym;side;qty;price);
    result:checkMarginAvailable[newPosition;cashAvail];
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`marginInsufficientBreach;strategy;sym;exchange;details;`reject;`critical];
      :result];
  ];

  / Check 14: Expiry risk (if option expiring within 3 days)
  if[isOpt;
    contract:.schema.optionContract[sym];
    if[not ()~contract;
      daysToExpiry:contract[`expiry] - .z.d;
      if[daysToExpiry <= 3;
        logRiskEvent[.z.p;`expiryRiskWarning;strategy;sym;exchange;`daysToExpiry!daysToExpiry;`warn;`warning];
        / Allow but warn
      ];
    ];
  ];

  / Check 15: Quote freshness (if option, reject if quote older than 5 min)
  if[isOpt;
    result:checkQuoteFreshness[sym;300000000000];  / 5 min in nanos
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`staleQuoteBreach;strategy;sym;exchange;details;`reject;`critical];
      :result];
  ];

  / ═══════════════════════════════════════════════════════════════════
  / Phase 3: Alpaca-Specific Equity Regulations
  / ═══════════════════════════════════════════════════════════════════

  / Check 16: PDT rule (equity only)
  if[isEq;
    result:checkPDT[sym;side;qty];
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`pdtBreach;strategy;sym;exchange;details;`reject;`critical];
      :result];
  ];

  / Check 17: Margin requirement (equity only)
  if[isEq;
    result:checkMarginAvailable[sym;qty;price];
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`marginInsufficientBreach;strategy;sym;exchange;details;`reject;`critical];
      :result];
  ];

  / Check 18: Freeriding violation (equity only)
  if[isEq;
    result:checkFreeridingViolation[sym;side;qty;price];
    if[not result 0;
      details:$[2<count result; result 2; ()];  / Safe extraction
      logRiskEvent[.z.p;`freeridingViolation;strategy;sym;exchange;details;`reject;`critical];
      :result];
  ];

  / All checks passed
  (1b;`)
 };

/ Post-fill updates (call after order fill)
onFill:{[strategy;sym;exchange;side;qty;price]
  signedQty:$[side=`buy;qty;neg qty];
  updatePosition[strategy;sym;signedQty];
  updateDailyVolume[strategy;qty];
  updateExposure[exchange;sym;signedQty;price];

  / Phase 3: Alpaca equity regulations (equity only)
  if[.schema.isEquity[sym];
    / Record settlement (T+1)
    recordSettlement[.z.d;sym;side;qty;price];

    / TODO: Day trade detection requires position tracking to detect round-trips
    / This will be implemented when position manager is available
  ];
 };

/ Enhanced post-fill updates with advanced risk controls
/ signalType: type of signal that generated this trade (e.g., `arb, `momentum, `meanReversion)
onFillEnhanced:{[strategy;sym;exchange;side;qty;price;signalType]
  / Execute standard onFill updates
  signedQty:$[side=`buy;qty;neg qty];
  updatePosition[strategy;sym;signedQty];
  updateDailyVolume[strategy;qty];
  updateExposure[exchange;sym;signedQty;price];

  / Update advanced risk controls
  updateConcentration[exchange;sym;qty;price];
  updateCorrelationExposure[sym;qty;price];

  / Record fill for P&L attribution
  recordFill[strategy;exchange;sym;side;qty;price;signalType];

  / Update intraday risk modules (if loaded)
  if[not ()~key `.risk.updatePnLOnFill; updatePnLOnFill[strategy;exchange;sym;side;qty;price]];
  if[not ()~key `.risk.recalcExposureGrid; recalcExposureGrid[]];
 };

/ Post-PnL updates (call on P&L change)
onPnLUpdate:{[currentPnL]
  breached:updatePnL[currentPnL];
  / If drawdown breached, activate emergency stop
  if[breached;activateEmergencyStop[`drawdownBreach;`system]];
 };

/ Get risk status summary (operational dashboard)
status:{[]
  `positions`globalPositions`orderLimits`globalOrderLimits`exposure`globalExposure`drawdown`emergencyStop`recentEvents!(
    select from .risk.positionLimits;
    select from .risk.globalPositionLimits;
    select from .risk.orderSizeLimits;
    first select from .risk.globalOrderSizeLimits;
    select from .risk.exposureLimits;
    first select from .risk.globalExposureLimit;
    first select from .risk.drawdownState;
    first select from .risk.emergencyStopState;
    select from .risk.riskEvents where time>.z.p-01:00:00
  )
 };

\d .
