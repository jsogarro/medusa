/ ============================================================================
/ test_greeks_limits.q - Greeks Limits Risk Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests:
/   - Greeks limits initialization
/   - Pre-trade Greeks limit checks
/   - Post-fill Greeks exposure updates
/   - Limit breach detection
/ ============================================================================

/ Load dependencies
\l src/q/schema/options.q
\l src/q/risk/schema.q
\l src/q/risk/greeksLimits.q

\d .test

// ============================================================================
// TEST HELPERS
// ============================================================================

passCount:0;
failCount:0;

assert:{[condition;msg]
  $[condition;
    [passCount+::1; -1 "  [PASS] ",msg];
    [failCount+::1; -1 "  [FAIL] ",msg]
  ];
 };

summary:{[]
  -1 "";
  -1 "Test Summary:";
  -1 "  Passed: ",string passCount;
  -1 "  Failed: ",string failCount;
  -1 "  Total:  ",string passCount + failCount;
  $[failCount=0; -1 "  Result: ALL TESTS PASSED"; -1 "  Result: SOME TESTS FAILED"];
 };

// ============================================================================
// SETUP TEST DATA
// ============================================================================

setupTestData:{[]
  -1 "Setting up test data...";

  / Clear tables
  delete from `.schema.optionContract;
  delete from `.schema.optionQuote;
  delete from `.risk.greeksLimits;
  delete from `.risk.greeksEvents;

  / Insert test contract
  `.schema.optionContract upsert (
    `AAPL250117C00150000;
    `AAPL;
    2025.01.17;
    150000000j;
    `call;
    `american;
    100j;
    `active
  );

  / Insert test quote with Greeks
  `.schema.optionQuote insert (
    .z.p;
    `AAPL250117C00150000;
    5500000j;  / bidPrice
    5600000j;  / askPrice
    100j;      / bidSize
    150j;      / askSize
    0.25;      / impliedVol
    0.55;      / delta
    0.05;      / gamma
    -0.03;     / theta
    0.15;      / vega
    0.02;      / rho
    150500000j / underlyingPrice
  );

  / Initialize Greeks limits for test strategy
  .risk.initGreeksLimits[`testStrategy;1000.0;100.0;500.0;5000.0];

  -1 "Test data setup complete";
 };

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

testInitialization:{[]
  -1 "Testing Greeks limits initialization...";

  / Check limits table has entry
  assert[`testStrategy in key .risk.greeksLimits; "Test strategy initialized"];

  / Check limits values
  limits:.risk.greeksLimits[`testStrategy];
  assert[1000.0 = limits`maxDelta; "Max delta set correctly"];
  assert[100.0 = limits`maxGamma; "Max gamma set correctly"];
  assert[500.0 = limits`maxTheta; "Max theta set correctly"];
  assert[5000.0 = limits`maxVega; "Max vega set correctly"];

  / Check initial exposure is zero
  assert[0.0 = limits`currentDelta; "Initial delta exposure zero"];
  assert[0.0 = limits`currentGamma; "Initial gamma exposure zero"];
  assert[0.0 = limits`currentTheta; "Initial theta exposure zero"];
  assert[0.0 = limits`currentVega; "Initial vega exposure zero"];
 };

// ============================================================================
// PRE-TRADE CHECK TESTS
// ============================================================================

testPreTradeCheck:{[]
  -1 "Testing pre-trade Greeks limit checks...";

  / Test 1: Check small position (should pass)
  result:.risk.checkGreeksLimit[`testStrategy;`AAPL250117C00150000;`buy;1j];
  assert[result 0; "Small position passes Greeks check"];

  / Test 2: Check large position that breaches delta limit
  / Delta per contract = 0.55 * 100 = 55
  / Need > 1000 / 55 = 18.18 contracts to breach
  result:.risk.checkGreeksLimit[`testStrategy;`AAPL250117C00150000;`buy;20j];
  assert[not result 0; "Large position breaches delta limit"];
  assert[`deltaLimitExceeded = result 1; "Correct breach reason"];

  / Test 3: Check unconfigured strategy
  result:.risk.checkGreeksLimit[`unconfiguredStrategy;`AAPL250117C00150000;`buy;1j];
  assert[not result 0; "Unconfigured strategy rejected"];
  assert[`noGreeksLimitConfigured = result 1; "Correct rejection reason"];

  / Test 4: Check missing quote
  result:.risk.checkGreeksLimit[`testStrategy;`NONEXISTENT;`buy;1j];
  assert[not result 0; "Missing quote rejected"];
  assert[`noQuoteAvailable = result 1; "Correct rejection reason"];
 };

// ============================================================================
// POST-FILL UPDATE TESTS
// ============================================================================

testPostFillUpdate:{[]
  -1 "Testing post-fill Greeks exposure updates...";

  / Reset exposure
  update currentDelta:0.0, currentGamma:0.0, currentTheta:0.0, currentVega:0.0
    from `.risk.greeksLimits where strategy=`testStrategy;

  / Update exposure after buying 5 contracts
  .risk.updateGreeksExposure[`testStrategy;`AAPL250117C00150000;`buy;5j];

  / Check updated exposure
  / Delta: 0.55 * 5 * 100 = 275
  / Gamma: 0.05 * 5 * 100 = 25
  / Theta: -0.03 * 5 * 100 = -15
  / Vega: 0.15 * 5 * 100 = 75
  limits:.risk.greeksLimits[`testStrategy];
  assert[275.0 = limits`currentDelta; "Delta exposure updated correctly"];
  assert[25.0 = limits`currentGamma; "Gamma exposure updated correctly"];
  assert[-15.0 = limits`currentTheta; "Theta exposure updated correctly"];
  assert[75.0 = limits`currentVega; "Vega exposure updated correctly"];

  / Test selling (negative delta)
  .risk.updateGreeksExposure[`testStrategy;`AAPL250117C00150000;`sell;2j];
  limits:.risk.greeksLimits[`testStrategy];

  / After selling 2: net = 5 - 2 = 3 contracts
  / Delta: 0.55 * 3 * 100 = 165
  assert[165.0 = limits`currentDelta; "Delta reduced after sell"];
 };

// ============================================================================
// EVENT LOGGING TESTS
// ============================================================================

testEventLogging:{[]
  -1 "Testing Greeks event logging...";

  / Clear events
  delete from `.risk.greeksEvents;

  / Update exposure
  .risk.updateGreeksExposure[`testStrategy;`AAPL250117C00150000;`buy;1j];

  / Check event logged
  events:select from .risk.greeksEvents where strategy=`testStrategy;
  assert[1 = count events; "Event logged"];
  assert[`AAPL250117C00150000 = first events`contractId; "Contract ID logged"];
  assert[`buy = first events`side; "Side logged"];
  assert[1j = first events`qty; "Quantity logged"];
  assert[`allowed = first events`action; "Action logged"];
 };

// ============================================================================
// RUN ALL TESTS
// ============================================================================

runAllTests:{[]
  -1 "=======================================================";
  -1 "Greeks Limits Risk Tests";
  -1 "=======================================================";

  passCount::0;
  failCount::0;

  setupTestData[];
  testInitialization[];
  testPreTradeCheck[];
  testPostFillUpdate[];
  testEventLogging[];

  summary[];
 };

\d .

/ Run tests
.test.runAllTests[];

/ Exit with appropriate code
exit $[.test.failCount = 0; 0; 1];
