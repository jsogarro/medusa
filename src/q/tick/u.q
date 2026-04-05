/ ============================================================================
/ u.q - Tickerplant Utility Functions
/ ============================================================================
/
/ Standard kdb+tick infrastructure providing:
/   - .u.init   : Initialize tables from schema
/   - .u.sub    : Subscribe to updates (by table and symbol)
/   - .u.upd    : Receive data from publishers, distribute to subscribers
/   - .u.pub    : Publish updates to all subscribers for a table
/   - .u.end    : End-of-day processing
/
/ Usage:
/   Load after sym.q in the tickerplant process
/ ============================================================================

\d .u

/ Subscriber registry: handle -> (table names; symbol lists)
/ Each subscriber is keyed by handle (IPC connection)
w:()!();

/ Tables being managed by this tickerplant
/ Set during .u.init from global namespace
t:();

/ Log handle for journaling (if enabled)
/ Set to 0Ni for no journaling, or file handle for persistence
L:0Ni;

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize tickerplant tables and metadata
/ @param tables symbol list - Table names to manage (empty list = all tables)
/ @return null
init:{[tables]
  / Store table list - always as symbol list, never as dict
  t::$[count tables; tables; `symbol$()];

  / Initialize subscriber registry as empty
  w::()!();

  / Display init confirmation
  -1 ".u.init complete — managing tables: ",(" " sv string t);
 };

/ ============================================================================
/ SUBSCRIPTION MANAGEMENT
/ ============================================================================

/ Subscribe caller to updates
/ @param tableName symbol - Table to subscribe to (` = all tables)
/ @param symList symbol list - Symbols to subscribe (` or () = all symbols)
/ @return (table name; table data) pair for recovery
sub:{[tableName;symList]
  handle:.z.w;  / Caller's handle

  / Register subscription
  if[not handle in key w; w[handle]:(`symbol$();`symbol$())];

  / Add table to subscriber's table list (prevent duplicates)
  if[not tableName in first w[handle];
    w[handle]:(w[handle][0],tableName; w[handle][1],symList)
  ];

  / Return table data for recovery (full snapshot)
  / If specific table requested, return that table; otherwise return all
  if[tableName~`;
    :(`;{x!get each x}t)
  ];

  (tableName; $[count symList;
    ?[tableName;enlist(in;`sym;enlist symList);0b;()];
    get tableName])
 };

/ Unsubscribe caller
/ @param tableName symbol - Table to unsubscribe from
/ @return null
unsub:{[tableName]
  handle:.z.w;

  if[handle in key w;
    / Remove table from subscriber's list
    idx:where not tableName = first w[handle];
    w[handle]:(w[handle][0][idx]; w[handle][1][idx]);

    / If no tables left, remove subscriber entirely
    if[0=count first w[handle]; w::handle _ w];
  ];
 };

/ ============================================================================
/ DATA DISTRIBUTION
/ ============================================================================

/ Receive data from publisher and distribute to subscribers
/ @param tableName symbol - Table receiving data
/ @param data table - Data rows to insert and publish
/ @return null
upd:{[tableName;data]
  / Insert into local table with protected evaluation
  result:@[{[tn;d] tn insert d; 1b}; (tableName;data); {[tn;err]
    -1 "[ERROR] Failed to insert into ",string[tn],": ",err;
    .gds.alert.raise[`CRITICAL;`tickerplant;"Insert failed for ",string[tn];`error`count!(err;count d)];
    0b
  }[tableName]];

  / Only publish if insert succeeded
  if[result;
    pub[tableName;data];
  ];
 };

/ Publish data to all subscribers of a table
/ @param tableName symbol - Table name
/ @param data table - Data to publish
/ @return null
pub:{[tableName;data]
  / Get all subscriber handles subscribed to this table
  handles:key[w] where {tableName in x[0]} each value w;

  / For each subscriber, filter data by their symbol subscription
  / and send via async IPC
  {[h;tn;d]
    / Get subscriber's symbol list for this table
    idx:where tn = first w[h];
    symList:w[h][1][first idx];

    / Filter data if subscriber wants specific symbols
    filteredData:$[count symList;
      ?[d;enlist(in;`sym;enlist symList);0b;()];
      d];

    / Send update via IPC (negative handle = async)
    if[count filteredData; (neg h)(`.u.upd;tn;filteredData)];
  }[;tableName;data] each handles;
 };

/ ============================================================================
/ END-OF-DAY PROCESSING
/ ============================================================================

/ End-of-day processing
/ @param date date - Date to process (typically .z.d)
/ @return null
end:{[date]
  -1 ".u.end called for date: ",string date;

  / Send end-of-day message to all subscribers
  {(neg x)`.u.end} each key w;

  / Close log handle if open
  if[not 0Ni~L; hclose L; L::0Ni];

  -1 ".u.end complete";
 };

/ ============================================================================
/ UTILITY FUNCTIONS
/ ============================================================================

/ Get subscriber count
/ @return long - Number of active subscribers
subCount:{[] count w};

/ Get subscriber info
/ @return table - Subscriber details (handle, tables, symbols)
subInfo:{[]
  flip `handle`tables`symbols!(key w; first each value w; last each value w)
 };

-1 ".u namespace loaded: init, sub, unsub, upd, pub, end, subCount, subInfo";

\d .
