/ ============================================================================
/ margin.q - Reg T Margin Requirements
/ ============================================================================
/ // Provides:
/   - Reg T initial margin (50% for equities)
/   - Maintenance margin (25% minimum, 30% house requirement typical)
/   - Buying power calculation
/   - Margin call detection
/   - Integration with Alpaca account API
/ // Regulatory Context:
/   - Regulation T (Federal Reserve): Initial margin = 50% for equities
/   - FINRA Rule 4210: Minimum maintenance margin = 25%
/   - Most brokers enforce 30-40% house maintenance margin
/   - Pattern Day Traders must maintain $25,000 minimum
/ // Margin Calculation:
/   - Long position: Initial margin = 50% of purchase price
/   - Short position: Initial margin = 50% of sale price + proceeds
/   - Maintenance margin = 25% of current market value (FINRA minimum)
/ // Dependencies:
/   - .schema.isEquity (asset class detection)
/ // Functions:
/   - initMargin: Initialize margin tracking
/   - calcMarginRequirement: Calculate initial margin for order
/   - calcMaintenanceMargin: Calculate maintenance margin for position
/   - checkMarginAvailable: Pre-trade buying power check
/   - updateMarginState: Update margin state from account API
/   - detectMarginCall: Check if account is in margin call
/ ============================================================================

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Margin Configuration and State
/ ═══════════════════════════════════════════════════════════════════

/ Margin configuration (single-row table)
marginConfig:([]
  enabled:enlist 1b;
  initialMarginPct:enlist 50.0;  / Reg T: 50% for equities
  maintenanceMarginPct:enlist 30.0;  / House requirement (25% FINRA minimum)
  minEquity:enlist 2000.0;  / Minimum equity to open margin account
  pdtMinEquity:enlist 25000.0;  / Pattern Day Trader minimum
  lastUpdate:enlist .z.p
 );

/ Margin state (single-row table)
/ Synced from Alpaca account API
marginState:([]
  equity:enlist 0.0;  / Account equity (cash + positions)
  buyingPower:enlist 0.0;  / Available buying power
  cash:enlist 0.0;  / Cash balance
  marginUsed:enlist 0.0;  / Total margin currently used
  maintenanceMargin:enlist 0.0;  / Required maintenance margin
  excessMargin:enlist 0.0;  / Excess above maintenance
  marginCallActive:enlist 0b;  / True if in margin call
  lastSync:enlist 0Np
 );

/ Margin call history (append-only)
marginCallHistory:([]
  time:`timestamp$();
  callType:`symbol$();  / `maintenance, `fed, `house
  equity:`float$();
  maintenanceMargin:`float$();
  deficiency:`float$();
  resolved:`boolean$();
  resolvedAt:`timestamp$()
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

/ Initialize margin tracking
/ @return void
initMargin:{[]
  / Reset state
  delete from `.risk.marginCallHistory;

  / Set default config
  update enabled:1b, initialMarginPct:50.0, maintenanceMarginPct:30.0,
         minEquity:2000.0, pdtMinEquity:25000.0, lastUpdate:.z.p from `.risk.marginConfig;

  / Reset margin state
  update equity:0.0, buyingPower:0.0, cash:0.0, marginUsed:0.0,
         maintenanceMargin:0.0, excessMargin:0.0, marginCallActive:0b,
         lastSync:0Np from `.risk.marginState;

  -1 "  Margin tracking initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Margin Calculation
/ ═══════════════════════════════════════════════════════════════════

/ Calculate initial margin requirement for an order
/ @param sym symbol - Trading symbol
/ @param qty float - Order quantity (signed: positive=long, negative=short)
/ @param price float - Order price
/ @return float - Initial margin requirement
calcMarginRequirement:{[sym;qty;price]
  / Only applies to equities
  if[not .schema.isEquity[sym]; :0.0];

  config:first .risk.marginConfig;
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Reg T initial margin: 50% of notional
  notional * config[`initialMarginPct] % 100.0
 };

/ Calculate maintenance margin for a position
/ @param sym symbol - Trading symbol
/ @param qty float - Position quantity (signed)
/ @param price float - Current market price
/ @return float - Maintenance margin requirement
calcMaintenanceMargin:{[sym;qty;price]
  / Only applies to equities
  if[not .schema.isEquity[sym]; :0.0];

  config:first .risk.marginConfig;
  notional:.money.mul[.money.new[abs qty;`USD]; price]`amount;

  / Maintenance margin: 30% of notional (house requirement)
  notional * config[`maintenanceMarginPct] % 100.0
 };

/ Calculate buying power for margin account
/ @param equity float - Account equity
/ @param marginUsed float - Margin currently used
/ @return float - Available buying power
calcBuyingPower:{[equity;marginUsed]
  / Buying power = 2 * (equity - margin used)
  / Reg T allows 2:1 leverage on overnight positions
  (2.0 * equity) - marginUsed
 };

/ ═══════════════════════════════════════════════════════════════════
/ Pre-Trade Margin Check
/ ═══════════════════════════════════════════════════════════════════

/ Check if sufficient buying power is available for order
/ @param sym symbol - Trading symbol
/ @param qty float - Order quantity (signed)
/ @param price float - Order price
/ @return (boolean; reason; details) - (pass; reason; details dict)
checkMarginAvailable:{[sym;qty;price]
  config:first .risk.marginConfig;
  state:first .risk.marginState;

  / Skip if margin checking disabled
  if[not config`enabled; :(1b;`;())];

  / Only applies to equities
  if[not .schema.isEquity[sym]; :(1b;`;())];

  / Skip if in cash account (no margin)
  if[state[`buyingPower] = 0.0; :(1b;`;())];

  / Calculate margin requirement for this order
  marginReq:calcMarginRequirement[sym;qty;price];

  / Check if buying power sufficient
  if[state[`buyingPower] < marginReq;
    details:`required`available`shortfall!(marginReq;state`buyingPower;marginReq - state`buyingPower);
    :(0b;`insufficientMargin;details)
  ];

  / Pass
  (1b;`;())
 };

/ ═══════════════════════════════════════════════════════════════════
/ Account Sync (Integration with Alpaca)
/ ═══════════════════════════════════════════════════════════════════

/ Update margin state from Alpaca account object
/ @param account dict - Account data from Alpaca API
/ @return void
updateMarginState:{[account]
  / Extract margin fields
  acctEquity:account`equity;
  acctBuyingPower:account`buying_power;
  acctCash:account`cash;
  acctMaintenanceMargin:account`maintenance_margin;

  / Calculate derived fields
  usedMargin:acctEquity - acctCash;
  marginExcess:acctEquity - acctMaintenanceMargin;

  / Update state
  update equity:acctEquity, buyingPower:acctBuyingPower, cash:acctCash, marginUsed:usedMargin,
         maintenanceMargin:acctMaintenanceMargin, excessMargin:marginExcess,
         lastSync:.z.p from `.risk.marginState;

  / Check for margin call
  detectMarginCall[];

  / Update PDT account value (for PDT rule check)
  .risk.updateAccountValue[acctEquity];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Margin Call Detection
/ ═══════════════════════════════════════════════════════════════════

/ Detect and log margin calls
/ @return void
detectMarginCall:{[]
  state:first .risk.marginState;

  / Margin call triggered if equity < maintenance margin
  inCall:state[`equity] < state`maintenanceMargin;

  / If margin call active but wasn't before, log it
  if[inCall and not state`marginCallActive;
    deficiency:state[`maintenanceMargin] - state`equity;
    `.risk.marginCallHistory insert (.z.p;`maintenance;state`equity;state`maintenanceMargin;deficiency;0b;0Np);
    -1 "MARGIN CALL: Equity $",string[state`equity]," < Maintenance $",string[state`maintenanceMargin];
    update marginCallActive:1b from `.risk.marginState;
  ];

  / If margin call resolved, log it
  if[(not inCall) and state`marginCallActive;
    / Mark most recent call as resolved
    update resolved:1b, resolvedAt:.z.p from `.risk.marginCallHistory where (null resolvedAt) and time=(max;time) fby 1b;
    -1 "Margin call resolved";
    update marginCallActive:0b from `.risk.marginState;
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Utilities
/ ═══════════════════════════════════════════════════════════════════

/ Get margin status summary
/ @return dict - Margin status
marginStatus:{[]
  state:first .risk.marginState;
  config:first .risk.marginConfig;

  `enabled`equity`buyingPower`cash`marginUsed`maintenanceMargin`excessMargin`marginCallActive`initialMarginPct`maintenanceMarginPct!(
    config`enabled;
    state`equity;
    state`buyingPower;
    state`cash;
    state`marginUsed;
    state`maintenanceMargin;
    state`excessMargin;
    state`marginCallActive;
    config`initialMarginPct;
    config`maintenanceMarginPct
  )
 };

/ Get margin utilization percentage
/ @return float - Margin utilization (0-100%)
getMarginUtilization:{[]
  state:first .risk.marginState;
  if[state[`equity] = 0.0; :0.0];

  (state[`marginUsed] % state`equity) * 100.0
 };

\d .

/ Export namespace
-1 "  Margin management loaded: .risk.checkMarginAvailable, .risk.calcMarginRequirement, .risk.updateMarginState";
