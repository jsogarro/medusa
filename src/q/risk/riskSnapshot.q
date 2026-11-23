/ Risk Snapshot & Replay (Time Travel)
/ Capture risk state every 1s for forensics and replay

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Snapshot Tables
/ ═══════════════════════════════════════════════════════════════════

/ Risk snapshots (stored every 1 second)
/ NOTE: In production, this should be partitioned in HDB
riskSnapshots:([]
  time:`timestamp$();
  totalPnL:`float$();
  realizedPnL:`float$();
  unrealizedPnL:`float$();
  grossExposure:`float$();
  netExposure:`float$();
  ordersPerSec:`float$();
  rejectionRate:`float$();
  emergencyStopActive:`boolean$()
 );

/ Trade impact log (what did each trade change?)
tradeImpactLog:([]
  time:`timestamp$();
  tradeId:`long$();
  sym:`symbol$();
  side:`symbol$();
  qty:`float$();
  price:`float$();
  beforePnL:`float$();
  afterPnL:`float$();
  beforeExposure:`float$();
  afterExposure:`float$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

initRiskSnapshot:{[]
  / Clear tables
  delete from `.risk.riskSnapshots;
  delete from `.risk.tradeImpactLog;

  -1 "  Risk snapshot initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Snapshot Capture
/ ═══════════════════════════════════════════════════════════════════

/ Snapshot risk state (run every 1 second via .z.ts)
/ PERFORMANCE REQUIREMENT: Must complete in <10ms
snapshot.capture:{[]
  / Start timer
  startTime:.z.p;

  / Capture current state (all reads are in-memory, no disk I/O)
  pnl:first select from .risk.intradayPnL;
  exposure:first select from .risk.exposureSummary;
  orderFlow:first -1#select from .risk.orderFlowMetrics;
  emergencyStop:first select from .risk.emergencyStopState;

  / Extract values with null guards
  totalPnL:$[()~pnl; 0.0; pnl`totalPnL];
  realizedPnL:$[()~pnl; 0.0; pnl`realizedPnL];
  unrealizedPnL:$[()~pnl; 0.0; pnl`unrealizedPnL];
  grossExposure:$[()~exposure; 0.0; exposure`totalGross];
  netExposure:$[()~exposure; 0.0; exposure`totalNet];
  ordersPerSec:$[()~orderFlow; 0.0; orderFlow`ordersPerSecond];
  rejectionRate:$[()~orderFlow; 0.0; orderFlow`rejectionRate];
  emergencyStopActive:$[()~emergencyStop; 0b; emergencyStop`active];

  / Insert snapshot
  `.risk.riskSnapshots insert (.z.p;totalPnL;realizedPnL;unrealizedPnL;grossExposure;netExposure;
                                ordersPerSec;rejectionRate;emergencyStopActive);

  / Trim snapshots (keep last 24 hours in RDB)
  / Delete snapshots older than 24h
  cutoff:.z.p - 24:00:00;
  delete from `.risk.riskSnapshots where time < cutoff;

  / End timer
  elapsed:`long$(.z.p - startTime) % 1000000; / microseconds to milliseconds
  / Performance check: warn if > 10ms
  if[elapsed > 10;
    -1 "WARNING: Risk snapshot took ",string[elapsed],"ms (target: <10ms)";
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Trade Impact Logging
/ ═══════════════════════════════════════════════════════════════════

/ Log trade impact (called on every fill)
logTradeImpact:{[tradeId;sym;side;qty;price]
  / Capture before state
  beforePnL:first .risk.intradayPnL`totalPnL;
  beforeExposure:first .risk.exposureSummary`totalGross;

  / (Fill logic runs here in validate.q onFillEnhanced)

  / Capture after state
  afterPnL:first .risk.intradayPnL`totalPnL;
  afterExposure:first .risk.exposureSummary`totalGross;

  / Log impact
  `.risk.tradeImpactLog insert (.z.p;tradeId;sym;side;qty;price;
    beforePnL;afterPnL;beforeExposure;afterExposure);

  / Trim impact log (keep last 24 hours)
  cutoff:.z.p - 24:00:00;
  delete from `.risk.tradeImpactLog where time < cutoff;
 };

/ ═══════════════════════════════════════════════════════════════════
/ Replay Functions
/ ═══════════════════════════════════════════════════════════════════

/ Replay risk state at timestamp
snapshot.replay:{[timestamp]
  / Query snapshot closest to timestamp (but not after)
  snapshot:first select from .risk.riskSnapshots where time <= timestamp;

  / If no snapshot found, return empty
  if[()~snapshot; :`msg`snapshot!("No snapshot found before timestamp";())];

  / Return snapshot
  `msg`snapshot!("Snapshot found";snapshot)
 };

/ Get trade impact for time range
snapshot.tradeImpact:{[startTime;endTime]
  select from .risk.tradeImpactLog where time within (startTime;endTime)
 };

/ Get snapshots for time range (for charting)
snapshot.range:{[startTime;endTime]
  select from .risk.riskSnapshots where time within (startTime;endTime)
 };

/ Find loss events (where P&L dropped significantly)
snapshot.findLossEvents:{[minLoss]
  / Find snapshots where P&L dropped by >= minLoss
  / (Compare each snapshot to previous one)
  snapshots:select time, totalPnL from .risk.riskSnapshots;

  / Calculate deltas
  pnlDeltas:update pnlDelta:totalPnL - prev totalPnL from snapshots;

  / Find loss events
  lossEvents:select from pnlDeltas where pnlDelta <= neg minLoss;

  lossEvents
 };

\d .
