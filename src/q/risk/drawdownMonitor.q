/ Risk Management — Drawdown Monitor
/ Tracks peak-to-trough PnL drawdown and halts trading on breach

\d .risk

/ Update P&L and check drawdown (called on P&L change)
/ Returns: boolean — 1b if drawdown breached
updatePnL:{[cp]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.drawdownState;
    -1 "CRITICAL: drawdownState table corrupted (row count: ",string[count .risk.drawdownState],")";
    :0b
  ];

  / ROBUSTNESS: Validate input PnL is finite (not null or infinity)
  if[(null cp) or (cp~0w) or (cp~-0w);
    -1 "CRITICAL: Invalid PnL value received: ",string[cp];
    :0b
  ];

  state:first select from .risk.drawdownState;

  pk:state`peakPnL;
  maxDDPct:state`maxDrawdownPct;

  / Update peak if new high
  if[cp>pk;pk:cp];

  / Calculate drawdown as a fraction: 0.1 = 10%
  dd:$[pk<=0.0;0.0;(pk-cp)%pk];

  / Check if breach
  breach:dd>maxDDPct;

  / Update state
  drawdownState::update peakPnL:pk, currentPnL:cp, currentDrawdown:dd, maxDrawdown:dd | maxDrawdown, drawdownPct:dd, maxDrawdownPct:maxDDPct, breached:breach, lastUpdate:.z.p from drawdownState;

  / Log event if breach
  if[breach;
    .risk.logRiskEvent[.z.p;`drawdownHalt;`;`;`;
      `peakPnL`currentPnL`drawdownPct`maxDrawdownPct!(pk;cp;dd;maxDDPct);
      `halt;`critical];
    -1 "CRITICAL: Drawdown limit breached! ",string[100.0*dd],"% > ",string[100.0*maxDDPct],"%";
    .risk.activateEmergencyStop[`drawdownBreach;`system];
  ];

  breach
 };

/ Check if drawdown halt is active (pre-trade)
/ Returns: (pass:boolean; reason:symbol)
checkDrawdownHalt:{[]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.drawdownState;
    -1 "CRITICAL: drawdownState table corrupted (row count: ",string[count .risk.drawdownState],")";
    / FAIL-SAFE: If state is corrupted, HALT trading
    :(0b;`drawdownStateCorrupted)
  ];

  breached:first exec breached from .risk.drawdownState;
  $[breached;(0b;`drawdownHaltActive);(1b;`)]
 };

/ Set max drawdown percentage
setMaxDrawdown:{[maxDrawdownPct]
  drawdownState::update maxDrawdownPct:maxDrawdownPct from drawdownState;
  -1 "Max drawdown set: ",string[maxDrawdownPct],"%";
 };

/ Reset drawdown state (admin function)
resetDrawdown:{[]
  drawdownState::update peakPnL:0.0, currentPnL:0.0, currentDrawdown:0.0, maxDrawdown:0.0, drawdownPct:0.0, maxDrawdownPct:0.2, breached:0b, lastUpdate:.z.p from drawdownState;
  -1 "Drawdown state reset";
 };

\d .
