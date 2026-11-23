/ Position Exposure Heatmap
/ Real-time exposure grid (exchange × asset) with concentration alerts

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Exposure Tables
/ ═══════════════════════════════════════════════════════════════════

/ Exposure grid (for heatmap visualization)
exposureSnapshot:([]
  exchange:`symbol$();
  sym:`symbol$();
  grossExposure:`float$();
  netExposure:`float$();
  longExposure:`float$();
  shortExposure:`float$();
  pctOfPortfolio:`float$();
  concentration:`symbol$(); / `ok, `warn, `critical
  lastUpdate:`timestamp$()
 );

/ Beta-adjusted exposure (vs BTC)
betaAdjustedExposure:([]
  sym:`symbol$();
  notionalExposure:`float$();
  betaToBTC:`float$();
  btcEquivalent:`float$();
  lastUpdate:`timestamp$()
 );

/ Exposure summary (single-row table)
exposureSummary:([]
  totalGross:enlist 0.0;
  totalNet:enlist 0.0;
  totalLong:enlist 0.0;
  totalShort:enlist 0.0;
  lastUpdate:enlist .z.p
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

initExposureHeatmap:{[]
  / Clear tables
  delete from `.risk.exposureSnapshot;
  delete from `.risk.betaAdjustedExposure;

  / Initialize summary
  `.risk.exposureSummary set ([] totalGross:enlist 0.0; totalNet:enlist 0.0;
                                 totalLong:enlist 0.0; totalShort:enlist 0.0;
                                 lastUpdate:enlist .z.p);

  -1 "  Exposure heatmap initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Exposure Calculation
/ ═══════════════════════════════════════════════════════════════════

/ Recalc exposure grid (run on every fill/quote update)
recalcExposureGrid:{[]
  / Clear grid
  delete from `.risk.exposureSnapshot;

  / Get all positions
  positions:select from .schema.position where quantity <> 0;

  / If no positions, return
  if[0 = count positions; :()];

  / Calculate gross/net by exchange x sym
  grid:select
    grossExposure:sum abs[quantity * avgEntryPrice],
    netExposure:sum quantity * avgEntryPrice,
    longExposure:sum ?[quantity > 0; quantity * avgEntryPrice; 0.0],
    shortExposure:sum ?[quantity < 0; abs[quantity * avgEntryPrice]; 0.0]
    by exchange, sym
    from positions;

  / Calculate portfolio total
  portfolioValue:sum exec grossExposure from grid;

  / Calculate % of portfolio (guard against division by zero)
  grid:update pctOfPortfolio:?[0 = portfolioValue; 0.0; 100.0 * grossExposure % portfolioValue] from grid;

  / Determine concentration level
  warnThreshold:30.0;
  critThreshold:50.0;
  grid:update concentration:`ok from grid;
  grid:update concentration:`warn from grid where pctOfPortfolio > warnThreshold;
  grid:update concentration:`critical from grid where pctOfPortfolio > critThreshold;

  / Insert into exposureSnapshot
  grid:update lastUpdate:.z.p from grid;
  `.risk.exposureSnapshot set 0!grid;

  / Update summary
  totalGross:sum exec grossExposure from grid;
  totalNet:sum exec netExposure from grid;
  totalLong:sum exec longExposure from grid;
  totalShort:sum exec shortExposure from grid;

  .risk.exposureSummary[`totalGross]:totalGross;
  .risk.exposureSummary[`totalNet]:totalNet;
  .risk.exposureSummary[`totalLong]:totalLong;
  .risk.exposureSummary[`totalShort]:totalShort;
  .risk.exposureSummary[`lastUpdate]:.z.p;
 };

/ Calculate beta-adjusted exposure (simplified: correlation-based)
recalcBetaAdjustedExposure:{[]
  / Clear table
  delete from `.risk.betaAdjustedExposure;

  / Get all positions
  positions:select from .schema.position where quantity <> 0;

  / If no positions, return
  if[0 = count positions; :()];

  / For each position, estimate beta to BTC (simplified: hardcoded for now)
  / In production, calculate beta using historical correlation
  betaExposure:{[pos]
    sym:pos`sym;
    qty:pos`quantity;
    price:pos`avgEntryPrice;
    notional:qty * price;

    / Simplified beta lookup (in production, calculate from returns)
    / BTC = 1.0, ETH = 0.8, SOL = 0.6, others = 0.0
    betaToBTC:$[sym=`BTCUSD; 1.0;
                sym=`ETHUSD; 0.8;
                sym=`SOLUSD; 0.6;
                0.0];

    / Beta-adjusted exposure
    btcEquiv:notional * betaToBTC;

    (sym; notional; betaToBTC; btcEquiv; .z.p)
   } each positions;

  / Update table
  if[count betaExposure;
    `.risk.betaAdjustedExposure set flip `sym`notionalExposure`betaToBTC`btcEquivalent`lastUpdate!flip betaExposure;
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Query Functions (for UI)
/ ═══════════════════════════════════════════════════════════════════

/ Get exposure grid
exposure.grid:{[]
  select from .risk.exposureSnapshot
 };

/ Get gross exposure
exposure.gross:{[]
  first .risk.exposureSummary`totalGross
 };

/ Get net exposure
exposure.net:{[]
  first .risk.exposureSummary`totalNet
 };

/ Get exposure by exchange
exposure.byExchange:{[]
  select grossExposure:sum grossExposure, netExposure:sum netExposure,
         longExposure:sum longExposure, shortExposure:sum shortExposure
    by exchange from .risk.exposureSnapshot
 };

/ Get exposure by asset
exposure.byAsset:{[]
  select grossExposure:sum grossExposure, netExposure:sum netExposure,
         longExposure:sum longExposure, shortExposure:sum shortExposure
    by sym from .risk.exposureSnapshot
 };

/ Get beta-adjusted exposure
exposure.betaAdjusted:{[]
  select from .risk.betaAdjustedExposure
 };

\d .
