/ Mode management and safeguards
/ Load order: 6 - mode.q (depends on types.q)

\d .engine

/ Current global default mode
mode.current:`dryrun

/ Live mode confirmation flag
mode.liveConfirmed:0b

/ Set execution mode
/ @param m symbol - `live or `dryrun
mode.set:{[m]
  / Validate mode
  if[not m in types.validModes;
    '"Invalid mode: ",string[m],". Must be one of: ",", " sv string types.validModes];

  / Require explicit confirmation for live mode
  if[m~`live;
    if[not mode.liveConfirmed;
      '"Live mode requires explicit confirmation. Call .engine.mode.confirmLive[] first.";
    ];
    / Reset confirmation after successful live mode activation (one-time use)
    mode.liveConfirmed:0b;
  ];

  / Set mode
  mode.current:m;

  / Log mode change
  -1"[MODE] Set to: ",string m;

  m
 }

/ Explicitly confirm live mode activation
mode.confirmLive:{
  mode.liveConfirmed:1b;
  -1"[MODE] Live mode confirmed. Call .engine.mode.set[`live] to activate.";
  1b
 }

/ Query if currently in live mode
/ @return boolean - true if live mode
mode.isLive:{
  mode.current~`live
 }

/ Query if currently in dry-run mode
/ @return boolean - true if dry-run mode
mode.isDryRun:{
  mode.current~`dryrun
 }

/ Execute function only in specified mode
/ @param m symbol - required mode
/ @param fn function - function to execute
/ @param args list - function arguments
/ @return any - function result if mode matches, null otherwise
mode.guard:{[m;fn;args]
  / Check if current mode matches required mode
  if[not mode.current~m;
    -1"[MODE] Function requires mode: ",string[m],", current mode: ",string mode.current;
    :(::);
  ];

  / Execute function with args
  fn . args
 }

/ Validate mode consistency between strategy and harness
/ @param strategy dict - strategy state
/ @param harness dict - harness state
/ @return boolean - true if modes match
mode.validateConsistency:{[strategy;harness]
  strategyMode:strategy[`mode];
  harnessMode:harness[`mode];

  if[not strategyMode~harnessMode;
    '"Mode mismatch: strategy is ",string[strategyMode],", harness is ",string harnessMode;
  ];

  1b
 }

/ Reset live mode confirmation (for safety)
mode.resetConfirmation:{
  mode.liveConfirmed:0b;
  -1"[MODE] Live mode confirmation reset";
 }

/ Get current mode
/ @return symbol - current mode
mode.get:{
  mode.current
 }

\d .
