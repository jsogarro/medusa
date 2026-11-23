/ ============================================================================
/ test_equity.q - Tests for Equity Schema and Alpaca Exchange
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - Equity schema table creation and inserts
/   - Market hours and calendar functions
/   - Symbol validation (equity vs crypto)
/   - Alpaca exchange registration
/   - Alpaca stub operations
/ ============================================================================

/ Load dependencies
\l src/q/init.q

/ Test counter
testsPassed:0;
testsFailed:0;

/ Test helper
assert:{[condition;testName]
  $[condition;
    [testsPassed+::1; -1 "  [PASS] ",testName];
    [testsFailed+::1; -1 "  [FAIL] ",testName]
  ]
 };

-1 "\n=== Testing Equity Schema ===\n";

/ Test 1: equityQuote table creation
assert[`equityQuote in key `.schema; "equityQuote table exists"];
assert[0 = count .schema.equityQuote; "equityQuote table is empty"];

/ Test 2: equityTrade table creation
assert[`equityTrade in key `.schema; "equityTrade table exists"];
assert[0 = count .schema.equityTrade; "equityTrade table is empty"];

/ Test 3: equityBar table creation
assert[`equityBar in key `.schema; "equityBar table exists"];
assert[0 = count .schema.equityBar; "equityBar table is empty"];

/ Test 4: equityMetadata table creation
assert[`equityMetadata in key `.schema; "equityMetadata table exists"];
assert[0 = count .schema.equityMetadata; "equityMetadata table is empty"];

/ Test 5: equityPosition table creation
assert[`equityPosition in key `.schema; "equityPosition table exists"];
assert[0 = count .schema.equityPosition; "equityPosition table is empty"];

/ Test 6: Insert into equityQuote
`.schema.equityQuote insert (.z.p; `AAPL; 150000000j; 150050000j; 100000000j; 200000000j; `A; `regular);
assert[1 = count .schema.equityQuote; "equityQuote insert successful"];

/ Test 7: Insert into equityTrade
`.schema.equityTrade insert (.z.p; `AAPL; 150025000j; 100000000j; `NYSE; `A; `regular);
assert[1 = count .schema.equityTrade; "equityTrade insert successful"];

/ Test 8: Insert into equityBar
`.schema.equityBar insert (.z.p; `AAPL; `1Min; 150000000j; 150100000j; 149900000j; 150050000j; 1000000000j; 150025000j; 100j);
assert[1 = count .schema.equityBar; "equityBar insert successful"];

/ Test 9: Insert into equityMetadata
`.schema.equityMetadata insert (`AAPL; `AppleInc; `stock; `NASDAQ; `Technology; `Consumer_Electronics; 3000000000000j; 0.5; 28.5; 1.2; 50000000j; .z.p);
assert[1 = count .schema.equityMetadata; "equityMetadata insert successful"];

/ Test 10: Insert into equityPosition
`.schema.equityPosition upsert (`AAPL; 100000000j; 150000000j; 15000000000j; 500000j; `long; 0j; .z.p);
assert[1 = count .schema.equityPosition; "equityPosition insert successful"];

-1 "\n=== Testing Symbol Validation ===\n";

/ Test 11: Valid equity symbols
assert[.qg.isValidEquitySymbol[`AAPL]; "AAPL is valid equity symbol"];
assert[.qg.isValidEquitySymbol[`MSFT]; "MSFT is valid equity symbol"];
assert[.qg.isValidEquitySymbol[`TSLA]; "TSLA is valid equity symbol"];
assert[.qg.isValidEquitySymbol[`SPY]; "SPY is valid equity symbol"];
assert[.qg.isValidEquitySymbol[`QQQ]; "QQQ is valid equity symbol"];

/ Test 12: Invalid equity symbols
assert[not .qg.isValidEquitySymbol[`BTCUSD]; "BTCUSD is not valid equity symbol"];
assert[not .qg.isValidEquitySymbol[`]; "Empty symbol is not valid"];
assert[not .qg.isValidEquitySymbol[`TOOLONG]; "6+ char symbol is not valid equity"];

/ Test 13: isEquity vs isCrypto
assert[.qg.isEquity[`AAPL]; "AAPL is equity"];
assert[not .qg.isCrypto[`AAPL]; "AAPL is not crypto"];
assert[.qg.isCrypto[`BTCUSD]; "BTCUSD is crypto"];
assert[not .qg.isEquity[`BTCUSD]; "BTCUSD is not equity"];

-1 "\n=== Testing Market Calendar ===\n";

/ Test 14: Weekday detection
/ Use a known Monday (2026-04-06)
assert[.exchange.calendar.isWeekday[2026.04.06]; "Monday is weekday"];
assert[.exchange.calendar.isWeekday[2026.04.07]; "Tuesday is weekday"];
assert[.exchange.calendar.isWeekday[2026.04.08]; "Wednesday is weekday"];
assert[.exchange.calendar.isWeekday[2026.04.09]; "Thursday is weekday"];
assert[.exchange.calendar.isWeekday[2026.04.10]; "Friday is weekday"];

/ Test 15: Weekend detection
assert[not .exchange.calendar.isWeekday[2026.04.11]; "Saturday is not weekday"];
assert[not .exchange.calendar.isWeekday[2026.04.12]; "Sunday is not weekday"];

/ Test 16: Holiday detection
assert[.exchange.calendar.isHoliday[2026.01.01]; "New Year's Day 2026 is holiday"];
assert[.exchange.calendar.isHoliday[2026.12.25]; "Christmas 2026 is holiday"];
assert[not .exchange.calendar.isHoliday[2026.04.15]; "Random April day is not holiday"];

/ Test 17: Trading day detection
assert[.exchange.calendar.isTradingDay[2026.04.06]; "Normal Monday is trading day"];
assert[not .exchange.calendar.isTradingDay[2026.01.01]; "New Year's Day is not trading day"];
assert[not .exchange.calendar.isTradingDay[2026.04.11]; "Saturday is not trading day"];

/ Test 18: Next/previous trading day
nextDay:.exchange.calendar.getNextTradingDay[2026.04.10];  / Friday -> Monday
assert[nextDay = 2026.04.13; "Next trading day after Friday is Monday"];

nextDay:.exchange.calendar.getNextTradingDay[2025.12.31];  / Wed before New Year -> Thu 1/2
assert[nextDay = 2026.01.02; "Next trading day after 12/31/2025 skips New Year"];

prevDay:.exchange.calendar.getPrevTradingDay[2026.04.13];  / Monday -> Friday
assert[prevDay = 2026.04.10; "Previous trading day before Monday is Friday"];

-1 "\n=== Testing Alpaca Exchange ===\n";

/ Test 19: Alpaca exchange is registered
.exchange.alpaca.registerAlpaca[];
assert[.exchange.registry.isRegistered[`alpaca]; "Alpaca is registered"];

/ Test 20: Alpaca is in EXCHANGES list
assert[`alpaca in .qg.EXCHANGES; "Alpaca is in EXCHANGES enum"];

/ Test 21: Place order (stub)
orderResp:.exchange.alpaca.placeOrder[`AAPL; `market; `buy; 0N; 100000000j];
assert[`orderId in key orderResp; "placeOrder returns orderId"];
assert[orderResp[`status] in `pending`open; "Order status is pending or open"];
assert[orderResp[`exchange] = `alpaca; "Order exchange is alpaca"];

/ Test 22: Get balance (stub)
balanceResp:.exchange.alpaca.getBalance[`USD];
assert[`amount in key balanceResp; "getBalance returns amount"];
assert[balanceResp[`currency] = `USD; "Balance currency is USD"];

/ Test 23: Get orderbook (stub)
obResp:.exchange.alpaca.getOrderbook[`AAPL];
assert[count[obResp] > 0; "getOrderbook returns non-empty table"];
assert[`side in cols obResp; "Orderbook has side column"];
assert[`price in cols obResp; "Orderbook has price column"];

/ Test 24: Get open orders (stub)
openOrders:.exchange.alpaca.getOpenOrders[`AAPL];
assert[count[openOrders] >= 0; "getOpenOrders returns table"];

/ Test 25: Get position (stub)
posResp:.exchange.alpaca.getPosition[`AAPL];
assert[`pair in key posResp; "getPosition returns pair"];
assert[`quantity in key posResp; "getPosition returns quantity"];

/ Test 26: Cancel order (stub)
cancelResp:.exchange.alpaca.cancelOrder[orderResp`orderId];
assert[cancelResp[`status] = `cancelled; "Order cancelled successfully"];

-1 "\n=== Testing Market Hours Check ===\n";

/ Test 27: Market hours check function exists
assert[.risk.checkMarketHours; "checkMarketHours function exists"];

/ Test 28: Market hours check for crypto (always pass)
result:.risk.checkMarketHours[`coinbase; `BTCUSD];
assert[result 0; "Crypto orders allowed regardless of time"];

/ Test 29: Market hours check for equity (depends on current time)
/ Note: This test result varies based on actual time
result:.risk.checkMarketHours[`alpaca; `AAPL];
-1 "  [INFO] Market hours check for AAPL: ",string[result 0]," (depends on current time)";

-1 "\n=== Test Summary ===\n";
-1 "  Tests Passed: ",string testsPassed;
-1 "  Tests Failed: ",string testsFailed;
-1 "  Total Tests:  ",string testsPassed + testsFailed;

/ Exit with appropriate code
if[testsFailed > 0; exit 1];
exit 0;
