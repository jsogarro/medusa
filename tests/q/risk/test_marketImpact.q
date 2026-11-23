/ Tests for Market Impact Module

\l src/q/risk/init.q
\l tests/q/test_framework.q

/ ═══════════════════════════════════════════════════════════════════
/ Market Impact Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== MARKET IMPACT TESTS ===";

/ Test 1: Initialization
test_marketImpact_init:{[]
  .risk.initMarketImpact[];

  / Check default limits exist
  .test.assert["impactLimits initialized"; 4 = count .risk.impactLimits];
  .test.assert["binance BTCUSD in limits"; (`binance;`BTCUSD) in key .risk.impactLimits];
  .test.assertEqual["BTCUSD warn threshold"; 5.0; first exec warnPct from .risk.impactLimits where exchange=`binance, sym=`BTCUSD];
  .test.assertEqual["BTCUSD reject threshold"; 10.0; first exec rejectPct from .risk.impactLimits where exchange=`binance, sym=`BTCUSD];

  / Check orderbook initialized
  .test.assert["orderbook table exists"; .Q.qt .risk.orderbook];
 };

/ Test 2: Set market impact limit
test_marketImpact_setLimit:{[]
  .risk.initMarketImpact[];

  / Set custom limit
  .risk.setMarketImpactLimit[`kraken;`ADAUSD;3.0;8.0];

  / Verify it was set
  .test.assert["Custom limit exists"; (`kraken;`ADAUSD) in key .risk.impactLimits];
  .test.assertEqual["Custom warn pct"; 3.0; first exec warnPct from .risk.impactLimits where exchange=`kraken, sym=`ADAUSD];
  .test.assertEqual["Custom reject pct"; 8.0; first exec rejectPct from .risk.impactLimits where exchange=`kraken, sym=`ADAUSD];
 };

/ Test 3: Check market impact - no orderbook data
test_marketImpact_noData:{[]
  .risk.initMarketImpact[];

  / Check without orderbook data (should pass with warning)
  result:.risk.checkMarketImpact[`binance;`BTCUSD;`buy;1.0;50000.0];
  .test.assert["Check passes without orderbook"; result 0];
 };

/ Test 4: Check market impact - with orderbook - pass
test_marketImpact_withBook_pass:{[]
  .risk.initMarketImpact[];

  / Populate orderbook with bid depth
  `.risk.orderbook insert (
    .z.p .z.p .z.p .z.p .z.p;
    `binance`binance`binance`binance`binance;
    `BTCUSD`BTCUSD`BTCUSD`BTCUSD`BTCUSD;
    `bid`bid`bid`bid`bid;
    49999 49998 49997 49996 49995f;
    10 10 10 10 10f;
    0 1 2 3 4i
  );

  / Small order (1 BTC, plenty of depth)
  result:.risk.checkMarketImpact[`binance;`BTCUSD;`buy;1.0;50000.0];
  .test.assert["Check passes with adequate depth"; result 0];
 };

/ Test 5: Check market impact - with orderbook - warn
test_marketImpact_withBook_warn:{[]
  .risk.initMarketImpact[];

  / Populate orderbook with limited bid depth
  `.risk.orderbook insert (
    .z.p .z.p;
    `binance`binance;
    `BTCUSD`BTCUSD;
    `bid`bid;
    49999 49998f;
    5 5f;
    0 1i
  );

  / Order that consumes 70% of book (7 BTC vs 10 BTC available)
  / Impact = 30% (exceeds 5% warn threshold but below 10% reject)
  result:.risk.checkMarketImpact[`binance;`BTCUSD;`buy;7.0;50000.0];
  .test.assert["Check passes but logs warning"; result 0];
 };

/ Test 6: Check market impact - with orderbook - reject
test_marketImpact_withBook_reject:{[]
  .risk.initMarketImpact[];

  / Populate orderbook with very limited bid depth
  `.risk.orderbook insert (
    .z.p;
    `binance;
    `BTCUSD;
    `bid;
    49999f;
    5f;
    0i
  );

  / Large order that far exceeds available depth (50 BTC vs 5 BTC available)
  / Impact = 90% (exceeds 10% reject threshold)
  result:.risk.checkMarketImpact[`binance;`BTCUSD;`buy;50.0;50000.0];
  .test.assert["Check fails with excessive impact"; not result 0];
  .test.assertEqual["Reason is marketImpactTooHigh"; `marketImpactTooHigh; result 1];
 };

/ Test 7: Get book liquidity
test_marketImpact_bookLiquidity:{[]
  .risk.initMarketImpact[];

  / Populate orderbook
  `.risk.orderbook insert (
    .z.p .z.p .z.p;
    `binance`binance`binance;
    `BTCUSD`BTCUSD`BTCUSD;
    `bid`bid`ask;
    49999 49998 50001f;
    10 10 5f;
    0 1 0i
  );

  / Get liquidity
  liq:.risk.getBookLiquidity[`binance;`BTCUSD];

  / Verify structure
  .test.assert["Liquidity has bid"; `bid in key liq];
  .test.assert["Liquidity has ask"; `ask in key liq];
  .test.assert["Liquidity has bidDepth"; `bidDepth in key liq];
  .test.assertEqual["Bid depth correct"; 20.0; liq`bidDepth];
  .test.assertEqual["Ask depth correct"; 5.0; liq`askDepth];
 };

/ Test 8: Event logging
test_marketImpact_events:{[]
  .risk.initMarketImpact[];

  / Clear events
  delete from `.risk.impactEvents;

  / Populate orderbook
  `.risk.orderbook insert (
    .z.p .z.p;
    `binance`binance;
    `BTCUSD`BTCUSD;
    `bid`bid;
    49999 49998f;
    10 10f;
    0 1i
  );

  / Perform check
  .risk.checkMarketImpact[`binance;`BTCUSD;`buy;1.0;50000.0];

  / Verify event logged
  .test.assert["Event logged"; 1 = count .risk.impactEvents];
  .test.assertEqual["Event exchange"; `binance; first exec exchange from .risk.impactEvents];
 };

if[not `medusaRunAll in key `.; exit .test.run[`.]];
