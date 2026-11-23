/ ============================================================================
/ test_strategies.q - Comprehensive Strategy Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests for:
/   - Arbitrage strategies (arb.q, simpleArb.q)
/   - Market making strategies (mm.q, simpleMM.q)
/   - Options strategies (coveredCall, ironCondor, verticalSpread, straddle)
/   - Black-Scholes pricing and Greeks (optionsCommon.q)
/ ----------------------------------------------------------------------------
/ Test Coverage:
/   - Signal generation with mock market data
/   - Edge cases: zero spread, empty orderbook, expired options
/   - Black-Scholes calculation verification
/   - Greeks calculation (delta bounds, gamma positive, theta negative)
/   - Payoff calculation at expiry
/   - Multi-leg option structures
/ ----------------------------------------------------------------------------
/ Usage:
/   q test_strategies.q
/ ============================================================================

/ Load test framework
\l ../src/q/test/test_framework.q

/ Load dependencies
\l ../src/q/lib/money.q
\l ../src/q/strategy/arb.q
\l ../src/q/strategy/mm.q
\l ../src/q/strategy/optionsCommon.q
\l ../src/q/strategy/coveredCall.q
\l ../src/q/strategy/ironCondor.q
\l ../src/q/strategy/verticalSpread.q
\l ../src/q/strategy/straddle.q

// ============================================================================
// TEST FIXTURES
// ============================================================================

/ Mock orderbook fixtures
\d .fixtures

/ Standard 2-sided orderbook
standardOb:([]
  side:`ask`ask`ask`bid`bid`bid;
  price:100.5 100.6 100.7 100.4 100.3 100.2;
  volume:10.0 15.0 20.0 12.0 18.0 25.0
 );

/ Crossed orderbook (bid >= ask)
crossedOb:([]
  side:`ask`ask`ask`bid`bid`bid;
  price:100.0 100.1 100.2 100.5 100.4 100.3;
  volume:10.0 15.0 20.0 12.0 18.0 25.0
 );

/ Empty orderbook
emptyOb:([] side:`symbol$(); price:`float$(); volume:`float$());

/ Single-level orderbook
singleLevelOb:([]
  side:`ask`bid;
  price:100.5 100.4;
  volume:10.0 12.0
 );

\d .

// ============================================================================
// ARBITRAGE STRATEGY TESTS
// ============================================================================

\d .test.arb

/ Test directional cross detection - basic profit case
test_directionalCross_basicProfit:{[]
  / Setup: Buy from ex1 at 100, sell to ex2 at 102
  buyOb:([] side:`ask`ask; price:100.0 100.5; volume:10.0 15.0);
  sellOb:([] side:`bid`bid; price:102.0 101.5; volume:8.0 12.0);

  / Execute
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`ex1;`ex2;`BTCUSD];

  / Assert
  .test.assert["Cross detected"; not null cross];
  .test.assertNear["Volume is 8.0"; 8.0; cross`volume; 0.01];  / Limited by bid side
  .test.assert["Profit is positive"; cross[`profit] > 0.0];
  .test.assert["BuyExchange is ex1"; cross[`buyExchange]=`ex1];
  .test.assert["SellExchange is ex2"; cross[`sellExchange]=`ex2];
 };

/ Test no cross when bid < ask
test_directionalCross_noCross:{[]
  / Setup: Buy at 100, sell at 99 (no overlap)
  buyOb:([] side:`ask`ask; price:100.0 100.5; volume:10.0 15.0);
  sellOb:([] side:`bid`bid; price:99.0 98.5; volume:8.0 12.0);

  / Execute
  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`ex1;`ex2;`BTCUSD];

  / Assert
  .test.assert["No cross detected"; ()~cross];
 };

/ Test empty orderbook
test_directionalCross_emptyBuyOb:{[]
  buyOb:([] side:`symbol$(); price:`float$(); volume:`float$());
  sellOb:([] side:`bid`bid; price:102.0 101.5; volume:8.0 12.0);

  cross:.strategy.arb.detectDirectionalCross[buyOb;sellOb;`ex1;`ex2;`BTCUSD];

  .test.assert["Empty buy orderbook returns null"; ()~cross];
 };

/ Test spread calculation with fees
test_calculateSpread:{[]
  / Setup
  buyPrice:100.0;
  sellPrice:102.0;
  feeRate:0.001;  / 0.1%

  / Execute
  spread:.strategy.arb.calculateSpread[buyPrice;sellPrice;feeRate];

  / Assert
  .test.assertNear["GrossSpread is 2.0"; 2.0; spread`grossSpread; 0.01];
  / GrossPct = (102 - 100) / 100 * 100 = 2%
  .test.assertNear["GrossPct is 2%"; 2.0; spread`grossSpreadPct; 0.1];
  .test.assert["TotalFees > 0"; spread[`totalFees] > 0.0];
  .test.assert["NetSpread < GrossSpread"; spread[`netSpread] < spread`grossSpread];
 };

/ Test zero buyPrice signals error
test_calculateSpread_zeroBuyPrice:{[]
  .test.assertError["Zero buyPrice signals"; {.strategy.arb.calculateSpread[0.0;100.0;0.001]}];
 };

/ Test max buy volume calculation
test_maxBuyVolume_sufficientBalance:{[]
  / Setup
  balance:1000.0;  / Can afford 10 units at 100
  buyOb:([] side:`ask`ask`ask; price:100.0 101.0 102.0; volume:5.0 5.0 5.0);

  / Execute
  maxVol:.strategy.arb.maxBuyVolume[balance;buyOb];

  / Assert
  .test.assertNear["Can buy 10.0 units"; 10.0; maxVol; 0.01];
 };

/ Test max buy volume with insufficient balance
test_maxBuyVolume_insufficientBalance:{[]
  / Setup
  balance:250.0;  / Can afford 2.5 units at 100
  buyOb:([] side:`ask`ask; price:100.0 101.0; volume:5.0 5.0);

  / Execute
  maxVol:.strategy.arb.maxBuyVolume[balance;buyOb];

  / Assert
  .test.assertNear["Can buy 2.5 units"; 2.5; maxVol; 0.01];
 };

/ Test score opportunity
test_scoreOpportunity_fullExecution:{[]
  / Setup
  cross:`volume`revenue`fees`profit`buyExchange`sellExchange`pair!(10.0;1020.0;2.0;18.0;`ex1;`ex2;`BTCUSD);
  executableVolume:10.0;

  / Execute
  scored:.strategy.arb.scoreOpportunity[cross;executableVolume];

  / Assert
  .test.assertEqual["ExecutableVolume is 10.0"; 10.0; scored`executableVolume];
  .test.assertNear["TotalProfit is 18.0"; 18.0; scored`totalProfit; 0.01];
  .test.assert["VolumeRisk is 0 (full execution)"; scored[`volumeRisk]=0.0];
  .test.assert["Score > 0"; scored[`score] > 0.0];
 };

// ============================================================================
// MARKET MAKING STRATEGY TESTS
// ============================================================================

\d .test.mm

/ Test midpoint calculation with depth
test_midpoint_withDepth:{[]
  / Setup
  ob:([] side:`bid`bid`bid`ask`ask`ask;
          price:100.0 99.9 99.8 100.1 100.2 100.3;
          volume:10.0 15.0 20.0 12.0 18.0 25.0);

  / Execute
  mid:.strategy.mm.midpoint[ob;30.0];  / Use 30 units depth

  / Assert
  .test.assert["Midpoint calculated"; not null mid];
  .test.assert["Midpoint between 99.8 and 100.3"; (mid >= 99.8) and mid <= 100.3];
 };

/ Test simple midpoint (no depth weighting)
test_simpleMidpoint:{[]
  / Setup
  ob:([] side:`bid`bid`ask`ask;
          price:100.0 99.9 100.1 100.2;
          volume:10.0 15.0 12.0 18.0);

  / Execute
  mid:.strategy.mm.simpleMidpoint[ob];

  / Assert
  .test.assertNear["SimpleMidpoint is 100.05"; 100.05; mid; 0.01];
 };

/ Test empty orderbook returns null midpoint
test_midpoint_emptyOb:{[]
  emptyOb:([] side:`symbol$(); price:`float$(); volume:`float$());

  / Execute - function should handle empty orderbook gracefully
  mid:.strategy.mm.midpoint[emptyOb;10.0];

  / Assert
  .test.assert["Empty orderbook returns null"; null mid];
 };

/ Test crossed orderbook midpoint
test_midpoint_crossedBook:{[]
  / Setup: bid > ask (crossed)
  crossedOb:([] side:`bid`bid`ask`ask;
                  price:100.5 100.4 100.0 100.1;
                  volume:10.0 15.0 12.0 18.0);

  / Execute
  mid:.strategy.mm.midpoint[crossedOb;20.0];

  / Assert - should still return midpoint even if crossed
  .test.assert["Midpoint calculated for crossed book"; not null mid];
 };

/ Test generate quote with spread
test_generateQuote_validSpread:{[]
  / Setup
  midpoint:100.0;
  spreadBps:10.0;  / 0.1%

  / Execute
  quote:.strategy.mm.generateQuote[midpoint;spreadBps;1.0;1000.0];

  / Assert
  .test.assert["BidPrice < Midpoint"; quote[`bidPrice] < midpoint];
  .test.assert["AskPrice > Midpoint"; quote[`askPrice] > midpoint];
  .test.assertNear["Spread is 10bps"; spreadBps; quote`spreadBps; 0.1];
  .test.assertNear["Midpoint preserved"; midpoint; quote`midpoint; 0.001];
 };

/ Test generate quote with null midpoint
test_generateQuote_nullMidpoint:{[]
  quote:.strategy.mm.generateQuote[0n;10.0;1.0;1000.0];

  / Assert all prices are null
  .test.assert["BidPrice is null"; null quote`bidPrice];
  .test.assert["AskPrice is null"; null quote`askPrice];
  .test.assert["SpreadBps is null"; null quote`spreadBps];
 };

/ Test calculate order sizes with neutral position
test_calculateOrderSizes_neutralPosition:{[]
  / Setup
  baseSize:10.0;
  position:0.0;  / Neutral
  maxPosition:100.0;
  skewFactor:0.1;

  / Execute
  sizes:.strategy.mm.calculateOrderSizes[baseSize;position;maxPosition;skewFactor;0.01];

  / Assert
  .test.assertNear["BidSize equals BaseSize"; baseSize; sizes`bidSize; 0.01];
  .test.assertNear["AskSize equals BaseSize"; baseSize; sizes`askSize; 0.01];
 };

/ Test calculate order sizes with long position (skew to sell)
test_calculateOrderSizes_longPosition:{[]
  / Setup
  baseSize:10.0;
  position:50.0;  / 50% long
  maxPosition:100.0;
  skewFactor:0.1;

  / Execute
  sizes:.strategy.mm.calculateOrderSizes[baseSize;position;maxPosition;skewFactor;0.01];

  / Assert
  .test.assert["BidSize < BaseSize"; sizes[`bidSize] < baseSize];  / Reduce buying
  .test.assert["AskSize > BaseSize"; sizes[`askSize] > baseSize];  / Increase selling
 };

/ Test calculate order sizes with short position (skew to buy)
test_calculateOrderSizes_shortPosition:{[]
  / Setup
  baseSize:10.0;
  position:neg 50.0;  / 50% short
  maxPosition:100.0;
  skewFactor:0.1;

  / Execute
  sizes:.strategy.mm.calculateOrderSizes[baseSize;position;maxPosition;skewFactor;0.01];

  / Assert
  .test.assert["BidSize > BaseSize"; sizes[`bidSize] > baseSize];  / Increase buying
  .test.assert["AskSize < BaseSize"; sizes[`askSize] < baseSize];  / Reduce selling
 };

// ============================================================================
// BLACK-SCHOLES TESTS
// ============================================================================

\d .test.bs

/ Test Black-Scholes call option pricing
test_calculateBS_call:{[]
  / Setup (known inputs)
  S:100.0;  / Spot
  K:100.0;  / Strike (ATM)
  r:0.05;   / Risk-free rate
  T:1.0;    / 1 year to expiry
  sigma:0.2;  / 20% volatility

  / Execute
  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`call];

  / Assert
  .test.assert["Call price > 0"; callPrice > 0.0];
  .test.assert["Call price < Spot"; callPrice < S];  / ATM call cheaper than spot
  / For ATM call with S=100, K=100, r=0.05, T=1, sigma=0.2
  / Expected price ≈ 10.45 (Black-Scholes formula)
  .test.assertNear["Call price around 10.45"; 10.45; callPrice; 0.5];
 };

/ Test Black-Scholes put option pricing
test_calculateBS_put:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  putPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`put];

  / Assert
  .test.assert["Put price > 0"; putPrice > 0.0];
  .test.assert["Put price < Strike"; putPrice < K];
  / For ATM put with S=100, K=100, r=0.05, T=1, sigma=0.2
  / Expected price ≈ 5.57 (Black-Scholes formula, put-call parity)
  .test.assertNear["Put price around 5.57"; 5.57; putPrice; 0.5];
 };

/ Test expired option returns intrinsic value
test_calculateBS_expired:{[]
  / Setup
  S:110.0;  / Spot above strike
  K:100.0;
  r:0.05;
  T:0.0;    / Expired
  sigma:0.2;

  / Execute
  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`call];
  putPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`put];

  / Assert
  .test.assertNear["Expired call intrinsic value"; 10.0; callPrice; 0.01];  / S - K
  .test.assertNear["Expired put intrinsic value"; 0.0; putPrice; 0.01];     / max(K - S, 0) = 0
 };

/ Test negative spot price signals error
test_calculateBS_invalidSpot:{[]
  .test.assertError["Negative spot signals"; {.strategy.options.calculateBS[-100.0;100.0;0.05;1.0;0.2;`call]}];
 };

/ Test invalid option type signals error
test_calculateBS_invalidType:{[]
  .test.assertError["Invalid optType signals"; {.strategy.options.calculateBS[100.0;100.0;0.05;1.0;0.2;`invalid]}];
 };

// ============================================================================
// GREEKS TESTS
// ============================================================================

\d .test.greeks

q:0.0;  / Set dividend yield to 0 (crypto)

/ Test delta bounds for call option
test_greeks_call_deltaBounds:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];

  / Assert
  .test.assert["Call delta >= 0"; greeks[`delta] >= 0.0];
  .test.assert["Call delta <= 1"; greeks[`delta] <= 1.0];
  / ATM call delta should be around 0.5-0.6 (accounts for drift from r)
  .test.assertNear["ATM call delta around 0.5-0.6"; 0.55; greeks`delta; 0.1];
 };

/ Test delta bounds for put option
test_greeks_put_deltaBounds:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  / Assert
  .test.assert["Put delta <= 0"; greeks[`delta] <= 0.0];
  .test.assert["Put delta >= -1"; greeks[`delta] >= -1.0];
  / ATM put delta should be around -0.4 to -0.5 (accounts for drift from r)
  .test.assertNear["ATM put delta around -0.45"; -0.45; greeks`delta; 0.1];
 };

/ Test gamma is positive for both call and put
test_greeks_gammaPositive:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  callGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];
  putGreeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`put];

  / Assert
  .test.assert["Call gamma > 0"; callGreeks[`gamma] > 0.0];
  .test.assert["Put gamma > 0"; putGreeks[`gamma] > 0.0];
  / Gamma should be same for call and put with same params
  .test.assertNear["Call and Put gamma equal"; callGreeks`gamma; putGreeks`gamma; 0.0001];
 };

/ Test theta is negative for long call (time decay)
test_greeks_thetaNegativeForCall:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];

  / Assert
  / For long call, theta should be negative (loses value over time)
  .test.assert["Call theta < 0"; greeks[`theta] < 0.0];
 };

/ Test vega is positive (higher volatility = higher price)
test_greeks_vegaPositive:{[]
  / Setup
  S:100.0;
  K:100.0;
  r:0.05;
  T:1.0;
  sigma:0.2;

  / Execute
  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];

  / Assert
  .test.assert["Vega > 0"; greeks[`vega] > 0.0];
 };

/ Test expired option has zero Greeks (after verifying intrinsic value)
test_greeks_expiredOption:{[]
  / Setup
  S:110.0;  / Spot above strike for ITM call
  K:100.0;
  r:0.05;
  T:0.0;  / Expired
  sigma:0.2;

  / Execute
  callPrice:.strategy.options.calculateBS[S;K;r;T;sigma;`call];
  greeks:.strategy.options.calculateGreeks[S;K;r;T;sigma;`call];

  / Assert - verify intrinsic value first
  .test.assertNear["Expired call has intrinsic value"; 10.0; callPrice; 0.01];

  / Then verify Greeks are zero (no time value left)
  .test.assertNear["Delta is 0"; 0.0; greeks`delta; 0.01];
  .test.assertNear["Gamma is 0"; 0.0; greeks`gamma; 0.01];
  .test.assertNear["Theta is 0"; 0.0; greeks`theta; 0.01];
  .test.assertNear["Vega is 0"; 0.0; greeks`vega; 0.01];
  .test.assertNear["Rho is 0"; 0.0; greeks`rho; 0.01];
 };

// ============================================================================
// OPTIONS STRATEGY TESTS
// ============================================================================

\d .test.options

/ Test covered call structure
test_coveredCall_calculateMaxProfit:{[]
  / Setup
  entryPrice:100.0;
  strike:105.0;
  premium:2.0;  / Premium received per share
  qty:1;  / 1 contract = 100 shares

  / Execute
  result:.strategy.coveredCall.calculateMaxProfit[entryPrice;strike;premium;qty];

  / Assert
  / Max profit = (Strike - Entry + Premium) × 100
  .test.assertNear["Max profit is 700"; 700.0; result`maxProfit; 0.01];
  / Max loss = (Entry - Premium) × 100 (if stock goes to zero)
  .test.assertNear["Max loss is 9800"; 9800.0; result`maxLoss; 0.01];
  / Breakeven = Entry - Premium
  .test.assertNear["Breakeven is 98"; 98.0; result`breakeven; 0.01];
 };

/ Test iron condor max profit calculation
test_ironCondor_calculateMaxProfit:{[]
  / Setup
  netPremium:2.0;  / Net credit received
  wingWidth:5.0;   / $5 between strikes

  / Execute
  result:.strategy.ironCondor.calculateMaxProfit[netPremium;wingWidth];

  / Assert
  / Max profit = Net premium × 100
  .test.assertNear["Max profit is 200"; 200.0; result`maxProfit; 0.01];
  / Max loss = (Wing width - Net premium) × 100
  .test.assertNear["Max loss is 300"; 300.0; result`maxLoss; 0.01];
 };

/ Test straddle breakeven calculation
test_straddle_calculateBreakevens:{[]
  / Setup
  strike:100.0;
  callPremium:5.0;
  putPremium:4.0;

  / Execute
  result:.strategy.straddle.calculateBreakevens[strike;callPremium;putPremium];

  / Assert
  / Total premium = 5 + 4 = 9
  .test.assertNear["TotalPremium is 9"; 9.0; result`totalPremium; 0.01];
  / Upper breakeven = Strike + Total premium = 109
  .test.assertNear["Upper breakeven is 109"; 109.0; result`upperBreakeven; 0.01];
  / Lower breakeven = Strike - Total premium = 91
  .test.assertNear["Lower breakeven is 91"; 91.0; result`lowerBreakeven; 0.01];
  / Max loss = Total premium × 100 = 900
  .test.assertNear["Max loss is 900"; 900.0; result`maxLoss; 0.01];
 };

\d .

// ============================================================================
// RUN ALL TESTS
// ============================================================================

-1 "\n=== Running Strategy Tests ===\n";
.test.run[`.test.arb];
.test.run[`.test.mm];
.test.run[`.test.bs];
.test.run[`.test.greeks];
.test.run[`.test.options];

/ Exit with appropriate code
exit .test.failed
