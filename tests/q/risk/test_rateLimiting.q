/ Tests for Rate Limiting Module

\l src/q/risk/init.q
\l tests/q/test_framework.q

/ ═══════════════════════════════════════════════════════════════════
/ Rate Limiting Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== RATE LIMITING TESTS ===";

/ Test 1: Initialization
test_rateLimits_init:{[]
  .risk.initRateLimits[];

  / Check default exchange limits exist
  .test.assert["globalRateLimits initialized"; 3 = count .risk.globalRateLimits];
  .test.assert["binance in limits"; `binance in exec exchange from .risk.globalRateLimits];
  .test.assert["coinbase in limits"; `coinbase in exec exchange from .risk.globalRateLimits];
  .test.assert["kraken in limits"; `kraken in exec exchange from .risk.globalRateLimits];

  / Check default burst sizes
  .test.assertEqual["binance burst size"; 20j; first exec burstSize from .risk.globalRateLimits where exchange=`binance];
  .test.assertEqual["coinbase burst size"; 30j; first exec burstSize from .risk.globalRateLimits where exchange=`coinbase];

  / Check initial token counts equal burst size
  .test.assertEqual["binance initial tokens"; 20.0; first exec currentTokens from .risk.globalRateLimits where exchange=`binance];
 };

/ Test 2: Token consumption
test_rateLimits_consumption:{[]
  .risk.initRateLimits[];

  / Check rate limit (should pass and consume 1 token)
  result:.risk.checkRateLimit[`binance;`BTCUSD];
  .test.assert["First check passes"; result 0];
  .test.assertEqual["First check reason empty"; `; result 1];

  / Verify token was consumed
  tokens:first exec currentTokens from .risk.globalRateLimits where exchange=`binance;
  .test.assert["Token consumed"; tokens < 20.0];
 };

/ Test 3: Rate limit exhaustion
test_rateLimits_exhaustion:{[]
  .risk.initRateLimits[];

  / Consume all tokens (20 for binance)
  i:0;
  while[i < 20;
    .risk.checkRateLimit[`binance;`BTCUSD];
    i+:1
  ];

  / Next check should fail
  result:.risk.checkRateLimit[`binance;`BTCUSD];
  .test.assert["Check fails when exhausted"; not result 0];
  .test.assertEqual["Reason is rateLimitExceeded"; `rateLimitExceeded; result 1];
 };

/ Test 4: Token refill
test_rateLimits_refill:{[]
  .risk.initRateLimits[];

  / Consume tokens
  .risk.checkRateLimit[`binance;`BTCUSD];
  tokensBefore:first exec currentTokens from .risk.globalRateLimits where exchange=`binance;

  / Wait a bit (simulate time passing)
  system "sleep 0.1";

  / Refill tokens
  .risk.refillTokens[`binance];
  tokensAfter:first exec currentTokens from .risk.globalRateLimits where exchange=`binance;

  .test.assert["Tokens increased after refill"; tokensAfter > tokensBefore];
 };

/ Test 5: Custom exchange limit
test_rateLimits_custom:{[]
  .risk.initRateLimits[];

  / Set custom limit
  .risk.setExchangeRateLimit[`ftx;10.0;25j];

  / Verify it was set
  .test.assert["Custom exchange in limits"; `ftx in exec exchange from .risk.globalRateLimits];
  .test.assertEqual["Custom max rate"; 10.0; first exec maxRate from .risk.globalRateLimits where exchange=`ftx];
  .test.assertEqual["Custom burst size"; 25j; first exec burstSize from .risk.globalRateLimits where exchange=`ftx];
 };

/ Test 6: Symbol-specific limit
test_rateLimits_symbol:{[]
  .risk.initRateLimits[];

  / Set symbol-specific limit
  .risk.setSymbolRateLimit[`binance;`BTCUSD;5.0;10j];

  / Verify it was set
  .test.assert["Symbol limit exists"; (`binance;`BTCUSD) in key .risk.rateLimits];
  .test.assertEqual["Symbol max rate"; 5.0; first exec maxRate from .risk.rateLimits where exchange=`binance, sym=`BTCUSD];
 };

/ Test 7: Event logging
test_rateLimits_events:{[]
  .risk.initRateLimits[];

  / Clear events
  delete from `.risk.rateLimitEvents;

  / Perform checks
  .risk.checkRateLimit[`binance;`BTCUSD];
  .risk.checkRateLimit[`binance;`ETHUSD];

  / Verify events logged
  .test.assert["Events logged"; 2 = count .risk.rateLimitEvents];
  .test.assert["All allowed"; all `allowed = exec action from .risk.rateLimitEvents];
 };

/ Test 8: Status monitoring
test_rateLimits_status:{[]
  .risk.initRateLimits[];

  / Get status
  status:.risk.getRateLimitStatus[];

  / Verify structure
  .test.assert["Status has global"; `global in key status];
  .test.assert["Status has symbol"; `symbol in key status];
  .test.assert["Status has recentEvents"; `recentEvents in key status];
  .test.assert["Global is table"; .Q.qt status`global];
 };

if[not `medusaRunAll in key `.; exit .test.run[`.]];
