/ Position tracking with caching
/ Load order: 9 - position.q (standalone)

\d .engine

/ Position cache (keyed table with strategyId for multi-strategy support)
position.cache:([exchange:`symbol$(); asset:`symbol$(); strategyId:`symbol$()] quantity:`float$(); avgPrice:`float$(); lastUpdate:`timestamp$())

/ Cache TTL in milliseconds
position.cacheTTL:5000

/ Get position for exchange/asset/strategy
/ @param exchange symbol - exchange identifier
/ @param asset symbol - asset identifier
/ @param strategyId symbol - strategy identifier
/ @return dict - position info (quantity, avgPrice)
position.get:{[exchange;asset;strategyId]
  / Check cache first (key now includes strategyId)
  cacheKey:(exchange;asset;strategyId);

  if[cacheKey in key position.cache;
    cached:position.cache[cacheKey];
    / Check if cache is fresh
    age:.z.p - cached[`lastUpdate];
    if[age < position.cacheTTL;
      :cached;
    ];
  ];

  / Cache miss or stale - query database
  pos:position.queryDB[exchange;asset;strategyId];

  / Update cache
  newRow:cacheKey!enlist(pos[`quantity];pos[`avgPrice];.z.p);
  position.cache,:newRow;

  pos
 }

/ Query database for position (stub - would query positions table)
/ @param exchange symbol - exchange identifier
/ @param asset symbol - asset identifier
/ @param strategyId symbol - strategy identifier
/ @return dict - position info
position.queryDB:{[exchange;asset;strategyId]
  / In real implementation, would query positions table
  / For now, return zero position
  `exchange`asset`quantity`avgPrice`strategyId!(exchange;asset;0.0;0.0;strategyId)
 }

/ Update position after trade
/ @param exchange symbol - exchange identifier
/ @param asset symbol - asset identifier
/ @param side symbol - `buy or `sell
/ @param price float - trade price
/ @param volume float - trade volume
/ @param strategyId symbol - strategy identifier
/ @return dict - updated position
position.update:{[exchange;asset;side;price;volume;strategyId]
  / Get current position
  pos:position.get[exchange;asset;strategyId];

  / Calculate new quantity and average price
  currentQty:pos[`quantity];
  currentAvg:pos[`avgPrice];

  / Determine new quantity based on side
  newQty:$[side~`buy; currentQty + volume; currentQty - volume];

  / Calculate new average price based on position magnitude change
  isIncreasing:(abs[newQty] > abs[currentQty]) and (currentQty * newQty > 0);

  newAvg:$[
    newQty=0;                                    / Full close
      0.0;
    currentQty=0;                                / Initial position
      price;
    (currentQty>0) and (newQty<0);              / Position flip from long to short
      price;
    (currentQty<0) and (newQty>0);              / Position flip from short to long
      price;
    isIncreasing;                                / Increasing position magnitude
      ((currentQty * currentAvg) + ($[side~`buy;volume;neg volume] * price)) % newQty;
      currentAvg                                 / Reducing position — avg stays same
  ];

  / Update cache (key includes strategyId)
  cacheKey:(exchange;asset;strategyId);
  newRow:cacheKey!enlist(newQty;newAvg;.z.p);
  position.cache,:newRow;

  / Return updated position
  `exchange`asset`quantity`avgPrice`strategyId!(exchange;asset;newQty;newAvg;strategyId)
 }

/ Get all positions for a strategy
/ @param strategyId symbol - strategy identifier
/ @return table - all positions for strategy
position.getAll:{[strategyId]
  select from position.cache where strategyId=strategyId
 }

/ Refresh cache from database
position.refreshCache:{
  / Clear stale entries
  cutoff:.z.p - position.cacheTTL;
  position.cache:select from position.cache where lastUpdate > cutoff;

  / Log refresh
  -1"[POSITION] Cache refreshed, ",string[count position.cache]," entries retained";
 }

/ Clear position cache
position.clearCache:{
  position.cache:0#position.cache;
  -1"[POSITION] Cache cleared";
 }

/ Get cache statistics
/ @return dict - cache statistics
position.stats:{
  `count`exchanges`assets`strategies`oldestEntry!(
    count position.cache;
    count exec distinct exchange from position.cache;
    count exec distinct asset from position.cache;
    count exec distinct strategyId from position.cache;
    exec min lastUpdate from position.cache
  )
 }

\d .
