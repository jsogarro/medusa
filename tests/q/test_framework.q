/ Lightweight test framework for Medusa q tests
/ Provides assertion helpers and test runner

\d .test

/ Test state
passed:0
failed:0
errors:()

/ Assert helpers
assert:{[msg;cond]
  $[cond;
    [passed+:1; -1 "  PASS: ",msg];
    [failed+:1; errors,:enlist msg; -1 "  FAIL: ",msg]
  ]
 }

assertEqual:{[msg;expected;actual]
  if[not expected~actual;
    -1 "    Expected: ",(-3!)expected;
    -1 "    Actual:   ",(-3!)actual
  ];
  assert[msg; expected~actual]
 }

assertNear:{[msg;expected;actual;tol]
  delta:abs expected - actual;
  if[not delta <= tol;
    -1 "    Expected: ",string expected;
    -1 "    Actual:   ",string actual;
    -1 "    Delta:    ",string delta;
    -1 "    Tolerance:",string tol
  ];
  assert[msg; delta <= tol]
 }

/ Assert error occurs when evaluating expression
assertError:{[msg;expr]
  result:@[{x[];0b}; expr; {1b}];
  assert[msg; result]
 }

assertType:{[msg;expected;actual]
  assert[msg; expected = type actual]
 }

/ Run all test functions in current namespace
run:{[ns]
  passed::0; failed::0; errors::();
  funcs:system "f ";
  tests:funcs where funcs like "test_*";
  -1 "\n=== Running ",string[count tests]," tests ===\n";

  {
    -1 "\n[",string[x],"]";
    @[value x; ::; {-1 "  ERROR: ",x; .test.failed+:1; .test.errors,:enlist x}]
  } each tests;

  -1 "\n=== Results: ",string[passed]," passed, ",string[failed]," failed ===";
  if[0 < count errors;
    -1 "Failed tests:";
    {-1 "  - ",x} each errors
  ];

  failed
 }

\d .

/ Export
-1 "Test framework loaded: .test namespace";
-1 "Usage: .test.run[`.] to run all tests in current namespace";
