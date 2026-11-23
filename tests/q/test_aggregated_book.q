/ Test suite for aggregated order book
/ Tests aggregation, GBBO calculation, and smart routing

/ Load dependencies
\l src/q/book/schema.q
\l src/q/book/aggregator.q
\l src/q/book/gbbo.q
\l src/q/book/router.q

/ Initialize .risk.orderbook table for testing
.risk.orderbook:([]
  time:`timestamp$();
  exchange:`symbol$();
  sym:`symbol$();
  side:`symbol$();
  price:`float$();
  size:`float$();
  level:`int$()
 );

/ Test utilities
testCount:0;
passCount:0;
failCount:0;

assert:{[condition;testName]
  testCount+:1;
  if[condition;
    passCount+:1;
    -1 "✓ ",testName;
    :1b
  ];
  failCount+:1;
  -1 "✗ ",testName;
  0b
 };

assertEqual:{[actual;expected;testName]
  assert[actual~expected; testName," (expected: ",string[expected],", got: ",string[actual],")"]
 };

/ Test setup helpers
setupThreeExchangeBook:{[]
  / Clear existing data
  delete from `.risk.orderbook;
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Insert orderbook data for 3 exchanges
  / Exchange A: best bid 99.5, best ask 100.5
  / Exchange B: best bid 99.4, best ask 100.6
  / Exchange C: best bid 99.6, best ask 100.4 (best bid and ask)
  `.risk.orderbook insert flip `time`exchange`sym`side`price`size`level!(
    12#enlist .z.p;
    `exchangeA`exchangeA`exchangeA`exchangeA`exchangeB`exchangeB`exchangeB`exchangeB`exchangeC`exchangeC`exchangeC`exchangeC;
    12#`BTCUSD;
    `bid`bid`ask`ask`bid`bid`ask`ask`bid`bid`ask`ask;
    99.5 99.0 100.5 101.0 99.4 98.8 100.6 101.2 99.6 99.1 100.4 100.9;
    10.0 20.0 15.0 25.0 12.0 18.0 14.0 22.0 8.0 16.0 11.0 20.0;
    0 1 0 1 0 1 0 1 0 1 0 1
  );
 };

/ Test 1: Aggregation with 3 exchanges
test_aggregation_three_exchanges:{[]
  setupThreeExchangeBook[];

  / Run aggregation
  levelsAggregated:.book.aggregate[`BTCUSD];

  / Verify aggregated book has correct structure
  agg:.book.aggregatedBook;

  / Check bid side
  bids:select from agg where pair=`BTCUSD, side=`bid;
  bids:`level xasc bids;

  / Best bid should be 99.6 (from exchangeC)
  bestBid:first exec price from bids where level=0;
  assert[bestBid=99.6; "Best bid is 99.6"];

  / Total size at best bid should be 8.0 (only exchangeC at this level)
  bestBidSize:first exec totalSize from bids where level=0;
  assert[bestBidSize=8.0; "Best bid size is 8.0"];

  / Check ask side
  asks:select from agg where pair=`BTCUSD, side=`ask;
  asks:`level xasc asks;

  / Best ask should be 100.4 (from exchangeC)
  bestAsk:first exec price from asks where level=0;
  assert[bestAsk=100.4; "Best ask is 100.4"];

  / Total size at best ask should be 11.0
  bestAskSize:first exec totalSize from asks where level=0;
  assert[bestAskSize=11.0; "Best ask size is 11.0"];

  / Verify levels are assigned correctly (0=best, 1=next, etc.)
  bidLevels:exec level from bids;
  assert[(til count bids)~bidLevels; "Bid levels assigned correctly"];

  askLevels:exec level from asks;
  assert[(til count asks)~askLevels; "Ask levels assigned correctly"];

  ()
 };

/ Test 2: GBBO calculation
test_gbbo_calculation:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];

  / Check GBBO
  gbbo:.book.getGBBO[`BTCUSD];

  / Best bid should be 99.6 (exchangeC)
  assert[gbbo[`bestBid]=99.6; "GBBO best bid is 99.6"];
  assert[gbbo[`bestBidExchange]=`exchangeC; "GBBO best bid exchange is C"];

  / Best ask should be 100.4 (exchangeC)
  assert[gbbo[`bestAsk]=100.4; "GBBO best ask is 100.4"];
  assert[gbbo[`bestAskExchange]=`exchangeC; "GBBO best ask exchange is C"];

  / Spread should be 0.8
  assert[gbbo[`spread]=0.8; "GBBO spread is 0.8"];

  / Spread in bps: (0.8 / 100.0) * 10000 = 80 bps
  expectedBps:(0.8 % 100.0) * 10000.0;
  assert[abs[gbbo[`spreadBps] - expectedBps] < 0.01; "GBBO spreadBps is ~80"];

  ()
 };

/ Test 3: Smart routing - best exchange with sufficient liquidity
test_smart_routing_best_exchange:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];
  .book.initFees[];

  / Route buy order for 5.0 BTC (all exchanges have enough at best ask)
  / Best ask is 100.4 on exchangeC with size 11.0
  bestExchange:.book.routeToBestExchange[`BTCUSD;`buy;5.0];

  / exchangeC should be selected (lowest ask)
  assert[bestExchange=`exchangeC; "Best exchange for buy is exchangeC"];

  / Route sell order for 5.0 BTC
  / Best bid is 99.6 on exchangeC with size 8.0
  bestExchange:.book.routeToBestExchange[`BTCUSD;`sell;5.0];

  / exchangeC should be selected (highest bid)
  assert[bestExchange=`exchangeC; "Best exchange for sell is exchangeC"];

  ()
 };

/ Test 4: Smart routing - split across exchanges
test_split_routing:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];

  / Route buy order for 50.0 BTC (more than any single exchange has)
  / Best ask is 100.4 (exchangeC, 11.0)
  / Next best is 100.5 (exchangeA, 15.0)
  / Next is 100.6 (exchangeB, 14.0)
  splits:.book.routeSplit[`BTCUSD;`buy;50.0];

  / Should split across all three exchanges
  assert[count[splits]=3; "Split routing uses 3 exchanges"];

  / Total quantity should be 40.0 (11 + 15 + 14)
  / because that's all the liquidity available at these levels
  totalQty:sum exec qty from splits;
  assert[totalQty=40.0; "Split routing fills 40.0 BTC"];

  / exchangeC should get 11.0 (best price)
  exchangeC_qty:exec first qty from splits where exchange=`exchangeC;
  assert[exchangeC_qty=11.0; "exchangeC gets 11.0 BTC"];

  / exchangeA should get 15.0 (next best price)
  exchangeA_qty:exec first qty from splits where exchange=`exchangeA;
  assert[exchangeA_qty=15.0; "exchangeA gets 15.0 BTC"];

  / exchangeB should get 14.0 (third best price)
  exchangeB_qty:exec first qty from splits where exchange=`exchangeB;
  assert[exchangeB_qty=14.0; "exchangeB gets 14.0 BTC"];

  ()
 };

/ Test 5: Single exchange - degenerate case
test_single_exchange:{[]
  / Clear existing data
  delete from `.risk.orderbook;
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Insert orderbook data for only 1 exchange
  `.risk.orderbook insert flip `time`exchange`sym`side`price`size`level!(
    2#enlist .z.p;
    `exchangeA`exchangeA;
    2#`ETHUSD;
    `bid`ask;
    50.0 51.0;
    10.0 12.0;
    0 0
  );

  / Run aggregation
  .book.aggregate[`ETHUSD];

  / GBBO should still work
  gbbo:.book.getGBBO[`ETHUSD];
  assert[gbbo[`bestBid]=50.0; "Single exchange best bid is 50.0"];
  assert[gbbo[`bestAsk]=51.0; "Single exchange best ask is 51.0"];
  assert[gbbo[`bestBidExchange]=`exchangeA; "Single exchange bid from exchangeA"];
  assert[gbbo[`bestAskExchange]=`exchangeA; "Single exchange ask from exchangeA"];

  / Routing should work
  bestExchange:.book.routeToBestExchange[`ETHUSD;`buy;5.0];
  assert[bestExchange=`exchangeA; "Single exchange routing works"];

  ()
 };

/ Test 6: Empty orderbook - edge case
test_empty_orderbook:{[]
  / Clear all data
  delete from `.risk.orderbook;
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Run aggregation on pair with no data
  levelsAggregated:.book.aggregate[`XRPUSD];

  / Should return 0 levels
  assert[levelsAggregated=0j; "Empty orderbook returns 0 levels"];

  / GBBO should not exist
  hasGBBO:.book.hasGBBO[`XRPUSD];
  assert[not hasGBBO; "Empty orderbook has no GBBO"];

  / Routing should return null
  bestExchange:.book.routeToBestExchange[`XRPUSD;`buy;10.0];
  assert[null bestExchange; "Empty orderbook routing returns null"];

  ()
 };

/ Test 7: GBBO helper functions
test_gbbo_helpers:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];

  / Test getMidPrice
  midPrice:.book.getMidPrice[`BTCUSD];
  expectedMid:(99.6 + 100.4) % 2.0;
  assert[midPrice=expectedMid; "getMidPrice returns correct midpoint"];

  / Test getSpread
  spread:.book.getSpread[`BTCUSD];
  assert[spread=0.8; "getSpread returns correct spread"];

  / Test hasGBBO
  hasGBBO:.book.hasGBBO[`BTCUSD];
  assert[hasGBBO; "hasGBBO returns true for existing pair"];

  / Test with non-existent pair
  hasGBBO:.book.hasGBBO[`INVALID];
  assert[not hasGBBO; "hasGBBO returns false for non-existent pair"];

  / Test isStale (should be fresh since we just aggregated)
  isStale:.book.isStale[`BTCUSD;1000]; / 1 second threshold
  assert[not isStale; "GBBO is not stale"];

  ()
 };

/ Test 8: Routing with fees
test_routing_with_fees:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];
  .book.initFees[];

  / Manually set different fee rates to test fee-adjusted routing
  `.book.exchangeFees upsert ([exchange:`exchangeA`exchangeB`exchangeC]
    makerFee:0.1 0.5 0.3;
    takerFee:0.1 0.5 0.3
  );

  / Buy order: best ask is 100.4 on exchangeC
  / With 0.3% fee: effective price = 100.4 * 1.003 = 100.7012
  / exchangeA has ask 100.5 with 0.1% fee: 100.5 * 1.001 = 100.6005 (better!)
  / exchangeB has ask 100.6 with 0.5% fee: 100.6 * 1.005 = 101.103

  / Route should pick exchangeA due to lower fees
  bestExchange:.book.routeToBestExchange[`BTCUSD;`buy;10.0];
  assert[bestExchange=`exchangeA; "Fee-adjusted routing picks exchangeA"];

  ()
 };

/ Test 9: Aggregation with price overlap
test_aggregation_price_overlap:{[]
  / Clear existing data
  delete from `.risk.orderbook;
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Two exchanges with same price on bid side
  `.risk.orderbook insert flip `time`exchange`sym`side`price`size`level!(
    4#enlist .z.p;
    `exchangeA`exchangeB`exchangeA`exchangeB;
    4#`BTCUSD;
    `bid`bid`ask`ask;
    100.0 100.0 101.0 101.0;
    10.0 15.0 12.0 18.0;
    0 0 0 0
  );

  .book.aggregate[`BTCUSD];

  / Aggregated book should combine sizes at same price
  agg:.book.aggregatedBook;
  bidRow:first select from agg where pair=`BTCUSD, side=`bid, level=0;

  / Total size should be 10 + 15 = 25
  assert[bidRow[`totalSize]=25.0; "Same-price levels combined (bid)"];

  / Should have both exchanges listed
  assert[count[bidRow[`exchanges]]=2; "Both exchanges listed for same price"];

  / Ask side should also combine
  askRow:first select from agg where pair=`BTCUSD, side=`ask, level=0;
  assert[askRow[`totalSize]=30.0; "Same-price levels combined (ask)"];

  ()
 };

/ Test 10: Route wrapper function
test_route_wrapper:{[]
  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];
  .book.initFees[];

  / Small order - should use single exchange routing
  result:.book.route[`BTCUSD;`buy;5.0];
  assert[result[`type]=`single; "Small order uses single routing"];
  assert[result[`exchange]=`exchangeC; "Small order routed to best exchange"];

  / Large order - should use split routing
  result:.book.route[`BTCUSD;`buy;50.0];
  assert[result[`type]=`split; "Large order uses split routing"];
  assert[count[result[`splits]]=3; "Large order split across 3 exchanges"];

  ()
 };

/ Test 11: GBBO publish (mock .u.pub)
test_gbbo_publish:{[]
  / Initialize test tracking vars
  `.test.pubCalled set 0b;
  `.test.pubTable set `;
  `.test.pubPair set `;

  / Create .u.pub function (set directly in .u namespace)
  `.u.pub set {[tbl;pair]
    `.test.pubCalled set 1b;
    `.test.pubTable set tbl;
    `.test.pubPair set pair;
  };

  setupThreeExchangeBook[];
  .book.aggregate[`BTCUSD];

  / Check that .u.pub was called
  assert[.test.pubCalled; "GBBO update published via .u.pub"];
  assert[.test.pubTable=`gbbo; "Published to gbbo table"];
  assert[.test.pubPair=`BTCUSD; "Published for BTCUSD pair"];

  / Clean up
  delete pubCalled, pubTable, pubPair from `.test;
  delete pub from `.u;

  ()
 };

/ Test 12: Insufficient liquidity edge case
test_insufficient_liquidity:{[]
  / Clear existing data
  delete from `.risk.orderbook;
  delete from `.book.aggregatedBook;
  delete from `.book.gbbo;

  / Insert minimal liquidity (total 5.0 BTC available)
  `.risk.orderbook insert flip `time`exchange`sym`side`price`size`level!(
    2#enlist .z.p;
    `exchangeA`exchangeA;
    2#`BTCUSD;
    `bid`ask;
    100.0 101.0;
    2.0 3.0;
    0 0
  );

  .book.aggregate[`BTCUSD];

  / Try to buy 10.0 BTC (more than available)
  splits:.book.routeSplit[`BTCUSD;`buy;10.0];

  / Should fill what's available (3.0)
  totalFilled:sum exec qty from splits;
  assert[totalFilled=3.0; "Split routing fills available liquidity only"];

  / Single exchange routing should return null (insufficient liquidity)
  bestExchange:.book.routeToBestExchange[`BTCUSD;`buy;10.0];
  assert[null bestExchange; "Single exchange routing returns null for large order"];

  ()
 };

/ Run all tests
runAllTests:{[]
  -1 "\n=== Aggregated Order Book Test Suite ===\n";

  testCount::0;
  passCount::0;
  failCount::0;

  / Run tests
  test_aggregation_three_exchanges[];
  test_gbbo_calculation[];
  test_smart_routing_best_exchange[];
  test_split_routing[];
  test_single_exchange[];
  test_empty_orderbook[];
  test_gbbo_helpers[];
  test_routing_with_fees[];
  test_aggregation_price_overlap[];
  test_route_wrapper[];
  test_gbbo_publish[];
  test_insufficient_liquidity[];

  / Print summary
  -1 "\n=== Test Summary ===";
  -1 "Total: ",string[testCount];
  -1 "Passed: ",string[passCount];
  -1 "Failed: ",string[failCount];
  -1 "Success rate: ",string[100.0 * passCount % testCount],"%%\n";

  / Return pass/fail status
  failCount=0
 };

/ Auto-run tests
exit $[runAllTests[]; 0; 1];
