/ Test configuration validator and type coercion
\l ../../src/q/config/validator.q

/ Simple test framework
assert:{[condition;msg]
  if[not condition; -1 "FAIL: ",msg; exit 1];
  -1 "PASS: ",msg
 };

/ Test 1: Integer coercion
testIntCoercion:{
  assert[42~.conf.validator.coerceInt["42"]; "Positive integer"];
  assert[-42~.conf.validator.coerceInt["-42"]; "Negative integer"];
  assert[0~.conf.validator.coerceInt["0"]; "Zero"];
  assert[null .conf.validator.coerceInt["abc"]; "Invalid integer returns null"];

  -1 "✓ testIntCoercion passed";
 };

/ Test 2: Float coercion
testFloatCoercion:{
  assert[3.14~.conf.validator.coerceFloat["3.14"]; "Positive float"];
  assert[-3.14~.conf.validator.coerceFloat["-3.14"]; "Negative float"];
  assert[0.0~.conf.validator.coerceFloat["0.0"]; "Zero float"];
  assert[null .conf.validator.coerceFloat["abc"]; "Invalid float returns null"];

  -1 "✓ testFloatCoercion passed";
 };

/ Test 3: Symbol coercion
testSymbolCoercion:{
  assert[`kraken~.conf.validator.coerceSymbol["kraken"]; "String to symbol"];
  assert[`test123~.conf.validator.coerceSymbol["test123"]; "Alphanumeric symbol"];

  -1 "✓ testSymbolCoercion passed";
 };

/ Test 4: Boolean coercion
testBoolCoercion:{
  / True values
  assert[1b~.conf.validator.coerceBool["true"]; "true"];
  assert[1b~.conf.validator.coerceBool["True"]; "True (capitalized)"];
  assert[1b~.conf.validator.coerceBool["TRUE"]; "TRUE (uppercase)"];
  assert[1b~.conf.validator.coerceBool["1"]; "1"];
  assert[1b~.conf.validator.coerceBool["yes"]; "yes"];
  assert[1b~.conf.validator.coerceBool["on"]; "on"];

  / False values
  assert[0b~.conf.validator.coerceBool["false"]; "false"];
  assert[0b~.conf.validator.coerceBool["False"]; "False (capitalized)"];
  assert[0b~.conf.validator.coerceBool["FALSE"]; "FALSE (uppercase)"];
  assert[0b~.conf.validator.coerceBool["0"]; "0"];
  assert[0b~.conf.validator.coerceBool["no"]; "no"];
  assert[0b~.conf.validator.coerceBool["off"]; "off"];

  / Invalid value
  assert[null .conf.validator.coerceBool["maybe"]; "Invalid boolean returns null"];

  -1 "✓ testBoolCoercion passed";
 };

/ Test 5: List coercion
testListCoercion:{
  / Integer list
  assert[(1 2 3)~.conf.validator.coerceList["1,2,3"]; "Integer list"];
  assert[(1 2 3)~.conf.validator.coerceList["[1,2,3]"]; "Integer list with brackets"];

  / Float list
  assert[(1.1 2.2 3.3)~.conf.validator.coerceList["1.1,2.2,3.3"]; "Float list"];

  / Symbol list
  assert[(`AAPL`GOOG`MSFT)~.conf.validator.coerceList["AAPL,GOOG,MSFT"]; "Symbol list"];

  / Empty list
  assert[()~.conf.validator.coerceList[""]; "Empty list"];

  -1 "✓ testListCoercion passed";
 };

/ Test 6: Type-based coercion
testCoerce:{
  assert[42~.conf.validator.coerce[`int; "42"]; "int type"];
  assert[3.14~.conf.validator.coerce[`float; "3.14"]; "float type"];
  assert[`kraken~.conf.validator.coerce[`symbol; "kraken"]; "symbol type"];
  assert[1b~.conf.validator.coerce[`bool; "true"]; "bool type"];
  assert["test"~.conf.validator.coerce[`string; "test"]; "string type"];
  assert[(1 2 3)~.conf.validator.coerce[`list; "1,2,3"]; "list type"];

  -1 "✓ testCoerce passed";
 };

/ Test 7: Validation with schema
testValidate:{
  / Define schema
  schema:()!();
  schema[`tick_sleep]:(`type`validator!(`int; {x>0}));
  schema[`name]:(`type`validator!(`symbol; {not null x}));

  / Valid config
  validConfig:()!();
  validConfig[`tick_sleep]:"100";
  validConfig[`name]:"kraken";

  errors:.conf.validator.validate[schema; validConfig];
  assert[0=count errors; "Valid config has no errors"];

  / Invalid config (missing key)
  invalidConfig:()!();
  invalidConfig[`tick_sleep]:"100";

  errors:.conf.validator.validate[schema; invalidConfig];
  assert[0<count errors; "Invalid config has errors"];
  assert[`missing_keys~first first errors; "Missing key error"];

  -1 "✓ testValidate passed";
 };

/ Run all tests
-1 "";
-1 "Running validator tests...";
-1 "";

testIntCoercion[];
testFloatCoercion[];
testSymbolCoercion[];
testBoolCoercion[];
testListCoercion[];
testCoerce[];
testValidate[];

-1 "";
-1 "All validator tests passed!";
-1 "";

exit 0
