/ Aggregated Order Book Schema
/ Tables for cross-exchange order book aggregation and global best bid/offer

\d .book

/ Aggregated order book — merged book across all exchanges
/ Keyed by (pair; side; price) for fast level lookup
aggregatedBook:([pair:`symbol$(); side:`symbol$(); price:`float$()]
  time:`timestamp$();
  totalSize:`float$();
  exchanges:();
  exchangeSizes:();
  level:`long$()
 );

/ Global Best Bid/Offer — top-of-book across all exchanges
/ Keyed by pair for O(1) GBBO lookup
gbbo:([pair:`symbol$()]
  time:`timestamp$();
  bestBid:`float$();
  bestBidSize:`float$();
  bestBidExchange:`symbol$();
  bestAsk:`float$();
  bestAskSize:`float$();
  bestAskExchange:`symbol$();
  spread:`float$();
  spreadBps:`float$()
 );

/ Clear all book tables
clearTables:{[]
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;
  -1 "Book tables cleared";
 };

-1 "  Book schema loaded: aggregatedBook, gbbo";

\d .
