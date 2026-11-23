/ ============================================================================
/ logger.q - Structured Logging for Critical Paths
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides structured logging with severity levels and machine-parseable output.
/ All logs include timestamp, level, module, and action for audit trails.
/ ----------------------------------------------------------------------------
/ Dependencies: None
/ ----------------------------------------------------------------------------
/ Usage:
/   .log.INFO["Order placed successfully"]
/   .log.WARN["Rate limit approaching"]
/   .log.ERROR["Failed to connect to exchange"]
/   .log.CRITICAL["Emergency stop activated"]
/   .log.event[`INFO;`risk;`checkPosition;`sym`qty!(`BTCUSD;100)]
/ ============================================================================

\d .log

/ ============================================================================
/ LOG LEVELS
/ ============================================================================

/ Severity levels (increasing severity)
LEVELS:`DEBUG`INFO`WARN`ERROR`CRITICAL;

/ Current minimum log level (set via .log.setLevel)
minLevel:`INFO;

/ Check if a log level should be emitted
shouldLog:{[level]
  (LEVELS?level) >= LEVELS?minLevel
 };

/ ============================================================================
/ SIMPLE LOGGING FUNCTIONS
/ ============================================================================

/ INFO level — general informational messages
/ @param msg string - Log message
INFO:{[msg]
  if[shouldLog[`INFO];
    -1 ("[INFO  ",string[.z.p],"] ",msg);
  ];
 };

/ WARN level — warning messages (non-fatal issues)
/ @param msg string - Log message
WARN:{[msg]
  if[shouldLog[`WARN];
    -1 ("[WARN  ",string[.z.p],"] ",msg);
  ];
 };

/ ERROR level — error messages (recoverable failures)
/ @param msg string - Log message
ERROR:{[msg]
  if[shouldLog[`ERROR];
    -2 ("[ERROR ",string[.z.p],"] ",msg);
  ];
 };

/ CRITICAL level — critical errors (system-level failures)
/ @param msg string - Log message
CRITICAL:{[msg]
  if[shouldLog[`CRITICAL];
    -2 ("[CRIT  ",string[.z.p],"] ",msg);
  ];
 };

/ DEBUG level — verbose debugging messages
/ @param msg string - Log message
DEBUG:{[msg]
  if[shouldLog[`DEBUG];
    -1 ("[DEBUG ",string[.z.p],"] ",msg);
  ];
 };

/ ============================================================================
/ STRUCTURED EVENT LOGGING
/ ============================================================================

/ Structured event log (machine-parseable with pipe-delimited fields)
/ Format: timestamp|level|module|action|detail
/ @param level symbol - Log level (`INFO, `WARN, `ERROR, `CRITICAL)
/ @param module symbol - Module name (e.g., `risk, `exchange, `algo)
/ @param action symbol - Action being performed (e.g., `placeOrder, `rejectOrder)
/ @param detail dict - Key-value pairs with event details
event:{[level;module;action;detail]
  if[shouldLog[level];
    / Serialize detail dict to compact q notation
    detailStr:.Q.s1[detail];
    -1 (string[.z.p],"|",string[level],"|",string[module],"|",string[action],"|",detailStr);
  ];
 };

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Set minimum log level (suppress logs below this level)
/ @param level symbol - One of `DEBUG`INFO`WARN`ERROR`CRITICAL
setLevel:{[level]
  if[not level in LEVELS;
    ERROR["Invalid log level: ",string level];
    :();
  ];
  minLevel::level;
  INFO["Log level set to ",string level];
 };

/ Get current log level
/ @return symbol - Current minimum log level
getLevel:{[]
  minLevel
 };

/ ============================================================================
/ LOG FILE OUTPUT (OPTIONAL)
/ ============================================================================

/ Log file handle (set via .log.openFile)
fileHandle:0Ni;

/ Open a log file for writing
/ @param path symbol - Path to log file (e.g., `:/tmp/medusa.log)
/ @return boolean - 1b if successful
openFile:{[path]
  / Close existing handle
  if[not null fileHandle; hclose fileHandle];

  / Open new file (append mode)
  fileHandle::@[hopen;path;{[e] ERROR["Failed to open log file: ",e]; 0Ni}];
  not null fileHandle
 };

/ Close log file
closeFile:{[]
  if[not null fileHandle; hclose fileHandle; fileHandle::0Ni];
 };

/ Write to log file (if open)
/ @param msg string - Message to write
writeFile:{[msg]
  if[not null fileHandle;
    @[fileHandle;msg,"\n";{ERROR["Failed to write to log file: ",x]}];
  ];
 };

\d .
