/ Tests for Order Flow Risk Monitoring

/ Load test framework
\l tests/q/testFramework.q

\d .test

/ ═══════════════════════════════════════════════════════════════════
/ Setup
/ ═══════════════════════════════════════════════════════════════════

setup:{[]
  / Initialize risk system
  .risk.init[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Test Cases
/ ═══════════════════════════════════════════════════════════════════

/ Test: Order flow metrics calculation
testOrderFlowMetrics:{[]
  setup[];

  / Create test orders in last 60 seconds
  windowStart:.z.p - 00:01:00;

  `.schema.order upsert ([] id:1 2 3 4 5j; strategy:`arb_v2`arb_v2`arb_v2`arb_v2`arb_v2;
                            sym:`BTCUSD`BTCUSD`BTCUSD`BTCUSD`BTCUSD; exchange:`coinbase`coinbase`coinbase`coinbase`coinbase;
                            side:`buy`buy`buy`buy`buy; quantity:1.0 1.0 1.0 1.0 1.0;
                            price:60000.0 60000.0 60000.0 60000.0 60000.0;
                            status:`accepted`rejected`filled`cancelled`open;
                            time_created:windowStart windowStart windowStart windowStart windowStart;
                            time_updated:.z.p .z.p .z.p .z.p .z.p);

  / Update order flow metrics
  .risk.updateOrderFlowMetrics[];

  / Check metrics
  metrics:first -1#select from .risk.orderFlowMetrics;
  assert[metrics[`ordersSubmitted] = 5i; "Should have 5 orders submitted"];
  assert[metrics[`ordersAccepted] = 3i; "Should have 3 orders accepted (accepted+filled+open)"];
  assert[metrics[`ordersRejected] = 1i; "Should have 1 order rejected"];
  assert[metrics[`ordersCancelled] = 1i; "Should have 1 order cancelled"];
  assert[metrics[`ordersFilled] = 1i; "Should have 1 order filled"];

  / Check rates
  assert[metrics[`ordersPerSecond] = 5.0 % 60.0; "Orders/sec should be 5/60"];
  assert[metrics[`rejectionRate] = 20.0; "Rejection rate should be 20%"];
  assert[metrics[`fillRate] = 20.0; "Fill rate should be 20%"];

  pass[];
 };

/ Test: Pending order exposure calculation
testPendingOrderExposure:{[]
  setup[];

  / Create pending orders
  windowStart:.z.p - 00:01:00;

  `.schema.order upsert ([] id:1 2j; strategy:`arb_v2`arb_v2; sym:`BTCUSD`ETHUSD; exchange:`coinbase`coinbase;
                            side:`buy`buy; quantity:1.0 5.0; price:60000.0 3000.0;
                            status:`open`partiallyFilled;
                            time_created:windowStart windowStart; time_updated:.z.p .z.p);

  / Update order flow metrics
  .risk.updateOrderFlowMetrics[];

  / Check pending exposure
  metrics:first -1#select from .risk.orderFlowMetrics;
  assert[metrics[`pendingOrderExposure] = 75000.0; "Pending exposure should be 75000"];

  pass[];
 };

/ Test: Order flow threshold breach
testOrderFlowThreshold:{[]
  setup[];

  / Create many orders to exceed threshold
  windowStart:.z.p - 00:01:00;
  orderCount:150;

  `.schema.order upsert ([] id:til orderCount; strategy:orderCount#`arb_v2; sym:orderCount#`BTCUSD;
                            exchange:orderCount#`coinbase; side:orderCount#`buy; quantity:orderCount#1.0;
                            price:orderCount#60000.0; status:orderCount#`accepted;
                            time_created:orderCount#windowStart; time_updated:orderCount#.z.p);

  / Update order flow metrics
  .risk.updateOrderFlowMetrics[];

  / Check threshold breach (default is 100 orders/sec)
  metrics:first -1#select from .risk.orderFlowMetrics;
  assert[metrics[`ordersPerSecond] > 2.0; "Orders/sec should exceed threshold"];

  / Check risk event was logged
  events:select from .risk.riskEvents where eventType=`orderFlowExcessive;
  assert[count[events] > 0; "Order flow threshold breach should be logged"];

  pass[];
 };

/ Test: Order flow by exchange
testOrderFlowByExchange:{[]
  setup[];

  / Create orders on different exchanges
  windowStart:.z.p - 00:01:00;

  `.schema.order upsert ([] id:1 2 3 4j; strategy:`arb_v2`arb_v2`arb_v2`arb_v2;
                            sym:`BTCUSD`BTCUSD`BTCUSD`BTCUSD; exchange:`coinbase`coinbase`kraken`kraken;
                            side:`buy`buy`buy`buy; quantity:1.0 1.0 1.0 1.0; price:60000.0 60000.0 60000.0 60000.0;
                            status:`accepted`rejected`accepted`filled;
                            time_created:windowStart windowStart windowStart windowStart; time_updated:.z.p .z.p .z.p .z.p);

  / Update order flow metrics
  .risk.updateOrderFlowMetrics[];

  / Check by exchange
  byExchange:select from .risk.orderFlowByExchange;
  assert[2 = count byExchange; "Should have 2 exchanges"];

  / Coinbase: 2 orders, 1 rejected
  coinbaseFlow:first select from byExchange where exchange=`coinbase;
  assert[coinbaseFlow[`rejectionRate] = 50.0; "Coinbase rejection rate should be 50%"];

  / Kraken: 2 orders, 1 filled
  krakenFlow:first select from byExchange where exchange=`kraken;
  assert[krakenFlow[`fillRate] = 50.0; "Kraken fill rate should be 50%"];

  pass[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests
/ ═══════════════════════════════════════════════════════════════════

runTests:{[]
  .test.run[`testOrderFlowMetrics];
  .test.run[`testPendingOrderExposure];
  .test.run[`testOrderFlowThreshold];
  .test.run[`testOrderFlowByExchange];
 };

/ Run tests
runTests[];

\d .
