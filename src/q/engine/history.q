/ Trade history tracking with in-memory cache
/ Load order: 8 - history.q (standalone)

\d .engine

/ Trade history cache (keyed table for fast lookups)
history.cache:([id:`long$()] timestamp:`timestamp$(); exchange:`symbol$(); asset:`symbol$(); side:`symbol$(); price:`float$(); volume:`float$(); strategyId:`symbol$(); actor:`symbol$())

/ Cache size limit
history.cacheLimit:10000

/ Record a trade in the cache
/ @param trade dict - trade record with keys: id, timestamp, exchange, asset, side, price, volume, strategyId, actor
history.record:{[trade]
  / Insert into cache
  newRow:(enlist trade[`id])!enlist(trade[`timestamp];trade[`exchange];trade[`asset];trade[`side];trade[`price];trade[`volume];trade[`strategyId];trade[`actor]);
  history.cache,:newRow;

  / Trim cache if over limit (delete oldest rows)
  if[history.cacheLimit<count history.cache;
    / Delete oldest trades (first N rows since inserts are chronological)
    numToDelete:(count history.cache) - history.cacheLimit;
    history.cache:delete from history.cache where i<numToDelete;
  ];

  / Log if enabled
  if[.engine.config.baseSchema[`enableLogging];
    -1"[HISTORY] Recorded trade: ",string trade[`id];
  ];

  trade[`id]
 }

/ Get all trades for a strategy
/ @param strategyId symbol - strategy identifier
/ @return table - trades for strategy
history.getStrategyTrades:{[strategyId]
  select from history.cache where strategyId=strategyId
 }

/ Get all trades for an actor
/ @param actor symbol - actor identifier
/ @return table - trades for actor
history.getActorTrades:{[actor]
  select from history.cache where actor=actor
 }

/ Get recent trades (last N)
/ @param n int - number of trades to retrieve
/ @return table - recent trades
history.getRecent:{[n]
  n sublist `timestamp xdesc history.cache
 }

/ Get trades by exchange
/ @param exchange symbol - exchange identifier
/ @return table - trades on exchange
history.getByExchange:{[exchange]
  select from history.cache where exchange=exchange
 }

/ Get trades by asset
/ @param asset symbol - asset identifier
/ @return table - trades for asset
history.getByAsset:{[asset]
  select from history.cache where asset=asset
 }

/ Get trades in time range
/ @param startTime timestamp - start of range (inclusive)
/ @param endTime timestamp - end of range (inclusive)
/ @return table - trades in time range
history.getByTimeRange:{[startTime;endTime]
  select from history.cache where timestamp within (startTime;endTime)
 }

/ Clear the cache
history.clearCache:{
  history.cache:0#history.cache;
  -1"[HISTORY] Cache cleared";
 }

/ Get cache statistics
/ @return dict - cache statistics
history.stats:{
  `count`oldestTrade`newestTrade`exchanges`strategies!(
    count history.cache;
    exec first timestamp from `timestamp xasc history.cache;
    exec first timestamp from `timestamp xdesc history.cache;
    count exec distinct exchange from history.cache;
    count exec distinct strategyId from history.cache
  )
 }

\d .
