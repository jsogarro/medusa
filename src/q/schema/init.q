/ init.q - Schema initialization script
/ Loads all schema modules and initializes tables

\d .qg

// ============================================================================
// LOGGING UTILITIES
// ============================================================================

set[`.qg.log;{[level; msg]
  timestamp:.z.p;
  logMsg:string[timestamp]," [",string[level],"] ",msg;
  -1 logMsg;
 }];

logInfo:{.qg.log[`INFO; x]};
logWarn:{.qg.log[`WARN; x]};
logError:{.qg.log[`ERROR; x]};

// ============================================================================
// SCHEMA LOADING
// ============================================================================

/ Load all schema files at top-level so single-colon definitions bind in .qg.
\l src/q/schema/types.q
\l src/q/schema/exchange.q
\l src/q/schema/order.q
\l src/q/schema/trade.q
\l src/q/schema/transaction.q
\l src/q/schema/metadata.q
\l src/q/schema/equity.q
\l src/q/schema/options.q

// Load all schema files in correct dependency order
loadAllSchemas:{[]
  .qg.logInfo["Schema files already loaded"];
  .qg.logInfo["All schema files loaded successfully"];
 };

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

publishTable:{[tableName]
  tableSym:`$".qg.",string tableName;
  if[tableName in system "a .qg"; set[tableName; value tableSym]];
 };

publishTables:{[]
  .qg.publishTable each `exchange`balance`position`target`order`trade`transaction`datum`flag;
 };

// Initialize all tables
initAllTables:{[]
  .qg.logInfo["Initializing tables..."];

  / Initialize each table group
  .qg.initExchangeTables[];
  .qg.logInfo["Exchange tables initialized: exchange, balance, position, target"];

  .qg.initOrderTable[];
  .qg.logInfo["Order table initialized"];

  .qg.initTradeTable[];
  .qg.logInfo["Trade table initialized"];

  .qg.initTransactionTable[];
  .qg.logInfo["Transaction table initialized"];

  .qg.initMetadataTables[];
  .qg.logInfo["Metadata tables initialized: datum, flag"];

  .qg.publishTables[];
  .qg.logInfo["All tables initialized successfully"];
 };

// ============================================================================
// VALIDATION
// ============================================================================

// Validate schema is properly loaded
validateSchema:{[]
  .qg.logInfo["Validating schema..."];

  / Check all expected tables exist
  expectedTables:`exchange`balance`position`target`order`trade`transaction`datum`flag;
  existingTables:tables `.;

  missingTables:expectedTables except existingTables;

  if[0 < count missingTables;
    .qg.logError["Missing tables: ", " " sv string missingTables];
    '"Schema validation failed: missing tables"];

  .qg.logInfo["Schema validation passed"];
  .qg.logInfo["Available tables: ", " " sv string expectedTables];

  / Return table metadata
  ([] table:expectedTables; rowCount:{count value x} each expectedTables)
 };

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

// Get schema statistics
getSchemaStats:{[]
  .qg.logInfo["Gathering schema statistics..."];

  stats:([]
    table:tables `.;
    rowCount:{count value x} each tables `.;
    columnCount:{count cols value x} each tables `.
  );

  stats
 };

// Reset all tables (CAUTION: deletes all data)
resetTables:{[]
  .qg.logWarn["Resetting all tables - all data will be lost!"];

  / Re-initialize tables (clears them)
  .qg.initAllTables[];

  .qg.logInfo["All tables reset"];
 };

\d .

/ Export namespace
-1 "  Schema initialization functions loaded";
-1 "  Usage: .qg.loadAllSchemas[] then .qg.initAllTables[] then .qg.validateSchema[]";
