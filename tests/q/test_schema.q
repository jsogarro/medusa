/ test_schema.q - Comprehensive schema tests
/ Tests all schema modules and operations

/ Load schema
\l src/q/schema/init.q
.qg.loadAllSchemas[];
.qg.initAllTables[];

/ Test framework
testCount:0;
passCount:0;
failCount:0;

assert:{[condition; testName]
  testCount+:1;
  if[condition;
    passCount+:1;
    -1 "  ✓ ", testName;
    :1b
  ];
  failCount+:1;
  -1 "  ✗ ", testName;
  0b
 };

// ============================================================================
// TYPE TESTS
// ============================================================================

-1 "\n=== Testing Types Module ===\n";

/ Test precision constants
assert[.qg.PRICE_PRECISION = 1000000; "PRICE_PRECISION is 1000000"];
assert[.qg.VOLUME_PRECISION = 1000000; "VOLUME_PRECISION is 1000000"];
assert[.qg.FEE_PRECISION = 1000000; "FEE_PRECISION is 1000000"];

/ Test toFixed conversion
testPrice:.qg.toPrice[123.456789];
assert[testPrice = 123456789j; "toPrice converts 123.456789 to 123456789j"];

/ Test fromFixed conversion
testFloat:.qg.fromPrice[123456789j];
assert[testFloat = 123.456789; "fromPrice converts 123456789j to 123.456789"];

/ Test round-trip conversion
original:50000.123456;
converted:.qg.fromPrice[.qg.toPrice[original]];
assert[converted = original; "Round-trip price conversion preserves value"];

/ Test validation functions
assert[.qg.isValidOrderStatus[`filled]; "isValidOrderStatus accepts `filled"];
assert[not .qg.isValidOrderStatus[`invalid]; "isValidOrderStatus rejects `invalid"];
assert[.qg.isValidCurrency[`BTC]; "isValidCurrency accepts `BTC"];
assert[.qg.isValidExchange[`coinbase]; "isValidExchange accepts `coinbase"];
assert[.qg.isValidPrice[1000000j]; "isValidPrice accepts positive long"];
assert[not .qg.isValidPrice[-1000j]; "isValidPrice rejects negative long"];

// ============================================================================
// EXCHANGE TESTS
// ============================================================================

-1 "\n=== Testing Exchange Module ===\n";

/ Test exchange creation
ex1:.qg.createExchange[`coinbase; `hash123; `region`usa`tier`pro!()];
assert[ex1 = `coinbase; "createExchange returns exchange name"];
assert[1 = count select from exchange where name=`coinbase; "Exchange record created"];

/ Test balance update
bal1:.qg.updateBalance[`coinbase; `BTC; 5000000j; 4000000j; 1000000j];
assert[bal1 ~ (`coinbase; `BTC); "updateBalance returns exchange/currency tuple"];
assert[1 = count select from balance where exchange_name=`coinbase, currency=`BTC; "Balance record created"];

/ Get balance
balRec:.qg.getBalance[`coinbase; `BTC];
assert[balRec[`amount] = 5000000j; "Balance amount correct"];
assert[balRec[`available] = 4000000j; "Balance available correct"];
assert[balRec[`reserved] = 1000000j; "Balance reserved correct"];

/ Test position opening
posId:.qg.openPosition[`coinbase; `BTCUSD; `long; 1000000j; 50000000000j; 2.0];
assert[posId = 1j; "openPosition returns position ID 1"];
assert[1 = count select from position where position_id=posId; "Position record created"];

/ Update position
.qg.updatePosition[posId; 51000000000j];
posRec:first select from position where position_id=posId;
assert[posRec[`current_price] = 51000000000j; "Position current price updated"];
assert[posRec[`unrealized_pnl] = 1000000000j; "Position P&L calculated correctly"];

/ Test target creation
tgtId:.qg.createTarget[`coinbase; `USD; 10000000000j; 100000000j; 1j];
assert[tgtId = 1j; "createTarget returns target ID 1"];
assert[1 = count select from target where target_id=tgtId; "Target record created"];

// ============================================================================
// ORDER TESTS
// ============================================================================

-1 "\n=== Testing Order Module ===\n";

/ Test order creation
ordId:.qg.createOrder[
  `coinbase; `limit; `strategy1; `BTC; `USD;
  1000000j; 50000000000j; 49500000000j; 0.8; 100000000j; ()!()
];
assert[ordId = 1j; "createOrder returns order ID 1"];
assert[1 = count select from order where order_id=ordId; "Order record created"];

/ Get order
ordRec:.qg.getOrder[ordId];
assert[ordRec[`status] = `pending; "Order status is pending"];
assert[ordRec[`volume] = 1000000j; "Order volume correct"];
assert[ordRec[`price] = 50000000000j; "Order price correct"];

/ Update order status
.qg.updateOrderStatus[ordId; `open; `EXCH12345];
ordRec:.qg.getOrder[ordId];
assert[ordRec[`status] = `open; "Order status updated to open"];
assert[ordRec[`exchange_order_id] = `EXCH12345; "Exchange order ID set"];

/ Partially fill order
.qg.updateOrderFill[ordId; 500000j];
ordRec:.qg.getOrder[ordId];
assert[ordRec[`filled_volume] = 500000j; "Order partially filled"];
assert[ordRec[`status] = `partially_filled; "Order status is partially_filled"];

/ Fully fill order
.qg.updateOrderFill[ordId; 1000000j];
ordRec:.qg.getOrder[ordId];
assert[ordRec[`filled_volume] = 1000000j; "Order fully filled"];
assert[ordRec[`status] = `filled; "Order status is filled"];

/ Test query functions
openOrders:.qg.getOpenOrders[];
assert[0 = count openOrders; "No open orders after filling"];

// ============================================================================
// TRADE TESTS
// ============================================================================

-1 "\n=== Testing Trade Module ===\n";

/ Create new order for trade testing
ordId2:.qg.createOrder[
  `coinbase; `market; `strategy2; `ETH; `USD;
  2000000j; 0j; 3000000000j; 0.9; 50000000j; ()!()
];

/ Record trade
trdId:.qg.createTrade[
  `coinbase; `TRD123; ordId2; `buy;
  1000000j; 3000000000j; `ETH; `USD;
  15000j; `USD; ()!()
];
assert[trdId = 1j; "createTrade returns trade ID 1"];
assert[1 = count select from trade where trade_id=trdId; "Trade record created"];

/ Verify order filled volume updated
ordRec2:.qg.getOrder[ordId2];
assert[ordRec2[`filled_volume] = 1000000j; "Order filled volume updated by trade"];

/ Test trade queries
trdRec:.qg.getTrade[trdId];
assert[trdRec[`price] = 3000000000j; "Trade price correct"];
assert[trdRec[`volume] = 1000000j; "Trade volume correct"];

tradesForOrder:.qg.getTradesForOrder[ordId2];
assert[1 = count tradesForOrder; "Found 1 trade for order"];

// ============================================================================
// TRANSACTION TESTS
// ============================================================================

-1 "\n=== Testing Transaction Module ===\n";

/ Set up second exchange with balance
.qg.createExchange[`kraken; `hash456; `region`usa`tier`basic!()];
.qg.updateBalance[`coinbase; `BTC; 10000000j; 10000000j; 0j];

/ Create transaction
txnId:.qg.createTransaction[
  `coinbase; `kraken; `BTC;
  2000000j; 1000j; `BTC; ()!()
];
assert[txnId = 1j; "createTransaction returns transaction ID 1"];
assert[1 = count select from transaction where transaction_id=txnId; "Transaction record created"];

/ Verify source balance reserved
srcBal:.qg.getBalance[`coinbase; `BTC];
assert[srcBal[`available] = 7999000j; "Source available reduced"];
assert[srcBal[`reserved] = 2001000j; "Source reserved increased"];

/ Update transaction status to completed
.qg.updateTransactionStatus[txnId; `completed; 6j; `0xabc];
txnRec:.qg.getTransaction[txnId];
assert[txnRec[`status] = `completed; "Transaction status is completed"];

/ Verify balances updated
srcBal:.qg.getBalance[`coinbase; `BTC];
dstBal:.qg.getBalance[`kraken; `BTC];
assert[srcBal[`amount] = 7999000j; "Source amount reduced"];
assert[dstBal[`amount] = 2000000j; "Destination amount increased"];

// ============================================================================
// METADATA TESTS
// ============================================================================

-1 "\n=== Testing Metadata Module ===\n";

/ Test datum operations
.qg.setDatum[`performance; `avg_latency; 123.45; `float; "Avg latency ms"; ()!()];
latency:.qg.getDatum[`performance; `avg_latency];
assert[latency = 123.45; "Datum value retrieved correctly"];

/ Test metric increment
.qg.setMetric[`trading; `total_trades; 1000j; "Total trades"];
.qg.incrMetric[`trading; `total_trades; 250j];
totalTrades:.qg.getDatum[`trading; `total_trades];
assert[totalTrades = 1250j; "Metric incremented correctly"];

/ Test flag operations
flagId:.qg.createFlag[`enable_arbitrage; `strategy; "Enable arb strategy"; ()!()];
assert[not .qg.isFlagEnabled[`enable_arbitrage]; "Flag disabled by default"];

.qg.enableFlag[`enable_arbitrage];
assert[.qg.isFlagEnabled[`enable_arbitrage]; "Flag enabled"];

.qg.toggleFlag[`enable_arbitrage];
assert[not .qg.isFlagEnabled[`enable_arbitrage]; "Flag toggled to disabled"];

// ============================================================================
// NEGATIVE TESTS (Error Cases)
// ============================================================================

-1 "\n=== Negative Tests (Error Handling) ===\n";

/ Test duplicate exchange creation
@[{.qg.createExchange[`coinbase; `newhash; ()!()]}; `; {()}];
assert[1 = count select from exchange where name=`coinbase; "Duplicate exchange rejected (still only 1)"];

/ Test negative balance update
negBalResult:@[{.qg.updateBalance[`coinbase; `BTC; -1000j; -500j; -500j]}; `; {`error}];
assert[negBalResult~`error; "Negative balance amounts should be prevented"];

/ Test position edge cases
/ Zero size position should fail
zeroSizeResult:@[{.qg.openPosition[`coinbase; `BTCUSD; `long; 0j; 50000000000j; 1.0]}; `; {`error}];
assert[zeroSizeResult~`error; "Zero size position rejected"];

/ Invalid position side
invalidSideResult:@[{.qg.openPosition[`coinbase; `BTCUSD; `invalid; 1000000j; 50000000000j; 1.0]}; `; {`error}];
assert[invalidSideResult~`error; "Invalid position side rejected"];

/ Test target state transitions
/ Create and deactivate target
tgt2:.qg.createTarget[`coinbase; `EUR; 5000000000j; 50000000j; 2j];
.qg.deactivateTarget[tgt2];
tgtRec:first select from target where target_id=tgt2;
assert[not tgtRec[`is_active]; "Target deactivated correctly"];

/ Test transaction with insufficient balance
/ Reset balance first
.qg.updateBalance[`coinbase; `ETH; 100000j; 100000j; 0j];
insuffResult:@[{.qg.createTransaction[`coinbase; `kraken; `ETH; 500000j; 1000j; `ETH; ()!()]}; `; {`error}];
assert[insuffResult~`error; "Transaction with insufficient balance rejected"];

/ Test transaction same source/destination
sameExchResult:@[{.qg.createTransaction[`coinbase; `coinbase; `BTC; 1000000j; 100j; `BTC; ()!()]}; `; {`error}];
assert[sameExchResult~`error; "Transaction to same exchange rejected"];

// ============================================================================
// SUMMARY
// ============================================================================

-1 "\n========================================";
-1 "Test Summary:";
-1 "  Total:  ", string testCount;
-1 "  Passed: ", string passCount;
-1 "  Failed: ", string failCount;
-1 "========================================\n";

/ Exit with appropriate code
if[failCount > 0; exit 1];
exit 0;
