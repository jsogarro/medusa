/ Medusa — Money Library Integration Tests
/ Real-world trading scenario tests

/ Load the money library
\l src/q/lib/money.q

/ Test framework
.test.assert:{[condition;msg]
  if[not condition;
    -1 "FAIL: ",msg;
    '"Test failed: ",msg
  ];
  -1 "PASS: ",msg;
 };

-1 "";
-1 "========================================";
-1 "  Money Library Integration Tests";
-1 "========================================";
-1 "";

/ ========================================
/ Scenario 1: Simple Trade P&L Calculation
/ ========================================

-1 "Scenario 1: Trade P&L Calculation";
-1 "----------------------------------------";

/ Buy 0.5 BTC at $50,000 per BTC
btcQuantity: 0.5;
entryPrice: .money.new[50000; `USD];
entryCost: .money.mul[entryPrice; btcQuantity];

.test.assert[entryCost[`amount] = 25000.0; "Entry cost: $25,000"];
.test.assert[entryCost[`currency] = `USD; "Entry cost in USD"];
-1 "  Entry: Bought ",string[btcQuantity]," BTC @ ",.money.fmt[entryPrice];
-1 "  Cost: ",.money.fmt[entryCost];

/ Sell 0.5 BTC at $52,000 per BTC
exitPrice: .money.new[52000; `USD];
exitValue: .money.mul[exitPrice; btcQuantity];

.test.assert[exitValue[`amount] = 26000.0; "Exit value: $26,000"];
-1 "  Exit: Sold ",string[btcQuantity]," BTC @ ",.money.fmt[exitPrice];
-1 "  Value: ",.money.fmt[exitValue];

/ Calculate P&L
pnl: .money.sub[exitValue; entryCost];
.test.assert[pnl[`amount] = 1000.0; "P&L: $1,000 profit"];
.test.assert[pnl[`currency] = `USD; "P&L in USD"];
-1 "  P&L: ",.money.fmt[pnl]," profit";

-1 "";

/ ========================================
/ Scenario 2: Portfolio Valuation
/ ========================================

-1 "Scenario 2: Portfolio Valuation";
-1 "----------------------------------------";

/ Portfolio holdings
btcHolding: 2.5;
ethHolding: 10.0;

/ Current prices
btcPrice: .money.new[50000; `USD];
ethPrice: .money.new[3000; `USD];

/ Calculate position values
btcValue: .money.mul[btcPrice; btcHolding];
ethValue: .money.mul[ethPrice; ethHolding];

.test.assert[btcValue[`amount] = 125000.0; "BTC position: $125,000"];
.test.assert[ethValue[`amount] = 30000.0; "ETH position: $30,000"];

-1 "  BTC: ",string[btcHolding]," @ ",.money.fmt[btcPrice]," = ",.money.fmt[btcValue];
-1 "  ETH: ",string[ethHolding]," @ ",.money.fmt[ethPrice]," = ",.money.fmt[ethValue];

/ Total portfolio value
portfolioValue: .money.add[btcValue; ethValue];
.test.assert[portfolioValue[`amount] = 155000.0; "Portfolio: $155,000"];
-1 "  Total: ",.money.fmt[portfolioValue];

-1 "";

/ ========================================
/ Scenario 3: Fee Calculation
/ ========================================

-1 "Scenario 3: Trading Fee Calculation";
-1 "----------------------------------------";

/ Trade size
tradeSize: .money.new[10000; `USD];
.test.assert[tradeSize[`amount] = 10000.0; "Trade size: $10,000"];
-1 "  Trade Size: ",.money.fmt[tradeSize];

/ Exchange fee: 0.1% (0.001)
feeRate: 0.001;
fee: .money.mul[tradeSize; feeRate];

.test.assert[fee[`amount] = 10.0; "Fee: $10"];
.test.assert[fee[`currency] = `USD; "Fee in USD"];
-1 "  Fee (0.1%): ",.money.fmt[fee];

/ Net proceeds after fee
netProceeds: .money.sub[tradeSize; fee];
.test.assert[netProceeds[`amount] = 9990.0; "Net: $9,990"];
-1 "  Net Proceeds: ",.money.fmt[netProceeds];

-1 "";

/ ========================================
/ Scenario 4: Cross-Currency Trade
/ ========================================

-1 "Scenario 4: Cross-Currency Trade";
-1 "----------------------------------------";

/ Start with USD
usdBalance: .money.new[10000; `USD];
-1 "  Starting Balance: ",.money.fmt[usdBalance];

/ Convert to EUR
eurBalance: .money.convert[usdBalance; `EUR];
.test.assert[eurBalance[`currency] = `EUR; "Converted to EUR"];
-1 "  After conversion: ",.money.fmt[eurBalance]," (rate: 0.855)";

/ Simulate trade profit in EUR
profit: .money.new[500; `EUR];
newEurBalance: .money.add[eurBalance; profit];
-1 "  Trade profit: ",.money.fmt[profit];
-1 "  New EUR balance: ",.money.fmt[newEurBalance];

/ Convert back to USD
finalUsdBalance: .money.convert[newEurBalance; `USD];
.test.assert[finalUsdBalance[`currency] = `USD; "Converted back to USD"];
-1 "  Final USD balance: ",.money.fmt[finalUsdBalance];

-1 "";

/ ========================================
/ Scenario 5: Position Sizing
/ ========================================

-1 "Scenario 5: Position Sizing (Risk Management)";
-1 "----------------------------------------";

/ Account balance
accountBalance: .money.new[100000; `USD];
-1 "  Account Balance: ",.money.fmt[accountBalance];

/ Risk 2% of account per trade
riskPercent: 0.02;
riskAmount: .money.mul[accountBalance; riskPercent];

.test.assert[riskAmount[`amount] = 2000.0; "Risk: $2,000 (2%)"];
-1 "  Risk per trade (2%): ",.money.fmt[riskAmount];

/ Entry and stop loss
entryPrice2: .money.new[50000; `USD];
stopPrice: .money.new[49000; `USD];
stopDistance: .money.sub[entryPrice2; stopPrice];

.test.assert[stopDistance[`amount] = 1000.0; "Stop distance: $1,000"];
-1 "  Entry: ",.money.fmt[entryPrice2];
-1 "  Stop: ",.money.fmt[stopPrice];
-1 "  Stop distance: ",.money.fmt[stopDistance];

/ Calculate position size
/ Position Size = Risk Amount / Stop Distance
positionSize: riskAmount[`amount] % stopDistance[`amount];
.test.assert[positionSize = 2.0; "Position size: 2.0 BTC"];
-1 "  Position Size: ",string[positionSize]," BTC";

/ Verify total risk
totalRisk: .money.mul[stopDistance; positionSize];
.test.assert[.money.eq[totalRisk; riskAmount]; "Total risk matches"];
-1 "  Total Risk: ",.money.fmt[totalRisk];

-1 "";

/ ========================================
/ Scenario 6: Multi-Asset Portfolio Comparison
/ ========================================

-1 "Scenario 6: Multi-Asset Portfolio Comparison";
-1 "----------------------------------------";

/ Create portfolio positions
positions: ([]
  asset: `BTC`ETH`USD;
  quantity: 1.5 2.0 5000.0;
  price: (.money.new[50000;`USD]; .money.new[3000;`USD]; .money.new[1;`USD])
 );

/ Calculate individual position values
positions: update value: {.money.mul[x;y]}[price;quantity] from positions;

-1 "  Portfolio Positions:";
{
  -1 "    ",string[x`asset],": ",string[x`quantity]," @ ",.money.fmt[x`price],
     " = ",.money.fmt[x`value]
 } each positions;

/ Sum total portfolio value using helper function
sumPositions:{[values]
  if[1 = count values; :first values];
  first over {.money.add[x;y]}/[values]
 };

totalValue: sumPositions[positions`value];
.test.assert[totalValue[`amount] = 86000.0; "Total: $86,000"];
-1 "  Total Portfolio Value: ",.money.fmt[totalValue];

-1 "";

/ ========================================
/ Scenario 7: Dollar-Cost Averaging
/ ========================================

-1 "Scenario 7: Dollar-Cost Averaging";
-1 "----------------------------------------";

/ Invest $1000 USD per week at different BTC prices
investments: ([]
  week: 1 2 3 4;
  amount: (.money.new[1000;`USD]; .money.new[1000;`USD];
           .money.new[1000;`USD]; .money.new[1000;`USD]);
  btcPrice: (.money.new[50000;`USD]; .money.new[48000;`USD];
             .money.new[52000;`USD]; .money.new[51000;`USD])
 );

/ Calculate BTC purchased each week
investments: update btcPurchased: {x[`amount] % y[`amount]}[amount;btcPrice] from investments;

-1 "  Weekly Investments:";
{
  -1 "    Week ",string[x`week],": ",.money.fmt[x`amount]," @ ",.money.fmt[x`btcPrice],
     " = ",string[x`btcPurchased]," BTC"
 } each investments;

/ Total invested and BTC accumulated
totalInvested: {.money.add[x;y]}/[investments`amount];
totalBTC: sum investments`btcPurchased;

.test.assert[totalInvested[`amount] = 4000.0; "Total invested: $4,000"];
.test.assert[totalBTC > 0.078; "Total BTC > 0.078"];
-1 "  Total Invested: ",.money.fmt[totalInvested];
-1 "  Total BTC: ",string[totalBTC]," BTC";

/ Average cost per BTC
avgCost: .money.div[totalInvested; totalBTC];
-1 "  Average Cost: ",.money.fmt[avgCost]," per BTC";

/ Current value (using last price)
currentBtcPrice: last investments`btcPrice;
currentValue: .money.mul[currentBtcPrice; totalBTC];
-1 "  Current Value: ",.money.fmt[currentValue];

/ Total P&L
dcaPnl: .money.sub[currentValue; totalInvested];
-1 "  P&L: ",.money.fmt[dcaPnl];

-1 "";
-1 "========================================";
-1 "  All Integration Tests Passed!";
-1 "========================================";
-1 "";

/ Exit successfully
exit 0;
