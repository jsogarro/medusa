/ ============================================================================
/ marketHours.q - Market Hours Risk Check
/ ============================================================================
/ // Provides:
/   - Pre-trade market hours validation for equity orders
/   - Integration with exchange calendar
/   - Bypass for crypto (24/7 markets)
/ // Dependencies:
/   - .exchange.calendar (market hours functions)
/   - .qg.isEquity (asset class detection)
/ // Functions:
/   - checkMarketHours: Validate market is open for equity orders
/ ============================================================================

\d .risk

/ Check market hours (equity only)
/ @param exchange symbol - Exchange name
/ @param sym symbol - Trading symbol
/ @return (boolean; reason) - (pass; reason for failure)
checkMarketHours:{[exchange;sym]
  / Skip check for crypto exchanges (24/7 markets)
  if[not exchange=`alpaca; :(1b;`)];

  / Skip check for crypto symbols (even on Alpaca)
  if[.schema.isCrypto[sym]; :(1b;`)];

  / For equity symbols, check if market is open
  if[.schema.isEquity[sym];
    / Check if regular market hours
    if[.exchange.calendar.isMarketOpen[];
      :(1b;`)
    ];

    / Market is closed - return failure
    :(0b;`marketClosed)
  ];

  / Default: allow (unknown asset class)
  (1b;`)
 };

\d .

/ Export namespace
-1 "  Market hours check loaded: .risk.checkMarketHours";
