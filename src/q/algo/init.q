/ ============================================================================
/ init.q - Execution Algorithm Engine Initialization
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Load all algo modules in correct order
/   - Initialize algo schemas and engine
/   - Entry point for algo engine subsystem
/ ----------------------------------------------------------------------------
/ Load Order:
/   1. schema.q - Table schemas (algoOrder, childOrder, executionBenchmark)
/   2. engine.q - Engine orchestrator (submit, pause, cancel, timer)
/   3. vwap.q - VWAP algorithm
/   4. twap.q - TWAP algorithm
/   5. iceberg.q - Iceberg algorithm
/ ----------------------------------------------------------------------------
/ Usage:
/   \l src/q/algo/init.q
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - q/schema/*.q (order.q, trade.q - must be loaded first)
/   - q/exchange/coordinator.q (order placement)
/   - q/risk/validate.q (pre-trade validation)
/ ============================================================================

/ Module paths are repo-root relative so tests and direct loads behave consistently.
basePath:"src/q/algo/";

-1 "";
-1 "=======================================================";
-1 "  Loading Execution Algorithm Engine";
-1 "=======================================================";

/ Load schema (tables)
-1 "  [1/5] Loading algo schemas...";
system "l ",basePath,"schema.q"

/ Initialize schemas
.algo.init[];

/ Load engine orchestrator
-1 "  [2/5] Loading algo engine...";
system "l ",basePath,"engine.q"

/ Initialize engine
.algo.engine.init[];

/ Load VWAP algorithm
-1 "  [3/5] Loading VWAP algorithm...";
system "l ",basePath,"vwap.q"

/ Load TWAP algorithm
-1 "  [4/5] Loading TWAP algorithm...";
system "l ",basePath,"twap.q"

/ Load Iceberg algorithm
-1 "  [5/5] Loading Iceberg algorithm...";
system "l ",basePath,"iceberg.q"

-1 "";
-1 "=======================================================";
-1 "  Execution Algorithm Engine Loaded";
-1 "=======================================================";
-1 "  Available algorithms:";
-1 "    - VWAP   (.algo.engine.submit[...;`vwap;...])";
-1 "    - TWAP   (.algo.engine.submit[...;`twap;...])";
-1 "    - Iceberg (.algo.engine.submit[...;`iceberg;...])";
-1 "";
-1 "  Key functions:";
-1 "    - .algo.engine.submit[exchange;pair;side;qty;algo;params]";
-1 "    - .algo.engine.pause[algoOrderId]";
-1 "    - .algo.engine.resume[algoOrderId]";
-1 "    - .algo.engine.cancel[algoOrderId]";
-1 "    - .algo.engine.onChildFill[childOrderId;filledQty;avgFillPrice]";
-1 "";
-1 "  Tables:";
-1 "    - .algo.algoOrder (parent orders)";
-1 "    - .algo.childOrder (child slices)";
-1 "    - .algo.executionBenchmark (TCA benchmarks)";
-1 "=======================================================";
-1 "";
