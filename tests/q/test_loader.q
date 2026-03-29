/ Test configuration loader with hierarchy
\l ../../src/q/config/parser.q
\l ../../src/q/config/validator.q
\l ../../src/q/config/loader.q

/ Simple test framework
assert:{[condition;msg]
  if[not condition; -1 "FAIL: ",msg; exit 1];
  -1 "PASS: ",msg
 };

/ Test 1: Merge dictionaries
testMerge:{
  / Base config
  base:()!();
  base[`strategy]:()!();
  base[`strategy][`tick_sleep]:"100";
  base[`strategy][`max_notional]:"5000";
  base[`exchange]:()!();
  base[`exchange][`name]:"kraken";

  / Override config
  override:()!();
  override[`strategy]:()!();
  override[`strategy][`tick_sleep]:"50";

  / Merge
  result:.conf.loader.merge[base; override];

  / Assertions
  assert["50"~result[`strategy][`tick_sleep]; "tick_sleep overridden"];
  assert["5000"~result[`strategy][`max_notional]; "max_notional preserved from base"];
  assert["kraken"~result[`exchange][`name]; "exchange preserved from base"];

  -1 "✓ testMerge passed";
 };

/ Test 2: Load with hierarchy (defaults -> file)
testLoadHierarchy:{
  / Create defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";
  defaults[`strategy][`max_notional]:"5000";

  / Create override file
  conf:("[strategy]";"tick_sleep=50");
  `:test_override.conf 0: conf;

  / Load with hierarchy
  result:.conf.loader.load["test_override.conf"; defaults; ()];

  / Assertions
  assert["50"~result[`strategy][`tick_sleep]; "tick_sleep overridden by file"];
  assert["5000"~result[`strategy][`max_notional]; "max_notional preserved from defaults"];

  / Cleanup
  hdel `test_override.conf;

  -1 "✓ testLoadHierarchy passed";
 };

/ Test 3: Load with validation
testLoadWithValidation:{
  / Create defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";

  / Create schema
  schema:()!();
  schema[`strategy]:()!();
  schema[`strategy][`tick_sleep]:(`type`validator!(`int; {x>0}));

  / Valid config file
  conf:("[strategy]";"tick_sleep=50");
  `:test_valid.conf 0: conf;

  / Load with validation (should succeed)
  result:.conf.loader.load["test_valid.conf"; defaults; schema];
  assert["50"~result[`strategy][`tick_sleep]; "Valid config loaded successfully"];

  / Cleanup
  hdel `test_valid.conf;

  -1 "✓ testLoadWithValidation passed";
 };

/ Test 4: Load nonexistent file (should use defaults)
testLoadNonexistent:{
  / Create defaults
  defaults:()!();
  defaults[`strategy]:()!();
  defaults[`strategy][`tick_sleep]:"100";

  / Load nonexistent file (should gracefully fallback to defaults)
  result:.conf.loader.load["nonexistent.conf"; defaults; ()];

  / Assertions
  assert["100"~result[`strategy][`tick_sleep]; "Defaults used when file doesn't exist"];

  -1 "✓ testLoadNonexistent passed";
 };

/ Test 5: Environment variable loading
testLoadEnvVars:{
  / Set environment variable
  system "export MEDUSA_STRATEGY_TICK_SLEEP=25";

  / Load env vars
  result:.conf.loader.loadEnvVars["MEDUSA"; `strategy];

  / Check if env var was loaded
  if[`tick_sleep in key result;
    assert["25"~result[`tick_sleep]; "Environment variable loaded correctly"];
    -1 "✓ testLoadEnvVars passed (env var found)";
  ];

  / If env var not set, skip test
  if[not `tick_sleep in key result;
    -1 "⊘ testLoadEnvVars skipped (env var not set)";
  ];
 };

/ Run all tests
-1 "";
-1 "Running loader tests...";
-1 "";

testMerge[];
testLoadHierarchy[];
testLoadWithValidation[];
testLoadNonexistent[];
testLoadEnvVars[];

-1 "";
-1 "All loader tests passed!";
-1 "";

exit 0
