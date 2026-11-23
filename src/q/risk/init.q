/ Risk Management — Module Loader
/ Loads all risk sub-modules in dependency order
/ Paths are repo-root relative so tests and direct loads behave consistently.

-1 "Loading risk management...";

/ Load schema first (table definitions)
\l src/q/risk/schema.q
\l src/q/lib/money.q

/ Load individual checkers
\l src/q/risk/positionLimits.q
\l src/q/risk/orderSizeLimits.q
\l src/q/risk/exposureLimits.q
\l src/q/risk/drawdownMonitor.q
\l src/q/risk/emergencyStop.q

/ Load advanced risk controls
\l src/q/risk/rateLimiting.q
\l src/q/risk/correlationLimits.q
\l src/q/risk/concentrationLimits.q
\l src/q/risk/marketImpact.q
\l src/q/risk/circuitBreaker.q
\l src/q/risk/pnlAttribution.q
\l src/q/risk/marketHours.q

/ Load intraday risk modules
\l src/q/risk/realtimePnL.q
\l src/q/risk/exposureHeatmap.q
\l src/q/risk/orderFlowRisk.q
\l src/q/risk/alertEngine.q
\l src/q/risk/riskSnapshot.q

/ Load Phase 3: Alpaca equity regulations
\l src/q/risk/pdt.q
\l src/q/risk/margin.q
\l src/q/risk/settlement.q

/ Load validation pipeline (depends on all checkers)
\l src/q/risk/validate.q

-1 "  Risk management loaded: .risk namespace";
