/ Integration tests for full configuration system
\l ../../src/q/config/config.q

/ Simple test framework
assert:{[condition;msg]
  if[not condition; -1 "FAIL: ",msg; exit 1];
  -1 "PASS: ",msg
 };

/ Test 1: Full initialization
testInit:{
  / Define defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";
  defaults[`strategy][`max_notional]:"5000";
  defaults[`exchange]:()!();
  defaults[`exchange][`name]:"kraken";

  / Create test config file
  conf:("[strategy]";"tick_sleep=50");
  `:test_init.conf 0: conf;

  / Initialize
  .conf.init["test_init.conf"; defaults; ()];

  / Assertions
  assert["50"~.conf.get[`strategy; `tick_sleep; "100"]; "Config value from file"];
  assert["5000"~.conf.get[`strategy; `max_notional; "0"]; "Config value from defaults"];
  assert["kraken"~.conf.get[`exchange; `name; ""]; "Config value from defaults"];

  / Cleanup
  hdel `test_init.conf;

  -1 "✓ testInit passed";
 };

/ Test 2: getTyped with type coercion
testGetTyped:{
  / Define defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";
  defaults[`strategy][`enabled]:"true";
  defaults[`strategy][`symbols]:"AAPL,GOOG,MSFT";

  / Initialize
  .conf.init[(); defaults; ()];

  / Test type coercion
  assert[100~.conf.getTyped[`strategy; `tick_sleep; `int; 0]; "Integer coercion"];
  assert[1b~.conf.getTyped[`strategy; `enabled; `bool; 0b]; "Boolean coercion"];
  assert[(`AAPL`GOOG`MSFT)~.conf.getTyped[`strategy; `symbols; `list; ()]; "List coercion"];

  -1 "✓ testGetTyped passed";
 };

/ Test 3: set (runtime override)
testSet:{
  / Define defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";

  / Initialize
  .conf.init[(); defaults; ()];

  / Set new value
  .conf.set[`strategy; `tick_sleep; "25"];

  / Verify
  assert["25"~.conf.get[`strategy; `tick_sleep; "0"]; "Runtime override works"];

  -1 "✓ testSet passed";
 };

/ Test 4: get with default
testGetDefault:{
  / Define defaults (empty)
  defaults:()!();

  / Initialize
  .conf.init[(); defaults; ()];

  / Get nonexistent key with default
  result:.conf.get[`strategy; `tick_sleep; "999"];
  assert["999"~result; "Default value returned for nonexistent key"];

  -1 "✓ testGetDefault passed";
 };

/ Test 5: initWithReload
testReload:{
  / Define defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";

  / Create config file
  conf:("[strategy]";"tick_sleep=50");
  `:test_reload.conf 0: conf;

  / Initialize with reload support
  .conf.initWithReload["test_reload.conf"; defaults; ()];

  / Verify initial value
  assert["50"~.conf.get[`strategy; `tick_sleep; "0"]; "Initial value from file"];

  / Modify config file
  conf2:("[strategy]";"tick_sleep=25");
  `:test_reload.conf 0: conf2;

  / Reload
  .conf.reload[];

  / Verify reloaded value
  assert["25"~.conf.get[`strategy; `tick_sleep; "0"]; "Reloaded value from file"];

  / Cleanup
  hdel `test_reload.conf;

  -1 "✓ testReload passed";
 };

/ Run all tests
-1 "";
-1 "Running config integration tests...";
-1 "";

testInit[];
testGetTyped[];
testSet[];
testGetDefault[];
testReload[];

-1 "";
-1 "All config integration tests passed!";
-1 "";

exit 0
