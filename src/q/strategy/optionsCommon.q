/ ============================================================================
/ optionsCommon.q - Shared Options Strategy Utilities
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Black-Scholes pricing and Greeks calculation
/   - Multi-leg option structure building
/   - Payoff calculation at expiry
/   - Market session detection
/   - Common option strategy helpers
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - schema/options.q (option table schemas)
/   - lib/money.q (fixed-precision money operations)
/ ----------------------------------------------------------------------------
/ Functions:
/   - calculateBS: Black-Scholes price (call/put)
/   - calculateGreeks: delta, gamma, theta, vega, rho
/   - calculatePayoff: P&L at expiry for multi-leg positions
/   - buildMultiLeg: construct multi-leg order from table
/   - getSession: market session (asia/europe/us)
/ ============================================================================

\d .strategy

// ============================================================================
// CONSTANTS
// ============================================================================

/ Risk-free rate (annual, decimal)
options.RISK_FREE_RATE:0.05;  / 5% annual

/ Days in year (trading days)
options.DAYS_PER_YEAR:252;

/ Volatility bounds
options.MIN_VOL:0.01;  / 1%
options.MAX_VOL:5.0;   / 500%

/ Cumulative normal distribution approximation constants
/ Using Abramowitz and Stegun approximation
options.CND_A1:0.31938153;
options.CND_A2:-0.356563782;
options.CND_A3:1.781477937;
options.CND_A4:-1.821255978;
options.CND_A5:1.330274429;
options.CND_RSQRT2PI:0.39894228040143267793994605993438;

// ============================================================================
// MATH HELPERS
// ============================================================================

/ Cumulative normal distribution (approximation)
/ @param x float - Input value
/ @return float - CDF(x)
options.cumulativeNormal:{[x]
  / Handle extreme values
  if[x < -7.0; :0.0];
  if[x > 7.0; :1.0];

  / Abramowitz and Stegun approximation
  k:1.0 % (1.0 + 0.2316419 * abs x);
  pdf:options.CND_RSQRT2PI * exp neg 0.5 * x * x;
  poly:options.CND_A1 + (k * options.CND_A2) + ((k xexp 2) * options.CND_A3) + ((k xexp 3) * options.CND_A4) + ((k xexp 4) * options.CND_A5);
  cnd:pdf * k * poly;

  $[x < 0.0; cnd; 1.0 - cnd]
 };

/ Probability density function (standard normal)
/ @param x float - Input value
/ @return float - PDF(x)
options.normalPDF:{[x]
  options.CND_RSQRT2PI * exp neg 0.5 * x * x
 };

// ============================================================================
// BLACK-SCHOLES PRICING
// ============================================================================

/ Calculate d1 parameter for Black-Scholes
/ @param S float - Spot price
/ @param K float - Strike price
/ @param r float - Risk-free rate (annual)
/ @param T float - Time to expiry (years)
/ @param sigma float - Volatility (annual)
/ @return float - d1 (or intrinsic value if T ≈ 0)
options.calculateD1:{[S;K;r;ttm;sigma]
  / Guard against division by zero when T approaches zero
  if[ttm <= 0.0001; :0n];  / Return null for near-expiry options
  sqrtT:sqrt ttm;
  if[(sqrtT * sigma) < 1e-10; :0n];  / Avoid division by near-zero
  varianceTerm:0.5 * sigma * sigma;
  numerator:log[S % K] + ((r + varianceTerm) * ttm);
  numerator % (sigma * sqrtT)
 };

/ Calculate d2 parameter for Black-Scholes
/ @param d1 float - d1 parameter
/ @param sigma float - Volatility (annual)
/ @param T float - Time to expiry (years)
/ @return float - d2 (or null if d1 is null)
options.calculateD2:{[d1;sigma;ttm]
  if[null d1; :0n];  / Propagate null from d1
  d1 - (sigma * sqrt ttm)
 };

/ Black-Scholes option price
/ @param S float - Spot price
/ @param K float - Strike price
/ @param r float - Risk-free rate (annual)
/ @param T float - Time to expiry (years)
/ @param sigma float - Volatility (annual)
/ @param optType symbol - Option type (`call or `put)
/ @return float - Option price
options.calculateBS:{[S;K;r;ttm;sigma;optType]
  / Validate inputs
  if[S <= 0.0; '"Spot price must be positive"];
  if[K <= 0.0; '"Strike price must be positive"];
  if[ttm <= 0.0; :0.0];  / Expired option - intrinsic value only
  if[sigma < options.MIN_VOL; sigma:options.MIN_VOL];  / Floor volatility
  if[sigma > options.MAX_VOL; sigma:options.MAX_VOL];  / Cap volatility

  / Calculate d1 and d2
  d1:options.calculateD1[S;K;r;ttm;sigma];
  d2:options.calculateD2[d1;sigma;ttm];

  / Handle near-expiry (null d1/d2) - return intrinsic value
  if[null d1;
    :$[optType=`call;
      0.0 | S - K;  / Call intrinsic value
      0.0 | K - S   / Put intrinsic value
    ]
  ];

  / Calculate price based on option type
  discount:exp neg r * ttm;
  Nd1:options.cumulativeNormal[d1];
  Nd2:options.cumulativeNormal[d2];
  Nnd1:options.cumulativeNormal[neg d1];
  Nnd2:options.cumulativeNormal[neg d2];
  forwardLeg:S * Nd1;
  strikeLeg:K * discount * Nd2;
  putStrikeLeg:K * discount * Nnd2;
  putSpotLeg:S * Nnd1;
  $[optType=`call;
    / Call option: S * N(d1) - K * e^(-rT) * N(d2)
    forwardLeg - strikeLeg;
  optType=`put;
    / Put option: K * e^(-rT) * N(-d2) - S * N(-d1)
    putStrikeLeg - putSpotLeg;
  / else
    '"Invalid option type: must be `call or `put"
  ]
 };

// ============================================================================
// GREEKS CALCULATION
// ============================================================================

/ Calculate option Greeks
/ @param S float - Spot price
/ @param K float - Strike price
/ @param r float - Risk-free rate (annual)
/ @param T float - Time to expiry (years)
/ @param sigma float - Volatility (annual)
/ @param optType symbol - Option type (`call or `put)
/ @return dict - Greeks (delta, gamma, theta, vega, rho)
options.calculateGreeks:{[S;K;r;ttm;sigma;optType]
  / Validate inputs
  if[S <= 0.0; '"Spot price must be positive"];
  if[K <= 0.0; '"Strike price must be positive"];
  if[ttm <= 0.0;
    / Expired option - all Greeks are zero
    :`delta`gamma`theta`vega`rho!(0.0;0.0;0.0;0.0;0.0)
  ];
  if[sigma < options.MIN_VOL; sigma:options.MIN_VOL];
  if[sigma > options.MAX_VOL; sigma:options.MAX_VOL];

  / Calculate d1 and d2
  d1:options.calculateD1[S;K;r;ttm;sigma];
  d2:options.calculateD2[d1;sigma;ttm];

  / Calculate N(d1), N(d2), N'(d1)
  Nd1:options.cumulativeNormal[d1];
  Nd2:options.cumulativeNormal[d2];
  Npd1:options.normalPDF[d1];

  / Delta (with dividend factor for q > 0)
  / For crypto q=0, so exp[neg q * T] = 1.0 (no effect)
  dividendYield:0.0;
  divFactor:exp neg dividendYield * ttm;
  delta:$[optType=`call;
    divFactor * Nd1;  / Call delta = e^(-qT) * N(d1)
  optType=`put;
    divFactor * (Nd1 - 1.0);  / Put delta = e^(-qT) * [N(d1) - 1]
  / else
    '"Invalid option type"
  ];

  / Gamma (same for call and put, with dividend factor)
  gamma:(divFactor * Npd1) % (S * sigma * sqrt ttm);

  / Theta (per day, not per year)
  / All three terms with correct signs
  term1:neg ((S * divFactor * Npd1 * sigma) % (2.0 * sqrt ttm));
  term2Call:dividendYield * S * divFactor * Nd1;
  term2Put:neg dividendYield * S * divFactor * options.cumulativeNormal[neg d1];
  discount:exp neg r * ttm;
  term3Call:neg r * K * discount * Nd2;  / CORRECTED: must be NEGATIVE
  term3Put:r * K * discount * options.cumulativeNormal[neg d2];  / Positive for puts
  thetaCall:(term1 + term2Call + term3Call) % options.DAYS_PER_YEAR;
  thetaPut:(term1 + term2Put + term3Put) % options.DAYS_PER_YEAR;
  theta:$[optType=`call; thetaCall; thetaPut];

  / Vega (per 1% change in volatility, with dividend factor)
  vega:(S * divFactor * Npd1 * sqrt ttm) % 100.0;

  / Rho (per 1% change in interest rate)
  rhoCall:(K * ttm * discount * Nd2) % 100.0;
  rhoPut:(neg K * ttm * discount * options.cumulativeNormal[neg d2]) % 100.0;
  rho:$[optType=`call; rhoCall; rhoPut];

  `delta`gamma`theta`vega`rho!(delta;gamma;theta;vega;rho)
 };

// ============================================================================
// MULTI-LEG OPTION STRUCTURES
// ============================================================================

/ Build multi-leg order from table of legs
/ @param legs table - Table with columns: contractId, side, qty
/ @return dict - Multi-leg order structure
options.buildMultiLeg:{[legs]
  / Validate input
  if[0 = count legs; '"Legs table cannot be empty"];
  requiredCols:`contractId`side`qty;
  if[not all requiredCols in cols legs; '"Missing required columns: contractId, side, qty"];

  / Validate side column
  if[not all (exec side from legs) in `buy`sell; '"Side must be `buy or `sell"];

  / Validate qty column
  if[not all (exec qty from legs) > 0; '"Quantity must be positive"];

  / Return multi-leg structure
  `legs`legCount!(legs;count legs)
 };

// ============================================================================
// PAYOFF CALCULATION
// ============================================================================

/ Calculate payoff at expiry for a single option leg
/ @param contractId symbol - Contract ID
/ @param side symbol - `buy or `sell
/ @param qty long - Quantity (contracts)
/ @param entryPrice long - Entry price (fixed-precision, .money)
/ @param underlyingPrice float - Underlying price at expiry
/ @return float - Payoff (positive = profit, negative = loss)
options.calculateLegPayoff:{[contractId;side;qty;entryPrice;underlyingPrice]
  / Look up contract details
  contract:.schema.optionContract[contractId];
  if[()~contract; '"Contract not found: ",string contractId];

  / Extract strike and option type
  strike:contract`strike;
  optType:contract`optionType;
  multiplier:contract`multiplier;

  / Convert strike from fixed-precision to float
  strikeFloat:strike % 1000000.0;

  / Calculate intrinsic value at expiry
  intrinsic:$[optType=`call;
    0.0 | underlyingPrice - strikeFloat;
  optType=`put;
    0.0 | strikeFloat - underlyingPrice;
  / else
    0.0
  ];

  / Convert entry price from fixed-precision to float
  entryFloat:entryPrice % 1000000.0;

  / Calculate payoff (long = positive intrinsic - premium paid, short = premium received - intrinsic)
  signedQty:$[side=`buy; qty; neg qty];
  payoff:(intrinsic - entryFloat) * signedQty * multiplier;

  payoff
 };

/ Calculate total payoff for multi-leg position
/ @param positions table - Table with columns: contractId, side, qty, avgEntryPrice
/ @param underlyingPrice float - Underlying price at expiry
/ @return float - Total payoff
options.calculatePayoff:{[positions;underlyingPrice]
  / Validate input
  if[0 = count positions; :0.0];
  requiredCols:`contractId`side`qty`avgEntryPrice;
  if[not all requiredCols in cols positions; '"Missing required columns"];

  / Calculate payoff for each leg
  payoffs:{[underlyingPrice;row]
    options.calculateLegPayoff[row`contractId;row`side;row`qty;row`avgEntryPrice;underlyingPrice]
   }[underlyingPrice] each flip positions;

  / Sum total payoff
  sum payoffs
 };

// ============================================================================
// MARKET SESSION DETECTION
// ============================================================================

/ Get market session based on timestamp
/ @param timestamp timestamp - Timestamp to check
/ @return symbol - Session (`asia, `europe, `us, `closed)
options.getSession:{[timestamp]
  / Convert timestamp to UTC hour
  hour:`hh$timestamp;

  / Market sessions (UTC):
  / Asia: 23:00 - 08:00 (Tokyo 8:00-17:00 JST)
  / Europe: 08:00 - 16:00 (London 8:00-16:00 GMT)
  / US: 13:30 - 20:00 (NYSE 9:30-16:00 ET)
  / Note: These are approximate and don't account for daylight saving

  $[hour >= 23;
    `asia;
  hour < 8;
    `asia;
  (hour >= 13) and (hour < 20);
    `us;
  (hour >= 8) and (hour < 16);
    `europe;
  / else
    `closed
  ]
 };

\d .

\d .risk

// ============================================================================
// QUOTE FRESHNESS VALIDATION
// ============================================================================

/ Check if the latest quote for an option contract is fresh
/ @param contractId symbol - Option contract ID
/ @param maxAgeNanos long - Maximum allowed age in nanoseconds
/ @return tuple - (pass:boolean; reason:symbol; detail:dict)
checkQuoteFreshness:{[contractId;maxAgeNanos]
  / Look up latest quote
  latestQuote:first select from .schema.optionQuote where contractId=contractId;

  / No quote available
  if[0 = count latestQuote;
    :(0b;`noQuoteAvailable;`contractId!contractId)
  ];

  / Calculate age
  quoteTimestamp:latestQuote`timestamp;
  ageNanos:.z.p - quoteTimestamp;

  / Check if stale
  if[ageNanos > maxAgeNanos;
    :(0b;`staleQuote;`contractId`ageSeconds!(contractId;ageNanos % 1000000000))
  ];

  / Quote is fresh
  (1b;`;())
 };

\d .

/ Export namespace
-1 "  Options common utilities loaded: calculateBS, calculateGreeks, calculatePayoff, buildMultiLeg, getSession, checkQuoteFreshness";
