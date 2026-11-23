/ Risk Management — Portfolio Greeks Limits
/ Pre-trade validation for aggregate Greeks exposure

\d .risk

// ============================================================================
// GREEKS LIMITS SCHEMA
// ============================================================================

/ Portfolio Greeks limits (keyed by strategy)
greeksLimits:([strategy:`symbol$()]
  maxDelta:`float$();       / Max portfolio delta
  maxGamma:`float$();       / Max portfolio gamma
  maxTheta:`float$();       / Max portfolio theta (per day)
  maxVega:`float$();        / Max portfolio vega
  currentDelta:`float$();   / Current portfolio delta
  currentGamma:`float$();   / Current portfolio gamma
  currentTheta:`float$();   / Current portfolio theta
  currentVega:`float$()     / Current portfolio vega
 );

/ Greeks event log
greeksEvents:([]
  time:`timestamp$();
  strategy:`symbol$();
  contractId:`symbol$();
  side:`symbol$();
  qty:`long$();
  deltaChange:`float$();
  gammaChange:`float$();
  thetaChange:`float$();
  vegaChange:`float$();
  newDelta:`float$();
  newGamma:`float$();
  newTheta:`float$();
  newVega:`float$();
  action:`symbol$()  / `allowed or `rejected
 );

// ============================================================================
// INITIALIZATION
// ============================================================================

/ Initialize Greeks limits for a strategy
/ @param strategy symbol - Strategy name
/ @param maxDelta float - Max delta
/ @param maxGamma float - Max gamma
/ @param maxTheta float - Max theta (per day)
/ @param maxVega float - Max vega
initGreeksLimits:{[strategy;maxDelta;maxGamma;maxTheta;maxVega]
  `.risk.greeksLimits upsert (
    strategy;
    maxDelta;
    maxGamma;
    maxTheta;
    maxVega;
    0.0;
    0.0;
    0.0;
    0.0
  );
  -1 "Greeks limits initialized for strategy: ",string strategy;
 };

/ Initialize all strategies with default Greeks limits
initAllGreeksLimits:{[]
  / Clear existing limits
  delete from `.risk.greeksLimits;

  / Set default limits for common strategies
  / (Adjust these based on strategy risk appetite)
  initGreeksLimits[`coveredCall; 1000.0; 100.0; 500.0; 5000.0];
  initGreeksLimits[`ironCondor; 500.0; 50.0; 300.0; 3000.0];
  initGreeksLimits[`verticalSpread; 800.0; 80.0; 400.0; 4000.0];
  initGreeksLimits[`straddle; 1500.0; 150.0; 700.0; 7000.0];

  -1 "All Greeks limits initialized";
 };

// ============================================================================
// PRE-TRADE VALIDATION
// ============================================================================

/ Check if adding position would breach Greeks limits
/ @param strategy symbol - Strategy name
/ @param contractId symbol - Option contract ID
/ @param side symbol - `buy or `sell
/ @param qty long - Quantity (contracts)
/ @return tuple - (pass:boolean; reason:symbol; detail:dict)
checkGreeksLimit:{[strategy;cid;side;qty]
  / Check if strategy has limits configured
  if[not strategy in key .risk.greeksLimits;
    :(0b;`noGreeksLimitConfigured;(enlist `strategy)!enlist strategy)
  ];

  / Look up contract Greeks from latest quote
  quotes:select from .schema.optionQuote where contractId=cid;
  if[0 = count quotes;
    :(0b;`noQuoteAvailable;(enlist `contractId)!enlist cid)
  ];
  latestQuote:first quotes;

  / Extract Greeks
  delta:latestQuote`delta;
  gamma:latestQuote`gamma;
  theta:latestQuote`theta;
  vega:latestQuote`vega;

  / Apply sign based on side (buy = positive, sell = negative)
  signedQty:$[side=`buy; qty; neg qty];
  multiplier:100;  / Standard option multiplier

  / Calculate change in Greeks
  deltaChange:delta * signedQty * multiplier;
  gammaChange:gamma * signedQty * multiplier;
  thetaChange:theta * signedQty * multiplier;
  vegaChange:vega * signedQty * multiplier;

  / Get current limits
  limits:.risk.greeksLimits[strategy];

  / Calculate new portfolio Greeks
  newDelta:limits[`currentDelta] + deltaChange;
  newGamma:limits[`currentGamma] + gammaChange;
  newTheta:limits[`currentTheta] + thetaChange;
  newVega:limits[`currentVega] + vegaChange;

  / Check against limits (absolute value)
  detail:`contractId`side`qty`deltaChange`gammaChange`thetaChange`vegaChange`newDelta`newGamma`newTheta`newVega!(
    cid;side;qty;deltaChange;gammaChange;thetaChange;vegaChange;newDelta;newGamma;newTheta;newVega
  );

  / Delta check
  if[abs[newDelta] > limits`maxDelta;
    :(0b;`deltaLimitExceeded;detail)
  ];

  / Gamma check
  if[abs[newGamma] > limits`maxGamma;
    :(0b;`gammaLimitExceeded;detail)
  ];

  / Theta check
  if[abs[newTheta] > limits`maxTheta;
    :(0b;`thetaLimitExceeded;detail)
  ];

  / Vega check
  if[abs[newVega] > limits`maxVega;
    :(0b;`vegaLimitExceeded;detail)
  ];

  / All checks passed
  (1b;`;detail)
 };

// ============================================================================
// POST-FILL UPDATES
// ============================================================================

/ Update Greeks exposure after fill (idempotent, atomic)
/ @param strategy symbol - Strategy name
/ @param contractId symbol - Option contract ID
/ @param side symbol - `buy or `sell
/ @param qty long - Quantity (contracts)
/ @return tuple - (success:boolean; reason:symbol; detail:dict)
updateGreeksExposure:{[strategy;cid;side;qty]
  / SAFETY CHECK: Ensure strategy has limits configured
  if[not strategy in key .risk.greeksLimits;
    .risk.logRiskEvent[.z.p;`unconfiguredGreeksLimit;strategy;`;`;((enlist `contractId)!enlist cid);`reject;`critical];
    -1 "CRITICAL: Attempted to update Greeks for unconfigured strategy: ",string strategy;
    :(0b;`unconfiguredStrategy;(enlist `strategy)!enlist strategy)
  ];

  / Look up contract Greeks from latest quote
  quotes:select from .schema.optionQuote where contractId=cid;
  if[0 = count quotes;
    -1 "WARNING: No quote available for contractId: ",string cid," (Greeks not updated)";
    :(0b;`noQuoteAvailable;(enlist `contractId)!enlist cid)
  ];
  latestQuote:first quotes;

  / Extract Greeks
  delta:latestQuote`delta;
  gamma:latestQuote`gamma;
  theta:latestQuote`theta;
  vega:latestQuote`vega;

  / Apply sign based on side
  signedQty:$[side=`buy; qty; neg qty];
  multiplier:100;

  / Calculate change in Greeks
  deltaChange:delta * signedQty * multiplier;
  gammaChange:gamma * signedQty * multiplier;
  thetaChange:theta * signedQty * multiplier;
  vegaChange:vega * signedQty * multiplier;

  / ATOMIC UPDATE: Read current state, compute new state, write with upsert
  / Keyed table upsert is atomic in single-threaded q
  currentLimits:.risk.greeksLimits[strategy];

  / Compute new state
  newDelta:currentLimits[`currentDelta] + deltaChange;
  newGamma:currentLimits[`currentGamma] + gammaChange;
  newTheta:currentLimits[`currentTheta] + thetaChange;
  newVega:currentLimits[`currentVega] + vegaChange;

  / Upsert atomically (keyed table upsert is atomic)
  `.risk.greeksLimits upsert (
    strategy;
    currentLimits`maxDelta;
    currentLimits`maxGamma;
    currentLimits`maxTheta;
    currentLimits`maxVega;
    newDelta;
    newGamma;
    newTheta;
    newVega
  );

  / Get updated values
  newLimits:.risk.greeksLimits[strategy];

  / Log event
  `.risk.greeksEvents insert (
    .z.p;strategy;cid;side;qty;
    deltaChange;gammaChange;thetaChange;vegaChange;
    newLimits`currentDelta;newLimits`currentGamma;newLimits`currentTheta;newLimits`currentVega;
    `allowed
  );

  -1 "Greeks updated for ",string[strategy],": Delta=",string[newLimits`currentDelta],
     " Gamma=",string[newLimits`currentGamma]," Theta=",string[newLimits`currentTheta]," Vega=",string[newLimits`currentVega];

  / Return success
  (1b;`;`deltaChange`gammaChange`thetaChange`vegaChange!(deltaChange;gammaChange;thetaChange;vegaChange))
 };

\d .

/ Export namespace
-1 "  Greeks limits loaded: checkGreeksLimit, updateGreeksExposure, initGreeksLimits";
