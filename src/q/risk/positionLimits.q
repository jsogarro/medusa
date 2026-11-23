/ Risk Management — Position Limit Checker
/ Per-strategy and global position limit validation

\d .risk

/ Set position limits for a strategy/symbol
setPositionLimit:{[strategy;sym;maxLong;maxShort]
  $[(strategy;sym) in key .risk.positionLimits;
    / Key exists — update limits, preserve currentPosition
    update maxLongQty:maxLong,maxShortQty:maxShort from `.risk.positionLimits where strategy=strategy,sym=sym;
    / New entry — insert with zero position
    `.risk.positionLimits upsert ([] strategy:enlist strategy; sym:enlist sym; maxLongQty:enlist maxLong; maxShortQty:enlist maxShort; currentPosition:enlist 0j)
  ];
  -1 "Position limit set: ",string[strategy]," ",string[sym]," [",string[maxLong],"/",string[maxShort],"]";
 };

/ Set global position limits for a symbol
setGlobalPositionLimit:{[sym;maxLong;maxShort]
  `.risk.globalPositionLimits upsert ([] sym:enlist sym; maxLongQty:enlist maxLong; maxShortQty:enlist maxShort; currentPosition:enlist 0j);
  -1 "Global position limit set: ",string[sym]," [",string[maxLong],"/",string[maxShort],"]";
 };

/ Update current position (called on fill)
/ qty is signed: positive for buy, negative for sell
/ CRITICAL: This function now REQUIRES limits to be pre-configured via setPositionLimit[]
updatePosition:{[strategy;sym;qty]
  / SAFETY CHECK: Ensure strategy/sym entry exists (fail-safe)
  if[not (strategy;sym) in key .risk.positionLimits;
    / CRITICAL: Log error and reject fill (limits must be set before trading)
    .risk.logRiskEvent[.z.p;`unconfiguredStrategyPosition;strategy;sym;`;`qty!qty;`reject;`critical];
    -1 "CRITICAL: Attempted to update position for unconfigured strategy/sym: ",string[strategy]," ",string[sym];
    :(::)
  ];
  / Update strategy-level position (atomic)
  update currentPosition:currentPosition+qty from `.risk.positionLimits where strategy=strategy,sym=sym;

  / SAFETY CHECK: Ensure global entry exists (fail-safe)
  if[not sym in key .risk.globalPositionLimits;
    / CRITICAL: Log error and reject fill
    .risk.logRiskEvent[.z.p;`unconfiguredGlobalPosition;strategy;sym;`;`qty!qty;`reject;`critical];
    -1 "CRITICAL: Attempted to update global position for unconfigured sym: ",string[sym];
    :(::)
  ];
  / Update global position (atomic)
  update currentPosition:currentPosition+qty from `.risk.globalPositionLimits where sym=sym;
 };

/ Check position limit (pre-trade)
/ Returns: (pass:boolean; reason:symbol)
/ HOT PATH: Optimized to use keyed table indexing (O(1)) instead of select (O(n))
checkPositionLimit:{[strategy;sym;side;qty]
  / Use keyed table indexing for O(1) lookup (strategy;sym is the key)
  stratLimits:.risk.positionLimits[(strategy;sym)];

  / FAIL-SAFE: reject if no limits configured (missing key returns null values)
  if[null stratLimits`maxLongQty;
    :(0b;`noStrategyLimitConfigured)
  ];

  / Use keyed table indexing for O(1) lookup (sym is the key)
  globalLimits:.risk.globalPositionLimits[sym];

  / FAIL-SAFE: reject if no limits configured (missing key returns null values)
  if[null globalLimits`maxLongQty;
    :(0b;`noGlobalLimitConfigured)
  ];

  / Extract current positions (keyed table result is a dict)
  stratPos:stratLimits`currentPosition;
  globalPos:globalLimits`currentPosition;

  / Calculate new position after order
  newQty:$[side=`buy;qty;neg qty];
  newStratPos:stratPos+newQty;
  newGlobalPos:globalPos+newQty;

  / Check strategy limits (direct dict access)
  if[newStratPos>stratLimits`maxLongQty;:(0b;`strategyLongLimitExceeded)];
  if[newStratPos<neg stratLimits`maxShortQty;:(0b;`strategyShortLimitExceeded)];

  / Check global limits (direct dict access)
  if[newGlobalPos>globalLimits`maxLongQty;:(0b;`globalLongLimitExceeded)];
  if[newGlobalPos<neg globalLimits`maxShortQty;:(0b;`globalShortLimitExceeded)];

  / All checks passed
  (1b;`)
 };

/ Adjust position limits (operational function — can be called while trading)
adjustPositionLimit:{[strategy;sym;newMaxLong;newMaxShort;user]
  / Validation: new limits must be >= current position
  if[not (strategy;sym) in key .risk.positionLimits;
    -1 "ERROR: Cannot adjust limit for unconfigured strategy/sym: ",string[strategy]," ",string[sym];
    :0b
  ];
  currentPos:first exec currentPosition from .risk.positionLimits where strategy=strategy,sym=sym;
  if[(currentPos>newMaxLong) or (currentPos<neg newMaxShort);
    -1 "ERROR: Cannot set limit below current position. Position: ",string[currentPos]," NewLimits: ",string[newMaxLong],"/",string[newMaxShort];
    :0b
  ];
  / Update limits
  update maxLongQty:newMaxLong,maxShortQty:newMaxShort from `.risk.positionLimits where strategy=strategy,sym=sym;
  / Log event
  .risk.logRiskEvent[.z.p;`positionLimitAdjusted;strategy;sym;`;`user`newLong`newShort!(user;newMaxLong;newMaxShort);`update;`info];
  -1 "Position limit adjusted by ",string[user],": ",string[strategy]," ",string[sym]," [",string[newMaxLong],"/",string[newMaxShort],"]";
  1b
 };

\d .
