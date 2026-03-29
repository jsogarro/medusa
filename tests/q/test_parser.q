/ Test configuration parser
\l ../../src/q/config/parser.q

/ Simple test framework
assert:{[condition;msg]
  if[not condition; -1 "FAIL: ",msg; exit 1];
  -1 "PASS: ",msg
 };

/ Test 1: Simple conf parsing
testSimpleConf:{
  conf:("[strategy]";"tick_sleep=100";"max_notional=5000");
  `:test.conf 0: conf;
  result:.conf.parser.parseFile["test.conf"];

  / Assertions
  assert[`strategy in key result; "Strategy section exists"];
  assert[`tick_sleep in key result[`strategy]; "tick_sleep key exists"];
  assert["100"~result[`strategy][`tick_sleep]; "tick_sleep value correct"];
  assert["5000"~result[`strategy][`max_notional]; "max_notional value correct"];

  hdel `test.conf;
  -1 "✓ testSimpleConf passed";
 };

/ Test 2: Comments are ignored
testComments:{
  conf:("# Comment";"[strategy]";"# Another comment";"tick_sleep=100");
  `:test.conf 0: conf;
  result:.conf.parser.parseFile["test.conf"];

  assert[1=count result[`strategy]; "Only one key parsed"];
  assert[`tick_sleep in key result[`strategy]; "tick_sleep key exists"];

  hdel `test.conf;
  -1 "✓ testComments passed";
 };

/ Test 3: Multiple sections
testMultipleSections:{
  conf:("[strategy]";"tick_sleep=100";"[exchange]";"name=kraken";"api_url=https://api.kraken.com");
  `:test.conf 0: conf;
  result:.conf.parser.parseFile["test.conf"];

  assert[`strategy in key result; "Strategy section exists"];
  assert[`exchange in key result; "Exchange section exists"];
  assert["100"~result[`strategy][`tick_sleep]; "tick_sleep value correct"];
  assert["kraken"~result[`exchange][`name]; "exchange name correct"];
  assert["https://api.kraken.com"~result[`exchange][`api_url]; "api_url correct"];

  hdel `test.conf;
  -1 "✓ testMultipleSections passed";
 };

/ Test 4: Empty lines
testEmptyLines:{
  conf:("[strategy]";"";"tick_sleep=100";"";"[exchange]";"";"name=kraken");
  `:test.conf 0: conf;
  result:.conf.parser.parseFile["test.conf"];

  assert[`strategy in key result; "Strategy section exists"];
  assert[`exchange in key result; "Exchange section exists"];

  hdel `test.conf;
  -1 "✓ testEmptyLines passed";
 };

/ Test 5: Whitespace handling
testWhitespace:{
  conf:("[strategy]";"  tick_sleep = 100  ";"   max_notional=5000");
  `:test.conf 0: conf;
  result:.conf.parser.parseFile["test.conf"];

  assert[`tick_sleep in key result[`strategy]; "tick_sleep key exists (whitespace trimmed)"];
  assert["100"~result[`strategy][`tick_sleep]; "tick_sleep value correct (whitespace trimmed)"];

  hdel `test.conf;
  -1 "✓ testWhitespace passed";
 };

/ Run all tests
-1 "";
-1 "Running parser tests...";
-1 "";

testSimpleConf[];
testComments[];
testMultipleSections[];
testEmptyLines[];
testWhitespace[];

-1 "";
-1 "All parser tests passed!";
-1 "";

exit 0
