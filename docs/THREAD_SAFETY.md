# Thread Safety in Medusa

## Executive Summary

**q/kdb+ is single-threaded by design** — all operations within a single q process execute serially. This eliminates race conditions, deadlocks, and most concurrency bugs that plague multi-threaded systems.

However, **multi-process scenarios** (multiple q processes accessing shared resources) require careful design to ensure data consistency.

---

## Single-Process Guarantees

### No Race Conditions Within a Process

All operations in a q process are **atomic and sequential**:

- **Timer callbacks** (`.z.ts`) execute synchronously — the timer fires, runs the callback to completion, then schedules the next timer
- **IPC message handlers** (`.z.pg`, `.z.ps`, `.z.pp`) process messages one at a time from the IPC queue
- **Table operations** (insert, upsert, delete, update, select) are atomic within a single process

**Implication**: You **cannot** have two functions modifying the same table simultaneously within one q process. All modifications happen sequentially.

### Timer Callback Ordering

The `.z.ts` timer callback executes **synchronously**:

```q
.z.ts:{[]
  / This function runs to completion before the next timer fires
  .cleanup.pruneRDB[];
  .risk.snapshotRisk[];
 }

system "t 1000";  / Fire every 1 second
```

**No interleaving**: If `.cleanup.pruneRDB[]` takes 800ms, `.risk.snapshotRisk[]` will still complete before the next 1-second timer fires.

### IPC Message Handling

IPC messages are queued and processed **one at a time**:

```q
/ TP receives .u.upd messages from multiple publishers
.u.upd:{[tbl;data]
  / This runs to completion before the next .u.upd is processed
  insert[tbl;data];
  pub[tbl;data];  / Publish to subscribers
 }
```

**No concurrent modifications**: If 100 messages arrive simultaneously, they are processed sequentially.

---

## Multi-Process Scenarios (Concurrency Concerns)

### Scenario 1: Multiple RDBs Writing to HDB

**Unsafe**:
```q
/ Two RDB processes writing to the same HDB partition simultaneously
/ RDB1 writes to /hdb/2025.01.01/trade/
/ RDB2 writes to /hdb/2025.01.01/trade/
/ Result: Last-write-wins, data corruption possible
```

**Mitigation**:
- **One writer per partition** — only one RDB should write to a given HDB partition
- **Tickerplant log replay** — HDB built from TP log, not from multiple RDBs
- **Timestamped directories** — each RDB writes to its own timestamped directory, merged later

### Scenario 2: Multiple Strategies Accessing Shared State

**Unsafe**:
```q
/ Strategy 1 and Strategy 2 both read/write `.risk.positionLimits`
/ If running in separate processes, last-write-wins
```

**Mitigation**:
- **Single risk process** — all strategies in separate processes send IPC messages to a central risk process
- **Keyed table upserts** — atomic within a process (see below)

### Scenario 3: Keyed Table Upserts Are Atomic (Single Process)

**Safe within one process**:
```q
/ Even if multiple functions call this, they execute sequentially
`.risk.positionLimits upsert (`arbitrage;`BTCUSD;1000j;-1000j;500j);
`.risk.positionLimits upsert (`marketMaking;`ETHUSD;5000j;-5000j;2000j);
```

**Why**: `upsert` on a keyed table is an atomic operation in q. The key lookup, value update, and row insertion all happen in one uninterruptible step.

**Unsafe across processes**:
```q
/ Process 1: upsert (`arbitrage;`BTCUSD;1000j;-1000j;500j)
/ Process 2: upsert (`arbitrage;`BTCUSD;1000j;-1000j;600j)  / Overwrites
```

**Mitigation**:
- **Single writer** — only one process modifies the keyed table
- **IPC-based updates** — strategies send update requests to a central risk process via IPC

---

## Recommended Architecture Patterns

### Pattern 1: Central State Process (Recommended)

```
┌─────────────┐    IPC updates    ┌─────────────┐
│ Strategy 1  │ ─────────────────> │             │
└─────────────┘                    │   Risk      │
┌─────────────┐    IPC updates    │   Process   │ <── Single writer
│ Strategy 2  │ ─────────────────> │             │
└─────────────┘                    │   Manages   │
┌─────────────┐    IPC updates    │   all state │
│ Strategy 3  │ ─────────────────> │             │
└─────────────┘                    └─────────────┘
```

**Benefits**:
- No race conditions — all state updates are serialized in the risk process
- Single source of truth
- Atomic keyed table upserts are safe (single process)

### Pattern 2: Process-Local State (Alternative)

Each strategy process maintains its own state, no sharing:

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Arbitrage      │  │  Market Making  │  │  Momentum       │
│  Strategy       │  │  Strategy       │  │  Strategy       │
│  + Local State  │  │  + Local State  │  │  + Local State  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

**Benefits**:
- No IPC overhead
- Each process is independent

**Trade-offs**:
- No global position aggregation
- Each strategy must enforce its own limits

---

## Q-Specific Concurrency Primitives

### Atomic Operations (Single Process)

- `insert[tbl;rows]` — atomic append
- `upsert[keyed_tbl;rows]` — atomic merge (key lookup + update/insert)
- `delete from tbl where condition` — atomic delete
- `update col:val from tbl where condition` — atomic update
- `tbl,:row` — atomic append (equivalent to `insert`)

### Non-Atomic Operations (Multi-Statement Modifications)

```q
/ NOT atomic across processes:
delete from `positionLimits;  / Step 1
insert[`positionLimits;newRows];  / Step 2
/ If another process reads between Step 1 and Step 2, sees empty table
```

**Mitigation**: Perform multi-step modifications in a single process, or use a transaction log pattern.

---

## Multi-Threading in q (Experimental)

q supports **`peach` (parallel each)** for CPU-bound tasks:

```q
/ Run function in parallel across cores
result:{x * x} peach til 1000000;
```

**Caveats**:
- Each slave thread has its own memory space (no shared state)
- Data is serialized and sent to slave threads (overhead)
- Results are serialized back to the main thread
- **Not suitable for shared table modifications**

**Use case**: Parallel computation on independent data (e.g., backtesting 1000 parameter sets simultaneously)

---

## Summary

| Scenario | Thread-Safe? | Mitigation |
|----------|-------------|-----------|
| **Single q process** | ✅ Yes | All operations are sequential |
| **`.z.ts` timer callbacks** | ✅ Yes | Runs to completion before next timer |
| **IPC message handling** | ✅ Yes | Messages processed one at a time |
| **Keyed table upsert (single process)** | ✅ Yes | Atomic operation |
| **Multiple processes, same table** | ❌ No | Use central state process or IPC coordination |
| **Multi-step modifications** | ❌ No | Use single-process logic or transaction log |

**Bottom line**: In Medusa, all critical state (risk tables, position limits, order routing) lives in **single-process q instances**. Strategies running in separate processes communicate via IPC with the central risk/TP processes, ensuring all state modifications are serialized.

---

## References

- [q Language Reference: `.z` namespace](https://code.kx.com/q/ref/dotz/)
- [kdb+tick Architecture](https://code.kx.com/q/wp/rt-tick/)
- [Concurrent Access in kdb+](https://code.kx.com/q/kb/multi-threading/)
