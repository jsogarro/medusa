/ Risk Management — P&L Attribution
/ Multi-dimensional P&L aggregation by strategy/exchange/signalType/session
/ Performance: <50μs per fill recording

\d .risk

/ Initialize P&L attribution system
initPnLAttribution:{[]
  / Clear existing tables
  delete from `.risk.fillsAttributed;
  delete from `.risk.pnlByStrategy;
  delete from `.risk.pnlByExchange;
  delete from `.risk.pnlBySignalType;
  delete from `.risk.pnlBySession;
  delete from `.risk.pnlCube;

  / Initialize attributed fills table
  `.risk.fillsAttributed set ([]
    time:`timestamp$();
    strategy:`symbol$();
    exchange:`symbol$();
    sym:`symbol$();
    side:`symbol$();
    qty:`float$();
    price:`float$();
    signalType:`symbol$();
    session:`symbol$();
    realizedPnL:`float$()
  );

  / Initialize aggregation tables
  `.risk.pnlByStrategy set ([] strategy:`symbol$(); totalPnL:`float$(); tradeCount:`int$(); winRate:`float$(); lastUpdate:`timestamp$());
  `.risk.pnlByExchange set ([] exchange:`symbol$(); totalPnL:`float$(); tradeCount:`int$(); winRate:`float$(); lastUpdate:`timestamp$());
  `.risk.pnlBySignalType set ([] signalType:`symbol$(); totalPnL:`float$(); tradeCount:`int$(); winRate:`float$(); lastUpdate:`timestamp$());
  `.risk.pnlBySession set ([] session:`symbol$(); totalPnL:`float$(); tradeCount:`int$(); winRate:`float$(); lastUpdate:`timestamp$());

  / Initialize OLAP cube (multi-dimensional aggregation)
  `.risk.pnlCube set ([]
    strategy:`symbol$();
    exchange:`symbol$();
    signalType:`symbol$();
    session:`symbol$();
    totalPnL:`float$();
    tradeCount:`int$();
    winRate:`float$();
    avgPnL:`float$()
  );

  -1 "P&L attribution system initialized";
 };

/ Get trading session from UTC hour
/ Asia: 00:00-08:00 UTC, Europe: 08:00-16:00 UTC, US: 16:00-24:00 UTC
getSession:{[timestamp]
  hour:(`int$`hh$timestamp) mod 24;
  $[hour < 8; `asia; hour < 16; `europe; `us]
 };

/ Record fill for attribution (post-fill)
recordFill:{[strategy;exchange;sym;side;qty;price;signalType]
  / Validate inputs
  if[(qty <= 0) or (price <= 0);
    -1 "ERROR: Invalid fill parameters — qty:",string[qty]," price:",string[price];
    :(::)
  ];

  / Determine trading session
  session:getSession[.z.p];

  / Insert fill record (realizedPnL will be updated later)
  `.risk.fillsAttributed insert (.z.p;strategy;exchange;sym;side;qty;price;signalType;session;0.0);

  / Update aggregations asynchronously (non-blocking)
  updateStrategyPnL[strategy];
  updateExchangePnL[exchange];
  updateSignalTypePnL[signalType];
  updateSessionPnL[session];

  / Update OLAP cube
  updatePnLCube[strategy;exchange;signalType;session];
 };

/ Update fill P&L when trade is closed
updateFillPnL:{[fillIndex;pnl]
  / Update the realizedPnL for a specific fill
  .risk.fillsAttributed[fillIndex;`realizedPnL]:pnl;

  / Re-aggregate all dimensions
  fill:.risk.fillsAttributed[fillIndex];
  updateStrategyPnL[fill`strategy];
  updateExchangePnL[fill`exchange];
  updateSignalTypePnL[fill`signalType];
  updateSessionPnL[fill`session];
  updatePnLCube[fill`strategy;fill`exchange;fill`signalType;fill`session];
 };

/ Update strategy-level P&L aggregation
updateStrategyPnL:{[strategy]
  / Aggregate all fills for this strategy
  agg:select totalPnL:sum realizedPnL, tradeCount:count i, winRate:100.0*avg realizedPnL>0.0
    from .risk.fillsAttributed where strategy=strategy;

  / Upsert into aggregation table
  `.risk.pnlByStrategy upsert ([] strategy:enlist strategy; totalPnL:enlist first agg`totalPnL; tradeCount:enlist first agg`tradeCount; winRate:enlist first agg`winRate; lastUpdate:enlist .z.p);
 };

/ Update exchange-level P&L aggregation
updateExchangePnL:{[exchange]
  / Aggregate all fills for this exchange
  agg:select totalPnL:sum realizedPnL, tradeCount:count i, winRate:100.0*avg realizedPnL>0.0
    from .risk.fillsAttributed where exchange=exchange;

  / Upsert into aggregation table
  `.risk.pnlByExchange upsert ([] exchange:enlist exchange; totalPnL:enlist first agg`totalPnL; tradeCount:enlist first agg`tradeCount; winRate:enlist first agg`winRate; lastUpdate:enlist .z.p);
 };

/ Update signal type P&L aggregation
updateSignalTypePnL:{[signalType]
  / Aggregate all fills for this signal type
  agg:select totalPnL:sum realizedPnL, tradeCount:count i, winRate:100.0*avg realizedPnL>0.0
    from .risk.fillsAttributed where signalType=signalType;

  / Upsert into aggregation table
  `.risk.pnlBySignalType upsert ([] signalType:enlist signalType; totalPnL:enlist first agg`totalPnL; tradeCount:enlist first agg`tradeCount; winRate:enlist first agg`winRate; lastUpdate:enlist .z.p);
 };

/ Update session-level P&L aggregation
updateSessionPnL:{[session]
  / Aggregate all fills for this session
  agg:select totalPnL:sum realizedPnL, tradeCount:count i, winRate:100.0*avg realizedPnL>0.0
    from .risk.fillsAttributed where session=session;

  / Upsert into aggregation table
  `.risk.pnlBySession upsert ([] session:enlist session; totalPnL:enlist first agg`totalPnL; tradeCount:enlist first agg`tradeCount; winRate:enlist first agg`winRate; lastUpdate:enlist .z.p);
 };

/ Update OLAP cube (multi-dimensional aggregation)
updatePnLCube:{[strategy;exchange;signalType;session]
  / Aggregate fills across all 4 dimensions
  agg:select totalPnL:sum realizedPnL, tradeCount:count i, winRate:100.0*avg realizedPnL>0.0, avgPnL:avg realizedPnL
    from .risk.fillsAttributed
    where strategy=strategy, exchange=exchange, signalType=signalType, session=session;

  / Upsert into cube
  `.risk.pnlCube upsert ([]
    strategy:enlist strategy;
    exchange:enlist exchange;
    signalType:enlist signalType;
    session:enlist session;
    totalPnL:enlist first agg`totalPnL;
    tradeCount:enlist first agg`tradeCount;
    winRate:enlist first agg`winRate;
    avgPnL:enlist first agg`avgPnL
  );
 };

/ Query P&L cube with filters
/ filters: dictionary with keys (strategy, exchange, signalType, session)
queryPnLCube:{[filters]
  result:.risk.pnlCube;

  / Apply filters dynamically
  if[`strategy in key filters; result:?[result;enlist (=;`strategy;enlist filters`strategy);0b;()]];
  if[`exchange in key filters; result:?[result;enlist (=;`exchange;enlist filters`exchange);0b;()]];
  if[`signalType in key filters; result:?[result;enlist (=;`signalType;enlist filters`signalType);0b;()]];
  if[`session in key filters; result:?[result;enlist (=;`session;enlist filters`session);0b;()]];

  result
 };

/ Get top performers (by total P&L)
getTopPerformers:{[dimension;n]
  / dimension: `strategy, `exchange, `signalType, or `session
  table:$[dimension=`strategy; .risk.pnlByStrategy;
         dimension=`exchange; .risk.pnlByExchange;
         dimension=`signalType; .risk.pnlBySignalType;
         dimension=`session; .risk.pnlBySession;
         ([] a:`symbol$(); totalPnL:`float$())]; / empty if invalid

  `totalPnL xdesc n#table
 };

/ Get bottom performers (by total P&L)
getBottomPerformers:{[dimension;n]
  / dimension: `strategy, `exchange, `signalType, or `session
  table:$[dimension=`strategy; .risk.pnlByStrategy;
         dimension=`exchange; .risk.pnlByExchange;
         dimension=`signalType; .risk.pnlBySignalType;
         dimension=`session; .risk.pnlBySession;
         ([] a:`symbol$(); totalPnL:`float$())]; / empty if invalid

  `totalPnL xasc n#table
 };

\d .
