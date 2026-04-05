/ ============================================================================
/ alert_manager.q - GDS Alert Management & Routing
/ ============================================================================
/
/ Centralized alert routing system for GDS auditors.
/ Logs all alerts and routes to configured channels (console, logfile, webhook).
/
/ Dependencies: None
/
/ Usage:
/   .gds.alert.init[]
/   .gds.alert.raise[`CRITICAL;`heartbeat;"No data for 60s";`exchange`sym!(`kraken;`BTCUSD)]
/ ============================================================================

\d .gds

/ ============================================================================
/ ALERT CONFIGURATION
/ ============================================================================

/ Alert channel configuration
/ severity -> (channel list; enabled)
alertConfig:([severity:`symbol$()]
  channels:();
  enabled:`boolean$()
 );

/ Audit log: persistent record of all alerts
/ Note: Since q is single-threaded, no race conditions are possible here.
/ All inserts are atomic within the q process thread model.
auditLog:([]
  timestamp:`timestamp$();
  auditor:`symbol$();
  severity:`symbol$();
  message:();
  details:()
 );

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

alert.init:{[]
  / Configure alert routing by severity
  `.gds.alertConfig upsert (
    (`INFO;enlist`console;1b);
    (`WARN;`console`logfile;1b);
    (`CRITICAL;`console`logfile`webhook;1b)
  );

  -1 ".gds.alert initialized: console, logfile, webhook channels available";
 };

/ ============================================================================
/ ALERT ROUTING
/ ============================================================================

/ Raise an alert and route to configured channels
/ @param severity symbol - Alert severity: `INFO, `WARN, `CRITICAL
/ @param auditor symbol - Auditor name (source of alert)
/ @param message string - Human-readable alert description
/ @param details dict - Additional context (exchange, sym, metrics, etc.)
/ @return null
alert.raise:{[severity;auditor;message;details]
  / Log the alert with protected evaluation
  timestamp:.z.P;
  @[{[tbl;row] tbl insert row}; (`.gds.auditLog;(timestamp;auditor;severity;message;details));
    {-1 "[ERROR] Failed to insert alert into auditLog: ",x}];

  / Get configured channels for this severity
  channels:$[severity in key alertConfig;
    exec first channels from alertConfig where severity=severity;
    enlist `console];

  enabled:$[severity in key alertConfig;
    exec first enabled from alertConfig where severity=severity;
    1b];

  / Route to each channel if enabled
  if[enabled;
    {[sev;aud;msg;det;ch]
      $[ch=`console; alert.sendConsole[sev;aud;msg;det];
        ch=`logfile; alert.sendLogfile[sev;aud;msg;det];
        ch=`webhook; alert.sendWebhook[sev;aud;msg;det];
        / Unknown channel
        -1 "Unknown alert channel: ",string ch]
    }[severity;auditor;message;details] each channels;
  ];
 };

/ ============================================================================
/ CHANNEL HANDLERS
/ ============================================================================

/ Send alert to console
/ @param severity symbol
/ @param auditor symbol
/ @param message string
/ @param details dict
/ @return null
alert.sendConsole:{[severity;auditor;message;details]
  / Color code by severity
  prefix:$[severity=`CRITICAL;"[CRITICAL] ";
           severity=`WARN;"[WARN] ";
           "[INFO] "];

  -1 prefix,"[",string[auditor],"] ",message;

  / Print details if non-empty
  if[count details;
    -1 "  Details: ",(.Q.s1 details);
  ];
 };

/ Send alert to logfile
/ @param severity symbol
/ @param auditor symbol
/ @param message string
/ @param details dict
/ @return null
alert.sendLogfile:{[severity;auditor;message;details]
  / Log to gds_alerts.log in current directory
  logPath:`:gds_alerts.log;

  / Ensure log directory exists (if path has directory component)
  @[{system "mkdir -p ",1_string hsym`$"." -1_"/",string x}; logPath;
    {/ Ignore error if already exists or path is current dir
    }];

  / Format log entry
  timestamp:.z.P;
  entry:"\n",(string timestamp)," ",(string severity)," [",string[auditor],"] ",message;

  / Append details
  if[count details;
    entry:entry," | Details: ",(.Q.s1 details);
  ];

  / Write to file (append mode) with protected evaluation
  @[{[lp;ent]
    h:hopen lp;
    h ent;
    hclose h;
   }; (logPath;entry);
   {[sev;aud;msg;err]
    -1 "[ERROR] Failed to write to log file: ",err;
    -1 "  Severity: ",string sev;
    -1 "  Auditor: ",string aud;
    -1 "  Message: ",msg;
   }[severity;auditor;message]];
 };

/ Send alert to webhook
/ @param severity symbol
/ @param auditor symbol
/ @param message string
/ @param details dict
/ @return null
alert.sendWebhook:{[severity;auditor;message;details]
  / Webhook endpoint (configurable)
  webhookUrl:getenv`GDS_WEBHOOK_URL;

  / Skip if no webhook configured
  if[""~webhookUrl;
    -1 "[webhook] No GDS_WEBHOOK_URL configured, skipping webhook alert";
    :();
  ];

  / Build JSON payload
  payload:.j.j `severity`auditor`message`details`timestamp!(
    severity;auditor;message;details;.z.P);

  / Send HTTP POST request (async, fire-and-forget)
  / In production, use proper HTTP library or message queue
  -1 "[webhook] Would POST to ",webhookUrl," (not implemented)";
  / TODO: Implement with .Q.hg or external HTTP library
 };

/ ============================================================================
/ ALERT QUERIES
/ ============================================================================

/ Get recent alerts
/ @param minutes long - Number of minutes to look back
/ @return table - Recent alerts
alert.recent:{[minutes]
  cutoff:.z.P - minutes * 0D00:01:00;
  select from auditLog where timestamp >= cutoff
 };

/ Get alerts by severity
/ @param severity symbol - Severity level
/ @return table - Alerts matching severity
alert.bySeverity:{[severity]
  select from auditLog where severity=severity
 };

/ Get alerts by auditor
/ @param auditor symbol - Auditor name
/ @return table - Alerts from this auditor
alert.byAuditor:{[auditor]
  select from auditLog where auditor=auditor
 };

/ Count alerts by severity in last N minutes
/ @param minutes long - Minutes to look back
/ @return dict - severity -> count
alert.countBySeverity:{[minutes]
  cutoff:.z.P - minutes * 0D00:01:00;
  exec count i by severity from auditLog where timestamp >= cutoff
 };

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Enable/disable channel for severity
/ @param severity symbol
/ @param enabled boolean
/ @return null
alert.setEnabled:{[severity;enabled]
  update enabled:enabled from `.gds.alertConfig where severity=severity;
  -1 "Alert channel for ",string[severity]," set to: ",$[enabled;"enabled";"disabled"];
 };

/ Add channel to severity
/ @param severity symbol
/ @param channel symbol
/ @return null
alert.addChannel:{[severity;channel]
  if[not severity in key alertConfig;
    -1 "Unknown severity: ",string severity;
    :();
  ];

  / Get current channels
  currentChannels:exec first channels from alertConfig where severity=severity;

  / Add if not already present
  if[not channel in currentChannels;
    newChannels:currentChannels,enlist channel;
    update channels:enlist newChannels from `.gds.alertConfig where severity=severity;
    -1 "Added ",string[channel]," to ",string severity;
  ];
 };

/ Remove channel from severity
/ @param severity symbol
/ @param channel symbol
/ @return null
alert.removeChannel:{[severity;channel]
  if[not severity in key alertConfig;
    -1 "Unknown severity: ",string severity;
    :();
  ];

  / Get current channels
  currentChannels:exec first channels from alertConfig where severity=severity;

  / Remove if present
  if[channel in currentChannels;
    newChannels:currentChannels except enlist channel;
    update channels:enlist newChannels from `.gds.alertConfig where severity=severity;
    -1 "Removed ",string[channel]," from ",string severity;
  ];
 };

-1 ".gds.alert namespace loaded: init, raise, recent, bySeverity, byAuditor";

\d .
