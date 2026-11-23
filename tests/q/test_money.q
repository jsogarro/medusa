/ Tests for .money namespace (lib/money.q)
/ Fixed-precision money arithmetic and currency operations

/ Load test framework
\l tests/q/test_framework.q

/ Load money module
\l src/q/lib/money.q

/ ========================================
/ Currency validation tests
/ ========================================

test_validCurrency_valid:{
  .test.assert["BTC is valid currency"; .money.validCurrency[`BTC]];
  .test.assert["USD is valid currency"; .money.validCurrency[`USD]];
  .test.assert["ETH is valid currency"; .money.validCurrency[`ETH]];
 }

test_validCurrency_invalid:{
  .test.assert["XYZ is invalid"; not .money.validCurrency[`XYZ]];
  .test.assert["FOO is invalid"; not .money.validCurrency[`FOO]];
 }

test_precision_lookup:{
  .test.assertEqual["BTC precision is 8"; 8; .money.precision[`BTC]];
  .test.assertEqual["USD precision is 2"; 2; .money.precision[`USD]];
  .test.assertEqual["ETH precision is 18"; 18; .money.precision[`ETH]];
  .test.assertEqual["JPY precision is 0"; 0; .money.precision[`JPY]];
 }

test_precision_invalid_currency:{
  .test.assertError["Invalid currency throws"; {.money.precision[`XYZ]}];
 }

/ ========================================
/ Money creation tests
/ ========================================

test_new_basic:{
  m:.money.new[100.0; `USD];
  .test.assert["isMoney returns true"; .money.isMoney[m]];
  .test.assertEqual["amount is 100.0"; 100.0; m`amount];
  .test.assertEqual["currency is USD"; `USD; m`currency];
 }

test_new_rounding:{
  m:.money.new[100.555; `USD];
  .test.assertEqual["Rounded to 2 decimals"; 100.56; m`amount];
 }

test_new_string_input:{
  m:.money.new["123.45"; `USD];
  .test.assertEqual["Parsed from string"; 123.45; m`amount];
 }

test_new_invalid_currency:{
  .test.assertError["Invalid currency throws"; {.money.new[100.0; `XYZ]}];
 }

test_new_negative_amount:{
  .test.assertError["Negative amount throws"; {.money.new[-10.0; `USD]}];
 }

test_zero_money:{
  z:.money.zero[`BTC];
  .test.assert["Zero is Money"; .money.isMoney[z]];
  .test.assertEqual["Zero amount is 0"; 0.0; z`amount];
  .test.assert["Zero check works"; .money.isZero[z]];
 }

/ ========================================
/ Arithmetic tests
/ ========================================

test_add_basic:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[50.0; `USD];
  result:.money.add[m1; m2];
  .test.assertEqual["Addition result"; 150.0; result`amount];
  .test.assertEqual["Currency preserved"; `USD; result`currency];
 }

test_add_currency_mismatch:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[0.001; `BTC];
  .test.assertError["Currency mismatch throws"; {.money.add[m1; m2]}];
 }

test_sub_basic:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[30.0; `USD];
  result:.money.sub[m1; m2];
  .test.assertEqual["Subtraction result"; 70.0; result`amount];
 }

test_sub_allows_negative:{
  m1:.money.new[50.0; `USD];
  m2:.money.new[100.0; `USD];
  result:.money.sub[m1; m2];
  .test.assertEqual["Negative result allowed"; -50.0; result`amount];
 }

test_mul_basic:{
  m:.money.new[100.0; `USD];
  result:.money.mul[m; 2.5];
  .test.assertEqual["Multiplication result"; 250.0; result`amount];
 }

test_mul_int_scalar:{
  m:.money.new[100.0; `USD];
  result:.money.mul[m; 3];
  .test.assertEqual["Int multiplier works"; 300.0; result`amount];
 }

test_div_basic:{
  m:.money.new[100.0; `USD];
  result:.money.div[m; 4];
  .test.assertEqual["Division result"; 25.0; result`amount];
 }

test_div_zero:{
  m:.money.new[100.0; `USD];
  .test.assertError["Division by zero throws"; {.money.div[m; 0]}];
  .test.assertError["Division by 0.0 throws"; {.money.div[m; 0.0]}];
 }

/ ========================================
/ Comparison tests
/ ========================================

test_eq_true:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[100.0; `USD];
  .test.assert["Equal moneys"; .money.eq[m1; m2]];
 }

test_eq_false_amount:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[101.0; `USD];
  .test.assert["Different amounts not equal"; not .money.eq[m1; m2]];
 }

test_eq_false_currency:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[100.0; `EUR];
  .test.assert["Different currencies not equal"; not .money.eq[m1; m2]];
 }

test_lt_basic:{
  m1:.money.new[50.0; `USD];
  m2:.money.new[100.0; `USD];
  .test.assert["50 < 100"; .money.lt[m1; m2]];
  .test.assert["100 not < 50"; not .money.lt[m2; m1]];
 }

test_gt_basic:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[50.0; `USD];
  .test.assert["100 > 50"; .money.gt[m1; m2]];
  .test.assert["50 not > 100"; not .money.gt[m2; m1]];
 }

test_lte_basic:{
  m1:.money.new[50.0; `USD];
  m2:.money.new[100.0; `USD];
  m3:.money.new[50.0; `USD];
  .test.assert["50 <= 100"; .money.lte[m1; m2]];
  .test.assert["50 <= 50"; .money.lte[m1; m3]];
 }

test_gte_basic:{
  m1:.money.new[100.0; `USD];
  m2:.money.new[50.0; `USD];
  m3:.money.new[100.0; `USD];
  .test.assert["100 >= 50"; .money.gte[m1; m2]];
  .test.assert["100 >= 100"; .money.gte[m1; m3]];
 }

/ ========================================
/ Conversion tests
/ ========================================

test_convert_same_currency:{
  m:.money.new[100.0; `USD];
  result:.money.convert[m; `USD];
  .test.assertEqual["Same currency 1:1"; 100.0; result`amount];
  .test.assertEqual["Currency preserved"; `USD; result`currency];
 }

test_convert_usd_to_eur:{
  m:.money.new[100.0; `USD];
  result:.money.convert[m; `EUR];
  .test.assertEqual["Converted currency"; `EUR; result`currency];
  / Rate is 0.855, so 100 USD = 85.5 EUR
  .test.assertNear["Converted amount"; 85.5; result`amount; 0.1];
 }

test_convert_btc_to_usd:{
  m:.money.new[1.0; `BTC];
  result:.money.convert[m; `USD];
  .test.assertEqual["Converted currency"; `USD; result`currency];
  / Rate is 50000, so 1 BTC = 50000 USD
  .test.assertEqual["Converted amount"; 50000.0; result`amount];
 }

test_convert_unknown_pair:{
  m:.money.new[100.0; `GBP];
  .test.assertError["Unknown rate throws"; {.money.convert[m; `JPY]}];
 }

/ ========================================
/ Helper function tests
/ ========================================

test_abs_positive:{
  m:.money.new[100.0; `USD];
  result:.money.abs[m];
  .test.assertEqual["Abs of positive"; 100.0; result`amount];
 }

test_abs_negative:{
  m1:.money.new[50.0; `USD];
  m2:.money.new[100.0; `USD];
  negMoney:.money.sub[m1; m2];
  result:.money.abs[negMoney];
  .test.assertEqual["Abs of negative"; 50.0; result`amount];
 }

test_neg_basic:{
  m:.money.new[100.0; `USD];
  result:.money.neg[m];
  .test.assertEqual["Negation"; -100.0; result`amount];
 }

test_fmt_usd:{
  m:.money.new[123.45; `USD];
  fmt:.money.fmt[m];
  .test.assert["USD formatted with prefix"; fmt like "$*"];
 }

test_fmt_btc:{
  m:.money.new[0.00500000; `BTC];
  fmt:.money.fmt[m];
  .test.assert["BTC formatted with suffix"; fmt like "* BTC"];
 }

-1 "Money tests loaded";
