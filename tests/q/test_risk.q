/ Tests for .risk namespace (risk/*.q)

\l tests/q/test_framework.q
\l src/q/risk/init.q

/ ========================================
/ Position limits tests
/ ========================================

test_risk_setPositionLimit:{
  / Set strategy/symbol limit
  .risk.setPositionLimit[`testStrat; `BTCUSD; 1000000j; 500000j];

  entry:.risk.positionLimits[(`testStrat;`BTCUSD)];
  .test.assertEqual["Max long set"; 1000000j; entry`maxLongQty];
  .test.assertEqual["Max short set"; 500000j; entry`maxShortQty];
  .test.assertEqual["Current position zero"; 0j; entry`currentPosition];
 }

test_risk_setGlobalPositionLimit:{
  / Set global symbol limit
  .risk.setGlobalPositionLimit[`ETHUSD; 5000000j; 3000000j];

  entry:.risk.globalPositionLimits[`ETHUSD];
  .test.assertEqual["Global max long set"; 5000000j; entry`maxLongQty];
  .test.assertEqual["Global max short set"; 3000000j; entry`maxShortQty];
 }

test_risk_updatePosition:{
  / Set limits
  .risk.setPositionLimit[`strat1; `BTCUSD; 2000000j; 1000000j];
  .risk.setGlobalPositionLimit[`BTCUSD; 10000000j; 5000000j];

  / Buy 500k (positive qty)
  .risk.updatePosition[`strat1; `BTCUSD; 500000j];

  stratEntry:.risk.positionLimits[(`strat1;`BTCUSD)];
  .test.assertEqual["Strategy position updated"; 500000j; stratEntry`currentPosition];

  globalEntry:.risk.globalPositionLimits[`BTCUSD];
  .test.assertEqual["Global position updated"; 500000j; globalEntry`currentPosition];

  / Sell 200k (negative qty)
  .risk.updatePosition[`strat1; `BTCUSD; -200000j];

  stratEntry:.risk.positionLimits[(`strat1;`BTCUSD)];
  .test.assertEqual["Strategy position reduced"; 300000j; stratEntry`currentPosition];
 }

test_risk_checkPositionLimit_pass:{
  / Set limits
  .risk.setPositionLimit[`strat2; `ETHUSD; 1000000j; 500000j];
  .risk.setGlobalPositionLimit[`ETHUSD; 5000000j; 3000000j];

  / Check valid buy order
  result:.risk.checkPositionLimit[`strat2; `ETHUSD; `buy; 500000j];
  .test.assert["Buy within limit passes"; result 0];
  .test.assertEqual["Reason is null"; `; result 1];
 }

test_risk_checkPositionLimit_strategy_long_breach:{
  / Set limits
  .risk.setPositionLimit[`strat3; `BTCUSD; 1000000j; 500000j];
  .risk.setGlobalPositionLimit[`BTCUSD; 10000000j; 5000000j];

  / Try to buy beyond limit
  result:.risk.checkPositionLimit[`strat3; `BTCUSD; `buy; 2000000j];
  .test.assert["Exceeds limit fails"; not result 0];
  .test.assertEqual["Reason is strategyLongLimitExceeded"; `strategyLongLimitExceeded; result 1];
 }

test_risk_checkPositionLimit_strategy_short_breach:{
  / Set limits
  .risk.setPositionLimit[`strat4; `BTCUSD; 1000000j; 500000j];
  .risk.setGlobalPositionLimit[`BTCUSD; 10000000j; 5000000j];

  / Try to sell beyond short limit
  result:.risk.checkPositionLimit[`strat4; `BTCUSD; `sell; 1000000j];
  .test.assert["Exceeds short limit fails"; not result 0];
  .test.assertEqual["Reason is strategyShortLimitExceeded"; `strategyShortLimitExceeded; result 1];
 }

test_risk_checkPositionLimit_global_breach:{
  / Set limits where global is tighter
  .risk.setPositionLimit[`strat5; `BTCUSD; 5000000j; 3000000j];
  .risk.setGlobalPositionLimit[`BTCUSD; 1000000j; 500000j];

  / Try to buy beyond global limit
  result:.risk.checkPositionLimit[`strat5; `BTCUSD; `buy; 2000000j];
  .test.assert["Exceeds global limit fails"; not result 0];
  .test.assertEqual["Reason is globalLongLimitExceeded"; `globalLongLimitExceeded; result 1];
 }

/ ========================================
/ Order size limits tests
/ ========================================

test_risk_setOrderSizeLimit:{
  / Set strategy limit
  .risk.setOrderSizeLimit[`strat6; 100000j; 50000000j];

  entry:.risk.orderSizeLimits[`strat6];
  .test.assertEqual["Min order size set"; 100000j; entry`minOrderQty];
  .test.assertEqual["Max order size set"; 50000000j; entry`maxOrderQty];
 }

test_risk_setGlobalOrderSizeLimit:{
  / Set global limit
  .risk.setGlobalOrderSizeLimit[10000j; 100000000j];

  entry:first .risk.globalOrderSizeLimits;
  .test.assertEqual["Global min set"; 10000j; entry`minOrderQty];
  .test.assertEqual["Global max set"; 100000000j; entry`maxOrderQty];
 }

test_risk_checkOrderSizeLimit_pass:{
  / Set limits
  .risk.setOrderSizeLimit[`strat7; 100000j; 10000000j];
  .risk.setGlobalOrderSizeLimit[50000j; 50000000j];

  / Check valid order size
  result:.risk.checkOrderSizeLimit[`strat7; 500000j];
  .test.assert["Valid size passes"; result 0];
 }

test_risk_checkOrderSizeLimit_too_small:{
  / Set limits
  .risk.setOrderSizeLimit[`strat8; 100000j; 10000000j];
  .risk.setGlobalOrderSizeLimit[50000j; 50000000j];

  / Order too small
  result:.risk.checkOrderSizeLimit[`strat8; 10000j];
  .test.assert["Too small fails"; not result 0];
  .test.assertEqual["Reason is belowMinOrderSize"; `belowMinOrderSize; result 1];
 }

test_risk_checkOrderSizeLimit_too_large:{
  / Set limits
  .risk.setOrderSizeLimit[`strat9; 100000j; 1000000j];
  .risk.setGlobalOrderSizeLimit[50000j; 50000000j];

  / Order too large
  result:.risk.checkOrderSizeLimit[`strat9; 2000000j];
  .test.assert["Too large fails"; not result 0];
  .test.assertEqual["Reason is aboveMaxOrderSize"; `aboveMaxOrderSize; result 1];
 }

/ ========================================
/ Emergency stop tests
/ ========================================

test_risk_emergencyStop_initial_state:{
  / Emergency stop should be inactive initially
  state:first .risk.emergencyStopState;
  .test.assert["Initially inactive"; not state`active];
 }

test_risk_activateEmergencyStop:{
  / Activate emergency stop
  .risk.activateEmergencyStop[`testReason; `testUser];

  state:first .risk.emergencyStopState;
  .test.assert["Emergency stop active"; state`active];
  .test.assertEqual["Reason set"; `testReason; state`reason];
  .test.assertEqual["User set"; `testUser; state`activatedBy];

  / Deactivate for cleanup
  .risk.deactivateEmergencyStop[`testUser];
 }

test_risk_checkEmergencyStop:{
  / Deactivate first
  .risk.deactivateEmergencyStop[`cleanup];

  / Check when inactive
  result:.risk.checkEmergencyStop[];
  .test.assert["Passes when inactive"; result 0];

  / Activate
  .risk.activateEmergencyStop[`test; `system];

  / Check when active
  result:.risk.checkEmergencyStop[];
  .test.assert["Fails when active"; not result 0];
  .test.assertEqual["Reason is emergencyStopActive"; `emergencyStopActive; result 1];

  / Deactivate cleanup
  .risk.deactivateEmergencyStop[`cleanup];
 }

/ ========================================
/ Drawdown monitor tests
/ ========================================

test_risk_updatePnL_no_breach:{
  / Initialize drawdown state
  update currentPnL:0j,peakPnL:0j,currentDrawdown:0.0,maxDrawdown:0.0,breached:0b from `.risk.drawdownState;

  / Update with positive P&L
  breached:.risk.updatePnL[1000000j];

  .test.assert["No breach on positive P&L"; not breached];

  state:first .risk.drawdownState;
  .test.assertEqual["Current P&L updated"; 1000000j; state`currentPnL];
  .test.assertEqual["Peak P&L updated"; 1000000j; state`peakPnL];
 }

test_risk_updatePnL_drawdown:{
  / Set peak P&L
  update currentPnL:1000000j,peakPnL:1000000j,currentDrawdown:0.0,maxDrawdown:0.0,breached:0b from `.risk.drawdownState;
  update maxDrawdownPct:0.2 from `.risk.drawdownState;

  / Update with loss (but within threshold)
  breached:.risk.updatePnL[900000j];

  .test.assert["No breach within threshold"; not breached];

  state:first .risk.drawdownState;
  .test.assertNear["Drawdown calculated"; 0.1; state`currentDrawdown; 0.01];
 }

test_risk_updatePnL_breach:{
  / Set peak P&L and threshold
  update currentPnL:1000000j,peakPnL:1000000j,currentDrawdown:0.0,maxDrawdown:0.0,breached:0b from `.risk.drawdownState;
  update maxDrawdownPct:0.1 from `.risk.drawdownState;

  / Deactivate emergency stop first
  .risk.deactivateEmergencyStop[`cleanup];

  / Update with large loss (breach threshold)
  breached:.risk.updatePnL[800000j];

  .test.assert["Breach detected"; breached];

  state:first .risk.drawdownState;
  .test.assert["Breached flag set"; state`breached];

  / Emergency stop should be active
  esState:first .risk.emergencyStopState;
  .test.assert["Emergency stop activated"; esState`active];

  / Cleanup
  .risk.deactivateEmergencyStop[`cleanup];
  update breached:0b from `.risk.drawdownState;
 }

/ ========================================
/ Full validation pipeline tests
/ ========================================

test_risk_validateOrder_pass:{
  / Set up all limits
  .risk.setPositionLimit[`stratTest; `BTCUSD; 10000000j; 5000000j];
  .risk.setGlobalPositionLimit[`BTCUSD; 100000000j; 50000000j];
  .risk.setOrderSizeLimit[`stratTest; 100000j; 10000000j];
  .risk.setGlobalOrderSizeLimit[50000j; 50000000j];
  .risk.deactivateEmergencyStop[`cleanup];
  update breached:0b from `.risk.drawdownState;

  / Validate order
  result:.risk.validateOrder[`stratTest; `BTCUSD; `coinbase; `buy; 500000j; 50000000000j];

  .test.assert["Validation passes"; result 0];
  .test.assertEqual["Reason is null"; `; result 1];
 }

test_risk_validateOrder_emergency_stop:{
  / Activate emergency stop
  .risk.activateEmergencyStop[`test; `system];

  / Validate order
  result:.risk.validateOrder[`stratTest; `BTCUSD; `coinbase; `buy; 500000j; 50000000000j];

  .test.assert["Validation fails"; not result 0];

  / Cleanup
  .risk.deactivateEmergencyStop[`cleanup];
 }

-1 "Risk tests loaded";
