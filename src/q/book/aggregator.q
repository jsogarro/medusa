/ Real-time Order Book Aggregation
/ Merges order books from multiple exchanges into unified aggregated book
/ Performance target: <1ms per pair

\d .book

/ Aggregate order book for a single pair across all exchanges
/ @param pair symbol - Trading pair (e.g., `BTCUSD)
/ @return long - Number of levels aggregated
aggregate:{[pair]
  / Get latest orderbook snapshots from .risk.orderbook
  / Filter by pair, group by exchange/side
  rawBook:select from .risk.orderbook where sym=pair;

  / If no orderbook data, clear aggregated book and return
  if[0=count rawBook;
    delete from `.book.aggregatedBook where pair=pair;
    :(0j)
  ];

  / Process bids and asks separately
  bids:select from rawBook where side=`bid;
  asks:select from rawBook where side=`ask;

  / Aggregate bid side (descending price)
  aggregatedBids:aggregateSide[pair;`bid;bids];

  / Aggregate ask side (ascending price)
  aggregatedAsks:aggregateSide[pair;`ask;asks];

  / Clear old aggregated book for this pair
  delete from `.book.aggregatedBook where pair=pair;

  / Insert new aggregated book (unkey first since destination is also keyed)
  `.book.aggregatedBook upsert 0!aggregatedBids;
  `.book.aggregatedBook upsert 0!aggregatedAsks;

  / Update GBBO
  updateGBBO[pair];

  / Return total levels aggregated
  count[aggregatedBids] + count[aggregatedAsks]
 };

/ Aggregate one side of the book (bid or ask)
/ @param pair symbol - Trading pair
/ @param side symbol - `bid or `ask
/ @param bookData table - Orderbook data for this side
/ @return table - Aggregated book with keys (pair; side; price)
aggregateSide:{[pair;side;bookData]
  / If no data, return empty table
  if[0=count bookData; :0#.book.aggregatedBook];

  / Group by price level, aggregate across exchanges
  / For each price level, collect:
  /   - totalSize = sum of sizes across all exchanges
  /   - exchanges = list of exchange symbols with liquidity at this level
  /   - exchangeSizes = list of sizes per exchange
  grouped:select
    totalSize:sum size,
    exchanges:exchange,
    exchangeSizes:size
    by price
    from bookData;

  / Sort by price (bids descending, asks ascending)
  sorted:$[side=`bid;
    `price xdesc grouped;
    `price xasc grouped
  ];

  / Assign level numbers (0=best, 1=next, etc.)
  sorted:update level:til count sorted from sorted;

  / Add pair, side, and timestamp
  sorted:update pair:pair, side:side, time:.z.p from sorted;

  / Rekey by (pair; side; price)
  1!select pair, side, price, time, totalSize, exchanges, exchangeSizes, level from sorted
 };

/ Update GBBO from aggregated book
/ @param pair symbol - Trading pair
updateGBBO:{[pair]
  / Get best bid (highest price)
  bestBidRow:select from .book.aggregatedBook where pair=pair, side=`bid, level=0;

  / Get best ask (lowest price)
  bestAskRow:select from .book.aggregatedBook where pair=pair, side=`ask, level=0;

  / If no bid or ask, clear GBBO for this pair
  if[(0=count bestBidRow) or (0=count bestAskRow);
    delete from `.book.gbbo where pair=pair;
    :()
  ];

  / Extract best bid/ask data
  bestBid:first exec price from bestBidRow;
  bestBidSize:first exec totalSize from bestBidRow;
  bestBidExchanges:first exec exchanges from bestBidRow;
  bestBidExchange:first bestBidExchanges; / Pick first exchange (could be random or lowest fee)

  bestAsk:first exec price from bestAskRow;
  bestAskSize:first exec totalSize from bestAskRow;
  bestAskExchanges:first exec exchanges from bestAskRow;
  bestAskExchange:first bestAskExchanges;

  / Calculate spread
  spread:bestAsk - bestBid;

  / Calculate spread in basis points (bps)
  / spreadBps = (spread / midPrice) * 10000
  midPrice:(bestBid + bestAsk) % 2.0;
  spreadBps:$[midPrice=0.0; 0n; (spread % midPrice) * 10000.0];

  / Update GBBO table (keyed by pair)
  `.book.gbbo upsert ([pair:enlist pair]
    time:enlist .z.p;
    bestBid:enlist bestBid;
    bestBidSize:enlist bestBidSize;
    bestBidExchange:enlist bestBidExchange;
    bestAsk:enlist bestAsk;
    bestAskSize:enlist bestAskSize;
    bestAskExchange:enlist bestAskExchange;
    spread:enlist spread;
    spreadBps:enlist spreadBps
  );

  / Publish GBBO update via tickerplant
  / Check if .u.pub exists (may not be available in test environment)
  if[not ()~key `.u.pub; .u.pub[`gbbo; pair]];

  ()
 };

-1 "  Aggregator loaded: aggregate[], aggregateSide[], updateGBBO[]";

\d .
