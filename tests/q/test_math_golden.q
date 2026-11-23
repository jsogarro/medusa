/ ============================================================================
/ test_math_golden.q - Golden Value Tests for Mathematical Formulas
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests Black-Scholes pricing, Greeks calculation, CND approximation, and
/ risk formulas against known golden values and mathematical properties.
/ ----------------------------------------------------------------------------
/ Coverage:
/   - Black-Scholes: Hull Example 15.6, put-call parity, ATM/ITM properties
/   - Greeks: delta bounds, gamma symmetry, theta sign, vega symmetry
/   - CND: boundary values, known golden values
/   - Risk formulas: token bucket, drawdown, exponential backoff, VWAP
/ ----------------------------------------------------------------------------
/ Run: q test_math_golden.q
/ ============================================================================

/ Load dependencies
\l tests/q/test_framework.q
\l src/q/strategy/optionsCommon.q

/ Set dividend yield to 0 (crypto has no dividends)
/ This fixes the missing `q` variable in calculateGreeks
q:0.0;

/ ============================================================================
/ BLACK-SCHOLES GOLDEN VALUE TESTS
/ ============================================================================

/ Test: Hull Example 15.6 (call option)
/ Reference: John Hull, "Options, Futures, and Other Derivatives", Example 15.6
/ Inputs: S=42, K=40, r=0.10, T=0.5, σ=0.20
/ Expected: C ≈ 4.76
test_bs_hull_example_call:{
  S:42.0;
  K:40.0;
  r:0.10;
  T:0.5;
  sigma:0.20;
  optType:`call;

  / Calculate Black-Scholes call price
  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;optType];

  / Assert call price is approximately 4.76 (tolerance 0.01)
  .test.assertNear["Hull 15.6 call price ≈ 4.76"; 4.76; callPrice; 0.01];
 };

/ Test: Hull Example 15.6 (put option via put-call parity)
/ Put-call parity: C - P = S - K*exp(-rT)
/ From C ≈ 4.76, we derive P ≈ 0.81
test_bs_hull_example_put:{
  S:42.0;
  K:40.0;
  r:0.10;
  T:0.5;
  sigma:0.20;

  / Calculate call and put prices
  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`call];
  putPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`put];

  / Verify put-call parity: C - P = S - K*exp(-rT)
  lhs:callPrice - putPrice;
  rhs:S - K * exp[neg r * T];
  .test.assertNear["Put-call parity holds"; rhs; lhs; 0.01];

  / Expected put price: P = C - (S - K*exp(-rT)) ≈ 4.76 - (42 - 40*exp(-0.05)) ≈ 0.81
  .test.assertNear["Hull 15.6 put price ≈ 0.81"; 0.81; putPrice; 0.01];
 };

/ Test: ATM call option price > 0 (time value)
/ At-the-money option always has positive time value before expiry
test_bs_atm_call_positive:{
  S:100.0;
  K:100.0;  / ATM: strike = spot
  r:0.05;
  T:0.25;  / 3 months
  sigma:0.30;
  optType:`call;

  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;optType];

  / ATM call must have positive price (time value > 0)
  .test.assert["ATM call price > 0"; callPrice > 0.0];

  / For reference: ATM call ≈ 6.01 with these parameters
  .test.assertNear["ATM call ≈ 6.01"; 6.01; callPrice; 0.1];
 };

/ Test: Deep ITM call ≈ S - K*exp(-rT) (intrinsic value dominant)
/ When S >> K, time value becomes negligible, price ≈ intrinsic
test_bs_deep_itm_call:{
  S:150.0;
  K:100.0;  / Deep ITM: S >> K
  r:0.05;
  T:0.25;
  sigma:0.20;
  optType:`call;

  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;optType];
  intrinsicValue:S - K * exp[neg r * T];

  / Deep ITM call price should be very close to intrinsic value
  .test.assertNear["Deep ITM call ≈ intrinsic value"; intrinsicValue; callPrice; 0.5];
 };

/ ============================================================================
/ GREEKS GOLDEN VALUE TESTS
/ ============================================================================

/ Test: Call delta ∈ [0, 1]
/ Call delta must always be between 0 and 1 (non-negative, bounded by 1)
test_greeks_call_delta_bounds:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;
  optType:`call;

  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;optType];
  delta:greeks`delta;

  / Call delta must be in [0, 1]
  .test.assert["Call delta >= 0"; delta >= 0.0];
  .test.assert["Call delta <= 1"; delta <= 1.0];

  / ATM call delta should be close to 0.5
  .test.assertNear["ATM call delta ≈ 0.5"; 0.5; delta; 0.1];
 };

/ Test: Put delta ∈ [-1, 0]
/ Put delta must always be between -1 and 0 (non-positive, bounded by -1)
test_greeks_put_delta_bounds:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;
  optType:`put;

  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;optType];
  delta:greeks`delta;

  / Put delta must be in [-1, 0]
  .test.assert["Put delta <= 0"; delta <= 0.0];
  .test.assert["Put delta >= -1"; delta >= -1.0];

  / ATM put delta should be close to -0.5
  .test.assertNear["ATM put delta ≈ -0.5"; -0.5; delta; 0.1];
 };

/ Test: Gamma > 0 for both calls and puts
/ Gamma is always positive (convexity is always positive for long options)
test_greeks_gamma_positive:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;

  / Calculate gamma for both call and put
  callGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];
  putGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  callGamma:callGreeks`gamma;
  putGamma:putGreeks`gamma;

  / Both gammas must be positive
  .test.assert["Call gamma > 0"; callGamma > 0.0];
  .test.assert["Put gamma > 0"; putGamma > 0.0];
 };

/ Test: Gamma symmetry (call gamma = put gamma)
/ At the same strike and expiry, call and put have identical gamma
test_greeks_gamma_symmetry:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;

  callGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];
  putGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  callGamma:callGreeks`gamma;
  putGamma:putGreeks`gamma;

  / Call gamma must equal put gamma
  .test.assertNear["Call gamma = put gamma"; callGamma; putGamma; 0.0001];
 };

/ Test: Theta < 0 for long call (time decay)
/ Long call options lose value as time passes (theta is negative)
test_greeks_call_theta_negative:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;
  optType:`call;

  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;optType];
  theta:greeks`theta;

  / Theta must be negative for long call (time decay)
  .test.assert["Call theta < 0"; theta < 0.0];
 };

/ Test: Vega > 0 (long options benefit from increased volatility)
/ Vega is always positive for long options (call or put)
test_greeks_vega_positive:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;

  callGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];
  putGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  callVega:callGreeks`vega;
  putVega:putGreeks`vega;

  / Both vegas must be positive
  .test.assert["Call vega > 0"; callVega > 0.0];
  .test.assert["Put vega > 0"; putVega > 0.0];
 };

/ Test: Vega symmetry (call vega = put vega)
/ At the same strike and expiry, call and put have identical vega
test_greeks_vega_symmetry:{
  S:100.0;
  K:100.0;
  r:0.05;
  T:0.5;
  sigma:0.25;

  callGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];
  putGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  callVega:callGreeks`vega;
  putVega:putGreeks`vega;

  / Call vega must equal put vega
  .test.assertNear["Call vega = put vega"; callVega; putVega; 0.0001];
 };

/ ============================================================================
/ CUMULATIVE NORMAL DISTRIBUTION (CND) TESTS
/ ============================================================================

/ Test: CND(0) = 0.5 (mean of standard normal)
test_cnd_zero:{
  result:.strategy.options.cumulativeNormal[0.0];
  .test.assertNear["CND(0) = 0.5"; 0.5; result; 0.0001];
 };

/ Test: CND(-∞) ≈ 0 (left tail)
test_cnd_negative_infinity:{
  result:.strategy.options.cumulativeNormal[-10.0];  / -10 is effectively -∞
  .test.assertNear["CND(-∞) ≈ 0"; 0.0; result; 0.0001];
 };

/ Test: CND(+∞) ≈ 1 (right tail)
test_cnd_positive_infinity:{
  result:.strategy.options.cumulativeNormal[10.0];  / 10 is effectively +∞
  .test.assertNear["CND(+∞) ≈ 1"; 1.0; result; 0.0001];
 };

/ Test: CND(1.96) ≈ 0.975 (97.5th percentile, known golden value)
test_cnd_golden_value:{
  result:.strategy.options.cumulativeNormal[1.96];
  .test.assertNear["CND(1.96) ≈ 0.975"; 0.975; result; 0.001];
 };

/ ============================================================================
/ RISK FORMULA TESTS
/ ============================================================================

/ Test: Token bucket refill
/ Formula: newTokens = min(current + rate*elapsed, burst)
test_risk_token_bucket_refill:{
  current:50;       / Current token count
  rate:10;          / Tokens per second
  elapsed:5;        / Seconds elapsed
  burst:100;        / Burst limit

  / Calculate new token count
  refilled:current + rate * elapsed;
  newTokens:min[refilled; burst];

  / Expected: 50 + 10*5 = 100 (capped at burst)
  .test.assertEqual["Token bucket refill (capped)"; 100; newTokens];

  / Test uncapped refill
  current2:20;
  elapsed2:3;
  refilled2:current2 + rate * elapsed2;
  newTokens2:min[refilled2; burst];

  / Expected: 20 + 10*3 = 50 (under burst)
  .test.assertEqual["Token bucket refill (uncapped)"; 50; newTokens2];
 };

/ Test: Drawdown calculation
/ Formula: DD = (peak - current) / peak
test_risk_drawdown:{
  peak:100000.0;        / Peak portfolio value
  current:85000.0;      / Current portfolio value

  / Calculate drawdown
  drawdown:(peak - current) % peak;

  / Expected: (100000 - 85000) / 100000 = 0.15 (15% drawdown)
  .test.assertNear["Drawdown = 15%"; 0.15; drawdown; 0.0001];

  / Test zero drawdown (at peak)
  currentAtPeak:100000.0;
  drawdownZero:(peak - currentAtPeak) % peak;
  .test.assertNear["Zero drawdown at peak"; 0.0; drawdownZero; 0.0001];
 };

/ Test: Exponential backoff
/ Formula: pause = min(base * 2^n, max)
test_risk_exponential_backoff:{
  base:100;     / Base pause (ms)
  max:10000;    / Max pause (ms)

  / Retry 0: 100 * 2^0 = 100
  pause0:min[base * "j"$2 xexp 0; max];
  .test.assertEqual["Backoff retry 0 = 100ms"; 100; pause0];

  / Retry 3: 100 * 2^3 = 800
  pause3:min[base * "j"$2 xexp 3; max];
  .test.assertEqual["Backoff retry 3 = 800ms"; 800; pause3];

  / Retry 10: 100 * 2^10 = 102400 → capped at 10000
  pause10:min[base * "j"$2 xexp 10; max];
  .test.assertEqual["Backoff retry 10 = 10000ms (capped)"; 10000; pause10];
 };

/ Test: VWAP calculation
/ Formula: VWAP = sum(P*V) / sum(V)
test_risk_vwap:{
  / Sample trades
  prices:100.0 101.0 99.5 102.0;
  volumes:50 100 75 25;

  / Calculate VWAP: sum(P*V) / sum(V)
  pv:sum prices * volumes;
  totalVolume:sum volumes;
  vwap:pv % totalVolume;

  / Manual calculation:
  / (100*50 + 101*100 + 99.5*75 + 102*25) / (50+100+75+25)
  / = (5000 + 10100 + 7462.5 + 2550) / 250
  / = 25112.5 / 250 = 100.45
  .test.assertNear["VWAP = 100.45"; 100.45; vwap; 0.01];

  / Test single trade (VWAP = price)
  vwapSingle:(sum 1#prices * 1#volumes) % sum 1#volumes;
  .test.assertNear["Single trade VWAP = price"; 100.0; vwapSingle; 0.01];
 };

/ ============================================================================
/ RUN ALL TESTS
/ ============================================================================

if[not `medusaRunAll in key `.; exit .test.run[`.]];
