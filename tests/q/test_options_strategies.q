/ ============================================================================
/ test_options_strategies.q - Options Strategy Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests:
/   - Black-Scholes pricing
/   - Greeks calculation
/   - Covered call strategy
/   - Iron condor strategy
/   - Vertical spread strategy
/   - Straddle strategy
/   - Payoff calculation
/ ============================================================================

/ Load dependencies
\l src/q/schema/options.q
\l src/q/strategy/optionsCommon.q
\l src/q/strategy/coveredCall.q
\l src/q/strategy/ironCondor.q
\l src/q/strategy/verticalSpread.q
\l src/q/strategy/straddle.q

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

assertClose:{[actual;expected;tolerance;msg]
  diff:abs[actual - expected];
  $[diff <= tolerance;
    [passCount+::1; -1 "  [PASS] ",msg," (diff: ",string[diff],")"];
    [failCount+::1; -1 "  [FAIL] ",msg," (actual: ",string[actual]," expected: ",string[expected]," diff: ",string[diff],")"]
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
// BLACK-SCHOLES TESTS
// ============================================================================

testBlackScholes:{[]
  -1 "Testing Black-Scholes pricing...";

  / Test ATM call option
  / S=$100, K=$100, r=5%, T=1 year, sigma=20%
  callPrice:.strategy.options.calculateBS[100.0;100.0;0.05;1.0;0.20;`call];
  assertClose[callPrice;10.4506;0.01;"ATM call price ($100 stock, $100 strike, 1yr, 20% vol, 5% rate)"];

  / Test ATM put option (put-call parity)
  putPrice:.strategy.options.calculateBS[100.0;100.0;0.05;1.0;0.20;`put];
  assertClose[putPrice;5.5735;0.01;"ATM put price (put-call parity, 5% rate)"];

  / Test OTM call (should be cheaper)
  otmCall:.strategy.options.calculateBS[100.0;110.0;0.05;1.0;0.20;`call];
  assert[otmCall < callPrice; "OTM call cheaper than ATM call"];

  / Test ITM call (should be more expensive)
  itmCall:.strategy.options.calculateBS[100.0;90.0;0.05;1.0;0.20;`call];
  assert[itmCall > callPrice; "ITM call more expensive than ATM call"];

  / Test near-expiry option (theta decay)
  nearExpiry:.strategy.options.calculateBS[100.0;100.0;0.05;0.1;0.20;`call];
  assert[nearExpiry < callPrice; "Near-expiry option cheaper (theta decay)"];
 };

// ============================================================================
// GREEKS TESTS
// ============================================================================

testGreeks:{[]
  -1 "Testing Greeks calculation...";

  / Calculate Greeks for ATM call
  greeks:.strategy.options.calculateGreeks[100.0;100.0;0.05;1.0;0.20;`call];

  / Delta should match Black-Scholes ATM call with 5% rate
  assertClose[greeks`delta;0.6368;0.01;"ATM call delta with 5% rate"];

  / Gamma should be positive
  assert[greeks[`gamma] > 0.0; "Gamma positive"];

  / Theta should be negative (time decay)
  assert[greeks[`theta] < 0.0; "Theta negative (time decay)"];

  / Vega should be positive (positive vol exposure)
  assert[greeks[`vega] > 0.0; "Vega positive"];

  / Test put Greeks
  putGreeks:.strategy.options.calculateGreeks[100.0;100.0;0.05;1.0;0.20;`put];

  / Put delta should match Black-Scholes ATM put with 5% rate
  assertClose[putGreeks`delta;-0.3632;0.01;"ATM put delta with 5% rate"];

  / Put gamma same as call (always positive)
  assertClose[putGreeks`gamma;greeks`gamma;0.01;"Put gamma same as call gamma"];
 };

// ============================================================================
// COVERED CALL TESTS
// ============================================================================

testCoveredCall:{[]
  -1 "Testing covered call strategy...";

  / Test max profit calculation
  / Buy stock at $100, sell $110 call for $3 premium
  profits:.strategy.coveredCall.calculateMaxProfit[100.0;110.0;3.0;1];

  / Max profit = (Strike - Entry) + Premium = ($110 - $100) + $3 = $13 per share * 100
  assertClose[profits`maxProfit;1300.0;1.0;"Covered call max profit"];

  / Breakeven = Entry - Premium = $100 - $3 = $97
  assertClose[profits`breakeven;97.0;0.1;"Covered call breakeven"];

  / Max loss = (Entry - Premium) * 100 (if stock goes to zero)
  assertClose[profits`maxLoss;9700.0;1.0;"Covered call max loss"];
 };

// ============================================================================
// IRON CONDOR TESTS
// ============================================================================

testIronCondor:{[]
  -1 "Testing iron condor strategy...";

  / Test max profit/loss
  / Net premium = $2.00, wing width = $5
  profits:.strategy.ironCondor.calculateMaxProfit[2.0;5.0];

  / Max profit = Net premium * 100 = $200
  assertClose[profits`maxProfit;200.0;1.0;"Iron condor max profit"];

  / Max loss = (Wing width - Net premium) * 100 = ($5 - $2) * 100 = $300
  assertClose[profits`maxLoss;300.0;1.0;"Iron condor max loss"];

  / Test probability calculation
  / Stock at $100, inner strikes at $95 and $105, 30 days, 25% vol
  prob:.strategy.ironCondor.calculateProbability[100.0;105.0;95.0;30;0.25];

  / Probability should be reasonable (0.3 to 0.7)
  assert[(prob > 0.3) and (prob < 0.7); "Probability of profit reasonable"];
 };

// ============================================================================
// PAYOFF TESTS
// ============================================================================

testPayoff:{[]
  -1 "Testing payoff calculation...";

  / Set up test contract
  .schema.optionContract:([contractId:enlist `TEST250117C00100000]
    underlying:enlist `TEST;
    expiry:enlist 2025.01.17;
    strike:enlist 100000000j;  / $100 strike
    optionType:enlist `call;
    style:enlist `american;
    multiplier:enlist 100j;
    status:enlist `active
  );

  / Test long call payoff
  / Buy call at $5, strike $100, underlying at expiry = $110
  payoff:.strategy.options.calculateLegPayoff[
    `TEST250117C00100000;
    `buy;
    1j;
    5000000j;  / $5 entry price
    110.0      / $110 underlying at expiry
  ];

  / Payoff = (Intrinsic - Premium) * 100 = ($10 - $5) * 100 = $500
  assertClose[payoff;500.0;1.0;"Long call payoff"];

  / Test short call payoff
  / Sell call at $5, strike $100, underlying at expiry = $110
  shortPayoff:.strategy.options.calculateLegPayoff[
    `TEST250117C00100000;
    `sell;
    1j;
    5000000j;
    110.0
  ];

  / Payoff = (Premium - Intrinsic) * 100 = ($5 - $10) * 100 = -$500
  assertClose[shortPayoff;-500.0;1.0;"Short call payoff (loss)"];

  / Test OTM expiry (worthless)
  / Buy call at $5, strike $100, underlying at expiry = $95 (OTM)
  otmPayoff:.strategy.options.calculateLegPayoff[
    `TEST250117C00100000;
    `buy;
    1j;
    5000000j;
    95.0
  ];

  / Payoff = (0 - Premium) * 100 = -$500 (lose premium)
  assertClose[otmPayoff;-500.0;1.0;"OTM call expires worthless (max loss)"];
 };

// ============================================================================
// MARKET SESSION TESTS
// ============================================================================

testMarketSession:{[]
  -1 "Testing market session detection...";

  / Test Asia session (23:00 UTC)
  asiaTime:2025.01.17D23:30:00.000000000;
  assert[`asia = .strategy.options.getSession[asiaTime]; "Asia session detected"];

  / Test Europe session (10:00 UTC)
  europeTime:2025.01.17D10:00:00.000000000;
  assert[`europe = .strategy.options.getSession[europeTime]; "Europe session detected"];

  / Test US session (15:00 UTC)
  usTime:2025.01.17D15:00:00.000000000;
  assert[`us = .strategy.options.getSession[usTime]; "US session detected"];

  / Test closed session (22:00 UTC)
  closedTime:2025.01.17D22:00:00.000000000;
  assert[`closed = .strategy.options.getSession[closedTime]; "Closed session detected"];
 };

// ============================================================================
// RUN ALL TESTS
// ============================================================================

runAllTests:{[]
  -1 "=======================================================";
  -1 "Options Strategy Tests";
  -1 "=======================================================";

  passCount::0;
  failCount::0;

  testBlackScholes[];
  testGreeks[];
  testCoveredCall[];
  testIronCondor[];
  testPayoff[];
  testMarketSession[];

  summary[];
 };

\d .

/ Run tests
.test.runAllTests[];

/ Exit with appropriate code
exit $[.test.failCount = 0; 0; 1];
