/ Focused verification for Alpaca Phase 3 PDT/margin/settlement modules (#36)

\l tests/q/test_framework.q
\l src/q/schema/equity.q
\d .exchange
\d .
\l src/q/exchange/calendar.q
\l src/q/risk/init.q

/ Pin the PDT clock to a known trading date so the suite runs deterministically
/ regardless of when it executes (weekends, holidays). 2026.04.06 is a Monday
/ with no holiday adjacent in the 5-trading-day lookback window.
.risk.pdt.today:{2026.04.06};

reset_alpaca_phase3_fixtures:{[]
  .risk.initPDT[];
  .risk.initMargin[];
  .risk.initSettlement[];
 };

test_alpaca_phase3_pdt_allows_under_threshold:{[]
  reset_alpaca_phase3_fixtures[];

  .risk.updateAccountValue[10000.0];
  result:.risk.checkPDT[`AAPL;`buy;100.0];

  .test.assert["PDT allows first day trade when account is below threshold"; result 0];
  .test.assertEqual["Initial PDT day trade count is zero"; 0i; .risk.getDayTradeCount[]];
 };

test_alpaca_phase3_pdt_blocks_after_four_day_trades:{[]
  reset_alpaca_phase3_fixtures[];

  .risk.updateAccountValue[10000.0];
  .risk.recordDayTrade[`AAPL;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`MSFT;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`TSLA;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`NVDA;`buy;`sell;100.0;100.0;10.0];

  result:.risk.checkPDT[`GOOG;`buy;100.0];
  .test.assert["PDT rejects equities after fourth day trade"; not result 0];
  .test.assertEqual["PDT rejection reason is pdtBreach"; `pdtBreach; result 1];
  .test.assertEqual["PDT status reports four day trades"; 4i; .risk.pdtStatus[]`currentDayTrades];
 };

test_alpaca_phase3_pdt_bypasses_crypto:{[]
  reset_alpaca_phase3_fixtures[];

  .risk.updateAccountValue[10000.0];
  .risk.recordDayTrade[`AAPL;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`MSFT;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`TSLA;`buy;`sell;100.0;100.0;10.0];
  .risk.recordDayTrade[`NVDA;`buy;`sell;100.0;100.0;10.0];

  result:.risk.checkPDT[`BTCUSD;`buy;1.0];
  .test.assert["PDT bypasses crypto symbols"; result 0];
 };

test_alpaca_phase3_margin_calculates_and_checks_buying_power:{[]
  reset_alpaca_phase3_fixtures[];

  account:`equity`buying_power`cash`maintenance_margin!(10000.0;5000.0;8000.0;1500.0);
  .risk.updateMarginState[account];

  requirement:.risk.calcMarginRequirement[`AAPL;100.0;10.0];
  .test.assertNear["Initial margin requirement is 50 percent of notional"; 500.0; requirement; 0.01];

  result:.risk.checkMarginAvailable[`AAPL;100.0;10.0];
  .test.assert["Margin check passes when buying power covers requirement"; result 0];
  .test.assertNear["Buying power calculation uses Reg T 2:1 leverage"; 19000.0; .risk.calcBuyingPower[10000.0;1000.0]; 0.01];
 };

test_alpaca_phase3_margin_detects_call:{[]
  reset_alpaca_phase3_fixtures[];

  account:`equity`buying_power`cash`maintenance_margin!(1000.0;0.0;500.0;1500.0);
  .risk.updateMarginState[account];

  status:.risk.marginStatus[];
  .test.assert["Margin call becomes active when equity is below maintenance"; status`marginCallActive];
  .test.assertEqual["Margin call history records the event"; 1; count .risk.marginCallHistory];
 };

test_alpaca_phase3_settlement_tracks_unsettled_cash:{[]
  reset_alpaca_phase3_fixtures[];

  tradeDate:.z.d;
  settleDate:.risk.getSettlementDate[tradeDate;1i];
  .risk.recordSettlement[tradeDate;`AAPL;`sell;10.0;100.0];

  .test.assert["Settlement date moves forward"; settleDate > tradeDate];
  .test.assertNear["Sale proceeds are tracked as unsettled cash"; 1000.0; .risk.getUnsettledCash[]; 0.01];
  .test.assertEqual["Settlement tracking records the fill"; 1; count .risk.settlementTracking];
 };

-1 "Focused Alpaca Phase 3 tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];
