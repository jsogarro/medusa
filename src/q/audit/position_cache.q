/ ============================================================================
/ position_cache.q - Position Cache Audit
/ ============================================================================
/
/ Verifies that cached positions (stored for performance) match positions
/ calculated from transaction/ledger history. Stale cache entries indicate
/ missed updates or backdated transactions.
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - engine/position.q (.engine.position.cache, .engine.position.queryDB)
/
/ Usage:
/   .audit.POSITION_CACHE.validate[]
/   .audit.run[`POSITION_CACHE_AUDIT]
/ ============================================================================

\d .audit

/ ============================================================================
/ POSITION CACHE AUDIT NAMESPACE
/ ============================================================================

/ Tolerance for position comparisons (1 satoshi)
POSITION_CACHE.tolerance:0.00000001f;

/ Compare cached position to freshly calculated position
/ @param exchange symbol
/ @param asset symbol
/ @param strategyId symbol
/ @return dict - (matches; cachedQty; calculatedQty; delta)
POSITION_CACHE.comparePosition:{[exchange;asset;strategyId]
  cacheKey:(exchange;asset;strategyId);

  / Get cached position
  cachedQty:$[cacheKey in key .engine.position.cache;
    .engine.position.cache[cacheKey;`quantity];
    0f
  ];

  / Calculate from database (bypassing cache)
  calculated:@[.engine.position.queryDB;(exchange;asset;strategyId);{`quantity`avgPrice!(0f;0f)}];
  calculatedQty:calculated`quantity;

  delta:abs cachedQty - calculatedQty;
  `matches`cachedQty`calculatedQty`delta!(delta<=.audit.POSITION_CACHE.tolerance; cachedQty; calculatedQty; delta)
 };

/ ============================================================================
/ MAIN VALIDATION FUNCTION
/ ============================================================================

/ Main position cache audit
/ @return dict - Standardized audit result
POSITION_CACHE.validate:{[]
  / Check that position cache exists
  if[not `position in key `.engine;
    :.audit.newResult[`POSITION_CACHE_AUDIT;`WARNING;();enlist "Position cache not available";()!()]
  ];

  / Get all cached positions
  cacheKeys:key .engine.position.cache;
  if[0=count cacheKeys;
    :.audit.newResult[`POSITION_CACHE_AUDIT;`PASS;();enlist "No cached positions to audit";`positionsChecked`mismatchCount!(0;0)]
  ];

  / Compare each cached position
  errors:();
  checkResults:();

  {[cacheKey]
    exchange:cacheKey 0;
    asset:cacheKey 1;
    strategyId:cacheKey 2;
    comp:.audit.POSITION_CACHE.comparePosition[exchange;asset;strategyId];

    checkResults,::(`exchange`asset`strategyId`cachedQty`calculatedQty`delta`matches)!(
      exchange;asset;strategyId;comp`cachedQty;comp`calculatedQty;comp`delta;comp`matches);

    if[not comp`matches;
      errors,::enlist "Position cache mismatch for ",(string exchange),"/",(string asset),"/",(string strategyId),
        ": cached=",(string comp`cachedQty)," calculated=",(string comp`calculatedQty)," delta=",string comp`delta;
    ];
  } each cacheKeys;

  resultTable:$[0<count checkResults;
    flip `exchange`asset`strategyId`cachedQty`calculatedQty`delta`matches!flip checkResults;
    ([] exchange:`symbol$(); asset:`symbol$(); strategyId:`symbol$(); cachedQty:`float$(); calculatedQty:`float$(); delta:`float$(); matches:`boolean$())
  ];

  status:$[0<count errors;`FAIL;`PASS];
  metrics:`positionsChecked`mismatchCount`results!(count cacheKeys; sum not resultTable`matches; resultTable);

  .audit.newResult[`POSITION_CACHE_AUDIT;status;errors;();metrics]
 };

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.audit.registerType[`POSITION_CACHE_AUDIT; "Position Cache Audit"; "Verifies cached positions match calculated positions from ledger"; `.audit.POSITION_CACHE.validate];

\d .
