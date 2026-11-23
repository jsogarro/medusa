/ ============================================================================
/ test_cleanup.q - Tests for Event Log Cleanup
/ ============================================================================

\l src/q/lib/cleanup.q
\l src/q/risk/schema.q
\l src/q/risk/riskSnapshot.q
\l src/q/tca/schema.q
\l tests/q/test_framework.q

/ Test 1: Verify pruning removes old events
test_pruneRemovesOldEvents:{[]
  / Insert old events (25 hours ago)
  oldTime:.z.p - 25D00:00:00;
  `.risk.riskEvents insert (oldTime;`testEvent;`;`;`;();`;`);

  / Insert recent events (1 hour ago)
  recentTime:.z.p - 01:00:00;
  `.risk.riskEvents insert (recentTime;`testEvent;`;`;`;();`;`);

  / Count before pruning
  beforeCount:count .risk.riskEvents;

  / Run cleanup
  deleted:.cleanup.pruneRDB[];

  / Count after pruning
  afterCount:count .risk.riskEvents;

  / Verify old events removed
  .test.assert["Cleanup should remove old events"; beforeCount > afterCount];
  .test.assert["Should have deleted at least one event"; deleted > 0];
  .test.assert["Should have 1 recent event remaining"; 1 = afterCount];

  / Cleanup
  delete from `.risk.riskEvents;
 };

/ Test 2: Verify pruning keeps recent events
test_pruneKeepsRecentEvents:{[]
  / Insert recent events (1 hour ago)
  recentTime:.z.p - 01:00:00;
  `.risk.riskEvents insert (recentTime;`testEvent1;`;`;`;();`;`);
  `.risk.riskEvents insert (recentTime;`testEvent2;`;`;`;();`;`);

  / Count before pruning
  beforeCount:count .risk.riskEvents;

  / Run cleanup
  deleted:.cleanup.pruneRDB[];

  / Count after pruning
  afterCount:count .risk.riskEvents;

  / Verify no events removed (all recent)
  .test.assert["Cleanup should NOT remove recent events"; beforeCount = afterCount];
  .test.assert["Should have deleted zero events"; deleted = 0];

  / Cleanup
  delete from `.risk.riskEvents;
 };

/ Test 3: Verify cleanup handles empty tables
test_pruneHandlesEmptyTables:{[]
  / Ensure table is empty
  delete from `.risk.riskEvents;

  / Run cleanup
  deleted:.cleanup.pruneRDB[];

  / Verify no errors and zero deleted
  .test.assert["Should have deleted zero events from empty table"; deleted = 0];
 };

/ Test 4: Verify cleanup handles missing tables gracefully
test_pruneHandlesMissingTables:{[]
  / Setup: ensure tables don't exist
  if[`riskEvents in tables[]; delete riskEvents from `.risk];

  / Run cleanup (should not error)
  deleted:@[{.cleanup.pruneRDB[]};::;{-1 "ERROR: ",x; -1j}];

  / Verify no errors
  .test.assert["Cleanup should handle missing tables gracefully"; deleted >= 0j];
 };

/ Test 5: Verify risk snapshots use shorter retention
test_snapshotsShorterRetention:{[]
  / Insert old snapshots (2 hours ago, should be deleted)
  oldTime:.z.p - 02:00:00;
  `.risk.riskSnapshots insert (oldTime;0f;0f;0f;0f;0f;0f;0f;0b);

  / Insert recent snapshots (30 minutes ago, should be kept)
  recentTime:.z.p - 00:30:00;
  `.risk.riskSnapshots insert (recentTime;0f;0f;0f;0f;0f;0f;0f;0b);

  / Count before pruning
  beforeCount:count .risk.riskSnapshots;

  / Run cleanup
  deleted:.cleanup.pruneRDB[];

  / Count after pruning
  afterCount:count .risk.riskSnapshots;

  / Verify old snapshots removed but recent kept
  .test.assert["Cleanup should remove old snapshots"; beforeCount > afterCount];
  .test.assert["Should have 1 recent snapshot remaining"; 1 = afterCount];

  / Cleanup
  delete from `.risk.riskSnapshots;
 };

-1 "Cleanup tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];
