/ Medusa — Main initialization script
/ Loads all modules in correct dependency order

\d .medusa

/ Project metadata
version:"0.1.0";
name:`medusa;

/ Display banner
-1 "========================================";
-1 "  Medusa — Algorithmic Trading System";
-1 "  Version: ",version;
-1 "========================================";
-1 "";

/ Load schema (table definitions)
-1 "Loading schema...";
\l schema/init.q
.qg.loadAllSchemas[];
.qg.initAllTables[];
.qg.validateSchema[];

/ Load libraries (uncomment as implemented)
-1 "Loading libraries...";
\l lib/money.q
\l lib/logger.q
\l lib/cleanup.q
\l config/config.q
\l config/riskLimits.q

/ Load pricing modules
-1 "Loading pricing modules...";
\l pricing/init.q

/ Load exchange wrappers
-1 "Loading exchange wrappers...";
\l exchange/base.q
\l exchange/registry.q
\l exchange/calendar.q
\l exchange/stub.q
\l exchange/alpaca.q
\l exchange/coordinator.q

/ Load strategy libraries
-1 "Loading strategy libraries...";
\l strategy/arb.q

/ Load engine
/ -1 "Loading strategy engine...";
/ \l engine/harness.q

/ Load audit system
-1 "Loading audit system...";
\l audit/audit.q
\l audit/order.q
\l audit/volume_balance.q
\l audit/fiat_balance.q
\l audit/ledger.q
\l audit/position_cache.q
\l audit/runner.q

/ Load risk management
\l risk/init.q

/ Load TCA (Transaction Cost Analysis)
-1 "Loading TCA module...";
\l tca/init.q

/ Load risk limits from config
-1 "Loading risk limits configuration...";
.config.risk.loadLimits[`$":configs/risk-limits.json"];

/ Schedule cleanup (run hourly)
-1 "Scheduling event log cleanup...";
.cleanup.scheduleCleanup[];

-1 "";
-1 "Medusa initialized successfully";
-1 "Available namespaces: .schema .money .log .cleanup .conf .qg .exchange .strategy .audit .risk .tca .pricing .config";
-1 "Core tables: exchange balance position target order trade transaction datum flag";
-1 "TCA tables: tcaBenchmark preTradeTCA tcaReport";
-1 "Exchange wrappers: base, registry, stub, coordinator";
-1 "Strategy libraries: arb (arbitrage detection)";
-1 "Audit system: ORDER, VOLUME_BALANCE, FIAT_BALANCE, LEDGER, POSITION_CACHE";
-1 "Risk management: position limits, order size, exposure, drawdown, emergency stop";
-1 "TCA: benchmark tracking, pre-trade estimates, post-trade reports, aggregate analytics";
-1 "Logging: structured logging with INFO/WARN/ERROR/CRITICAL levels";
-1 "Cleanup: hourly event log pruning (24h retention, 1h for snapshots)";
-1 "Config: risk limits loaded from configs/risk-limits.json";
-1 "";

\d .
