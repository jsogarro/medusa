/ ============================================================================
/ equity.q - Equity Market Data Schema
/ ============================================================================
/ /
/ Provides:
/   - Equity-specific table schemas (quotes, trades, bars, metadata, positions)
/   - Fixed-precision monetary types (.money namespace)
/   - Equity symbol validation
/ /
/ Asset Class: US Equities (stocks, ETFs)
/ Data Provider: Alpaca Markets
/ /
/ Tables:
/   - equityQuote: Real-time equity quotes (bid/ask)
/   - equityTrade: Equity trade ticks
/   - equityBar: OHLCV bars (multiple timeframes)
/   - equityMetadata: Company/ETF metadata
/   - equityPosition: Equity positions by symbol
/ /
/ Precision: All prices use .money fixed-precision (6 decimal places)
/ ============================================================================

\d .schema

// ============================================================================
// EQUITY QUOTE TABLE
// ============================================================================
/ Real-time quotes (bid/ask spreads)
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, strategies
equityQuote:([]
  timestamp:`timestamp$();
  sym:`symbol$();           / Equity symbol (e.g., `AAPL)
  bidPrice:`long$();        / Bid price (fixed-precision, .money)
  askPrice:`long$();        / Ask price (fixed-precision, .money)
  bidSize:`long$();         / Bid size (shares, fixed-precision)
  askSize:`long$();         / Ask size (shares, fixed-precision)
  tape:`symbol$();          / Tape (A=NYSE, B=NYSE Arca, C=Nasdaq)
  conditions:`symbol$()     / Quote conditions (e.g., `regular, `slow, `fast)
 );

// ============================================================================
// EQUITY TRADE TABLE
// ============================================================================
/ Real-time trade ticks
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, strategies
equityTrade:([]
  timestamp:`timestamp$();
  sym:`symbol$();           / Equity symbol
  price:`long$();           / Trade price (fixed-precision, .money)
  size:`long$();            / Trade size (shares, fixed-precision)
  tradeExchange:`symbol$(); / Exchange code (e.g., `NYSE, `NASDAQ)
  tape:`symbol$();          / Tape (A/B/C)
  conditions:`symbol$()     / Trade conditions (e.g., `regular, `odd_lot)
 );

// ============================================================================
// EQUITY BAR TABLE
// ============================================================================
/ OHLCV bars (multiple timeframes)
/ Published by: Rust Alpaca subscriber → Tickerplant
/ Consumed by: RDB, HDB, backtesting, strategies
equityBar:([]
  timestamp:`timestamp$();  / Bar start time
  sym:`symbol$();           / Equity symbol
  timeframe:`symbol$();     / Timeframe (e.g., `1Min, `5Min, `1Hour, `1Day)
  open:`long$();            / Open price (fixed-precision, .money)
  high:`long$();            / High price (fixed-precision, .money)
  low:`long$();             / Low price (fixed-precision, .money)
  close:`long$();           / Close price (fixed-precision, .money)
  volume:`long$();          / Volume (shares, fixed-precision)
  vwap:`long$();            / Volume-weighted average price (fixed-precision, .money)
  tradeCount:`long$()       / Number of trades in bar
 );

// ============================================================================
// EQUITY METADATA TABLE
// ============================================================================
/ Company/ETF metadata (semi-static reference data)
/ Published by: Python loader (one-time or daily refresh)
/ Consumed by: Risk management, strategy filters
equityMetadata:([]
  sym:`symbol$();           / Equity symbol
  name:`symbol$();          / Company name
  assetClass:`symbol$();    / Asset class (`stock or `etf)
  exchange:`symbol$();      / Primary exchange (e.g., `NYSE, `NASDAQ)
  sector:`symbol$();        / Sector (e.g., `Technology, `Healthcare)
  industry:`symbol$();      / Industry (e.g., `Software, `Biotechnology)
  marketCap:`long$();       / Market capitalization (USD, fixed-precision)
  dividendYield:`float$();  / Dividend yield (percent)
  peRatio:`float$();        / Price-to-earnings ratio
  beta:`float$();           / Beta (volatility vs market)
  avgVolume30d:`long$();    / 30-day average volume (shares)
  updatedAt:`timestamp$()   / Last metadata update
 );

// ============================================================================
// EQUITY POSITION TABLE
// ============================================================================
/ Current equity positions (updated on fills)
/ Keyed by: sym
/ Updated by: Strategy engine on fill, risk module
equityPosition:([sym:`symbol$()]
  quantity:`long$();        / Position size (shares, fixed-precision, signed)
  avgEntryPrice:`long$();   / Average entry price (fixed-precision, .money)
  marketValue:`long$();     / Current market value (fixed-precision, .money)
  unrealizedPnL:`long$();   / Unrealized P&L (fixed-precision, .money)
  side:`symbol$();          / Side (`long, `short, or ` for flat)
  marginUsed:`long$();      / Margin used (fixed-precision, .money, for short positions)
  updatedAt:`timestamp$()   / Last update timestamp
 );

// ============================================================================
// EQUITY SYMBOL VALIDATION
// ============================================================================

/ Validate equity symbol format (1-5 uppercase letters)
/ @param sym symbol - Symbol to validate
/ @return boolean - True if valid equity symbol
isValidEquitySymbol:{[sym]
  / Null check
  if[null sym; :0b];
  if[sym=`; :0b];

  / Convert to string and check format
  s:string sym;
  len:count s;

  / Length check (1-5 characters for US equities)
  if[(len < 1) or (len > 5); :0b];

  / All uppercase letters check
  all s in .Q.A
 };

/ Check if symbol is equity (vs crypto)
/ @param sym symbol - Symbol to check
/ @return boolean - True if equity
isEquity:{[sym]
  isValidEquitySymbol[sym]
 };

/ Check if symbol is crypto (vs equity)
/ @param sym symbol - Symbol to check
/ @return boolean - True if crypto (pair format like BTCUSD)
isCrypto:{[sym]
  / Null check
  if[null sym; :0b];
  if[sym=`; :0b];

  / Crypto pairs are 6-8 characters (e.g., BTCUSD, ETHUSD)
  s:string sym;
  len:count s;
  (len >= 6) and (len <= 8) and all s in .Q.A
 };

\d .

/ Export namespace
-1 "  Equity schema loaded: equityQuote, equityTrade, equityBar, equityMetadata, equityPosition";
