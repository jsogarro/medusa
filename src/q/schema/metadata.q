/ ============================================================================
/ metadata.q - Datum and Flag Management
/ ============================================================================
/
/ Provides:
/   - Generic key-value storage for metrics (datum table)
/   - Feature flag management (flag table)
/   - Metric helpers (setMetric, incrMetric, getMetricsDict)
/
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/
/ Tables:
/   - datum: Generic key-value storage (keyed by datum_id, unique on category+key)
/   - flag: Feature flags (keyed by flag_id, unique on name)
/
/ Functions:
/   - Datum: setDatum, getDatum, getDatumsByCategory, deleteDatum, getRecentDatums
/   - Datum Queries: searchDatums, getDatumsByType, getDatumCategories
/   - Flag Commands: createFlag, enableFlag, disableFlag, toggleFlag, updateFlag, deleteFlag
/   - Flag Queries: isFlagEnabled, getFlag, getFlagsByCategory, getEnabledFlags,
/                   getDisabledFlags, getFlagCategories, getFlagStats
/   - Convenience: setMetric, incrMetric, getMetricsDict
/ ============================================================================

\d .qg

// ============================================================================
// DATUM TABLE SCHEMA
// ============================================================================

// Generic key-value table for storing arbitrary metrics and data
datumSchema:([]
  datum_id: `long$();                    / Unique datum ID (auto-increment, PK)
  key: `symbol$();                       / Metric/data key
  value: ();                             / Value (any kdb+ type)
  value_type: `symbol$();                / Type indicator (long/float/symbol/etc.)
  category: `symbol$();                  / Category/namespace for organization
  description: `symbol$();               / Human-readable description
  time_created: `timestamp$();           / Creation timestamp
  time_updated: `timestamp$();           / Last update timestamp
  meta_data: ()                          / Additional metadata dictionary
 );

// Primary key: datum_id
// Unique key: (category, key)
// Index: category, time_updated

// ============================================================================
// FLAG TABLE SCHEMA
// ============================================================================

// Feature flags for enabling/disabling system features
flagSchema:([]
  flag_id: `long$();                     / Unique flag ID (auto-increment, PK)
  name: `symbol$();                      / Flag name (unique)
  enabled: `boolean$();                  / Whether flag is enabled
  category: `symbol$();                  / Category (strategy/exchange/system/etc.)
  description: `symbol$();               / Human-readable description
  time_created: `timestamp$();           / Creation timestamp
  time_updated: `timestamp$();           / Last update timestamp
  meta_data: ()                          / Additional metadata dictionary
 );

// Primary key: flag_id
// Unique key: name
// Index: category, enabled

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

initMetadataTables:{[]
  datum::datumSchema;
  flag::flagSchema;

  / Create primary keys
  `datum_id xkey `datum;
  `flag_id xkey `flag;
 };

// ============================================================================
// CRUD OPERATIONS - DATUM
// ============================================================================

// Set datum value (upsert)
// Usage: .qg.setDatum[`performance; `avg_latency; 123.45; `float; "Average latency in ms"; ...]
setDatum:{[category; key; value; valueType; description; metaData]
  / Validate inputs
  if[null key; '"Key cannot be null"];
  if[null category; '"Category cannot be null"];

  / Check if datum exists
  existing:select from datum where category=category, key=key;

  / Upsert
  if[0 = count existing;
    / Insert new datum
    datumId:.qg.nextId[`datum];

    `datum insert (
      datumId;                           / datum_id
      key;                               / key
      value;                             / value
      valueType;                         / value_type
      category;                          / category
      description;                       / description
      .z.p;                              / time_created
      .z.p;                              / time_updated
      metaData                           / meta_data
    );
  ];

  if[0 < count existing;
    / Update existing datum
    update value:value, value_type:valueType, description:description,
      meta_data:metaData, time_updated:.z.p
      from `datum where category=category, key=key;
  ];

  (category; key)
 };

// Get datum value
getDatum:{[category; key]
  res:first select from datum where category=category, key=key;
  if[0 = count res; :()];
  res[`value]
 };

// Get all datums in category
getDatumsByCategory:{[category]
  select from datum where category=category
 };

// Delete datum
deleteDatum:{[category; key]
  delete from `datum where category=category, key=key;
  (category; key)
 };

// Get recent datums
getRecentDatums:{[n]
  idx:n sublist idesc exec time_updated from datum;
  datum idx
 };

// ============================================================================
// QUERY FUNCTIONS - DATUM
// ============================================================================

// Search datums by key pattern
searchDatums:{[keyPattern]
  select from datum where key like keyPattern
 };

// Get datums by type
getDatumsByType:{[valueType]
  select from datum where value_type=valueType
 };

// Get all categories
getDatumCategories:{[]
  exec distinct category from datum
 };

// ============================================================================
// CRUD OPERATIONS - FLAG
// ============================================================================

// Create feature flag
// Usage: .qg.createFlag[`enable_arbitrage; `strategy; "Enable arbitrage strategy"; ...]
createFlag:{[name; category; description; metaData]
  / Validate inputs
  if[null name; '"Flag name cannot be null"];

  / Check if flag exists
  if[name in exec name from flag;
    '"Flag already exists"];

  / Generate new flag ID
  flagId:.qg.nextId[`flag];

  / Insert flag (disabled by default)
  `flag insert (
    flagId;                              / flag_id
    name;                                / name
    0b;                                  / enabled (default false)
    category;                            / category
    description;                         / description
    .z.p;                                / time_created
    .z.p;                                / time_updated
    metaData                             / meta_data
  );

  flagId
 };

// Enable flag
enableFlag:{[name]
  if[not name in exec name from flag;
    '"Flag not found"];

  update enabled:1b, time_updated:.z.p
    from `flag where name=name;

  name
 };

// Disable flag
disableFlag:{[name]
  if[not name in exec name from flag;
    '"Flag not found"];

  update enabled:0b, time_updated:.z.p
    from `flag where name=name;

  name
 };

// Toggle flag
toggleFlag:{[name]
  if[not name in exec name from flag;
    '"Flag not found"];

  currentState:first exec enabled from flag where name=name;

  update enabled:not currentState, time_updated:.z.p
    from `flag where name=name;

  name
 };

// Check if flag is enabled
isFlagEnabled:{[name]
  res:first select enabled from flag where name=name;
  if[0 = count res; :0b];  / Default to disabled if not found
  res[`enabled]
 };

// Get flag
getFlag:{[name]
  first select from flag where name=name
 };

// Get all flags in category
getFlagsByCategory:{[category]
  select from flag where category=category
 };

// Get all enabled flags
getEnabledFlags:{[]
  select from flag where enabled=1b
 };

// Get all disabled flags
getDisabledFlags:{[]
  select from flag where enabled=0b
 };

// Update flag metadata
updateFlag:{[name; description; metaData]
  update description:description, meta_data:metaData, time_updated:.z.p
    from `flag where name=name;

  name
 };

// Delete flag
deleteFlag:{[name]
  delete from `flag where name=name;
  name
 };

// ============================================================================
// QUERY FUNCTIONS - FLAG
// ============================================================================

// Get all flag categories
getFlagCategories:{[]
  exec distinct category from flag
 };

// Get flag statistics
getFlagStats:{[]
  select
    totalFlags:count i,
    enabledFlags:sum enabled,
    disabledFlags:sum not enabled,
    enabledPct:100.0 * (sum enabled) % count i
    by category
    from flag
 };

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

// Set numeric metric
setMetric:{[category; key; value; description]
  valueType:$[
    value~"j"$value; `long;
    value~"f"$value; `float;
    `unknown
  ];
  .qg.setDatum[category; key; value; valueType; description; ()!()]
 };

// Increment metric
incrMetric:{[category; key; delta]
  currentValue:.qg.getDatum[category; key];
  if[0 = count currentValue; currentValue:0j];
  newValue:currentValue + delta;
  .qg.setMetric[category; key; newValue; ""]
 };

// Get all metrics in category as dictionary
getMetricsDict:{[category]
  datums:.qg.getDatumsByCategory[category];
  (exec key from datums)!(exec value from datums)
 };

\d .

/ Export namespace
-1 "  Metadata tables loaded: datum and flag for metrics and feature flags";
