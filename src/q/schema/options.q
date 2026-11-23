/ ============================================================================
/ options.q - Options Market Data Schema
/ ============================================================================
/ /
/ Provides:
/   - Options-specific table schemas (contracts, quotes, trades, bars, surface, positions)
/   - Fixed-precision monetary types (.money namespace)
/   - Option Greeks calculation support
/ /
/ Asset Class: US Options (calls, puts)
/ Data Provider: Alpaca Markets (planned)
/ /
/ Tables:
/   - optionContract: Contract specifications (keyed by contractId)
/   - optionQuote: Real-time option quotes with Greeks
/   - optionTrade: Option trade ticks
/   - optionBar: OHLCV bars for options
/   - volatilitySurface: Implied volatility surface
/   - optionPosition: Option positions by contract (keyed by contractId)
/ /
/ Precision: All prices use .money fixed-precision (6 decimal places)
/ ============================================================================

\d .schema

// ============================================================================
// OPTION CONTRACT TABLE
// ============================================================================
/ Contract specifications (keyed by contractId)
/ Published by: Python loader (one-time or daily refresh)
/ Consumed by: Strategy engine, risk management
optionContract:([contractId:`symbol$()]
  underlying:`symbol$();        / Underlying equity symbol (e.g., `AAPL)
  expiry:`date$();              / Expiration date
  strike:`long$();              / Strike price (fixed-precision, .money)
  optionType:`symbol$();        / Option type (`call or `put)
  style:`symbol$();             / Exercise style (`american or `european)
  multiplier:`long$();          / Contract multiplier (usually 100)
  status:`symbol$()             / Status (`active, `expired, `suspended)
 );

// ============================================================================
// OPTION QUOTE TABLE
// ============================================================================
/ Real-time quotes with Greeks
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, strategies
optionQuote:([]
  timestamp:`timestamp$();
  contractId:`symbol$();        / Option contract ID
  bidPrice:`long$();            / Bid price (fixed-precision, .money)
  askPrice:`long$();            / Ask price (fixed-precision, .money)
  bidSize:`long$();             / Bid size (contracts, fixed-precision)
  askSize:`long$();             / Ask size (contracts, fixed-precision)
  impliedVol:`float$();         / Implied volatility (decimal, e.g., 0.25 = 25%)
  delta:`float$();              / Delta
  gamma:`float$();              / Gamma
  theta:`float$();              / Theta (per day)
  vega:`float$();               / Vega (per 1% change in vol)
  rho:`float$();                / Rho
  underlyingPrice:`long$()      / Current underlying price (fixed-precision, .money)
 );

// ============================================================================
// OPTION TRADE TABLE
// ============================================================================
/ Real-time trade ticks
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, strategies
optionTrade:([]
  timestamp:`timestamp$();
  contractId:`symbol$();        / Option contract ID
  price:`long$();               / Trade price (fixed-precision, .money)
  size:`long$();                / Trade size (contracts, fixed-precision)
  tradeExchange:`symbol$();     / Exchange code (e.g., `CBOE, `ISE)
  conditions:`symbol$()         / Trade conditions (e.g., `regular, `opening)
 );

// ============================================================================
// OPTION BAR TABLE
// ============================================================================
/ OHLCV bars for options (multiple timeframes)
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, backtesting, strategies
optionBar:([]
  timestamp:`timestamp$();      / Bar start time
  contractId:`symbol$();        / Option contract ID
  timeframe:`symbol$();         / Timeframe (e.g., `1Min, `5Min, `1Hour, `1Day)
  open:`long$();                / Open price (fixed-precision, .money)
  high:`long$();                / High price (fixed-precision, .money)
  low:`long$();                 / Low price (fixed-precision, .money)
  close:`long$();               / Close price (fixed-precision, .money)
  volume:`long$();              / Volume (contracts, fixed-precision)
  openInterest:`long$()         / Open interest (contracts)
 );

// ============================================================================
// VOLATILITY SURFACE TABLE
// ============================================================================
/ Implied volatility surface (for vol modeling and arbitrage)
/ Published by: Strategy engine or Python analytics
/ Consumed by: Strategies, risk management
volatilitySurface:([]
  timestamp:`timestamp$();
  underlying:`symbol$();        / Underlying equity symbol
  expiry:`date$();              / Option expiration date
  strike:`long$();              / Strike price (fixed-precision, .money)
  optionType:`symbol$();        / Option type (`call or `put)
  impliedVol:`float$();         / Implied volatility (decimal)
  delta:`float$();              / Delta
  moneyness:`float$();          / Moneyness (S/K for calls, K/S for puts)
  daysToExpiry:`int$()          / Days to expiration
 );

// ============================================================================
// OPTION POSITION TABLE
// ============================================================================
/ Current option positions (updated on fills)
/ Keyed by: contractId
/ Updated by: Strategy engine on fill, risk module
optionPosition:([contractId:`symbol$()]
  underlying:`symbol$();        / Underlying equity symbol
  expiry:`date$();              / Expiration date
  strike:`long$();              / Strike price (fixed-precision, .money)
  optionType:`symbol$();        / Option type (`call or `put)
  quantity:`long$();            / Position size (contracts, fixed-precision, signed)
  avgEntryPrice:`long$();       / Average entry price (fixed-precision, .money)
  marketValue:`long$();         / Current market value (fixed-precision, .money)
  unrealizedPnL:`long$();       / Unrealized P&L (fixed-precision, .money)
  delta:`float$();              / Portfolio delta
  gamma:`float$();              / Portfolio gamma
  theta:`float$();              / Portfolio theta (per day)
  vega:`float$();               / Portfolio vega
  side:`symbol$();              / Side (`long, `short, or ` for flat)
  marginUsed:`long$();          / Margin used (fixed-precision, .money)
  updatedAt:`timestamp$()       / Last update timestamp
 );

// ============================================================================
// OPTION VALIDATION
// ============================================================================

/ Validate option contract ID format (e.g., AAPL250117C00150000)
/ Format: SYMBOL + YYMMDD + C/P + STRIKE (8 digits, 3 decimals)
/ @param contractId symbol - Contract ID to validate
/ @return boolean - True if valid
isValidOptionContractId:{[contractId]
  / Null check
  if[null contractId; :0b];
  if[contractId=`; :0b];

  / Convert to string and check format
  s:string contractId;
  len:count s;

  / Minimum length: 3 (sym) + 6 (date) + 1 (type) + 8 (strike) = 18
  if[len < 18; :0b];

  / Extract components (assume 6-char date, 1-char type, 8-char strike)
  / Rest is symbol (variable length 1-5)
  strikeStart:len - 8;
  typePos:strikeStart - 1;
  dateStart:typePos - 6;
  symEnd:dateStart - 1;

  / Validate date portion (6 digits)
  datePortion:s[dateStart + til 6];
  if[not all datePortion in .Q.n; :0b];

  / Validate option type (C or P)
  optType:s[typePos];
  if[not optType in "CP"; :0b];

  / Validate strike (8 digits)
  strikePortion:s[strikeStart + til 8];
  if[not all strikePortion in .Q.n; :0b];

  / Validate symbol (1-5 uppercase letters)
  if[symEnd < 0; :0b];
  symPortion:s[til symEnd + 1];
  if[not all symPortion in .Q.A; :0b];

  1b
 };

/ Check if symbol is an option contract
/ @param sym symbol - Symbol to check
/ @return boolean - True if option
isOption:{[sym]
  isValidOptionContractId[sym]
 };

\d .

/ Export namespace
-1 "  Options schema loaded: optionContract, optionQuote, optionTrade, optionBar, volatilitySurface, optionPosition";
