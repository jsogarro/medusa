/ types.q - Core type definitions and utilities for Medusa schema
/ Author: Medusa Trading System
/ Date: 2026-03-29

\d .qg

// ============================================================================
// PRECISION CONSTANTS
// ============================================================================
// Use 6 decimal places for all monetary values (matches most exchange APIs)
PRICE_PRECISION:1000000      / 10^6 for 6 decimal places
VOLUME_PRECISION:1000000     / 10^6 for 6 decimal places
FEE_PRECISION:1000000        / 10^6 for 6 decimal places

// ============================================================================
// NULL VALUE CONSTANTS
// ============================================================================
NULL_TIMESTAMP:0Np;
NULL_LONG:0Nj;
NULL_FLOAT:0Nf;
NULL_SYMBOL:`;

// ============================================================================
// TYPE CONVERSION UTILITIES
// ============================================================================

// Convert float to fixed-precision long
// Usage: .qg.toFixed[123.456789; .qg.PRICE_PRECISION]
// Returns: 123456789j (long)
toFixed:{[value; precision]
  "j"$value * precision
 };

// Convert fixed-precision long to float
// Usage: .qg.fromFixed[123456789j; .qg.PRICE_PRECISION]
// Returns: 123.456789
fromFixed:{[value; precision]
  value % precision
 };

// Convert price float to fixed long
toPrice:{.qg.toFixed[x; .qg.PRICE_PRECISION]};

// Convert price long to float
fromPrice:{.qg.fromFixed[x; .qg.PRICE_PRECISION]};

// Convert volume float to fixed long
toVolume:{.qg.toFixed[x; .qg.VOLUME_PRECISION]};

// Convert volume long to float
fromVolume:{.qg.fromFixed[x; .qg.VOLUME_PRECISION]};

// Convert fee float to fixed long
toFee:{.qg.toFixed[x; .qg.FEE_PRECISION]};

// Convert fee long to float
fromFee:{.qg.fromFixed[x; .qg.FEE_PRECISION]};

// ============================================================================
// ENUMERATION DEFINITIONS
// ============================================================================

// Order status enumeration
ORDER_STATUS:`pending`open`filled`cancelled`partially_filled`rejected`expired;

// Order type enumeration
ORDER_TYPE:`market`limit`stop_loss`stop_limit`trailing_stop;

// Trade type enumeration
TRADE_TYPE:`buy`sell;

// Currency symbols (extend as needed)
CURRENCIES:`USD`EUR`GBP`BTC`ETH`USDT`USDC`SOL`DOGE`XRP`ADA`DOT`AVAX`MATIC;

// Exchange names (extend as needed)
EXCHANGES:`coinbase`kraken`binance`bitstamp`gemini`ftx`okx`bybit`huobi;

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

// Validate order status
isValidOrderStatus:{x in .qg.ORDER_STATUS};

// Validate order type
isValidOrderType:{x in .qg.ORDER_TYPE};

// Validate trade type
isValidTradeType:{x in .qg.TRADE_TYPE};

// Validate currency
isValidCurrency:{x in .qg.CURRENCIES};

// Validate exchange
isValidExchange:{x in .qg.EXCHANGES};

// Validate positive amount
isPositiveAmount:{x > 0j};

// Validate price (must be positive)
isValidPrice:{x > 0j};

// ============================================================================
// ID GENERATOR (AUTO-INCREMENT SEQUENCES)
// ============================================================================

/ Initialize ID generator dictionary
idgen:`order`trade`transaction`position`target`datum`flag!7#0j;

/ Get next ID for entity
/ Usage: .qg.nextId[`order]
nextId:{[entity]
  if[not entity in key .qg.idgen;
    '"Unknown entity for ID generation: ",string entity
  ];
  .qg.idgen[entity]+:1;
  .qg.idgen[entity]
 };

// ============================================================================
// COMPOSITE VALIDATION HELPERS
// ============================================================================

/ Validate exchange, currency, and amount in one call
validateExchangeCurrencyAmount:{[ex;cur;amt]
  if[not isValidExchange[ex]; '"Invalid exchange: ",string ex];
  if[not isValidCurrency[cur]; '"Invalid currency: ",string cur];
  if[not isPositiveAmount[amt]; '"Amount must be positive"];
 };

/ Validate exchange and two currencies
validateExchangeTwoCurrencies:{[ex;cur1;cur2]
  if[not isValidExchange[ex]; '"Invalid exchange: ",string ex];
  if[not isValidCurrency[cur1]; '"Invalid currency: ",string cur1];
  if[not isValidCurrency[cur2]; '"Invalid currency: ",string cur2];
 };

\d .

/ Export namespace
-1 "  Types loaded: .qg namespace with precision constants and validation functions";
