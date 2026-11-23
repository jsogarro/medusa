/ Global Best Bid/Offer (GBBO) utilities
/ Provides fast lookup and query functions for GBBO data

\d .book

/ Get GBBO for a pair
/ @param pair symbol - Trading pair
/ @return dict - GBBO with bestBid, bestAsk, spread, bestBidExchange, bestAskExchange
getGBBO:{[pair]
  / Lookup GBBO from keyed table (O(1))
  if[not pair in key .book.gbbo; :`error`msg!(`notFound;"GBBO not available for pair")];

  / Extract GBBO row
  gbboRow:.book.gbbo[pair];

  / Return as dictionary
  `time`bestBid`bestBidSize`bestBidExchange`bestAsk`bestAskSize`bestAskExchange`spread`spreadBps!(
    gbboRow`time;
    gbboRow`bestBid;
    gbboRow`bestBidSize;
    gbboRow`bestBidExchange;
    gbboRow`bestAsk;
    gbboRow`bestAskSize;
    gbboRow`bestAskExchange;
    gbboRow`spread;
    gbboRow`spreadBps
  )
 };

/ Get GBBO for multiple pairs
/ @param pairs symbol[] - List of trading pairs
/ @return table - GBBO table with pair as key
getGBBOMulti:{[pairs]
  / Filter GBBO table by pairs
  select from .book.gbbo where pair in pairs
 };

/ Get all available GBBO data
/ @return table - Full GBBO table
getAllGBBO:{[]
  .book.gbbo
 };

/ Check if GBBO is available for a pair
/ @param pair symbol - Trading pair
/ @return boolean - True if GBBO exists
hasGBBO:{[pair]
  pair in key .book.gbbo
 };

/ Get midpoint price from GBBO
/ @param pair symbol - Trading pair
/ @return float - Midpoint price or null if GBBO not available
getMidPrice:{[pair]
  if[not pair in key .book.gbbo; :0n];
  gbboRow:.book.gbbo[pair];
  (gbboRow[`bestBid] + gbboRow[`bestAsk]) % 2.0
 };

/ Get spread in absolute terms
/ @param pair symbol - Trading pair
/ @return float - Spread or null if GBBO not available
getSpread:{[pair]
  if[not pair in key .book.gbbo; :0n];
  .book.gbbo[pair;`spread]
 };

/ Get spread in basis points
/ @param pair symbol - Trading pair
/ @return float - Spread in bps or null if GBBO not available
getSpreadBps:{[pair]
  if[not pair in key .book.gbbo; :0n];
  .book.gbbo[pair;`spreadBps]
 };

/ Check if GBBO is stale (older than threshold)
/ @param pair symbol - Trading pair
/ @param maxAgeMs long - Maximum age in milliseconds
/ @return boolean - True if stale or not available
isStale:{[pair;maxAgeMs]
  if[not pair in key .book.gbbo; :1b];
  age:.z.p - .book.gbbo[pair;`time];
  age > maxAgeMs * 1000000j / Convert ms to ns
 };

-1 "  GBBO utilities loaded: getGBBO[], getMidPrice[], getSpread[], isStale[]";

\d .
