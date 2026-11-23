/ Risk Management — Market Impact Estimation
/ Real-time orderbook depth analysis to prevent excessive slippage
/ Performance: <50μs per check

\d .risk

/ Initialize market impact limits with default thresholds
initMarketImpact:{[]
  / Clear existing limits
  delete from `.risk.impactLimits;
  delete from `.risk.orderbook;
  delete from `.risk.impactEvents;

  / Default market impact thresholds (% of available book depth)
  / BTC/ETH: warn at 5%, reject at 10%
  / Alts: warn at 3%, reject at 8%
  `.risk.impactLimits set 2!flip `exchange`sym`warnPct`rejectPct`lastCheck!(
    `binance`binance`coinbase`coinbase;
    `BTCUSD`ETHUSD`BTCUSD`ETHUSD;
    5 5 5 5f;
    10 10 10 10f;
    .z.p .z.p .z.p .z.p
  );

  / Initialize orderbook snapshot table (populated from TP updates)
  / This will be updated via .u.upd from the tickerplant
  `.risk.orderbook set ([]
    time:`timestamp$();
    exchange:`symbol$();
    sym:`symbol$();
    side:`symbol$();
    price:`float$();
    size:`float$();
    level:`int$()
  );

  -1 "Market impact limits initialized: ",string[count .risk.impactLimits]," exchange-symbol pairs";
 };

/ Calculate available book depth for a given size
/ Helper function (not part of hot path)
calcBookDepth:{[exchange;sym;side;targetSize]
  / Get orderbook snapshot for this exchange/sym
  / side: `buy means we're buying (lift asks), `sell means we're selling (hit bids)
  bookSide:$[side=`buy;`ask;`bid];

  / Get sorted book levels
  book:select from .risk.orderbook where exchange=exchange, sym=sym, side=bookSide;

  / If no book data, return null
  if[0 = count book; :0n];

  / Sort by price (bids descending, asks ascending)
  book:$[bookSide=`bid;
    `price xdesc book;
    `price xasc book
  ];

  / Accumulate size until we reach targetSize
  cumSize:sums exec size from book;
  availableDepth:sum exec size from book where cumSize <= targetSize;

  / Guard against division by zero
  if[targetSize = 0; :0n];

  / Return available depth as % of target
  100.0 * availableDepth % targetSize
 };

/ Check market impact (pre-trade)
/ Returns: (pass:boolean; reason:symbol; detail:dictionary)
/ HOT PATH: <50μs per check
checkMarketImpact:{[exchange;sym;side;qty;price]
  / FAIL-SAFE: if no limits configured, default to warning at 5%, reject at 10%
  limits:$[
    (exchange;sym) in key .risk.impactLimits;
    .risk.impactLimits[(exchange;sym)];
    `warnPct`rejectPct!(5.0;10.0)
  ];

  / Calculate available book depth
  depthPct:calcBookDepth[exchange;sym;side;qty];

  / If no orderbook data available, log warning but allow order
  if[null depthPct;
    .risk.logRiskEvent[.z.p;`marketImpactNoData;`;sym;exchange;`qty`price!(qty;price);`warn;`warning];
    :(1b;`;()!())
  ];

  / Calculate impact percentage (inverse of depth)
  / If we can fill 100% from the book, impact is 0%
  / If we can fill 50% from the book, impact is 50%
  impactPct:100.0 - depthPct;

  / Log event
  `.risk.impactEvents insert (.z.p;exchange;sym;side;qty;price;depthPct;impactPct);

  / Check against reject threshold
  if[impactPct > limits`rejectPct;
    .risk.logRiskEvent[.z.p;`marketImpactReject;`;sym;exchange;`qty`price`impact`threshold!(qty;price;impactPct;limits`rejectPct);`reject;`critical];
    :(0b;`marketImpactTooHigh;`exchange`sym`impact`threshold!(exchange;sym;impactPct;limits`rejectPct))
  ];

  / Check against warn threshold
  if[impactPct > limits`warnPct;
    .risk.logRiskEvent[.z.p;`marketImpactWarn;`;sym;exchange;`qty`price`impact`threshold!(qty;price;impactPct;limits`warnPct);`warn;`warning];
    / Allow but warn
  ];

  / All checks passed
  (1b;`;()!())
 };

/ Set market impact limit for exchange+symbol
setMarketImpactLimit:{[exchange;sym;warnPct;rejectPct]
  `.risk.impactLimits upsert ([]
    exchange:enlist exchange;
    sym:enlist sym;
    warnPct:enlist warnPct;
    rejectPct:enlist rejectPct;
    lastCheck:enlist .z.p
  );
  -1 "Market impact limit set: ",string[exchange]," ",string[sym]," [warn:",string[warnPct],"%, reject:",string[rejectPct],"%]";
 };

/ Get book liquidity for a symbol (monitoring/debugging)
getBookLiquidity:{[exchange;sym]
  bidBook:select from .risk.orderbook where exchange=exchange, sym=sym, side=`bid;
  askBook:select from .risk.orderbook where exchange=exchange, sym=sym, side=`ask;

  `bid`ask`bidDepth`askDepth`bidLevels`askLevels!(
    bidBook;
    askBook;
    sum exec size from bidBook;
    sum exec size from askBook;
    count bidBook;
    count askBook
  )
 };

\d .
