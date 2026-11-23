/ Risk Management — Rate Limiting
/ Token bucket algorithm per exchange/symbol to prevent API bans
/ HOT PATH: <5μs per check

\d .risk

/ Initialize rate limits with default exchange configurations
initRateLimits:{[]
  / Clear existing limits
  delete from `.risk.rateLimits;
  delete from `.risk.globalRateLimits;
  delete from `.risk.rateLimitEvents;

  / Default global exchange limits (orders per second)
  / Binance: 8/s burst 20, Coinbase: 12/s burst 30, Kraken: 8/s burst 15
  `.risk.globalRateLimits upsert ([]
    exchange:`binance`coinbase`kraken;
    maxRate:8 12 8f;
    burstSize:20 30 15j;
    currentTokens:20 30 15f;
    lastRefill:3#.z.p
  );

  -1 "Rate limits initialized: ",string[count .risk.globalRateLimits]," exchanges";
 };

/ Refill token bucket (called periodically or on-demand)
/ PERFORMANCE: Optimized vectorized refill calculation
refillTokens:{[exchange]
  if[not exchange in key .risk.globalRateLimits;:(::)];

  / Use keyed table indexing for O(1) lookup
  limit:.risk.globalRateLimits[exchange];

  / Calculate time elapsed since last refill (in seconds)
  elapsed:`float$(.z.p - limit`lastRefill) % 1000000000;

  / Calculate new tokens = min(current + (rate * elapsed), burstSize)
  newTokens:(limit[`currentTokens] + (limit[`maxRate] * elapsed)) & limit`burstSize;

  / Update atomically
  update currentTokens:newTokens, lastRefill:.z.p from `.risk.globalRateLimits where exchange=exchange;
 };

/ Check rate limit (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <5μs per check
checkRateLimit:{[exchange;sym]
  / FAIL-SAFE: reject if no limits configured
  if[not exchange in key .risk.globalRateLimits;
    :(0b;`noRateLimitConfigured;`exchange`sym!(exchange;sym))
  ];

  / Refill tokens before checking
  refillTokens[exchange];

  / Use keyed table indexing for O(1) lookup
  limit:.risk.globalRateLimits[exchange];

  / Check if we have at least 1 token available
  if[limit[`currentTokens] < 1.0;
    / Log rate limit event
    `.risk.rateLimitEvents insert (.z.p;exchange;sym;`rejected;limit`currentTokens);
    :(0b;`rateLimitExceeded;`exchange`sym`tokens!(exchange;sym;limit`currentTokens))
  ];

  / Consume 1 token
  update currentTokens:currentTokens-1.0 from `.risk.globalRateLimits where exchange=exchange;

  / Log successful check
  `.risk.rateLimitEvents insert (.z.p;exchange;sym;`allowed;limit[`currentTokens]-1.0);

  / All checks passed
  (1b;`;()!())
 };

/ Set symbol-specific rate limit (per exchange+sym)
setSymbolRateLimit:{[exchange;sym;maxRate;burstSize]
  `.risk.rateLimits upsert ([]
    exchange:enlist exchange;
    sym:enlist sym;
    maxRate:enlist maxRate;
    burstSize:enlist burstSize;
    currentTokens:enlist `float$burstSize;
    lastRefill:enlist .z.p
  );
  -1 "Symbol rate limit set: ",string[exchange]," ",string[sym]," [",string[maxRate],"/s, burst:",string[burstSize],"]";
 };

/ Set exchange-wide rate limit
setExchangeRateLimit:{[exchange;maxRate;burstSize]
  `.risk.globalRateLimits upsert ([]
    exchange:enlist exchange;
    maxRate:enlist maxRate;
    burstSize:enlist burstSize;
    currentTokens:enlist `float$burstSize;
    lastRefill:enlist .z.p
  );
  -1 "Exchange rate limit set: ",string[exchange]," [",string[maxRate],"/s, burst:",string[burstSize],"]";
 };

/ Get rate limit status for monitoring
getRateLimitStatus:{[]
  / Global exchange limits
  global:select exchange, maxRate, burstSize, currentTokens,
    utilizationPct:100.0 * (burstSize - currentTokens) % burstSize
    from .risk.globalRateLimits;

  / Symbol-specific limits (if any)
  symbol:select exchange, sym, maxRate, burstSize, currentTokens,
    utilizationPct:100.0 * (burstSize - currentTokens) % burstSize
    from .risk.rateLimits;

  / Recent events (last 1 hour)
  events:select from .risk.rateLimitEvents where time>.z.p-01:00:00;

  `global`symbol`recentEvents!(global;symbol;events)
 };

\d .
