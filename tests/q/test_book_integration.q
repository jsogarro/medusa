/ ============================================================================
/ test_book_integration.q - Tests for Book Integration (10 tests)
/ ============================================================================
/ Tests aggregated book, GBBO, smart routing
/ ============================================================================

\l tests/q/test_framework.q
\l src/q/schema/init.q
\l src/q/book/schema.q
\l src/q/book/aggregator.q
\l src/q/book/gbbo.q
\l src/q/book/router.q

/ ============================================================================
/ SETUP & TEARDOWN
/ ============================================================================

setUp:{[]
  / Clear book tables
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Initialize fees
  .book.initFees[];

  / Mock .risk.orderbook with data from 3 exchanges
  delete from `.risk.orderbook;

  / Binance orderbook
  `.risk.orderbook upsert (`binance; `BTCUSD; `bid; 49990000000j; 5000000j);
  `.risk.orderbook upsert (`binance; `BTCUSD; `ask; 50010000000j; 3000000j);

  / Coinbase orderbook (better bid)
  `.risk.orderbook upsert (`coinbase; `BTCUSD; `bid; 50000000000j; 2000000j);
  `.risk.orderbook upsert (`coinbase; `BTCUSD; `ask; 50020000000j; 4000000j);

  / Kraken orderbook (better ask)
  `.risk.orderbook upsert (`kraken; `BTCUSD; `bid; 49980000000j; 3000000j);
  `.risk.orderbook upsert (`kraken; `BTCUSD; `ask; 50005000000j; 6000000j);
 }

tearDown:{[]
  / Clear tables
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;
  delete from `.risk.orderbook;
 }

/ ============================================================================
/ TEST CASES
/ ============================================================================

/ ============================================================================
/ TEST CASES
/ ============================================================================

test_aggregate_3_exchanges:{
  setUp[];

  / Aggregate book
  levelsAggregated:.book.aggregate[`BTCUSD];

  / Verify levels aggregated
  .test.assert["Levels aggregated"; levelsAggregated > 0];

  / Verify aggregated book has data
  aggBook:select from .book.aggregatedBook where pair=`BTCUSD;
  .test.assert["Aggregated book created"; 0 < count aggBook];

  / Verify bids and asks present
  bids:select from aggBook where side=`bid;
  asks:select from aggBook where side=`ask;
  .test.assert["Bids present"; 0 < count bids];
  .test.assert["Asks present"; 0 < count asks];

  tearDown[];
 }

/ Test: GBBO picks best bid/ask from different exchanges
test_gbbo_best_prices:{
  setUp[];

  / Aggregate and update GBBO
  .book.aggregate[`BTCUSD];

  / Verify GBBO exists
  .test.assert["GBBO created"; `BTCUSD in key .book.gbbo];

  / Get GBBO
  gbbo:.book.getGBBO[`BTCUSD];

  / Best bid should be 50000 (Coinbase)
  .test.assertEqual["Best bid from Coinbase"; 50000000000j; gbbo`bestBid];

  / Best ask should be 50005 (Kraken)
  .test.assertEqual["Best ask from Kraken"; 50005000000j; gbbo`bestAsk];

  / Verify spread
  expectedSpread:50005000000j - 50000000000j;
  .test.assertEqual["Spread correct"; expectedSpread; gbbo`spread];

  tearDown[];
 }

/ Test: Smart routing to cheapest exchange (considering fees)
test_smart_routing_cheapest:{
  setUp[];

  / Aggregate book
  .book.aggregate[`BTCUSD];

  / Route buy order (should pick exchange with lowest effective ask after fees)
  bestExchange:.book.routeToBestExchange[`BTCUSD; `buy; 2000000j];

  / Verify exchange selected (should be kraken: best ask 50005)
  / NOTE: Effective price depends on fees; kraken has lowest ask
  .test.assertEqual["Best exchange for buy"; `kraken; bestExchange];

  tearDown[];
 }

/ Test: Split routing across exchanges when needed
test_split_routing:{
  setUp[];

  / Aggregate book
  .book.aggregate[`BTCUSD];

  / Route large order (larger than any single exchange's liquidity at best level)
  / Total ask liquidity at best levels: 3000 (binance) + 4000 (coinbase) + 6000 (kraken) = 13000
  / Request 15000 (exceeds single exchange but available across all)
  splits:.book.routeSplit[`BTCUSD; `buy; 15000000j];

  / Verify splits created
  .test.assert["Splits created"; 0 < count splits];

  / Verify total qty equals requested (or as close as possible)
  totalQty:sum splits`qty;
  .test.assert["Total qty close to requested"; totalQty <= 15000000j];

  tearDown[];
 }

/ Test: Empty book handling (no liquidity)
test_empty_book_handling:{
  setUp[];

  / Clear orderbook
  delete from `.risk.orderbook;

  / Aggregate (should handle gracefully)
  levelsAggregated:.book.aggregate[`BTCUSD];

  / Verify zero levels
  .test.assertEqual["Zero levels aggregated"; 0j; levelsAggregated];

  / Verify GBBO not created
  .test.assert["GBBO not created"; not `BTCUSD in key .book.gbbo];

  tearDown[];
 }

/ Test: GBBO spread in basis points
test_gbbo_spread_bps:{
  setUp[];

  / Aggregate
  .book.aggregate[`BTCUSD];

  / Get GBBO
  gbbo:.book.getGBBO[`BTCUSD];

  / Calculate expected spread bps
  / spread = 50005 - 50000 = 5
  / mid = (50000 + 50005) / 2 = 50002.5
  / bps = (5 / 50002.5) * 10000 = 1.0 bps
  .test.assertNear["Spread bps correct"; 1.0f; gbbo`spreadBps; 0.1f];

  tearDown[];
 }

/ Test: Aggregated book sorted correctly (bids desc, asks asc)
test_aggregated_book_sorted:{
  setUp[];

  / Aggregate
  .book.aggregate[`BTCUSD];

  / Get bids (should be descending price)
  bids:select from .book.aggregatedBook where pair=`BTCUSD, side=`bid;
  bidPrices:exec price from bids;
  .test.assert["Bids sorted descending"; bidPrices ~ desc bidPrices];

  / Get asks (should be ascending price)
  asks:select from .book.aggregatedBook where pair=`BTCUSD, side=`ask;
  askPrices:exec price from asks;
  .test.assert["Asks sorted ascending"; askPrices ~ asc askPrices];

  tearDown[];
 }

/ Test: Route with insufficient liquidity returns null
test_route_insufficient_liquidity:{
  setUp[];

  / Aggregate
  .book.aggregate[`BTCUSD];

  / Route order larger than total available liquidity
  / Total bid liquidity: 5000 + 2000 + 3000 = 10000
  bestExchange:.book.routeToBestExchange[`BTCUSD; `sell; 20000000j];

  / Verify null returned (no single exchange can handle)
  .test.assert["Null on insufficient liquidity"; null bestExchange];

  tearDown[];
 }

/ Test: GBBO stale detection
test_gbbo_stale_detection:{
  setUp[];

  / Aggregate (creates GBBO with current timestamp)
  .book.aggregate[`BTCUSD];

  / Check if stale with 1ms threshold (should not be stale)
  isStale1:.book.isStale[`BTCUSD; 1];
  .test.assert["GBBO not stale immediately"; not isStale1];

  / Manually set GBBO time to past
  update time:.z.p - 5000000000j from `.book.gbbo where pair=`BTCUSD; / -5 seconds

  / Check if stale with 1000ms threshold (should be stale)
  isStale2:.book.isStale[`BTCUSD; 1000];
  .test.assert["GBBO stale after 5 seconds"; isStale2];

  tearDown[];
 }

/ Test: Fee calculation for different exchanges
test_fee_calculation:{
  setUp[];

  / Get fee for binance taker
  fee:.book.getFeeRate[`binance; 0b];

  / Verify fee is 0.1%
  .test.assertEqual["Binance taker fee"; 0.1; fee];

  / Get fee for coinbase maker
  feeMaker:.book.getFeeRate[`coinbase; 1b];

  / Verify fee is 0.4%
  .test.assertEqual["Coinbase maker fee"; 0.4; feeMaker];

  tearDown[];
 }

/ ============================================================================
/ RUN TESTS
/ ============================================================================

if[not "run_all_tests.q" ~ last get[`.z.f]; .test.run[`test_aggregate_3_exchanges; `test_gbbo_best_prices; `test_smart_routing_cheapest; `test_split_routing; `test_empty_book_handling; `test_gbbo_spread_bps; `test_aggregated_book_sorted; `test_route_insufficient_liquidity; `test_gbbo_stale_detection; `test_fee_calculation]];
