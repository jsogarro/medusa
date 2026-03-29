/ Medusa — Money Library Unit Tests
/ Comprehensive test coverage for .money namespace

/ Load the money library
\l src/q/lib/money.q

/ Test framework - simple assertion system
.test.assert:{[condition;msg]
  if[not condition;
    -1 "FAIL: ",msg;
    '"Test failed: ",msg
  ];
  -1 "PASS: ",msg;
 };

.test.assertError:{[f;msg]
  result: @[f;`;{`error}];
  if[not result~`error;
    -1 "FAIL: ",msg," (expected error but got result)";
    '"Test failed: ",msg
  ];
  -1 "PASS: ",msg;
 };

-1 "";
-1 "========================================";
-1 "  Money Library Unit Tests";
-1 "========================================";
-1 "";

/ ========================================
/ Phase 1 Tests: Currency Metadata
/ ========================================

-1 "Phase 1: Currency Metadata Tests";
-1 "----------------------------------------";

/ Test 1.1: Currency validation
.test.assert[.money.validCurrency[`BTC]; "Valid currency BTC"];
.test.assert[.money.validCurrency[`USD]; "Valid currency USD"];
.test.assert[.money.validCurrency[`EUR]; "Valid currency EUR"];
.test.assert[not .money.validCurrency[`INVALID]; "Invalid currency rejected"];
.test.assert[not .money.validCurrency[`XXX]; "Unknown currency rejected"];

/ Test 1.2: Currency precision lookup
.test.assert[.money.precision[`BTC] = 8; "BTC precision is 8"];
.test.assert[.money.precision[`USD] = 2; "USD precision is 2"];
.test.assert[.money.precision[`EUR] = 2; "EUR precision is 2"];
.test.assert[.money.precision[`JPY] = 0; "JPY precision is 0"];
.test.assert[.money.precision[`ETH] = 18; "ETH precision is 18"];

/ Test 1.3: Currency metadata table structure
.test.assert[`BTC in key .money.currencies; "BTC in currencies table"];
.test.assert[`USD in key .money.currencies; "USD in currencies table"];
.test.assert[.money.currencies[`USD;`symbol] ~ "$"; "USD symbol is $"];
.test.assert[.money.currencies[`EUR;`symbol] ~ "€"; "EUR symbol is €"];
.test.assert[.money.currencies[`BTC;`name] ~ "Bitcoin"; "BTC name is Bitcoin"];

/ Test 1.4: Invalid currency error handling
.test.assertError[{.money.requireCurrency[`INVALID]}; "requireCurrency throws on invalid"];
.test.assertError[{.money.precision[`XXX]}; "precision throws on invalid currency"];

-1 "";

/ ========================================
/ Phase 2 Tests: Money Constructor
/ ========================================

-1 "Phase 2: Money Constructor Tests";
-1 "----------------------------------------";

/ Test 2.1: Basic constructor
m1: .money.new[100; `USD];
.test.assert[m1[`amount] = 100.0; "Constructor sets amount"];
.test.assert[m1[`currency] = `USD; "Constructor sets currency"];

/ Test 2.2: Constructor with float
m2: .money.new[0.005; `BTC];
.test.assert[m2[`amount] = 0.005; "Constructor handles float"];
.test.assert[m2[`currency] = `BTC; "Float constructor sets currency"];

/ Test 2.3: Constructor with string
m3: .money.new["100.50"; `USD];
.test.assert[m3[`amount] = 100.5; "Constructor parses string"];
.test.assert[m3[`currency] = `USD; "String constructor sets currency"];

/ Test 2.4: Rounding to precision
m4: .money.new[0.123456789; `BTC];
.test.assert[m4[`amount] = 0.12345679; "BTC rounded to 8 decimals"];

m5: .money.new[100.5555; `USD];
.test.assert[m5[`amount] = 100.56; "USD rounded to 2 decimals"];

m6: .money.new[1000.999; `JPY];
.test.assert[m6[`amount] = 1001; "JPY rounded to 0 decimals"];

/ Test 2.5: Negative amount validation
.test.assertError[{.money.new[-10; `USD]}; "Negative amount rejected"];
.test.assertError[{.money.new[-0.5; `BTC]}; "Negative BTC rejected"];

/ Test 2.6: Invalid currency in constructor
.test.assertError[{.money.new[100; `INVALID]}; "Constructor rejects invalid currency"];

/ Test 2.7: Type checking
.test.assert[.money.isMoney[m1]; "isMoney recognizes Money dict"];
.test.assert[not .money.isMoney[`notmoney]; "isMoney rejects symbol"];
.test.assert[not .money.isMoney[100]; "isMoney rejects number"];
.test.assert[not .money.isMoney[`amount`currency!(100;`INVALID)]; "isMoney rejects invalid currency"];

/ Test 2.8: requireMoney validation
.test.assertError[{.money.requireMoney[`notmoney]}; "requireMoney throws on non-Money"];
.test.assertError[{.money.requireMoney[100]}; "requireMoney throws on number"];

-1 "";

/ ========================================
/ Phase 3 Tests: Arithmetic Operators
/ ========================================

-1 "Phase 3: Arithmetic Operators Tests";
-1 "----------------------------------------";

/ Test 3.1: Addition
usd1: .money.new[100; `USD];
usd2: .money.new[50; `USD];
sum: .money.add[usd1; usd2];
.test.assert[sum[`amount] = 150.0; "Addition correct"];
.test.assert[sum[`currency] = `USD; "Addition preserves currency"];

/ Test 3.2: Addition with rounding
usd3: .money.new[100.555; `USD];
usd4: .money.new[200.555; `USD];
sum2: .money.add[usd3; usd4];
.test.assert[sum2[`amount] = 301.11; "Addition rounds correctly"];

/ Test 3.3: Currency mismatch error in addition
btc1: .money.new[1; `BTC];
.test.assertError[{.money.add[usd1; btc1]}; "Addition rejects currency mismatch"];

/ Test 3.4: Subtraction
diff: .money.sub[usd1; usd2];
.test.assert[diff[`amount] = 50.0; "Subtraction correct"];
.test.assert[diff[`currency] = `USD; "Subtraction preserves currency"];

/ Test 3.5: Subtraction with negative result
diff2: .money.sub[usd2; usd1];
.test.assert[diff2[`amount] = -50.0; "Subtraction allows negative (P&L)"];

/ Test 3.6: Currency mismatch error in subtraction
.test.assertError[{.money.sub[usd1; btc1]}; "Subtraction rejects currency mismatch"];

/ Test 3.7: Multiplication by scalar
prod: .money.mul[usd1; 1.5];
.test.assert[prod[`amount] = 150.0; "Multiplication correct"];
.test.assert[prod[`currency] = `USD; "Multiplication preserves currency"];

/ Test 3.8: Multiplication by integer
prod2: .money.mul[btc1; 2];
.test.assert[prod2[`amount] = 2.0; "Multiplication by int correct"];

/ Test 3.9: Multiplication with rounding
btc2: .money.new[1; `BTC];
prod3: .money.mul[btc2; 0.01];
.test.assert[prod3[`amount] = 0.01; "Multiplication rounds to precision"];

/ Test 3.10: Invalid multiplier type
.test.assertError[{.money.mul[usd1; `invalid]}; "Multiplication rejects symbol multiplier"];

/ Test 3.11: Division by scalar
quot: .money.div[usd1; 2];
.test.assert[quot[`amount] = 50.0; "Division correct"];
.test.assert[quot[`currency] = `USD; "Division preserves currency"];

/ Test 3.12: Division with rounding
usd5: .money.new[100; `USD];
quot2: .money.div[usd5; 3];
.test.assert[quot2[`amount] = 33.33; "Division rounds correctly"];

/ Test 3.13: Division by zero error
.test.assertError[{.money.div[usd1; 0]}; "Division by zero rejected"];

/ Test 3.14: Invalid divisor type
.test.assertError[{.money.div[usd1; `invalid]}; "Division rejects symbol divisor"];

-1 "";

/ ========================================
/ Phase 4 Tests: Comparison Operators
/ ========================================

-1 "Phase 4: Comparison Operators Tests";
-1 "----------------------------------------";

/ Test 4.1: Equality
usd6: .money.new[100; `USD];
usd7: .money.new[100; `USD];
usd8: .money.new[50; `USD];
.test.assert[.money.eq[usd6; usd7]; "Equal amounts are equal"];
.test.assert[not .money.eq[usd6; usd8]; "Different amounts not equal"];

/ Test 4.2: Equality requires same currency
eur1: .money.new[100; `EUR];
.test.assert[not .money.eq[usd6; eur1]; "Different currencies not equal"];

/ Test 4.3: Less than
.test.assert[.money.lt[usd8; usd6]; "50 < 100"];
.test.assert[not .money.lt[usd6; usd8]; "100 not < 50"];
.test.assert[not .money.lt[usd6; usd7]; "Equal amounts not <"];

/ Test 4.4: Less than with currency mismatch
.test.assertError[{.money.lt[usd6; eur1]}; "Less than rejects currency mismatch"];

/ Test 4.5: Greater than
.test.assert[.money.gt[usd6; usd8]; "100 > 50"];
.test.assert[not .money.gt[usd8; usd6]; "50 not > 100"];
.test.assert[not .money.gt[usd6; usd7]; "Equal amounts not >"];

/ Test 4.6: Greater than with currency mismatch
.test.assertError[{.money.gt[usd6; eur1]}; "Greater than rejects currency mismatch"];

/ Test 4.7: Less than or equal
.test.assert[.money.lte[usd8; usd6]; "50 <= 100"];
.test.assert[.money.lte[usd6; usd7]; "100 <= 100"];
.test.assert[not .money.lte[usd6; usd8]; "100 not <= 50"];

/ Test 4.8: Greater than or equal
.test.assert[.money.gte[usd6; usd8]; "100 >= 50"];
.test.assert[.money.gte[usd6; usd7]; "100 >= 100"];
.test.assert[not .money.gte[usd8; usd6]; "50 not >= 100"];

-1 "";

/ ========================================
/ Phase 5 Tests: Formatting
/ ========================================

-1 "Phase 5: Formatting Tests";
-1 "----------------------------------------";

/ Test 5.1: USD formatting
usd9: .money.new[100.5; `USD];
.test.assert[.money.fmt[usd9] ~ "$100.50"; "USD formats with $ prefix"];

/ Test 5.2: BTC formatting
btc3: .money.new[0.005; `BTC];
.test.assert[.money.fmt[btc3] ~ "0.00500000 BTC"; "BTC formats with suffix"];

/ Test 5.3: EUR formatting
eur2: .money.new[50.25; `EUR];
.test.assert[.money.fmt[eur2] ~ "€50.25"; "EUR formats with € prefix"];

/ Test 5.4: JPY formatting (no decimals)
jpy1: .money.new[1000; `JPY];
.test.assert[.money.fmt[jpy1] ~ "¥1000"; "JPY formats without decimals"];

/ Test 5.5: ETH formatting (high precision)
eth1: .money.new[1.5; `ETH];
formatted: .money.fmt[eth1];
.test.assert[formatted like "1.500000000000000000 ETH"; "ETH formats with 18 decimals"];

-1 "";

/ ========================================
/ Phase 6 Tests: Currency Conversion
/ ========================================

-1 "Phase 6: Currency Conversion Tests";
-1 "----------------------------------------";

/ Test 6.1: Same currency conversion
usd10: .money.new[100; `USD];
conv1: .money.convert[usd10; `USD];
.test.assert[conv1[`amount] = 100.0; "Same currency conversion preserves amount"];
.test.assert[conv1[`currency] = `USD; "Same currency conversion preserves currency"];

/ Test 6.2: USD to EUR conversion
conv2: .money.convert[usd10; `EUR];
.test.assert[conv2[`amount] = 85.5; "USD to EUR conversion correct (rate 0.855)"];
.test.assert[conv2[`currency] = `EUR; "Conversion changes currency"];

/ Test 6.3: EUR to USD conversion (inverse rate)
eur3: .money.new[100; `EUR];
conv3: .money.convert[eur3; `USD];
.test.assert[conv3[`amount] = 117.0; "EUR to USD conversion uses inverse rate"];

/ Test 6.4: BTC to USD conversion
btc4: .money.new[1; `BTC];
conv4: .money.convert[btc4; `USD];
.test.assert[conv4[`amount] = 50000.0; "BTC to USD conversion correct"];

/ Test 6.5: USD to BTC conversion (inverse)
usd11: .money.new[50000; `USD];
conv5: .money.convert[usd11; `BTC];
.test.assert[conv5[`amount] = 1.0; "USD to BTC uses inverse rate"];

/ Test 6.6: Missing rate error
.test.assertError[{.money.convert[.money.new[100;`GBP]; `JPY]}; "Missing rate throws error"];

-1 "";

/ ========================================
/ Helper Functions Tests
/ ========================================

-1 "Helper Functions Tests";
-1 "----------------------------------------";

/ Test 7.1: Zero money
zero1: .money.zero[`USD];
.test.assert[zero1[`amount] = 0; "Zero creates 0 amount"];
.test.assert[zero1[`currency] = `USD; "Zero preserves currency"];

/ Test 7.2: isZero check
.test.assert[.money.isZero[zero1]; "isZero recognizes zero"];
.test.assert[not .money.isZero[usd1]; "isZero rejects non-zero"];

/ Test 7.3: Absolute value
neg1: .money.new[100; `USD];
neg2: .money.sub[.money.new[0;`USD]; neg1];  / Create negative via subtraction
abs1: .money.abs[neg2];
.test.assert[abs1[`amount] = 100.0; "Absolute value of negative is positive"];

/ Test 7.4: Negation
pos1: .money.new[100; `USD];
neg3: .money.neg[pos1];
.test.assert[neg3[`amount] = -100.0; "Negation changes sign"];
.test.assert[neg3[`currency] = `USD; "Negation preserves currency"];

-1 "";

/ ========================================
/ NEGATIVE TESTS (Edge Cases and Errors)
/ ========================================

-1 "Negative Tests (Edge Cases)";
-1 "----------------------------------------";

/ Test 8.1: Currency mismatch in add
.test.assertError[{.money.add[.money.new[100;`USD]; .money.new[100;`EUR]]}; "Add rejects currency mismatch"];

/ Test 8.2: Currency mismatch in sub
.test.assertError[{.money.sub[.money.new[100;`BTC]; .money.new[100;`ETH]]}; "Sub rejects currency mismatch"];

/ Test 8.3: Negative amount creation
.test.assertError[{.money.new[-100;`USD]}; "Constructor rejects negative amount"];

/ Test 8.4: Division by zero (float)
usd_test: .money.new[100; `USD];
.test.assertError[{.money.div[usd_test; 0f]}; "Division rejects float zero"];

/ Test 8.5: Division by zero (long)
.test.assertError[{.money.div[usd_test; 0]}; "Division rejects long zero"];

/ Test 8.6: Invalid currency in new
.test.assertError[{.money.new[100; `INVALID_CURRENCY]}; "Constructor rejects invalid currency"];

/ Test 8.7: Missing forex rate
btc_invalid: .money.new[1; `BTC];
.test.assertError[{.money.convert[btc_invalid; `JPY]}; "Convert fails when forex rate not found"];

/ Test 8.8: Null multiplier
.test.assertError[{.money.mul[usd_test; ()]}; "Multiply rejects null scalar"];

/ Test 8.9: Null divisor
.test.assertError[{.money.div[usd_test; ()]}; "Divide rejects null scalar"];

/ Test 8.10: Invalid type for Money operations
.test.assertError[{.money.add[100; 50]}; "Add requires Money dicts"];
.test.assertError[{.money.sub[`symbol; `other]}; "Sub requires Money dicts"];

-1 "";
-1 "========================================";
-1 "  All Tests Passed!";
-1 "========================================";
-1 "";

/ Exit successfully
exit 0;
