/ Tests for Circuit Breaker Module

\l src/q/risk/init.q

\l tests/q/test_framework.q

assert:{[condition;msg]
  .test.assert[msg; condition]
 };

/ ═══════════════════════════════════════════════════════════════════
/ Circuit Breaker Tests
/ ═══════════════════════════════════════════════════════════════════

-1 "\n=== CIRCUIT BREAKER TESTS ===";

/ Test 1: Initialization
test_circuitBreaker_init:{[]
  .risk.initCircuitBreakers[];

  / Check tables exist
  .test.assert["circuitBreakerConfig exists"; .Q.qt .risk.circuitBreakerConfig];
  .test.assert["circuitBreakerState exists"; .Q.qt .risk.circuitBreakerState];
  .test.assert["globalCircuitBreaker exists"; .Q.qt .risk.globalCircuitBreaker];

  / Check global breaker initialized
  .test.assert["Global breaker inactive"; not first .risk.globalCircuitBreaker`active];
  .test.assertEqual["Global threshold 10"; 10i; first .risk.globalCircuitBreaker`strategyBreachThreshold];
 };

/ Test 2: Record winning trade
test_circuitBreaker_recordWin:{[]
  .risk.initCircuitBreakers[];

  / Configure strategy
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 0i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Record winning trade
  .risk.recordTradeResult[`strat1;100.0];

  / Verify consecutive losses reset to 0
  .test.assertEqual["Consecutive losses reset"; 0i; first exec consecutiveLosses from .risk.circuitBreakerState where strategy=`strat1];
  .test.assertEqual["Last result is win"; `win; first exec lastTradeResult from .risk.circuitBreakerState where strategy=`strat1];
 };

/ Test 3: Record losing trade
test_circuitBreaker_recordLoss:{[]
  .risk.initCircuitBreakers[];

  / Configure strategy
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 0i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Record losing trade
  .risk.recordTradeResult[`strat1;-50.0];

  / Verify consecutive losses incremented
  .test.assertEqual["Consecutive losses incremented"; 1i; first exec consecutiveLosses from .risk.circuitBreakerState where strategy=`strat1];
  .test.assertEqual["Last result is loss"; `loss; first exec lastTradeResult from .risk.circuitBreakerState where strategy=`strat1];
 };

/ Test 4: Trigger circuit breaker
test_circuitBreaker_trigger:{[]
  .risk.initCircuitBreakers[];

  / Configure strategy
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 4i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Record 5th consecutive loss (should trigger)
  .risk.recordTradeResult[`strat1;-50.0];

  / Verify breaker triggered
  .test.assert["Circuit breaker active"; first exec active from .risk.circuitBreakerState where strategy=`strat1];
  .test.assertEqual["Breach count incremented"; 1i; first exec breachCount from .risk.circuitBreakerState where strategy=`strat1];
  .test.assert["PausedUntil set"; not null first exec pausedUntil from .risk.circuitBreakerState where strategy=`strat1];
 };

/ Test 5: Check circuit breaker - active
test_circuitBreaker_check_active:{[]
  .risk.initCircuitBreakers[];

  / Configure and trigger breaker
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 0i; breachCount:enlist 1i; active:enlist 1b; pausedUntil:enlist .z.p+3600000000000; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Check should fail
  result:.risk.checkCircuitBreaker[`strat1];
  .test.assert["Check fails when active"; not result 0];
  .test.assertEqual["Reason is circuitBreakerActive"; `circuitBreakerActive; result 1];
 };

/ Test 6: Check circuit breaker - expired
test_circuitBreaker_check_expired:{[]
  .risk.initCircuitBreakers[];

  / Configure breaker with expired pause
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 0i; breachCount:enlist 1i; active:enlist 1b; pausedUntil:enlist .z.p-1000000000; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Check should pass and auto-resume
  result:.risk.checkCircuitBreaker[`strat1];
  .test.assert["Check passes after expiry"; result 0];

  / Verify breaker deactivated
  .test.assert["Circuit breaker inactive"; not first exec active from .risk.circuitBreakerState where strategy=`strat1];
 };

/ Test 7: Exponential backoff
test_circuitBreaker_backoff:{[]
  .risk.initCircuitBreakers[];

  / Configure strategy
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 5i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / First breach (breach count 0 → 300s pause)
  .risk.triggerCircuitBreaker[`strat1];
  pausedUntil1:first exec pausedUntil from .risk.circuitBreakerState where strategy=`strat1;

  / Resume and trigger again
  update active:0b, consecutiveLosses:5i, pausedUntil:0Np from `.risk.circuitBreakerState where strategy=`strat1;
  .risk.triggerCircuitBreaker[`strat1];
  pausedUntil2:first exec pausedUntil from .risk.circuitBreakerState where strategy=`strat1;

  / Second breach should have longer pause (breach count 1 → 600s pause)
  .test.assert["Second pause longer than first"; pausedUntil2 > pausedUntil1];
 };

/ Test 8: Global circuit breaker
test_circuitBreaker_global:{[]
  .risk.initCircuitBreakers[];

  / Trigger 10 strategies to activate global breaker
  i:0;
  while[i < 10;
    stratName:`$"strat",string i;
    `.risk.circuitBreakerConfig upsert ([] strategy:enlist stratName; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
    `.risk.circuitBreakerState upsert ([] strategy:enlist stratName; consecutiveLosses:enlist 0i; breachCount:enlist 0i; active:enlist 1b; pausedUntil:enlist .z.p+3600000000000; lastTradeResult:enlist `; lastUpdate:enlist .z.p);
    i+:1
  ];

  / Trigger 10th breach (should activate global)
  .risk.triggerCircuitBreaker[`strat9];

  / Verify global breaker active
  .test.assert["Global circuit breaker active"; first .risk.globalCircuitBreaker`active];
 };

/ Test 9: Event logging
test_circuitBreaker_events:{[]
  .risk.initCircuitBreakers[];

  / Clear events
  delete from `.risk.circuitBreakerEvents;

  / Configure strategy
  `.risk.circuitBreakerConfig upsert ([] strategy:enlist `strat1; consecutiveLossThreshold:enlist 5i; basePauseDuration:enlist 300i; maxPauseDuration:enlist 3600i);
  `.risk.circuitBreakerState upsert ([] strategy:enlist `strat1; consecutiveLosses:enlist 0i; breachCount:enlist 0i; active:enlist 0b; pausedUntil:enlist 0Np; lastTradeResult:enlist `; lastUpdate:enlist .z.p);

  / Record trades
  .risk.recordTradeResult[`strat1;100.0];
  .risk.recordTradeResult[`strat1;-50.0];

  / Verify events logged
  .test.assert["Events logged"; 2 = count .risk.circuitBreakerEvents];
 };

/ Test 10: Get status
test_circuitBreaker_status:{[]
  .risk.initCircuitBreakers[];

  / Get status
  status:.risk.getCircuitBreakerStatus[];

  / Verify structure
  .test.assert["Status has config"; `config in key status];
  .test.assert["Status has state"; `state in key status];
  .test.assert["Status has global"; `global in key status];
  .test.assert["Config is table"; .Q.qt status`config];
 };

-1 "Circuit breaker tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];

