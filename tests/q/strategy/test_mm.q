/ ============================================================================
/ test_mm.q - Market Making Library Tests
/ ============================================================================

/ Load library
\l src/q/strategy/mm.q

/ Simple assertion framework
assert:{[cond;msg] if[not cond;-1 "FAIL: ",msg;exit 1]};

/ Test fixtures
.test.validOrderbook:([]
  side:`bid`bid`bid`ask`ask`ask;
  price:99.50 99.00 98.50 100.50 101.00 101.50;
  volume:1.0 2.0 1.0 1.0 2.0 1.0
 );

.test.emptyOrderbook:([] side:`symbol$(); price:`float$(); volume:`float$());

.test.bidsOnlyOrderbook:([]
  side:`bid`bid`bid;
  price:99.50 99.00 98.50;
  volume:1.0 2.0 1.0
 );

.test.asksOnlyOrderbook:([]
  side:`ask`ask`ask;
  price:100.50 101.00 101.50;
  volume:1.0 2.0 1.0
 );

// ============================================================================
/ ORDERBOOK VALIDATION TESTS
// ============================================================================

-1 "\n=== Testing Orderbook Validation ===";

/ Test: Valid orderbook passes validation
assert[.strategy.mm.validateOrderbook[.test.validOrderbook]; "Valid orderbook should pass"];

/ Test: Empty orderbook is still structurally valid
assert[.strategy.mm.validateOrderbook[.test.emptyOrderbook]; "Empty orderbook should be structurally valid"];

/ Test: Invalid table type fails
assert[not .strategy.mm.validateOrderbook[`invalid]; "Non-table should fail validation"];

/ Test: Missing required columns fails
invalidOb:([] side:`bid`ask; price:99.0 100.0);
assert[not .strategy.mm.validateOrderbook[invalidOb]; "Missing volume column should fail"];

/ Test: Invalid side values fail
invalidSides:([] side:`bid`invalid; price:99.0 100.0; volume:1.0 1.0);
assert[not .strategy.mm.validateOrderbook[invalidSides]; "Invalid side values should fail"];

/ Test: Zero/negative prices fail
invalidPrices:([] side:`bid`ask; price:0.0 -1.0; volume:1.0 1.0);
assert[not .strategy.mm.validateOrderbook[invalidPrices]; "Zero/negative prices should fail"];

/ Test: Zero/negative volumes fail
invalidVolumes:([] side:`bid`ask; price:99.0 100.0; volume:0.0 -1.0);
assert[not .strategy.mm.validateOrderbook[invalidVolumes]; "Zero/negative volumes should fail"];

-1 "Orderbook validation tests: PASSED";

// ============================================================================
/ ORDERBOOK FILTERING TESTS
// ============================================================================

-1 "\n=== Testing Orderbook Filtering ===";

/ Test: getBids extracts only bids in correct order
bids:.strategy.mm.getBids[.test.validOrderbook];
assert[(all `bid = bids`side); "getBids should only return bids"];
assert[(99.50 99.00 98.50) ~ bids`price; "getBids should sort descending by price"];

/ Test: getAsks extracts only asks in correct order
asks:.strategy.mm.getAsks[.test.validOrderbook];
assert[(all `ask = asks`side); "getAsks should only return asks"];
assert[(100.50 101.00 101.50) ~ asks`price; "getAsks should sort ascending by price"];

/ Test: bestBid returns highest bid
bestBid:.strategy.mm.bestBid[.test.validOrderbook];
assert[99.50 = bestBid; "bestBid should return 99.50"];

/ Test: bestAsk returns lowest ask
bestAsk:.strategy.mm.bestAsk[.test.validOrderbook];
assert[100.50 = bestAsk; "bestAsk should return 100.50"];

/ Test: bestBid returns null for empty/asks-only orderbook
assert[null .strategy.mm.bestBid[.test.emptyOrderbook]; "bestBid should return null for empty orderbook"];
assert[null .strategy.mm.bestBid[.test.asksOnlyOrderbook]; "bestBid should return null for asks-only orderbook"];

/ Test: bestAsk returns null for empty/bids-only orderbook
assert[null .strategy.mm.bestAsk[.test.emptyOrderbook]; "bestAsk should return null for empty orderbook"];
assert[null .strategy.mm.bestAsk[.test.bidsOnlyOrderbook]; "bestAsk should return null for bids-only orderbook"];

-1 "Orderbook filtering tests: PASSED";

// ============================================================================
/ MIDPOINT CALCULATION TESTS
// ============================================================================

-1 "\n=== Testing Midpoint Calculation ===";

/ Test: simpleMidpoint calculation
simpleMid:.strategy.mm.simpleMidpoint[.test.validOrderbook];
expectedSimpleMid:(99.50 + 100.50) % 2.0; / = 100.0
assert[abs[simpleMid - expectedSimpleMid] < 0.01; "simpleMidpoint should be 100.0"];

/ Test: weighted midpoint with depth
/ With depth=2.0 (2 units on each side)
/ Bids: 99.50*1.0 + 99.00*1.0 = 198.50 / 2.0 = 99.25
/ Asks: 100.50*1.0 + 101.00*1.0 = 201.50 / 2.0 = 100.75
/ Midpoint: (99.25 + 100.75) / 2 = 100.0
weightedMid:.strategy.mm.midpoint[.test.validOrderbook; 2.0];
assert[abs[weightedMid - 100.0] < 0.01; "weighted midpoint should be ~100.0"];

/ Test: midpoint with large depth (uses all liquidity)
largeMid:.strategy.mm.midpoint[.test.validOrderbook; 100.0];
assert[not null largeMid; "midpoint should handle depth exceeding liquidity"];

/ Test: midpoint returns null for incomplete orderbook
assert[null .strategy.mm.midpoint[.test.emptyOrderbook; 2.0]; "midpoint should return null for empty orderbook"];
assert[null .strategy.mm.midpoint[.test.bidsOnlyOrderbook; 2.0]; "midpoint should return null for bids-only orderbook"];
assert[null .strategy.mm.midpoint[.test.asksOnlyOrderbook; 2.0]; "midpoint should return null for asks-only orderbook"];

-1 "Midpoint calculation tests: PASSED";

// ============================================================================
/ SPREAD CALCULATION TESTS
// ============================================================================

-1 "\n=== Testing Spread Calculation ===";

/ Test: absolute spread
absSpread:.strategy.mm.absoluteSpread[99.50; 100.50];
assert[1.0 = absSpread; "absolute spread should be 1.0"];

/ Test: spread in bps
bpsSpread:.strategy.mm.spreadBps[99.50; 100.50; 100.0];
expectedBps:(1.0 % 100.0) * 10000.0; / = 100 bps
assert[abs[bpsSpread - expectedBps] < 0.01; "spread in bps should be 100"];

/ Test: spread bps guards against zero midpoint
assert[null .strategy.mm.spreadBps[99.50; 100.50; 0.0]; "spreadBps should return null for zero midpoint"];

-1 "Spread calculation tests: PASSED";

// ============================================================================
/ QUOTE GENERATION TESTS
// ============================================================================

-1 "\n=== Testing Quote Generation ===";

/ Test: basic quote generation
quote:.strategy.mm.generateQuote[100.0; 10.0; 1.0; 1000.0];
/ 10 bps on 100.0 midpoint = 0.1 total spread, 0.05 half-spread
/ bid = 100.0 - 0.05 = 99.95
/ ask = 100.0 + 0.05 = 100.05
assert[abs[quote[`bidPrice] - 99.95] < 0.01; "bid price should be ~99.95"];
assert[abs[quote[`askPrice] - 100.05] < 0.01; "ask price should be ~100.05"];
assert[abs[quote[`spreadBps] - 10.0] < 0.01; "spread bps should be 10.0"];
assert[quote[`midpoint] = 100.0; "midpoint should be preserved"];

/ Test: spread bounds enforcement (below min)
quoteLow:.strategy.mm.generateQuote[100.0; 0.5; 1.0; 1000.0];
assert[quoteLow[`spreadBps] = 1.0; "spread should be clamped to min (1.0 bps)"];

/ Test: spread bounds enforcement (above max)
quoteHigh:.strategy.mm.generateQuote[100.0; 2000.0; 1.0; 1000.0];
assert[quoteHigh[`spreadBps] = 1000.0; "spread should be clamped to max (1000.0 bps)"];

/ Test: quote generation guards against null midpoint
quoteNull:.strategy.mm.generateQuote[0n; 10.0; 1.0; 1000.0];
assert[null quoteNull`bidPrice; "quote should handle null midpoint"];
assert[null quoteNull`askPrice; "quote should handle null midpoint"];

/ Test: quote generation guards against zero midpoint
quoteZero:.strategy.mm.generateQuote[0.0; 10.0; 1.0; 1000.0];
assert[null quoteZero`bidPrice; "quote should handle zero midpoint"];

-1 "Quote generation tests: PASSED";

// ============================================================================
/ POSITION-RESPONSIVE SIZING TESTS
// ============================================================================

-1 "\n=== Testing Position-Responsive Sizing ===";

/ Test: neutral position (no skew)
sizesNeutral:.strategy.mm.calculateOrderSizes[1.0; 0.0; 10.0; 0.1; 0.01];
assert[abs[sizesNeutral[`bidSize] - 1.0] < 0.01; "neutral bid size should be 1.0"];
assert[abs[sizesNeutral[`askSize] - 1.0] < 0.01; "neutral ask size should be 1.0"];

/ Test: long position (sell bias - larger asks, smaller bids)
/ position = +5.0, maxPosition = 10.0, positionPct = 0.5, skewFactor = 0.1
/ bidSizeMultiplier = 1.0 - (0.5 * 0.1) = 0.95
/ askSizeMultiplier = 1.0 + (0.5 * 0.1) = 1.05
sizesLong:.strategy.mm.calculateOrderSizes[1.0; 5.0; 10.0; 0.1; 0.01];
assert[abs[sizesLong[`bidSize] - 0.95] < 0.01; "long position should reduce bid size"];
assert[abs[sizesLong[`askSize] - 1.05] < 0.01; "long position should increase ask size"];

/ Test: short position (buy bias - larger bids, smaller asks)
/ position = -5.0, maxPosition = 10.0, positionPct = -0.5, skewFactor = 0.1
/ bidSizeMultiplier = 1.0 - (-0.5 * 0.1) = 1.05
/ askSizeMultiplier = 1.0 + (-0.5 * 0.1) = 0.95
sizesShort:.strategy.mm.calculateOrderSizes[1.0; -5.0; 10.0; 0.1; 0.01];
assert[abs[sizesShort[`bidSize] - 1.05] < 0.01; "short position should increase bid size"];
assert[abs[sizesShort[`askSize] - 0.95] < 0.01; "short position should reduce ask size"];

/ Test: minimum size enforcement
sizesMin:.strategy.mm.calculateOrderSizes[0.005; 0.0; 10.0; 0.1; 0.01];
assert[sizesMin[`bidSize] >= 0.01; "bid size should respect minimum"];
assert[sizesMin[`askSize] >= 0.01; "ask size should respect minimum"];

/ Test: invalid parameters return null
sizesInvalid:.strategy.mm.calculateOrderSizes[0.0; 0.0; 10.0; 0.1; 0.01];
assert[null sizesInvalid`bidSize; "invalid base size should return null"];

-1 "Position-responsive sizing tests: PASSED";

// ============================================================================
/ INTEGRATION TESTS
// ============================================================================

-1 "\n=== Integration Tests ===";

/ Test: Full quote generation workflow
/ 1. Calculate midpoint
mid:.strategy.mm.midpoint[.test.validOrderbook; 2.0];

/ 2. Generate quote
quote:.strategy.mm.generateQuote[mid; 20.0; 5.0; 100.0];

/ 3. Calculate sizes
sizes:.strategy.mm.calculateOrderSizes[1.0; 2.0; 10.0; 0.1; 0.01];

/ 4. Validate all components produced valid output
assert[not null mid; "midpoint should be valid"];
assert[not null quote`bidPrice; "bid price should be valid"];
assert[not null quote`askPrice; "ask price should be valid"];
assert[quote[`bidPrice] < quote[`askPrice]; "bid should be less than ask"];
assert[sizes[`bidSize] > 0.0; "bid size should be positive"];
assert[sizes[`askSize] > 0.0; "ask size should be positive"];

-1 "Integration tests: PASSED";

-1 "\n=== All Market Making Library Tests PASSED ===\n";
