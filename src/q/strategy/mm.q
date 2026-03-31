/ ============================================================================
/ mm.q - Market Making Library
/ ============================================================================
/
/ Core market making primitives for quote generation and inventory management:
/   - Weighted midpoint calculation
/   - Spread-based quote generation
/   - Position-responsive order sizing
/   - Inventory skewing
/
/ Dependencies:
/   - lib/money.q (currency handling)
/
/ Functions:
/   - validateOrderbook: Validate orderbook structure
/   - getBids/getAsks: Extract and sort orderbook sides
/   - bestBid/bestAsk: Get top of book prices
/   - midpoint: Weighted midpoint calculation
/   - simpleMidpoint: Basic midpoint (best bid + ask) / 2
/   - calculateSpread: Calculate spread in bps
/   - generateQuote: Generate bid/ask prices with spread
/   - calculateOrderSizes: Position-responsive sizing with inventory skew
/ ============================================================================

\d .strategy.mm

// ============================================================================
/ ORDERBOOK VALIDATION
// ============================================================================

/ Validate orderbook table structure
/ @param ob table - Orderbook with columns (side; price; volume)
/ @return boolean - 1b if valid, 0b otherwise
validateOrderbook:{[ob]
  / Check table type
  if[not 98h~type ob; :0b];

  / Check required columns
  requiredCols:`side`price`volume;
  if[not all requiredCols in cols ob; :0b];

  / Check column types
  if[not 11h~type ob`side; :0b];   / symbol
  if[not ((9h~type ob`price) or (7h~type ob`price)); :0b];  / float or long
  if[not ((9h~type ob`volume) or (7h~type ob`volume)); :0b];  / float or long

  / Check sides are valid
  if[not all ob[`side] in `bid`ask; :0b];

  / Check positive prices and volumes
  if[any 0>=ob`price; :0b];
  if[any 0>=ob`volume; :0b];

  1b
  }

/ Require valid orderbook or throw error
/ @param ob table - Orderbook to validate
requireOrderbook:{[ob]
  if[not validateOrderbook[ob];
    '"Invalid orderbook structure"
  ];
 }

// ============================================================================
/ ORDERBOOK FILTERING
// ============================================================================

/ Get bids from orderbook sorted by price descending
/ @param ob table - Orderbook
/ @return table - Bids sorted by price (highest first)
getBids:{[ob]
  requireOrderbook[ob];
  bids: select from ob where side=`bid;
  `price xdesc bids
 }

/ Get asks from orderbook sorted by price ascending
/ @param ob table - Orderbook
/ @return table - Asks sorted by price (lowest first)
getAsks:{[ob]
  requireOrderbook[ob];
  asks: select from ob where side=`ask;
  `price xasc asks
 }

/ Get best bid price
/ @param ob table - Orderbook
/ @return float - Highest bid price or null if no bids
bestBid:{[ob]
  bids: getBids[ob];
  if[0=count bids; :0n];
  first exec price from bids
 }

/ Get best ask price
/ @param ob table - Orderbook
/ @return float - Lowest ask price or null if no asks
bestAsk:{[ob]
  asks: getAsks[ob];
  if[0=count asks; :0n];
  first exec price from asks
 }

// ============================================================================
/ MIDPOINT CALCULATION
// ============================================================================

/ Calculate weighted midpoint from orderbook using specified depth
/ Port of gryphon.lib.midpoint.get_midpoint_from_orderbook()
/ @param ob table - Orderbook with (side; price; volume)
/ @param depth float - Total depth to consider (in base currency units)
/ @return float - Volume-weighted midpoint price or null if insufficient data
midpoint:{[ob; depth]
  requireOrderbook[ob];

  / Get sorted bids and asks
  bids: getBids[ob];
  asks: getAsks[ob];

  / Handle empty orderbook
  if[(0=count bids) or 0=count asks; :0n];

  / Calculate cumulative volumes
  bids: update cumVolume: sums volume from bids;
  asks: update cumVolume: sums volume from asks;

  / Truncate to depth
  bidDepth: select from bids where cumVolume <= depth;
  askDepth: select from asks where cumVolume <= depth;

  / Handle case where depth exceeds available liquidity
  / Use all available liquidity up to depth
  if[0=count bidDepth; bidDepth: bids];
  if[0=count askDepth; askDepth: asks];

  / Guard against zero volume after depth truncation
  bidTotalVolume: exec sum volume from bidDepth;
  askTotalVolume: exec sum volume from askDepth;
  if[(bidTotalVolume <= 0.0) or askTotalVolume <= 0.0; :0n];

  / Calculate volume-weighted average for each side
  bidVWAP: (exec sum price * volume from bidDepth) % bidTotalVolume;
  askVWAP: (exec sum price * volume from askDepth) % askTotalVolume;

  / Midpoint is average of VWAP bid and VWAP ask
  midpointPrice: (bidVWAP + askVWAP) % 2.0;

  midpointPrice
 }

/ Simple midpoint (no depth weighting)
/ Convenience function for basic spread calculation
/ @param ob table - Orderbook
/ @return float - Simple midpoint (best_bid + best_ask) / 2 or null
simpleMidpoint:{[ob]
  requireOrderbook[ob];

  bid: bestBid[ob];
  ask: bestAsk[ob];

  if[any null (bid; ask); :0n];

  (bid + ask) % 2.0
 }

// ============================================================================
/ SPREAD CALCULATION
// ============================================================================

/ Calculate absolute spread
/ @param bidPrice float - Bid price
/ @param askPrice float - Ask price
/ @return float - Absolute spread (ask - bid)
absoluteSpread:{[bidPrice; askPrice]
  askPrice - bidPrice
 }

/ Calculate spread in basis points
/ @param bidPrice float - Bid price
/ @param askPrice float - Ask price
/ @param midpoint float - Midpoint price for percentage calculation
/ @return float - Spread in basis points (1 bp = 0.01%)
spreadBps:{[bidPrice; askPrice; midpoint]
  if[midpoint = 0.0; :0n];  / Guard against division by zero
  spread: absoluteSpread[bidPrice; askPrice];
  (spread % midpoint) * 10000.0  / Convert to bps
 }

// ============================================================================
/ QUOTE GENERATION
// ============================================================================

/ Generate bid/ask quote centered on midpoint with specified spread
/ Port of gryphon.lib.market_making.midpoint_centered_fixed_spread()
/ @param midpoint float - Center price
/ @param spreadBps float - Desired spread in basis points
/ @param minSpreadBps float - Minimum allowed spread (optional, default 1.0)
/ @param maxSpreadBps float - Maximum allowed spread (optional, default 1000.0)
/ @return dict - Quote with bid_price, ask_price, spread_bps, midpoint
generateQuote:{[midpoint; spreadBps; minSpreadBps; maxSpreadBps]
  / Default bounds if not provided
  minBps: $[null minSpreadBps; 1.0; minSpreadBps];
  maxBps: $[null maxSpreadBps; 1000.0; maxSpreadBps];

  / Guard against zero/null midpoint
  if[null midpoint; :`bidPrice`askPrice`spreadBps`midpoint!(0n;0n;0n;0n)];
  if[midpoint <= 0.0; :`bidPrice`askPrice`spreadBps`midpoint!(0n;0n;0n;0n)];

  / Enforce spread bounds
  boundedSpread: max[minBps; min[spreadBps; maxBps]];

  / Convert bps to price delta (1 bps = 0.01%)
  halfSpread: midpoint * (boundedSpread % 10000.0) % 2.0;

  / Calculate bid and ask prices
  bidPrice: midpoint - halfSpread;
  askPrice: midpoint + halfSpread;

  `bidPrice`askPrice`spreadBps`midpoint!(bidPrice; askPrice; boundedSpread; midpoint)
 }

// ============================================================================
/ POSITION-RESPONSIVE SIZING
// ============================================================================

/ Calculate order sizes with inventory-based skewing
/ Port of gryphon.lib.market_making.simple_position_responsive_sizing()
/ @param baseSize float - Base order size when position is neutral
/ @param position float - Current position (positive = long, negative = short)
/ @param maxPosition float - Maximum allowed position
/ @param skewFactor float - Skew aggressiveness (0.0-1.0, default 0.1)
/ @param minSize float - Minimum order size (optional, default 0.01)
/ @return dict - Sizes with bid_size, ask_size
calculateOrderSizes:{[baseSize; position; maxPosition; skewFactor; minSize]
  / Default values
  skew: $[null skewFactor; 0.1; skewFactor];
  minSz: $[null minSize; 0.01; minSize];

  / Guard against invalid parameters
  if[baseSize <= 0.0; :`bidSize`askSize!(0n;0n)];
  if[maxPosition <= 0.0; :`bidSize`askSize!(baseSize;baseSize)];

  / Calculate position as percentage of max (-1.0 to 1.0)
  positionPct: position % maxPosition;

  / Skew calculation
  / Positive position (long) -> reduce bid size, increase ask size (sell bias)
  / Negative position (short) -> increase bid size, reduce ask size (buy bias)
  bidSizeMultiplier: 1.0 - (positionPct * skew);
  askSizeMultiplier: 1.0 + (positionPct * skew);

  bidSize: baseSize * bidSizeMultiplier;
  askSize: baseSize * askSizeMultiplier;

  / Enforce minimum size
  bidSize: max[minSz; bidSize];
  askSize: max[minSz; askSize];

  `bidSize`askSize!(bidSize; askSize)
 }

\d .
