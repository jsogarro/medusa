/ Risk Management — Schema and State Tables
/ All risk state lives in-memory (not persisted to HDB)

\d .risk

/ Position limits (per strategy and global)
positionLimits: ([strategy: `symbol$(); sym: `symbol$()]
  maxLongQty: `long$();
  maxShortQty: `long$();
  currentPosition: `long$()
 );

/ Global position limits (across all strategies)
globalPositionLimits: ([sym: `symbol$()]
  maxLongQty: `long$();
  maxShortQty: `long$();
  currentPosition: `long$()
 );

/ Order size limits (per strategy)
orderSizeLimits: ([strategy: `symbol$()]
  minOrderQty: `long$();
  maxOrderQty: `long$();
  maxDailyVolume: `long$();
  dailyVolume: `long$();
  lastResetDate: `date$()
 );

/ Global order size limits — single-row table
globalOrderSizeLimits: ([]
  minOrderQty: enlist 0Nj;
  maxOrderQty: enlist 0Nj;
  maxDailyVolume: enlist 0Nj;
  dailyVolume: enlist 0j;
  lastResetDate: enlist .z.d
 );

/ Exposure limits (per exchange)
exposureLimits: ([exchange: `symbol$()]
  maxNotional: `float$();
  currentNotional: `float$()
 );

/ Global exposure limit — single-row table
globalExposureLimit: ([]
  maxNotional: enlist 0.0;  / FIXED: Should be 0.0 (float zero) not 0n (null)
  currentNotional: enlist 0.0
 );

/ Drawdown monitoring state — single-row table
drawdownState: ([]
  peakPnL: enlist 0.0;
  currentPnL: enlist 0.0;
  currentDrawdown: enlist 0.0;
  maxDrawdown: enlist 0.0;
  drawdownPct: enlist 0.0;
  maxDrawdownPct: enlist 0.2;
  breached: enlist 0b;
  lastUpdate: enlist .z.p
 );

/ Emergency stop state — single-row table
emergencyStopState: ([]
  active: enlist 0b;
  activatedBy: enlist `;
  activatedAt: enlist 0Np;
  reason: enlist `
 );

/ Risk event log (append-only)
/ NOTE: details column is generic list to hold dictionaries
riskEvents: flip `time`eventType`strategy`sym`exchange`details`action`severity!
  (`timestamp$();`symbol$();`symbol$();`symbol$();`symbol$();();`symbol$();`symbol$());

/ ═══════════════════════════════════════════════════════════════════
/ Rate Limiting Tables
/ ═══════════════════════════════════════════════════════════════════

/ Per-symbol rate limits (keyed by exchange+sym)
rateLimits: ([exchange:`symbol$(); sym:`symbol$()]
  maxRate:`float$();
  burstSize:`long$();
  currentTokens:`float$();
  lastRefill:`timestamp$()
 );

/ Global exchange rate limits (keyed by exchange)
globalRateLimits: ([exchange:`symbol$()]
  maxRate:`float$();
  burstSize:`long$();
  currentTokens:`float$();
  lastRefill:`timestamp$()
 );

/ Rate limit event log
rateLimitEvents: ([]
  time:`timestamp$();
  exchange:`symbol$();
  sym:`symbol$();
  action:`symbol$(); / `allowed or `rejected
  tokensRemaining:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Correlation Limits Tables
/ ═══════════════════════════════════════════════════════════════════

/ Correlation groups (keyed by groupId)
correlationGroups: ([groupId:`symbol$()]
  members:(); / list of symbols
  maxExposure:`float$();
  currentExposure:`float$();
  lastUpdate:`timestamp$()
 );

/ Correlation matrix (pairwise correlations)
correlationMatrix: ([]
  sym1:`symbol$();
  sym2:`symbol$();
  correlation:`float$();
  lastUpdate:`timestamp$()
 );

/ Correlation event log
correlationEvents: ([]
  time:`timestamp$();
  groupId:`symbol$();
  sym:`symbol$();
  action:`symbol$();
  currentExposure:`float$();
  addedExposure:`float$();
  newExposure:`float$();
  maxExposure:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Concentration Limits Tables
/ ═══════════════════════════════════════════════════════════════════

/ Exchange concentration limits (keyed by exchange)
exchangeConcentration: ([exchange:`symbol$()]
  maxPct:`float$();
  currentValue:`float$();
  currentPct:`float$();
  tier:`int$()
 );

/ Asset concentration limits (keyed by sym)
assetConcentration: ([sym:`symbol$()]
  maxPct:`float$();
  currentValue:`float$();
  currentPct:`float$()
 );

/ Portfolio total value (single-row table)
portfolioValue: ([]
  totalValue:enlist 0.0;
  lastUpdate:enlist .z.p
 );

/ Concentration event log
concentrationEvents: ([]
  time:`timestamp$();
  dimensionType:`symbol$(); / `exchange or `asset
  exchange:`symbol$();
  sym:`symbol$();
  action:`symbol$();
  currentPct:`float$();
  newPct:`float$();
  maxPct:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Market Impact Tables
/ ═══════════════════════════════════════════════════════════════════

/ Market impact limits (keyed by exchange+sym)
impactLimits: ([exchange:`symbol$(); sym:`symbol$()]
  warnPct:`float$();
  rejectPct:`float$();
  lastCheck:`timestamp$()
 );

/ Orderbook snapshot (updated from TP)
orderbook: ([]
  time:`timestamp$();
  exchange:`symbol$();
  sym:`symbol$();
  side:`symbol$(); / `bid or `ask
  price:`float$();
  size:`float$();
  level:`int$()
 );

/ Market impact event log
impactEvents: ([]
  time:`timestamp$();
  exchange:`symbol$();
  sym:`symbol$();
  side:`symbol$();
  qty:`float$();
  price:`float$();
  depthPct:`float$();
  impactPct:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Circuit Breaker Tables
/ ═══════════════════════════════════════════════════════════════════

/ Circuit breaker configuration (keyed by strategy)
circuitBreakerConfig: ([strategy:`symbol$()]
  consecutiveLossThreshold:`int$();
  basePauseDuration:`int$(); / seconds
  maxPauseDuration:`int$()  / seconds
 );

/ Circuit breaker state (keyed by strategy)
circuitBreakerState: ([strategy:`symbol$()]
  consecutiveLosses:`int$();
  breachCount:`int$();
  active:`boolean$();
  pausedUntil:`timestamp$();
  lastTradeResult:`symbol$();
  lastUpdate:`timestamp$()
 );

/ Global circuit breaker (single-row table)
globalCircuitBreaker: ([]
  active:enlist 0b;
  strategyBreachThreshold:enlist 10i;
  currentBreaches:enlist 0i;
  pausedUntil:enlist 0Np;
  lastUpdate:enlist .z.p
 );

/ Circuit breaker event log
circuitBreakerEvents: ([]
  time:`timestamp$();
  strategy:`symbol$();
  tradeResult:`symbol$();
  consecutiveLosses:`int$();
  breached:`boolean$();
  pnl:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ P&L Attribution Tables
/ ═══════════════════════════════════════════════════════════════════

/ Attributed fills (append-only)
fillsAttributed: ([]
  time:`timestamp$();
  strategy:`symbol$();
  exchange:`symbol$();
  sym:`symbol$();
  side:`symbol$();
  qty:`float$();
  price:`float$();
  signalType:`symbol$();
  session:`symbol$(); / `asia, `europe, `us
  realizedPnL:`float$()
 );

/ P&L by strategy
pnlByStrategy: ([]
  strategy:`symbol$();
  totalPnL:`float$();
  tradeCount:`int$();
  winRate:`float$();
  lastUpdate:`timestamp$()
 );

/ P&L by exchange
pnlByExchange: ([]
  exchange:`symbol$();
  totalPnL:`float$();
  tradeCount:`int$();
  winRate:`float$();
  lastUpdate:`timestamp$()
 );

/ P&L by signal type
pnlBySignalType: ([]
  signalType:`symbol$();
  totalPnL:`float$();
  tradeCount:`int$();
  winRate:`float$();
  lastUpdate:`timestamp$()
 );

/ P&L by session
pnlBySession: ([]
  session:`symbol$();
  totalPnL:`float$();
  tradeCount:`int$();
  winRate:`float$();
  lastUpdate:`timestamp$()
 );

/ OLAP cube (multi-dimensional aggregation)
pnlCube: ([]
  strategy:`symbol$();
  exchange:`symbol$();
  signalType:`symbol$();
  session:`symbol$();
  totalPnL:`float$();
  tradeCount:`int$();
  winRate:`float$();
  avgPnL:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialize risk management system with defaults
/ ═══════════════════════════════════════════════════════════════════
init:{[]
  / Clear per-strategy/per-exchange keyed tables
  delete from `.risk.positionLimits;
  delete from `.risk.orderSizeLimits;
  delete from `.risk.exposureLimits;

  / IDEMPOTENT: Clear global position limits before setting defaults
  delete from `.risk.globalPositionLimits;

  / Set default global position limits
  `.risk.globalPositionLimits upsert ([] sym:`BTCUSD`ETHUSD; maxLongQty:10 50j; maxShortQty:10 50j; currentPosition:0 0j);

  / Set default global order size limits
  .risk.globalOrderSizeLimits[`minOrderQty]:1j;
  .risk.globalOrderSizeLimits[`maxOrderQty]:1000j;
  .risk.globalOrderSizeLimits[`maxDailyVolume]:100000j;
  .risk.globalOrderSizeLimits[`dailyVolume]:0j;
  .risk.globalOrderSizeLimits[`lastResetDate]:.z.d;

  / Set default global exposure limit
  .risk.globalExposureLimit[`maxNotional]:1000000.0;
  .risk.globalExposureLimit[`currentNotional]:0.0;

  / Set default drawdown state
  .risk.drawdownState[`peakPnL]:0.0;
  .risk.drawdownState[`currentPnL]:0.0;
  .risk.drawdownState[`currentDrawdown]:0.0;
  .risk.drawdownState[`maxDrawdown]:0.0;
  .risk.drawdownState[`drawdownPct]:0.0;
  .risk.drawdownState[`maxDrawdownPct]:0.2;
  .risk.drawdownState[`breached]:0b;
  .risk.drawdownState[`lastUpdate]:.z.p;

  / Set default emergency stop state
  .risk.emergencyStopState[`active]:0b;
  .risk.emergencyStopState[`activatedBy]:`;
  .risk.emergencyStopState[`activatedAt]:0Np;
  .risk.emergencyStopState[`reason]:`;

  / Clear risk events (delete all rows)
  delete from `.risk.riskEvents;

  / Initialize advanced risk controls (if loaded)
  if[not ()~key `.risk.initRateLimits; initRateLimits[]];
  if[not ()~key `.risk.initCorrelationGroups; initCorrelationGroups[]];
  if[not ()~key `.risk.initConcentrationLimits; initConcentrationLimits[]];
  if[not ()~key `.risk.initMarketImpact; initMarketImpact[]];
  if[not ()~key `.risk.initCircuitBreakers; initCircuitBreakers[]];
  if[not ()~key `.risk.initPnLAttribution; initPnLAttribution[]];

  / Initialize intraday risk modules (if loaded)
  if[not ()~key `.risk.initRealtimePnL; initRealtimePnL[]];
  if[not ()~key `.risk.initExposureHeatmap; initExposureHeatmap[]];
  if[not ()~key `.risk.initOrderFlowRisk; initOrderFlowRisk[]];
  if[not ()~key `.risk.initAlertEngine; initAlertEngine[]];
  if[not ()~key `.risk.initRiskSnapshot; initRiskSnapshot[]];

  / Initialize Phase 3: Alpaca equity regulations (if loaded)
  if[not ()~key `.risk.initPDT; initPDT[]];
  if[not ()~key `.risk.initMargin; initMargin[]];
  if[not ()~key `.risk.initSettlement; initSettlement[]];

  -1 "Risk management system initialized";
 };

\d .
