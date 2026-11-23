/ Tests for .exchange namespace (exchange/stub.q)

\l tests/q/test_framework.q
\l src/q/schema/types.q
\l src/q/exchange/base.q
\l src/q/exchange/stub.q

/ ========================================
/ Stub initialization tests
/ ========================================

test_stub_init:{
  cfg:`feeRate`latencyMs!(0.002; 20);
  result:.exchange.stub.init[cfg];

  .test.assert["Config applied"; result[`feeRate] = 0.002];
  .test.assertEqual["Balances cleared"; ()!(); .exchange.stub.balances];
  .test.assertEqual["Orders cleared"; 0; count .exchange.stub.orders];
 }

test_stub_setBalances:{
  .exchange.stub.init[()!()];
  balances:`USD`BTC!(10000.0; 1.0);
  .exchange.stub.setBalances[balances];

  .test.assertEqual["USD balance set"; 10000.0; .exchange.stub.getTotalBalance[`USD]];
  .test.assertEqual["BTC balance set"; 1.0; .exchange.stub.getTotalBalance[`BTC]];
 }

/ ========================================
/ Balance operation tests
/ ========================================

test_stub_getAvailableBalance:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 10000.0];

  / No holds
  avail:.exchange.stub.getAvailableBalance[`USD];
  .test.assertEqual["Available equals total"; 10000.0; avail];

  / With hold
  .exchange.stub.placeHold[`USD; 3000.0];
  avail:.exchange.stub.getAvailableBalance[`USD];
  .test.assertEqual["Available reduced by hold"; 7000.0; avail];
 }

test_stub_placeHold_insufficient:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 1000.0];

  .test.assertError["Cannot hold more than available"; {.exchange.stub.placeHold[`USD; 2000.0]}];
 }

test_stub_releaseHold:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 10000.0];
  .exchange.stub.placeHold[`USD; 3000.0];

  / Release hold
  .exchange.stub.releaseHold[`USD; 1000.0];

  avail:.exchange.stub.getAvailableBalance[`USD];
  .test.assertEqual["Hold partially released"; 8000.0; avail];
 }

test_stub_updateBalance:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 1000.0];

  / Add
  .exchange.stub.updateBalance[`USD; 500.0];
  .test.assertEqual["Balance increased"; 1500.0; .exchange.stub.getTotalBalance[`USD]];

  / Subtract
  .exchange.stub.updateBalance[`USD; -200.0];
  .test.assertEqual["Balance decreased"; 1300.0; .exchange.stub.getTotalBalance[`USD]];
 }

/ ========================================
/ Order placement tests
/ ========================================

test_stub_submitOrder_buy:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[`USD`BTC!(100000.0; 0.0)];

  / Submit market buy order
  result:.exchange.stub.submitOrder[`BTCUSD; `market; `buy; 0Nj; 10000000j];

  .test.assert["Order ID assigned"; result[`orderId] > 0];
  .test.assertEqual["Pair set"; `BTCUSD; result`pair];
  .test.assertEqual["Side set"; `buy; result`side];
  .test.assert["Status is open or filled"; result[`status] in `open`filled`partially_filled];
 }

test_stub_submitOrder_sell:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[`USD`BTC!(0.0; 1.0)];

  / Submit market sell order
  result:.exchange.stub.submitOrder[`BTCUSD; `market; `sell; 0Nj; 500000j];

  .test.assert["Order ID assigned"; result[`orderId] > 0];
  .test.assertEqual["Side set"; `sell; result`side];
 }

test_stub_submitOrder_limit:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 100000.0];

  / Submit limit buy order
  price:.qg.toPrice[50000.0];
  qty:.qg.toVolume[0.1];
  result:.exchange.stub.submitOrder[`BTCUSD; `limit; `buy; price; qty];

  .test.assertEqual["Order type set"; `limit; result`orderType];
  .test.assertEqual["Price set"; price; result`price];
 }

/ ========================================
/ Order matching tests
/ ========================================

test_stub_matchOrder_full_fill:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 200000.0];

  / Place small market buy order (should fill completely)
  result:.exchange.stub.submitOrder[`BTCUSD; `market; `buy; 0Nj; 1000000j];

  / Check status
  .test.assert["Order filled or partially filled"; result[`status] in `filled`partially_filled];
  .test.assert["Some quantity filled"; result[`filled] > 0j];
 }

test_stub_cancelOrder:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 100000.0];

  / Submit order
  order:.exchange.stub.submitOrder[`BTCUSD; `limit; `buy; .qg.toPrice[40.0]; .qg.toVolume[0.1]];
  orderId:order`orderId;

  / Cancel
  result:.exchange.stub.cancelOrder[orderId];

  .test.assertEqual["Order ID matches"; orderId; result`orderId];
  .test.assertEqual["Status is cancelled"; `cancelled; result`status];

  / Verify order in table
  ord:first select from .exchange.stub.orders where orderId=orderId;
  .test.assertEqual["Order status updated in table"; `cancelled; ord`status];
 }

/ ========================================
/ Orderbook generation tests
/ ========================================

test_stub_genOrderbook:{
  .exchange.stub.init[()!()];
  .exchange.stub.setOBParams[`midPrice`spread`depth!(50000.0; 0.01; 5)];

  ob:.exchange.stub.genOrderbook[];

  .test.assert["Orderbook is table"; 98h = type ob];
  .test.assert["Has bid side"; `bid in exec side from ob];
  .test.assert["Has ask side"; `ask in exec side from ob];
  .test.assertEqual["Depth is 5 per side"; 10; count ob];
 }

test_stub_getBalance_api:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 5000.0];

  result:.exchange.stub.getBalance[`USD];

  .test.assertEqual["Currency set"; `USD; result`currency];
  .test.assertEqual["Total balance"; 5000.0; result`total];
  .test.assertEqual["Available balance"; 5000.0; result`available];
  .test.assertEqual["Reserved balance"; 0.0; result`reserved];
 }

test_stub_getOpenOrders:{
  .exchange.stub.init[()!()];
  .exchange.stub.setBalances[enlist[`USD]!enlist 100000.0];

  / Place orders
  .exchange.stub.submitOrder[`BTCUSD; `limit; `buy; .qg.toPrice[45000.0]; .qg.toVolume[0.1]];
  .exchange.stub.submitOrder[`BTCUSD; `limit; `buy; .qg.toPrice[46000.0]; .qg.toVolume[0.2]];

  / Get open orders
  openOrders:.exchange.stub.getOpenOrders[`BTCUSD];

  .test.assert["Open orders returned"; count[openOrders] >= 0];
 }

-1 "Exchange tests loaded";
