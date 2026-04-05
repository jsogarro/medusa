/ ============================================================================
/ heartbeat_auditor.q - GDS Heartbeat Monitoring
/ ============================================================================
/
/ Monitors last update time per exchange/symbol.
/ Alerts if no data received within configured threshold (staleness detection).
/
/ Dependencies:
/   - alert_manager.q (.gds.alert.raise)
/   - Tick schema (orderbook, trade tables in global namespace)
/
/ Usage:
/   .gds.heartbeat.init[]
/   .gds.heartbeat.check[]  / Returns `PASS or `FAIL
/ ============================================================================

\d .gds.heartbeat

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Staleness thresholds per exchange/symbol
/ If no threshold configured for a pair, uses default
config:([]
  exchange:`symbol$();
  sym:`symbol$();
  maxStaleSec:`long$()
 );

/ Default threshold (30 seconds)
defaultThreshold:30;

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize heartbeat monitor with default thresholds
/ @return null
init:{[]
  / Set default thresholds for all known exchange/sym pairs
  / Discover from tick schema tables if they exist
  exchanges:`kraken`coinbase`binance`bitstamp;
  symbols:`BTCUSD`ETHUSD`BTCEUR`ETHEUR;

  / Create config entries (exchange x symbol)
  `.gds.heartbeat.config upsert
    raze {[ex] {[ex;sy] (ex;sy;defaultThreshold)} [ex] each symbols} each exchanges;

  -1 ".gds.heartbeat initialized with ",string[count config]," exchange/symbol pairs";
  -1 "  Default staleness threshold: ",string[defaultThreshold]," seconds";
 };

/ ============================================================================
/ STALENESS DETECTION
/ ============================================================================

/ Get last update time for an exchange/symbol from orderbook table
/ @param exchange symbol
/ @param sym symbol
/ @return timestamp - Last update time (0Np if no data)
getLastOrderbookUpdate:{[exchange;sym]
  / Check if orderbook table exists
  if[not `orderbook in tables[];
    :0Np
  ];

  / Query last update time
  result:exec last time from orderbook where exchange=exchange, sym=sym;
  $[count result; first result; 0Np]
 };

/ Get last update time for an exchange/symbol from trade table
/ @param exchange symbol
/ @param sym symbol
/ @return timestamp - Last update time (0Np if no data)
getLastTradeUpdate:{[exchange;sym]
  / Check if trade table exists
  if[not `trade in tables[];
    :0Np
  ];

  / Query last update time
  result:exec last time from trade where exchange=exchange, sym=sym;
  $[count result; first result; 0Np]
 };

/ Check if exchange/symbol is stale
/ @param exchange symbol
/ @param sym symbol
/ @return dict - `stale (boolean), `lastUpdate, `staleSec, `threshold
checkStaleness:{[exchange;sym]
  / Get threshold for this pair
  threshold:$[count select from config where exchange=exchange, sym=sym;
    exec first maxStaleSec from config where exchange=exchange, sym=sym;
    defaultThreshold];

  / Get last update times from both orderbook and trade
  lastOrderbook:getLastOrderbookUpdate[exchange;sym];
  lastTrade:getLastTradeUpdate[exchange;sym];

  / Take the most recent update from either table
  lastUpdate:max (lastOrderbook; lastTrade);

  / If no data at all, not stale (not yet receiving data)
  if[0Np~lastUpdate;
    :`stale`lastUpdate`staleSec`threshold!(0b;0Np;0;threshold)
  ];

  / Calculate staleness
  staleSec:`long$(`timestamp$.z.P) - `timestamp$lastUpdate;
  staleSec:staleSec % 1000000000;  / nanoseconds to seconds

  / Check if stale
  isStale:staleSec > threshold;

  `stale`lastUpdate`staleSec`threshold!(isStale;lastUpdate;staleSec;threshold)
 };

/ ============================================================================
/ MAIN CHECK FUNCTION
/ ============================================================================

/ Run heartbeat check on all configured exchange/symbol pairs
/ @return symbol - `PASS or `FAIL
check:{[]
  / Get all configured pairs
  pairs:select exchange, sym from config;

  / Check each pair
  results:{[ex;sy]
    check:checkStaleness[ex;sy];
    `exchange`sym`stale`lastUpdate`staleSec`threshold!(ex;sy;check`stale;check`lastUpdate;check`staleSec;check`threshold)
  } ./: flip (pairs`exchange; pairs`sym);

  / Combine into table
  results:flip `exchange`sym`stale`lastUpdate`staleSec`threshold!(
    results[;`exchange];results[;`sym];results[;`stale];
    results[;`lastUpdate];results[;`staleSec];results[;`threshold]);

  / Find stale pairs
  stalePairs:select from results where stale;

  / Raise alerts for stale pairs
  {[pair]
    msg:"No data for ",string[pair`staleSec]," seconds (threshold: ",string[pair`threshold],"s)";
    details:`exchange`sym`staleSec`threshold`lastUpdate!(
      pair`exchange;pair`sym;pair`staleSec;pair`threshold;pair`lastUpdate);
    .gds.alert.raise[`WARN;`heartbeat;msg;details];
  } each stalePairs;

  / Return status
  $[count stalePairs; `FAIL; `PASS]
 };

/ ============================================================================
/ CONFIGURATION HELPERS
/ ============================================================================

/ Set threshold for specific exchange/symbol
/ @param exchange symbol
/ @param sym symbol
/ @param seconds long - Staleness threshold in seconds
/ @return null
setThreshold:{[exchange;sym;seconds]
  `.gds.heartbeat.config upsert (exchange;sym;seconds);
  -1 "Set heartbeat threshold for ",string[exchange]," ",string[sym],": ",string[seconds],"s";
 };

/ Get current config
/ @return table - Current configuration
getConfig:{[] config};

-1 ".gds.heartbeat namespace loaded: init, check, setThreshold";

\d .
