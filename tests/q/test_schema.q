/ Tests for schema module (schema/*.q)

\l tests/q/test_framework.q
\l src/q/schema/init.q

/ Initialize all schemas and tables
.qg.loadAllSchemas[];
.qg.initAllTables[];

/ ========================================
/ Schema loading tests
/ ========================================

test_schema_all_tables_exist:{
  expected:`exchange`balance`position`target`order`trade`transaction`datum`flag;
  existing:tables[];
  .test.assert["All expected tables exist"; all expected in existing];
 }

test_schema_validation:{
  result:.qg.validateSchema[];
  .test.assert["Validation returns table"; 98h = type result];
  .test.assert["No missing tables"; 0 < count result];
 }

/ ========================================
/ Order table tests
/ ========================================

test_order_insert:{
  / Get count before
  before:count order;

  / Create test order
  orderId:.qg.createOrder (`coinbase; `limit; `testStrategy; `BTC; `USD; 1000000j; 50000000000j; 50000000000j; 0.95; 100000j; ()!());

  / Check insert
  .test.assert["Order ID generated"; orderId > 0];
  .test.assertEqual["Order count increased"; before + 1; count order];

  / Verify order fields
  ord:.qg.getOrder[orderId];
  .test.assertEqual["Exchange name set"; `coinbase; ord`exchange_name];
  .test.assertEqual["Order type set"; `limit; ord`order_type];
  .test.assertEqual["Actor set"; `testStrategy; ord`actor];
  .test.assertEqual["Status is pending"; `pending; ord`status];

  / Clean up
  .qg.initOrderTable[];
 }

test_order_status_transition:{
  / Create order
  orderId:.qg.createOrder (`coinbase; `limit; `testStrategy; `BTC; `USD; 1000000j; 50000000j; 0j; 0.95; 100000j; ()!());

  / Update status
  .qg.updateOrderStatus[orderId; `open; `EXCH_123];

  / Verify
  ord:.qg.getOrder[orderId];
  .test.assertEqual["Status updated"; `open; ord`status];
  .test.assertEqual["Exchange order ID set"; `EXCH_123; ord`exchange_order_id];

  / Clean up
  .qg.initOrderTable[];
 }

test_order_fill:{
  / Create order
  orderId:.qg.createOrder (`coinbase; `limit; `testStrategy; `BTC; `USD; 1000000j; 50000000j; 0j; 0.95; 100000j; ()!());

  / Fill partially
  .qg.updateOrderFill[orderId; 500000j];

  ord:.qg.getOrder[orderId];
  .test.assertEqual["Filled volume updated"; 500000j; ord`filled_volume];
  .test.assertEqual["Status is partially_filled"; `partially_filled; ord`status];

  / Fill completely
  .qg.updateOrderFill[orderId; 1000000j];

  ord:.qg.getOrder[orderId];
  .test.assertEqual["Fully filled"; `filled; ord`status];

  / Clean up
  .qg.initOrderTable[];
 }

/ ========================================
/ Trade table tests
/ ========================================

test_trade_insert:{
  / Create order first
  orderId:.qg.createOrder (`coinbase; `limit; `testStrategy; `BTC; `USD; 1000000j; 50000000j; 0j; 0.95; 100000j; ()!());
  .qg.updateOrderStatus[orderId; `open; `EXCH_123];

  / Create trade
  tradeId:.qg.createTrade (`coinbase; `TRD_456; orderId; `buy; 500000j; 50000000j; `BTC; `USD; 10000j; `USD; ()!());

  .test.assert["Trade ID generated"; tradeId > 0];

  / Verify trade
  trd:.qg.getTrade[tradeId];
  .test.assertEqual["Exchange name set"; `coinbase; trd`exchange_name];
  .test.assertEqual["Order ID linked"; orderId; trd`order_id];
  .test.assertEqual["Trade type set"; `buy; trd`trade_type];
  .test.assertEqual["Volume set"; 500000j; trd`volume];

  / Verify order updated
  ord:.qg.getOrder[orderId];
  .test.assertEqual["Order filled volume updated"; 500000j; ord`filled_volume];

  / Clean up
  .qg.initOrderTable[];
  .qg.initTradeTable[];
 }

test_trade_vwap:{
  / Create order
  orderId:.qg.createOrder (`coinbase; `market; `testStrategy; `BTC; `USD; 3000000j; 0j; 0j; 0.95; 100000j; ()!());
  .qg.updateOrderStatus[orderId; `open; `EXCH_123];

  / Create multiple trades at different prices
  .qg.createTrade (`coinbase; `TRD_1; orderId; `buy; 1000000j; 50000000j; `BTC; `USD; 5000j; `USD; ()!());
  .qg.createTrade (`coinbase; `TRD_2; orderId; `buy; 1000000j; 51000000j; `BTC; `USD; 5100j; `USD; ()!());
  .qg.createTrade (`coinbase; `TRD_3; orderId; `buy; 1000000j; 52000000j; `BTC; `USD; 5200j; `USD; ()!());

  / Calculate VWAP
  startTime:.z.p - 00:01:00;
  endTime:.z.p + 00:01:00;
  vwap:.qg.getVWAP[`coinbase; `BTC; `USD; startTime; endTime];

  / VWAP = (50M*1M + 51M*1M + 52M*1M) / (1M + 1M + 1M) = 51M
  .test.assertNear["VWAP calculated"; 51000000j; vwap; 1000j];

  / Clean up
  .qg.initOrderTable[];
  .qg.initTradeTable[];
 }

/ ========================================
/ Reset and stats tests
/ ========================================

test_schema_reset:{
  / Insert test data
  .qg.createOrder (`coinbase; `limit; `test; `BTC; `USD; 1000000j; 50000000j; 0j; 0.95; 100000j; ()!());

  .test.assert["Order table has data"; 0 < count order];

  / Reset
  .qg.resetTables[];

  / Verify reset
  .test.assertEqual["Order table cleared"; 0; count order];
 }

test_schema_stats:{
  / Get stats
  stats:.qg.getSchemaStats[];

  .test.assert["Stats is table"; 98h = type stats];
  .test.assert["Has table column"; `table in cols stats];
  .test.assert["Has rowCount column"; `rowCount in cols stats];
 }

-1 "Schema tests loaded";
