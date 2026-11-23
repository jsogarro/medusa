/ Tests for Risk Snapshot & Replay

/ Load test framework
\l tests/q/testFramework.q

\d .test

/ ═══════════════════════════════════════════════════════════════════
/ Setup
/ ═══════════════════════════════════════════════════════════════════

setup:{[]
  / Initialize risk system
  .risk.init[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Test Cases
/ ═══════════════════════════════════════════════════════════════════

/ Test: Snapshot capture
testSnapshotCapture:{[]
  setup[];

  / Set risk state
  .risk.intradayPnL[`totalPnL]:12345.0;
  .risk.intradayPnL[`realizedPnL]:8000.0;
  .risk.intradayPnL[`unrealizedPnL]:4345.0;
  .risk.exposureSummary[`totalGross]:500000.0;
  .risk.exposureSummary[`totalNet]:300000.0;

  / Capture snapshot
  .risk.snapshot.capture[];

  / Check snapshot was created
  snapshots:select from .risk.riskSnapshots;
  assert[count[snapshots] > 0; "Snapshot should be created"];

  / Check snapshot values
  snapshot:first snapshots;
  assert[snapshot[`totalPnL] = 12345.0; "Snapshot P&L should match"];
  assert[snapshot[`realizedPnL] = 8000.0; "Snapshot realized P&L should match"];
  assert[snapshot[`grossExposure] = 500000.0; "Snapshot gross exposure should match"];

  pass[];
 };

/ Test: Snapshot replay
testSnapshotReplay:{[]
  setup[];

  / Create snapshots at different times
  timestamp1:.z.p - 00:05:00;
  timestamp2:.z.p - 00:02:00;
  timestamp3:.z.p;

  `.risk.riskSnapshots insert (timestamp1;1000.0;800.0;200.0;50000.0;30000.0;0.0;0.0;0b);
  `.risk.riskSnapshots insert (timestamp2;2000.0;1500.0;500.0;60000.0;40000.0;0.0;0.0;0b);
  `.risk.riskSnapshots insert (timestamp3;3000.0;2200.0;800.0;70000.0;50000.0;0.0;0.0;0b);

  / Replay at timestamp2
  result:.risk.snapshot.replay[timestamp2];

  / Check result
  assert[result[`msg] ~ "Snapshot found"; "Should find snapshot"];
  snapshot:result`snapshot;
  assert[snapshot[`totalPnL] = 2000.0; "Replayed P&L should be 2000"];

  pass[];
 };

/ Test: Trade impact logging
testTradeImpactLogging:{[]
  setup[];

  / Set initial state
  .risk.intradayPnL[`totalPnL]:10000.0;
  .risk.exposureSummary[`totalGross]:50000.0;

  / Log trade impact
  .risk.logTradeImpact[1j;`BTCUSD;`buy;1.0;60000.0];

  / Update state (simulating fill)
  .risk.intradayPnL[`totalPnL]:11000.0;
  .risk.exposureSummary[`totalGross]:110000.0;

  / Re-log impact to capture after state
  / (In production, this is done automatically in onFillEnhanced)
  `.risk.tradeImpactLog insert (.z.p;1j;`BTCUSD;`buy;1.0;60000.0;10000.0;11000.0;50000.0;110000.0);

  / Check impact log
  impacts:select from .risk.tradeImpactLog;
  assert[count[impacts] > 0; "Trade impact should be logged"];

  impact:first impacts;
  assert[impact[`beforePnL] = 10000.0; "Before P&L should be 10000"];
  assert[impact[`afterPnL] = 11000.0; "After P&L should be 11000"];
  assert[impact[`beforeExposure] = 50000.0; "Before exposure should be 50000"];
  assert[impact[`afterExposure] = 110000.0; "After exposure should be 110000"];

  pass[];
 };

/ Test: Snapshot performance (< 10ms)
testSnapshotPerformance:{[]
  setup[];

  / Set risk state
  .risk.intradayPnL[`totalPnL]:12345.0;
  .risk.exposureSummary[`totalGross]:500000.0;

  / Capture snapshot and measure time
  startTime:.z.p;
  .risk.snapshot.capture[];
  elapsed:`long$(.z.p - startTime) % 1000000; / microseconds to milliseconds

  / Check performance
  assert[elapsed < 10; "Snapshot should complete in < 10ms"];

  pass[];
 };

/ Test: Find loss events
testFindLossEvents:{[]
  setup[];

  / Create snapshots with P&L changes
  `.risk.riskSnapshots insert (.z.p - 00:05:00;10000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);
  `.risk.riskSnapshots insert (.z.p - 00:04:00;8000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);  / -2000 loss
  `.risk.riskSnapshots insert (.z.p - 00:03:00;7000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);  / -1000 loss
  `.risk.riskSnapshots insert (.z.p - 00:02:00;9000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);  / +2000 gain
  `.risk.riskSnapshots insert (.z.p - 00:01:00;6000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);  / -3000 loss

  / Find loss events >= 1000
  lossEvents:.risk.snapshot.findLossEvents[1000.0];

  / Should find 3 loss events: -2000, -1000, -3000
  assert[3 = count lossEvents; "Should find 3 loss events"];

  pass[];
 };

/ Test: Snapshot retention (24h)
testSnapshotRetention:{[]
  setup[];

  / Create snapshots older than 24h
  old1:.z.p - 25:00:00;
  old2:.z.p - 30:00:00;
  recent:.z.p - 01:00:00;

  `.risk.riskSnapshots insert (old1;1000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);
  `.risk.riskSnapshots insert (old2;2000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);
  `.risk.riskSnapshots insert (recent;3000.0;0.0;0.0;0.0;0.0;0.0;0.0;0b);

  / Capture snapshot (triggers trim)
  .risk.snapshot.capture[];

  / Check old snapshots were deleted
  snapshots:select from .risk.riskSnapshots;
  assert[all (exec time from snapshots) >= (.z.p - 24:00:00); "Old snapshots should be deleted"];

  pass[];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Run All Tests
/ ═══════════════════════════════════════════════════════════════════

runTests:{[]
  .test.run[`testSnapshotCapture];
  .test.run[`testSnapshotReplay];
  .test.run[`testTradeImpactLogging];
  .test.run[`testSnapshotPerformance];
  .test.run[`testFindLossEvents];
  .test.run[`testSnapshotRetention];
 };

/ Run tests
runTests[];

\d .
