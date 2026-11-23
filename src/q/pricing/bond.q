/ ============================================================================
/ bond.q - Bond Pricing and Analytics
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Present value calculation for fixed-rate bonds
/   - Modified and Macaulay duration
/   - Convexity calculation
/   - DV01 (dollar value of one basis point)
/   - Portfolio-level aggregation
/   - Key rate duration
/ ----------------------------------------------------------------------------
/ Performance target: <10us per calculation
/ ----------------------------------------------------------------------------
/ Reference: Python implementation in src/python/medusa/pricing/bond.py
/ Cross-validated with Python results (tolerance: 1e-6)
/ ----------------------------------------------------------------------------
/ Functions:
/   - presentValue: PV = Sum(C/f / (1+y/f)^t) + F/(1+y/f)^T
/   - macaulayDuration: D_Mac = (Sum t*PV(CF)) / PV
/   - modifiedDuration: D_Mod = D_Mac / (1+y/f)
/   - convexity: C = (Sum t*(t+1)*PV(CF)) / (PV * (1+y/f)^2)
/   - dv01: DV01 = D_Mod * PV * 0.0001
/   - portfolioDuration: Market-value weighted duration
/   - portfolioDV01: Sum of position DV01s
/   - keyRateDuration: Bump-and-reprice sensitivity
/ ============================================================================

\d .pricing

/ ============================================================================
/ CORE PRICING FUNCTIONS
/ ============================================================================

/ Present Value (clean price)
/ Calculates PV of future cash flows discounted at given yield
/ @param couponRate float - Annual coupon rate (e.g., 0.05 for 5%)
/ @param faceValue float - Par value (typically 100)
/ @param freq long - Coupon frequency per year (1, 2, or 4)
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @return float - Present value
bond_presentValue:{[couponRate;faceValue;freq;ytm;nPeriods]
  / Validate inputs
  if[faceValue <= 0; '"Face value must be positive"];
  if[freq <= 0; '"Frequency must be positive"];
  if[nPeriods <= 0; :0.0];  / Expired bond

  / Calculate coupon payment per period
  c:couponRate * faceValue % freq;

  / Calculate periodic yield
  y:ytm % freq;

  / Generate discount factors for each period
  / (1+y)^1, (1+y)^2, ..., (1+y)^nPeriods
  t:1+til nPeriods;
  discount:(1+y) xexp t;

  / Present value of coupon stream
  couponPV:sum c % discount;

  / Present value of principal at maturity
  principalPV:faceValue % last discount;

  / Total present value
  couponPV + principalPV
 };

/ Macaulay Duration
/ Weighted average time to cash flows
/ @param couponRate float - Annual coupon rate
/ @param faceValue float - Par value
/ @param freq long - Coupon frequency per year
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @return float - Macaulay duration in years
bond_macaulayDuration:{[couponRate;faceValue;freq;ytm;nPeriods]
  / Validate inputs
  if[nPeriods <= 0; :0.0];

  / Calculate present value
  pv:bond_presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  if[pv = 0; :0.0];

  / Coupon payment per period
  c:couponRate * faceValue % freq;

  / Periodic yield
  y:ytm % freq;

  / Time periods (in years)
  t:(1+til nPeriods) % freq;

  / Discount factors
  discount:(1+y) xexp 1+til nPeriods;

  / Cash flows: coupons for all periods except last, coupon+principal for last
  cf:(nPeriods-1)#c;
  cf,:c + faceValue;  / Last period: coupon + principal

  / Weighted present value: time * PV(cashflow)
  weightedPV:sum t * cf % discount;

  / Macaulay duration = weighted PV / total PV
  weightedPV % pv
 };

/ Modified Duration
/ Price sensitivity to yield changes
/ @param couponRate float - Annual coupon rate
/ @param faceValue float - Par value
/ @param freq long - Coupon frequency per year
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @return float - Modified duration in years
bond_modifiedDuration:{[couponRate;faceValue;freq;ytm;nPeriods]
  / Calculate Macaulay duration
  macDur:bond_macaulayDuration[couponRate;faceValue;freq;ytm;nPeriods];

  / Modified duration = Macaulay duration / (1 + y/f)
  y:ytm % freq;
  macDur % (1 + y)
 };

/ Convexity
/ Second derivative of price with respect to yield
/ @param couponRate float - Annual coupon rate
/ @param faceValue float - Par value
/ @param freq long - Coupon frequency per year
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @return float - Convexity
bond_convexity:{[couponRate;faceValue;freq;ytm;nPeriods]
  / Validate inputs
  if[nPeriods <= 0; :0.0];

  / Calculate present value
  pv:bond_presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  if[pv = 0; :0.0];

  / Coupon payment per period
  c:couponRate * faceValue % freq;

  / Periodic yield
  y:ytm % freq;

  / Period indices
  t:1+til nPeriods;

  / Discount factors
  discount:(1+y) xexp t;

  / Cash flows: coupons for all periods except last, coupon+principal for last
  cf:(nPeriods-1)#c;
  cf,:c + faceValue;

  / Convexity sum: t*(t+1) * PV(cashflow)
  / IMPORTANT: t is in periods, not years, for this formula
  weightedPV:sum (t * t+1) * cf % discount;

  / Convexity = sum / (PV * (1+y/f)^2 * f^2)
  / Note: The f^2 term converts from period-based to year-based
  weightedPV % (pv * (1+y) xexp 2 * freq * freq)
 };

/ DV01 (Dollar Value of One Basis Point)
/ Price change for 1 bp yield increase
/ @param couponRate float - Annual coupon rate
/ @param faceValue float - Par value
/ @param freq long - Coupon frequency per year
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @return float - DV01 (positive value)
bond_dv01:{[couponRate;faceValue;freq;ytm;nPeriods]
  / Calculate modified duration
  dmod:bond_modifiedDuration[couponRate;faceValue;freq;ytm;nPeriods];

  / Calculate present value
  pv:bond_presentValue[couponRate;faceValue;freq;ytm;nPeriods];

  / DV01 = Modified Duration * PV * 0.0001 (1 bp)
  dmod * pv * 0.0001
 };

/ ============================================================================
/ KEY RATE DURATION (SIMPLIFIED)
/ ============================================================================

/ Key Rate Duration
/ Sensitivity to specific tenor yield changes (simplified bump-and-reprice)
/ @param couponRate float - Annual coupon rate
/ @param faceValue float - Par value
/ @param freq long - Coupon frequency per year
/ @param ytm float - Yield to maturity (annual)
/ @param nPeriods long - Number of periods to maturity
/ @param keyRate symbol - Key rate identifier (not used in simplified version)
/ @param bumpBps float - Bump size in basis points (e.g., 1 for 1bp)
/ @return float - Key rate duration
bond_keyRateDuration:{[couponRate;faceValue;freq;ytm;nPeriods;keyRate;bumpBps]
  / Convert bump from basis points to decimal
  bump:bumpBps % 10000;

  / Calculate base PV
  pvBase:bond_presentValue[couponRate;faceValue;freq;ytm;nPeriods];
  if[pvBase = 0; :0.0];

  / Calculate PV with yield bumped up
  pvUp:bond_presentValue[couponRate;faceValue;freq;ytm+bump;nPeriods];

  / Calculate PV with yield bumped down
  pvDown:bond_presentValue[couponRate;faceValue;freq;ytm-bump;nPeriods];

  / Key rate duration (negative sign because price falls when yield rises)
  neg (pvUp - pvDown) % (2 * bump * pvBase)
 };

/ ============================================================================
/ PORTFOLIO LEVEL FUNCTIONS
/ ============================================================================

/ Portfolio Duration
/ Market-value weighted average duration
/ @param durations float[] - Duration of each bond
/ @param marketValues float[] - Market value of each position
/ @return float - Portfolio duration
bond_portfolioDuration:{[durations;marketValues]
  / Validate inputs
  if[(count durations) <> count marketValues; '"Durations and market values must have same length"];
  if[0 = count durations; :0.0];

  / Total market value
  totalMV:sum marketValues;
  if[totalMV = 0; :0.0];

  / Weighted average duration
  sum (durations * marketValues) % totalMV
 };

/ Portfolio DV01
/ Sum of individual position DV01s
/ @param dv01s float[] - DV01 of each bond
/ @param quantities long[] - Quantity of each position
/ @return float - Portfolio DV01
bond_portfolioDV01:{[dv01s;quantities]
  / Validate inputs
  if[(count dv01s) <> count quantities; '"DV01s and quantities must have same length"];
  if[0 = count dv01s; :0.0];

  / Sum of position DV01s
  sum dv01s * quantities
 };

/ ============================================================================
/ HELPER FUNCTIONS
/ ============================================================================

/ Calculate price change for yield change using duration and convexity
/ @param pv float - Current price
/ @param duration float - Modified duration
/ @param convexity float - Convexity
/ @param dyield float - Yield change (e.g., 0.001 for 10bp)
/ @return float - Estimated price change
bond_priceChangeApproximation:{[pv;duration;convexity;dyield]
  / DeltaP approx -D_mod * PV * Deltay + 0.5 * C * PV * (Deltay)^2
  durationTerm:neg duration * pv * dyield;
  convexityTerm:0.5 * convexity * pv * dyield * dyield;
  durationTerm + convexityTerm
 };

\d .

/ Export namespace
set[`.pricing.bond.presentValue;.pricing.bond_presentValue];
set[`.pricing.bond.macaulayDuration;.pricing.bond_macaulayDuration];
set[`.pricing.bond.modifiedDuration;.pricing.bond_modifiedDuration];
set[`.pricing.bond.convexity;.pricing.bond_convexity];
set[`.pricing.bond.dv01;.pricing.bond_dv01];
set[`.pricing.bond.keyRateDuration;.pricing.bond_keyRateDuration];
set[`.pricing.bond.portfolioDuration;.pricing.bond_portfolioDuration];
set[`.pricing.bond.portfolioDV01;.pricing.bond_portfolioDV01];
set[`.pricing.bond.priceChangeApproximation;.pricing.bond_priceChangeApproximation];

-1 "  Bond pricing loaded: presentValue, macaulayDuration, modifiedDuration, convexity, dv01, portfolioDuration, portfolioDV01, keyRateDuration";
