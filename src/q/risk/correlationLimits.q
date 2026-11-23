/ Risk Management — Correlation-Based Group Exposure Limits
/ Rolling correlation matrix with group-based exposure limits
/ Performance: <20μs per check

\d .risk

/ Initialize correlation groups with default crypto asset classes
initCorrelationGroups:{[]
  / Clear existing groups
  delete from `.risk.correlationGroups;
  delete from `.risk.correlationMatrix;
  delete from `.risk.correlationEvents;

  / Default correlation groups (crypto asset classes)
  / btcGroup: BTC and highly correlated (>0.8 correlation)
  / ethGroup: ETH and L1/L2 platforms
  / altGroup: Altcoins with lower market cap
  / stableGroup: Stablecoins and cash equivalents
  `.risk.correlationGroups upsert ([]
    groupId:`btcGroup`ethGroup`altGroup`stableGroup;
    members:(`BTCUSD`BTCEUR;`ETHUSD`ETHEUR;`ADAUSD`SOLUSD`AVAXUSD;`USDTUSD`USDCUSD);
    maxExposure:250000 200000 150000 500000f;
    currentExposure:0 0 0 0f;
    lastUpdate:.z.p .z.p .z.p .z.p
  );

  / Initialize empty correlation matrix (populated by background updater)
  `.risk.correlationMatrix set ([] sym1:`symbol$(); sym2:`symbol$(); correlation:`float$(); lastUpdate:`timestamp$());

  -1 "Correlation groups initialized: ",string[count .risk.correlationGroups]," groups";
 };

/ Calculate rolling correlation between two price series
/ Helper function (not part of hot path)
calcRollingCorrelation:{[prices1;prices2;window]
  / Return 0.0 if insufficient data
  if[(count prices1) < window; :0.0];
  if[(count prices2) < window; :0.0];

  / Take last N observations
  p1:neg[window]#prices1;
  p2:neg[window]#prices2;

  / Calculate Pearson correlation coefficient
  / cor = covariance(X,Y) / (stddev(X) * stddev(Y))
  n:count p1;
  meanP1:avg p1;
  meanP2:avg p2;

  covariance:(sum (p1-meanP1) * (p2-meanP2)) % n;
  stdP1:sqrt (sum (p1-meanP1) xexp 2) % n;
  stdP2:sqrt (sum (p2-meanP2) xexp 2) % n;

  / Handle division by zero
  if[(stdP1 = 0.0) or (stdP2 = 0.0); :0.0];

  covariance % (stdP1 * stdP2)
 };

/ Update correlation matrix (background job — run hourly)
/ This is NOT part of the hot path
updateCorrelationMatrix:{[priceData]
  / priceData: table with columns (time;sym;price)
  / Build pairwise correlation matrix for all symbols

  / Get unique symbols
  syms:exec distinct sym from priceData;

  / Calculate correlation for each pair (upper triangle only)
  pairs:raze {[s1;syms] {[s1;s2] (s1;s2)} [s1] each syms where syms > s1} [;syms] each syms;

  / Calculate correlations
  correlations:{[priceData;pair]
    s1:pair 0;
    s2:pair 1;
    p1:exec price from priceData where sym=s1;
    p2:exec price from priceData where sym=s2;
    corr:calcRollingCorrelation[p1;p2;100]; / 100-period rolling window
    (s1;s2;corr;.z.p)
  }[priceData] each pairs;

  / Update matrix (atomic replacement)
  `.risk.correlationMatrix set flip `sym1`sym2`correlation`lastUpdate!flip correlations;

  -1 "Correlation matrix updated: ",string[count correlations]," pairs";
 };

/ Check correlation group exposure limit (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <20μs per check
checkCorrelationLimit:{[sym;qty;price]
  / Find which correlation group this symbol belongs to
  groupIds:exec groupId from .risk.correlationGroups where sym in/:members;

  / If symbol not in any group, pass
  if[0=count groupIds; :(1b;`;()!())];
  groupId:first groupIds;

  / Calculate notional exposure from this order (use .money for precision)
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Use keyed table indexing for O(1) lookup
  grp:.risk.correlationGroups[groupId];

  / FAIL-SAFE: reject if no limits configured
  if[null grp`maxExposure;
    :(0b;`noCorrelationLimitConfigured;`groupId`sym!(groupId;sym))
  ];

  / Check if adding this exposure would breach the group limit
  newExposure:grp[`currentExposure] + notional;

  if[newExposure > grp`maxExposure;
    / Log event
    `.risk.correlationEvents insert (.z.p;groupId;sym;`rejected;grp`currentExposure;notional;newExposure;grp`maxExposure);
    :(0b;`correlationGroupLimitExceeded;`groupId`sym`current`added`new`max!(groupId;sym;grp`currentExposure;notional;newExposure;grp`maxExposure))
  ];

  / All checks passed
  (1b;`;()!())
 };

/ Update correlation exposure (post-fill)
updateCorrelationExposure:{[sym;qty;price]
  / Find which correlation group this symbol belongs to
  groupIds:exec groupId from .risk.correlationGroups where sym in/:members;

  / If symbol not in any group, return
  if[0=count groupIds; :(::)];
  groupId:first groupIds;

  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / SAFETY CHECK: Ensure group entry exists
  if[not groupId in key .risk.correlationGroups;
    .risk.logRiskEvent[.z.p;`unconfiguredCorrelationGroup;`;sym;`;`groupId`qty`price!(groupId;qty;price);`reject;`critical];
    -1 "CRITICAL: Attempted to update correlation exposure for unconfigured group: ",string[groupId];
    :(::)
  ];

  / Update group exposure atomically
  update currentExposure:currentExposure+notional, lastUpdate:.z.p from `.risk.correlationGroups where groupId=groupId;

  / Log event (single keyed lookup instead of triple table scan)
  grp:.risk.correlationGroups[groupId];
  `.risk.correlationEvents insert (.z.p;groupId;sym;`updated;grp[`currentExposure]-notional;notional;grp`currentExposure;grp`maxExposure);
 };

/ Set correlation group exposure limit
setCorrelationGroupLimit:{[groupId;maxExposure]
  / Validation: group must exist
  if[not groupId in exec groupId from .risk.correlationGroups;
    -1 "ERROR: Cannot set limit for non-existent group: ",string[groupId];
    :0b
  ];

  / Update limit
  update maxExposure:maxExposure from `.risk.correlationGroups where groupId=groupId;
  -1 "Correlation group limit set: ",string[groupId]," [",string[maxExposure]," USD]";
  1b
 };

\d .
