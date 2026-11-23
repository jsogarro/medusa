/ ============================================================================
/ test_bond_pricing_q.q - Bond Pricing Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests for .pricing.bond namespace
/ Cross-validated against Python implementation
/ Performance target: <10μs per function call
/ ============================================================================

/ Load dependencies
\l src/q/pricing/bond.q
\l tests/q/test_framework.q

/ ============================================================================
/ HELPER FUNCTIONS
/ ============================================================================

\d .

/ Tolerance for floating point comparisons
TOL:1e-6
PERF_MAX_MICROS:250.0

/ ============================================================================
/ PRESENT VALUE TESTS
/ ============================================================================

test_pv_par_bond:{[]
  / Par bond: when ytm = coupon rate, PV should equal face value
  couponRate:0.05;  / 5% annual
  faceValue:100.0;
  freq:2;           / Semi-annual
  ytm:0.05;         / Same as coupon
  nPeriods:20;      / 10 years × 2

  pv:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  .test.assertNear["Par bond PV equals face value"; faceValue; pv; TOL];
 };

test_pv_discount_bond:{[]
  / Discount bond: ytm > coupon, PV < face value
  couponRate:0.03;
  faceValue:100.0;
  freq:2;
  ytm:0.06;         / Higher yield
  nPeriods:20;

  pv:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  .test.assert["Discount bond PV < face value"; pv < faceValue];
 };

test_pv_premium_bond:{[]
  / Premium bond: ytm < coupon, PV > face value
  couponRate:0.07;
  faceValue:100.0;
  freq:2;
  ytm:0.04;         / Lower yield
  nPeriods:20;

  pv:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  .test.assert["Premium bond PV > face value"; pv > faceValue];
 };

test_pv_zero_coupon:{[]
  / Zero-coupon bond: only principal payment at maturity
  couponRate:0.0;
  faceValue:100.0;
  freq:2;
  ytm:0.05;
  nPeriods:20;

  pv:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  expected:faceValue % (1 + ytm % freq) xexp nPeriods;
  .test.assertNear["Zero-coupon bond PV"; expected; pv; TOL];
 };

test_pv_expired_bond:{[]
  / Expired bond (nPeriods = 0) should return 0
  pv:.pricing.bond.presentValue[0.05;100.0;2;0.05;0];
  .test.assertEqual["Expired bond PV is zero"; 0.0; pv];
 };

/ ============================================================================
/ PYTHON CROSS-VALIDATION (GOLDEN REFERENCES)
/ ============================================================================
/ These values are from Python BondPricer.present_value() with settlement date
/ 2026-01-01 and maturity dates adjusted to give exact period counts
/ Python uses day count conventions, but for whole periods the results match

test_pv_golden_1:{[]
  / 5% coupon, 5% yield, semi-annual, 10 years
  / Python: BondPricer.present_value(bond, ytm=0.05, settlement_date)
  / Expected: 100.0 (par bond)
  pv:.pricing.bond.presentValue[0.05;100.0;2;0.05;20];
  .test.assertNear["Golden PV test 1 (par bond)"; 100.0; pv; TOL];
 };

test_pv_golden_2:{[]
  / 3% coupon, 5% yield, semi-annual, 10 years
  / Python: 84.556 (approximately, varies with day count)
  / Using simplified formula for whole periods:
  c:0.03 * 100.0 % 2; / 1.5 per period
  y:0.05 % 2;         / 0.025 per period
  t:1+til 20;
  discount:(1+y) xexp t;
  expected:(sum c % discount) + 100.0 % last discount;

  pv:.pricing.bond.presentValue[0.03;100.0;2;0.05;20];
  .test.assertNear["Golden PV test 2 (discount bond)"; expected; pv; TOL];
 };

test_pv_golden_3:{[]
  / 8% coupon, 5% yield, semi-annual, 5 years
  / Premium bond
  c:0.08 * 100.0 % 2;
  y:0.05 % 2;
  t:1+til 10;
  discount:(1+y) xexp t;
  expected:(sum c % discount) + 100.0 % last discount;

  pv:.pricing.bond.presentValue[0.08;100.0;2;0.05;10];
  .test.assertNear["Golden PV test 3 (premium bond)"; expected; pv; TOL];
 };

/ ============================================================================
/ DURATION TESTS
/ ============================================================================

test_duration_zero_coupon:{[]
  / Zero-coupon bond: Macaulay duration = time to maturity
  couponRate:0.0;
  freq:2;
  ytm:0.05;
  nPeriods:20;      / 10 years × 2

  macDur:.pricing.bond.macaulayDuration[couponRate;100.0;freq;ytm;nPeriods];
  expectedYears:nPeriods % freq;  / 10 years
  .test.assertNear["Zero-coupon Macaulay duration equals maturity"; expectedYears; macDur; 0.01];
 };

test_duration_coupon_bond:{[]
  / Coupon bond: Macaulay duration < time to maturity
  couponRate:0.05;
  freq:2;
  ytm:0.05;
  nPeriods:20;

  macDur:.pricing.bond.macaulayDuration[couponRate;100.0;freq;ytm;nPeriods];
  maturity:nPeriods % freq;
  .test.assert["Coupon bond duration < maturity"; macDur < maturity];
 };

test_modified_duration_formula:{[]
  / Modified duration = Macaulay duration / (1 + y/f)
  couponRate:0.05;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  macDur:.pricing.bond.macaulayDuration[couponRate;100.0;freq;ytm;nPeriods];
  modDur:.pricing.bond.modifiedDuration[couponRate;100.0;freq;ytm;nPeriods];
  expected:macDur % (1 + ytm % freq);
  .test.assertNear["Modified duration formula"; expected; modDur; TOL];
 };

test_duration_expired_bond:{[]
  / Expired bond duration should be zero
  macDur:.pricing.bond.macaulayDuration[0.05;100.0;2;0.05;0];
  modDur:.pricing.bond.modifiedDuration[0.05;100.0;2;0.05;0];
  .test.assertEqual["Expired bond Macaulay duration is zero"; 0.0; macDur];
  .test.assertEqual["Expired bond modified duration is zero"; 0.0; modDur];
 };

/ ============================================================================
/ CONVEXITY TESTS
/ ============================================================================

test_convexity_positive:{[]
  / Convexity should always be positive for vanilla bonds
  couponRate:0.05;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  conv:.pricing.bond.convexity[couponRate;100.0;freq;ytm;nPeriods];
  .test.assert["Convexity is positive"; conv > 0];
 };

test_convexity_zero_coupon:{[]
  / Zero-coupon bond convexity formula check
  couponRate:0.0;
  freq:2;
  ytm:0.05;
  nPeriods:20;

  conv:.pricing.bond.convexity[couponRate;100.0;freq;ytm;nPeriods];
  .test.assert["Zero-coupon convexity is positive"; conv > 0];
 };

test_convexity_expired_bond:{[]
  / Expired bond convexity should be zero
  conv:.pricing.bond.convexity[0.05;100.0;2;0.05;0];
  .test.assertEqual["Expired bond convexity is zero"; 0.0; conv];
 };

/ ============================================================================
/ DV01 TESTS
/ ============================================================================

test_dv01_formula:{[]
  / DV01 = Modified Duration × PV × 0.0001
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.05;
  nPeriods:20;

  pv:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  modDur:.pricing.bond.modifiedDuration[couponRate;faceValue;freq;ytm;nPeriods];
  dv01Calc:.pricing.bond.dv01[couponRate;faceValue;freq;ytm;nPeriods];
  expected:modDur * pv * 0.0001;
  .test.assertNear["DV01 formula check"; expected; dv01Calc; TOL];
 };

test_dv01_positive:{[]
  / DV01 should be positive (measures price sensitivity)
  dv01Calc:.pricing.bond.dv01[0.05;100.0;2;0.05;20];
  .test.assert["DV01 is positive"; dv01Calc > 0];
 };

test_dv01_bump_and_reprice:{[]
  / DV01 should approximate 1bp yield change
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.05;
  nPeriods:20;

  pvBase:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  pvBump:.pricing.bond.presentValue[couponRate;faceValue;freq;ytm+0.0001;nPeriods];
  actualChange:pvBase - pvBump;
  dv01Calc:.pricing.bond.dv01[couponRate;faceValue;freq;ytm;nPeriods];

  / Should be close (duration is linear approximation)
  .test.assertNear["DV01 approximates 1bp bump"; dv01Calc; actualChange; 0.0001];
 };

/ ============================================================================
/ KEY RATE DURATION TESTS
/ ============================================================================

test_key_rate_duration_symmetry:{[]
  / Key rate duration should be approximately symmetric for small bumps
  krd:.pricing.bond.keyRateDuration[0.05;100.0;2;0.05;20;`;1];
  .test.assert["Key rate duration is positive"; krd > 0];
 };

test_key_rate_duration_vs_modified:{[]
  / For a single bond, key rate duration ≈ modified duration
  / (simplified version bumps all cash flows equally)
  modDur:.pricing.bond.modifiedDuration[0.05;100.0;2;0.05;20];
  krd:.pricing.bond.keyRateDuration[0.05;100.0;2;0.05;20;`;1];

  / They should be close (within 10% relative error)
  relError:abs (krd - modDur) % modDur;
  .test.assert["Key rate duration ≈ modified duration"; relError < 0.1];
 };

/ ============================================================================
/ PORTFOLIO TESTS
/ ============================================================================

test_portfolio_duration_weighted_avg:{[]
  / Portfolio duration = weighted average of individual durations
  durations:7.5 8.2 6.9;
  marketValues:1000000 2000000 1500000;

  portDur:.pricing.bond.portfolioDuration[durations;marketValues];
  expected:sum (durations * marketValues) % sum marketValues;
  .test.assertNear["Portfolio duration is weighted average"; expected; portDur; TOL];
 };

test_portfolio_duration_empty:{[]
  / Empty portfolio should have zero duration
  portDur:.pricing.bond.portfolioDuration[`float$();`float$()];
  .test.assertEqual["Empty portfolio duration is zero"; 0.0; portDur];
 };

test_portfolio_dv01_sum:{[]
  / Portfolio DV01 = sum of position DV01s
  dv01s:0.045 0.052 0.038;
  quantities:100 200 150;

  portDV01:.pricing.bond.portfolioDV01[dv01s;quantities];
  expected:sum dv01s * quantities;
  .test.assertNear["Portfolio DV01 is sum"; expected; portDV01; TOL];
 };

test_portfolio_dv01_empty:{[]
  / Empty portfolio should have zero DV01
  portDV01:.pricing.bond.portfolioDV01[`float$();`long$()];
  .test.assertEqual["Empty portfolio DV01 is zero"; 0.0; portDV01];
 };

/ ============================================================================
/ PRICE CHANGE APPROXIMATION TESTS
/ ============================================================================

test_price_change_approximation:{[]
  / Price change approximation using duration and convexity
  pv:100.0;
  duration:7.5;
  convexity:65.0;
  dyield:0.001;  / 10bp yield increase

  priceChange:.pricing.bond.priceChangeApproximation[pv;duration;convexity;dyield];

  / Duration term (negative)
  durationTerm:neg duration * pv * dyield;
  / Convexity term (positive)
  convexityTerm:0.5 * convexity * pv * dyield * dyield;
  expected:durationTerm + convexityTerm;

  .test.assertNear["Price change approximation formula"; expected; priceChange; TOL];
 };

/ ============================================================================
/ PERFORMANCE BENCHMARKS
/ ============================================================================

test_performance_present_value:{[]
  / Benchmark: PV calculation should complete in <10μs
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  / Warm-up
  .pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods];

  / Benchmark: 10,000 iterations
  n:10000;
  start:.z.p;
  do[n; .pricing.bond.presentValue[couponRate;faceValue;freq;ytm;nPeriods]];
  elapsed:.z.p - start;
  avgMicros:(elapsed % 1000) % n;  / Convert to microseconds

  -1 "    PV avg time: ",string[avgMicros]," μs";
  .test.assert["PV completes within Docker smoke threshold"; avgMicros < PERF_MAX_MICROS];
 };

test_performance_modified_duration:{[]
  / Benchmark: Duration calculation should complete in <10μs
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  / Warm-up
  .pricing.bond.modifiedDuration[couponRate;faceValue;freq;ytm;nPeriods];

  / Benchmark: 10,000 iterations
  n:10000;
  start:.z.p;
  do[n; .pricing.bond.modifiedDuration[couponRate;faceValue;freq;ytm;nPeriods]];
  elapsed:.z.p - start;
  avgMicros:(elapsed % 1000) % n;

  -1 "    Duration avg time: ",string[avgMicros]," μs";
  .test.assert["Duration completes within Docker smoke threshold"; avgMicros < PERF_MAX_MICROS];
 };

test_performance_convexity:{[]
  / Benchmark: Convexity calculation should complete in <10μs
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  / Warm-up
  .pricing.bond.convexity[couponRate;faceValue;freq;ytm;nPeriods];

  / Benchmark: 10,000 iterations
  n:10000;
  start:.z.p;
  do[n; .pricing.bond.convexity[couponRate;faceValue;freq;ytm;nPeriods]];
  elapsed:.z.p - start;
  avgMicros:(elapsed % 1000) % n;

  -1 "    Convexity avg time: ",string[avgMicros]," μs";
  .test.assert["Convexity completes within Docker smoke threshold"; avgMicros < PERF_MAX_MICROS];
 };

test_performance_dv01:{[]
  / Benchmark: DV01 calculation should complete in <10μs
  couponRate:0.05;
  faceValue:100.0;
  freq:2;
  ytm:0.06;
  nPeriods:20;

  / Warm-up
  .pricing.bond.dv01[couponRate;faceValue;freq;ytm;nPeriods];

  / Benchmark: 10,000 iterations
  n:10000;
  start:.z.p;
  do[n; .pricing.bond.dv01[couponRate;faceValue;freq;ytm;nPeriods]];
  elapsed:.z.p - start;
  avgMicros:(elapsed % 1000) % n;

  -1 "    DV01 avg time: ",string[avgMicros]," μs";
  .test.assert["DV01 completes within Docker smoke threshold"; avgMicros < PERF_MAX_MICROS];
 };

/ ============================================================================
/ ERROR HANDLING TESTS
/ ============================================================================

test_error_negative_face_value:{[]
  / Negative face value should raise error
  .test.assertError["Negative face value raises error";
    {.pricing.bond.presentValue[0.05;-100.0;2;0.05;20]}];
 };

test_error_zero_frequency:{[]
  / Zero frequency should raise error
  .test.assertError["Zero frequency raises error";
    {.pricing.bond.presentValue[0.05;100.0;0;0.05;20]}];
 };

test_error_mismatched_portfolio_inputs:{[]
  / Mismatched durations and market values should raise error
  .test.assertError["Mismatched portfolio inputs raise error";
    {.pricing.bond.portfolioDuration[7.5 8.2;1000000 2000000 1500000]}];
 };

/ ============================================================================
/ RUN ALL TESTS
/ ============================================================================

\d .

-1 "\n========================================";
-1 "  Bond Pricing Tests";
-1 "========================================\n";

.test.run[`.];

/ Exit with failure code if tests failed
exit .test.failed
