/ ============================================================================
/ orderbook_auditor.q - GDS Orderbook Quality Monitoring
/ ============================================================================
/
/ Detects invalid orderbook states:
/   - Crossed books (best bid >= best ask)
/   - Extreme spreads (beyond threshold)
/   - Empty books (no bids or asks)
/   - Insufficient levels (depth < minimum)
/
/ Dependencies:
/   - alert_manager.q (.gds.alert.raise)
/   - Tick schema (orderbook table in global namespace)
/
/ Usage:
/   .gds.orderbook.init[]
/   .gds.orderbook.check[]  / Returns `PASS or `FAIL
/ ============================================================================

\d .gds.orderbook

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Quality thresholds per exchange/symbol
config:([]
  exchange:`symbol$();
  sym:`symbol$();
  maxSpreadBps:`long$();   / Max spread in basis points
  minLevels:`long$()       / Minimum number of price levels required
 );

/ Default thresholds
defaultMaxSpreadBps:200;   / 2.00% (200 basis points)
defaultMinLevels:5;        / At least 5 levels on each side

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize orderbook monitor with default thresholds
/ @return null
init:{[]
  / Set default thresholds for all known exchange/sym pairs
  exchanges:`kraken`coinbase`binance`bitstamp;
  symbols:`BTCUSD`ETHUSD`BTCEUR`ETHEUR;

  / Create config entries (exchange x symbol)
  `.gds.orderbook.config upsert
    raze {[ex] {[ex;sy] (ex;sy;defaultMaxSpreadBps;defaultMinLevels)} [ex] each symbols} each exchanges;

  -1 ".gds.orderbook initialized with ",string[count config]," exchange/symbol pairs";
  -1 "  Default max spread: ",string[defaultMaxSpreadBps]," bps (basis points)";
  -1 "  Default min levels: ",string defaultMinLevels;
 };

/ ============================================================================
/ ORDERBOOK QUALITY CHECKS
/ ============================================================================

/ Check if orderbook is crossed (best bid >= best ask)
/ @param bids pair - (priceList;sizeList) where priceList is list of floats
/ @param asks pair - (priceList;sizeList) where priceList is list of floats
/ @return dict - `crossed (boolean), `bestBid, `bestAsk
checkCrossed:{[bids;asks]
  / Extract best bid and ask from nested structure
  / bids/asks format: (priceList;sizeList) — we want first price
  bestBid:$[count first bids; first first bids; 0f];
  bestAsk:$[count first asks; first first asks; 0f];

  / Check if crossed
  crossed:(bestBid >= bestAsk) and (bestBid > 0f) and (bestAsk > 0f);

  `crossed`bestBid`bestAsk!(crossed;bestBid;bestAsk)
 };

/ Calculate spread in basis points
/ @param bestBid float
/ @param bestAsk float
/ @return long - Spread in basis points (bps)
calculateSpreadBps:{[bestBid;bestAsk]
  / Spread = (ask - bid) / mid * 10000
  / Mid = (bid + ask) / 2
  mid:(bestBid + bestAsk) % 2;
  spreadBps:`long$(((bestAsk - bestBid) % mid) * 10000);
  spreadBps
 };

/ Check if spread is within threshold
/ @param bids pair - (priceList;sizeList)
/ @param asks pair - (priceList;sizeList)
/ @param maxSpreadBps long - Maximum spread in bps
/ @return dict - `excessive (boolean), `spreadBps, `threshold
checkSpread:{[bids;asks;maxSpreadBps]
  / Extract best bid and ask from nested structure
  bestBid:$[count first bids; first first bids; 0f];
  bestAsk:$[count first asks; first first asks; 0f];

  / If either is zero, can't calculate spread
  if[(bestBid = 0f) or bestAsk = 0f;
    :`excessive`spreadBps`threshold!(0b;0;maxSpreadBps)
  ];

  / Calculate spread
  spreadBps:calculateSpreadBps[bestBid;bestAsk];

  / Check if excessive
  excessive:spreadBps > maxSpreadBps;

  `excessive`spreadBps`threshold!(excessive;spreadBps;maxSpreadBps)
 };

/ Check if orderbook has sufficient levels
/ @param bids pair - (priceList;sizeList)
/ @param asks pair - (priceList;sizeList)
/ @param minLevels long - Minimum required levels
/ @return dict - `insufficient (boolean), `bidLevels, `askLevels, `threshold
checkLevels:{[bids;asks;minLevels]
  / Count levels from the price list (first element of the pair)
  bidLevels:count first bids;
  askLevels:count first asks;

  insufficient:(bidLevels < minLevels) or askLevels < minLevels;

  `insufficient`bidLevels`askLevels`threshold!(insufficient;bidLevels;askLevels;minLevels)
 };

/ Check if orderbook is empty
/ @param bids pair - (priceList;sizeList)
/ @param asks pair - (priceList;sizeList)
/ @return dict - `empty (boolean)
checkEmpty:{[bids;asks]
  / Check if price lists are empty
  empty:(0 = count first bids) or (0 = count first asks);
  `empty`bidCount`askCount!(empty;count first bids;count first asks)
 };

/ ============================================================================
/ MAIN CHECK FUNCTION
/ ============================================================================

/ Run orderbook check on latest snapshot per exchange/symbol
/ @return symbol - `PASS or `FAIL
check:{[]
  / Check if orderbook table exists
  if[not `orderbook in tables[];
    .gds.alert.raise[`WARN;`orderbook;"Orderbook table does not exist";()!()];
    :`FAIL
  ];

  / Get latest orderbook snapshot per exchange/symbol
  latestBooks:select last bids, last asks, last time, last mid
    by exchange, sym from orderbook;

  / Get config for each pair
  pairs:select exchange, sym from config;

  / Check each pair
  results:raze {[ex;sy]
    / Get latest book for this pair
    book:select from latestBooks where exchange=ex, sym=sy;

    / If no data, return empty result
    if[0 = count book;
      :()
    ];

    / Extract bids/asks
    bids:exec first bids from book;
    asks:exec first asks from book;

    / Get config for this pair
    cfg:exec first maxSpreadBps, first minLevels from config where exchange=ex, sym=sy;
    maxSpreadBps:cfg 0;
    minLevels:cfg 1;

    / Run all checks
    crossedCheck:checkCrossed[bids;asks];
    spreadCheck:checkSpread[bids;asks;maxSpreadBps];
    levelsCheck:checkLevels[bids;asks;minLevels];
    emptyCheck:checkEmpty[bids;asks];

    / Collect issues
    issues:();

    / Crossed book (CRITICAL)
    if[crossedCheck`crossed;
      msg:"Crossed book detected: bid=",string[crossedCheck`bestBid]," ask=",string[crossedCheck`bestAsk];
      details:`exchange`sym`bestBid`bestAsk!(ex;sy;crossedCheck`bestBid;crossedCheck`bestAsk);
      .gds.alert.raise[`CRITICAL;`orderbook;msg;details];
      issues,:enlist `crossed;
    ];

    / Excessive spread (WARN)
    if[spreadCheck`excessive;
      msg:"Excessive spread: ",string[spreadCheck`spreadBps]," bps (threshold: ",string[spreadCheck`threshold]," bps)";
      details:`exchange`sym`spreadBps`threshold!(ex;sy;spreadCheck`spreadBps;spreadCheck`threshold);
      .gds.alert.raise[`WARN;`orderbook;msg;details];
      issues,:enlist `excessive_spread;
    ];

    / Insufficient levels (WARN)
    if[levelsCheck`insufficient;
      msg:"Insufficient depth: ",string[levelsCheck`bidLevels]," bid levels, ",string[levelsCheck`askLevels]," ask levels (min: ",string[levelsCheck`threshold],")";
      details:`exchange`sym`bidLevels`askLevels`threshold!(ex;sy;levelsCheck`bidLevels;levelsCheck`askLevels;levelsCheck`threshold);
      .gds.alert.raise[`WARN;`orderbook;msg;details];
      issues,:enlist `insufficient_levels;
    ];

    / Empty book (CRITICAL)
    if[emptyCheck`empty;
      msg:"Empty orderbook: ",string[emptyCheck`bidCount]," bids, ",string[emptyCheck`askCount]," asks";
      details:`exchange`sym`bidCount`askCount!(ex;sy;emptyCheck`bidCount;emptyCheck`askCount);
      .gds.alert.raise[`CRITICAL;`orderbook;msg;details];
      issues,:enlist `empty;
    ];

    issues
  } ./: flip (pairs`exchange; pairs`sym);

  / Return status
  $[count results; `FAIL; `PASS]
 };

/ ============================================================================
/ CONFIGURATION HELPERS
/ ============================================================================

/ Set thresholds for specific exchange/symbol
/ @param exchange symbol
/ @param sym symbol
/ @param maxSpreadBps long - Max spread in basis points
/ @param minLevels long - Min depth levels
/ @return null
setThresholds:{[exchange;sym;maxSpreadBps;minLevels]
  `.gds.orderbook.config upsert (exchange;sym;maxSpreadBps;minLevels);
  -1 "Set orderbook thresholds for ",string[exchange]," ",string[sym],": maxSpread=",string[maxSpreadBps],"bps, minLevels=",string minLevels;
 };

/ Get current config
/ @return table - Current configuration
getConfig:{[] config};

-1 ".gds.orderbook namespace loaded: init, check, setThresholds";

\d .
