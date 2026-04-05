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
\l config/config.q

/ Load exchange wrappers
-1 "Loading exchange wrappers...";
\l exchange/base.q
\l exchange/registry.q
\l exchange/stub.q
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
/ -1 "Loading risk management...";
/ \l risk/limits.q

-1 "";
-1 "Medusa initialized successfully";
-1 "Available namespaces: .schema .money .conf .qg .exchange .strategy .audit";
-1 "Core tables: exchange balance position target order trade transaction datum flag";
-1 "Exchange wrappers: base, registry, stub, coordinator";
-1 "Strategy libraries: arb (arbitrage detection)";
-1 "Audit system: ORDER, VOLUME_BALANCE, FIAT_BALANCE, LEDGER, POSITION_CACHE";
-1 "";

\d .
