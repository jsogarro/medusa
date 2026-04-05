/ ============================================================================
/ r.q - Real-time Database (RDB) Process
/ ============================================================================
/
/ Subscribes to Tickerplant and maintains current day's data in memory.
/ Handles end-of-day processing: writes to HDB and clears tables.
/
/ Usage:
/   q tick/r.q [tickerplant_host:port] [hdb_directory] -p 5011
/
/ Examples:
/   q tick/r.q localhost:5010 hdb/ -p 5011
/   q tick/r.q :5010 ../hdb -p 5011
/
/ Environment:
/   TP_HOST - Tickerplant host:port (default: localhost:5010)
/   HDB_DIR - HDB directory path (default: hdb/)
/ ============================================================================

\d .rdb

/ Configuration
config:`tpHost`tpPort`hdbDir!(`localhost;5010;`:hdb);

/ Connection handle to Tickerplant
tpHandle:0Ni;

/ Statistics
stats:`rowsReceived`updatesReceived`lastUpdate!(0;0;0Np);

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Parse command line arguments
/ @return null
parseArgs:{[]
  / Arg 1: Tickerplant host:port
  if[1<=count .z.x;
    arg0:.z.x 0;
    / Validate and parse host:port format
    / Expected formats: ":5010" (localhost) or "host:5010"
    if[not (":"~first arg0) and not ":" in arg0;
      -1 "Invalid TP argument format. Expected ':port' or 'host:port', got: ",arg0;
      exit 1;
    ];

    $[":"~first arg0;
      / Format: ":5010" — localhost with explicit port
      [
        config[`tpHost]:`localhost;
        portStr:1_arg0;
        / Validate port is numeric
        if[not all portStr in .Q.n;
          -1 "Invalid port number: ",portStr;
          exit 1;
        ];
        config[`tpPort]:"J"$portStr
      ];
      / Format: "host:port"
      [
        parts:vs[":";arg0];
        / Validate we have exactly 2 parts
        if[2<>count parts;
          -1 "Invalid host:port format: ",arg0," (expected 'host:port')";
          exit 1;
        ];
        config[`tpHost]:`$parts 0;
        / Validate port is numeric
        if[not all parts[1] in .Q.n;
          -1 "Invalid port number: ",parts 1;
          exit 1;
        ];
        config[`tpPort]:"J"$parts 1
      ]
    ];
  ];

  / Arg 2: HDB directory
  if[2<=count .z.x;
    config[`hdbDir]:hsym `$last .z.x 1
  ];

  -1 "Parsed args: TP=",string[config`tpHost],":",string[config`tpPort],
     " HDB=",string config`hdbDir;
 };

/ Initialize RDB
/ @return null
init:{[]
  -1 "========================================";
  -1 "  Medusa RDB Starting";
  -1 "========================================";
  -1 "";

  / Parse command line
  parseArgs[];

  / Load schema
  -1 "Loading schema...";
  @[system;"l tick/sym.q";{-1 "Failed to load schema: ",x; exit 1}];

  / Connect to Tickerplant
  -1 "Connecting to Tickerplant...";
  connectToTP[];

  / Subscribe to all tables
  -1 "Subscribing to all tables...";
  subscribeAll[];

  -1 "";
  -1 "RDB initialized successfully";
  -1 "Listening for updates from TP: ",string[config`tpHost],":",string config`tpPort;
  -1 "HDB directory: ",string config`hdbDir;
  -1 "";
 };

/ Connect to Tickerplant with retry logic
/ @return null
connectToTP:{[]
  tpEndpoint:`$":",string[config`tpHost],":",$[`localhost~config`tpHost;"";""],string config`tpPort;

  / Retry connection up to 10 times with backoff
  retry:0;
  while[(0Ni~tpHandle) and retry<10;
    tpHandle::@[hopen;tpEndpoint;{-1 "Connection failed: ",x; 0Ni}];
    if[0Ni~tpHandle;
      -1 "Retry ",(string retry+1),"/10 in 2 seconds...";
      system "sleep 2";
      retry+:1;
    ];
  ];

  if[0Ni~tpHandle; -1 "Failed to connect to Tickerplant after 10 retries"; exit 1];
  -1 "Connected to Tickerplant (handle: ",string[tpHandle],")";
 };

/ Subscribe to all tables from Tickerplant
/ @return null
subscribeAll:{[]
  / .u.sub[tableName;symbolList] returns (table; data) for recovery
  / ` as table = all tables, ` as symbols = all symbols
  result:tpHandle(`.u.sub;`;`);

  / result is (tableName; tableData) or (`;dict of tables)
  / If subscribing to all tables, result[1] is dict
  if[99h~type result 1;
    {[tn;td] tn set td} ./: flip (key result 1; value result 1);
    -1 "Subscribed to all tables, received ",(string count result 1)," snapshots";
  ];

  if[-11h~type result 0;
    / Single table subscription
    result[0] set result 1;
    -1 "Subscribed to ",(string result 0),", received ",(string count result 1)," rows";
  ];
 };

/ ============================================================================
/ DATA HANDLERS
/ ============================================================================

/ Standard tick update handler
/ Called by Tickerplant via IPC: .u.upd[tableName;data]
/ @param tableName symbol - Table name
/ @param data table - Data rows to insert
/ @return null
upd:{[tableName;data]
  / Insert rows into table
  tableName insert data;

  / Update statistics
  stats[`rowsReceived]+:count data;
  stats[`updatesReceived]+:1;
  stats[`lastUpdate]:.z.P;

  / Apply attributes after every 1000 rows for better query performance
  if[0 = stats[`rowsReceived] mod 1000;
    applyAttributes[];
  ];
 };

/ Apply attributes to RDB tables for query optimization
/ @return null
applyAttributes:{[]
  / Apply `g# (grouped) attribute on exchange and sym for faster filtering
  / This is safe because we accumulate data in time order
  @[{update `g#exchange, `g#sym from `orderbook};::;{-1 "Failed to apply attributes to orderbook: ",x}];
  @[{update `g#exchange, `g#sym from `trade};::;{-1 "Failed to apply attributes to trade: ",x}];
  @[{update `g#severity from `gds_alert};::;{-1 "Failed to apply attributes to gds_alert: ",x}];
 };

/ ============================================================================
/ END-OF-DAY PROCESSING
/ ============================================================================

/ End-of-day handler called by Tickerplant
/ Writes all tables to HDB, clears in-memory tables
/ @param date date - Date to process (from TP)
/ @return null
.u.end:{[date]
  -1 "";
  -1 "========================================";
  -1 "  End-of-Day Processing";
  -1 "  Date: ",string date;
  -1 "========================================";
  -1 "";

  / Save all tables to HDB
  saveToHDB[date];

  / Clear all tables
  clearTables[];

  / Reset statistics
  stats[`rowsReceived]:0;
  stats[`updatesReceived]:0;

  -1 "End-of-day processing complete";
  -1 "";
 };

/ Save tables to HDB
/ @param date date - Date partition
/ @return null
saveToHDB:{[date]
  / Ensure HDB directory exists
  hdbPath:config`hdbDir;
  @[{system "mkdir -p ",1_string x};hdbPath;{-1 "Failed to create HDB dir: ",x}];

  / Get all tick tables (orderbook, trade, gds_alert)
  tables:`orderbook`trade`gds_alert;

  / Write each table to HDB
  {[dt;hdb;tn]
    / Get table data
    tbl:get tn;

    if[count tbl;
      / Create date partition directory
      partPath:` sv hdb,`$string dt;
      @[{system "mkdir -p ",1_string x};partPath;{-1 "Failed to create partition: ",x}];

      / Save table
      savePath:` sv partPath,tn;
      @[{x set y};(savePath;.Q.en[hdb]tbl);{-1 "Failed to save ",string[y],": ",x}[;tn]];
      -1 "Saved ",(string tn)," (",string[count tbl]," rows) to ",1_string savePath;
    ];
  }[date;hdbPath] each tables;
 };

/ Clear all tables
/ @return null
clearTables:{[]
  tables:`orderbook`trade`gds_alert;

  {[tn]
    / Delete all rows using functional form (tn is a variable)
    tn set 0#value tn;
    -1 "Cleared ",string tn;
  } each tables;
 };

/ ============================================================================
/ MONITORING & UTILITIES
/ ============================================================================

/ Get RDB statistics
/ @return dict - Current statistics
getStats:{[] stats};

/ Get table row counts
/ @return dict - Row counts per table
getCounts:{[]
  `orderbook`trade`gds_alert!(count orderbook; count trade; count gds_alert)
 };

/ Display status
/ @return null
status:{[]
  -1 "========================================";
  -1 "  RDB Status";
  -1 "========================================";
  -1 "Tickerplant: ",string[config`tpHost],":",string config`tpPort;
  -1 "HDB Directory: ",string config`hdbDir;
  -1 "Connected: ",$[0Ni~tpHandle;"No";"Yes (handle ",string[tpHandle],")"];
  -1 "";
  -1 "Statistics:";
  -1 "  Total rows received: ",string stats`rowsReceived;
  -1 "  Total updates: ",string stats`updatesReceived;
  -1 "  Last update: ",string stats`lastUpdate;
  -1 "";
  -1 "Table counts:";
  counts:getCounts[];
  -1 "  orderbook: ",string counts`orderbook;
  -1 "  trade: ",string counts`trade;
  -1 "  gds_alert: ",string counts`gds_alert;
  -1 "========================================";
 };

/ ============================================================================
/ STARTUP
/ ============================================================================

/ Initialize on load
init[];

\d .
