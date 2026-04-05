/ ============================================================================
/ trade_auditor.q - GDS Trade Data Quality Monitoring
/ ============================================================================
/
/ Detects trade data anomalies:
/   - Duplicate trades (same tradeId received multiple times)
/   - Price outliers (large price change between consecutive trades)
/   - Large time gaps (no trades for extended period)
/
/ Dependencies:
/   - alert_manager.q (.gds.alert.raise)
/   - Tick schema (trade table in global namespace)
/
/ Usage:
/   .gds.trade.init[]
/   .gds.trade.check[]  / Returns `PASS or `FAIL
/ ============================================================================

\d .gds.trade

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Quality thresholds per exchange/symbol
config:([]
  exchange:`symbol$();
  sym:`symbol$();
  maxPriceChangePercent:`float$();  / Max allowed % change between trades
  maxGapSec:`long$()                / Max allowed time gap in seconds
 );

/ Default thresholds
defaultMaxPriceChangePercent:10.0;  / 10% max price change
defaultMaxGapSec:60;                / 60 seconds max gap

/ ============================================================================
/ INITIALIZATION
/ ============================================================================

/ Initialize trade monitor with default thresholds
/ @return null
init:{[]
  / Set default thresholds for all known exchange/sym pairs
  exchanges:`kraken`coinbase`binance`bitstamp;
  symbols:`BTCUSD`ETHUSD`BTCEUR`ETHEUR;

  / Create config entries (exchange x symbol)
  `.gds.trade.config upsert
    raze {[ex] {[ex;sy] (ex;sy;defaultMaxPriceChangePercent;defaultMaxGapSec)} [ex] each symbols} each exchanges;

  -1 ".gds.trade initialized with ",string[count config]," exchange/symbol pairs";
  -1 "  Default max price change: ",string[defaultMaxPriceChangePercent],"%";
  -1 "  Default max gap: ",string[defaultMaxGapSec]," seconds";
 };

/ ============================================================================
/ DUPLICATE DETECTION
/ ============================================================================

/ Check for duplicate trade IDs
/ @param exchange symbol
/ @param sym symbol
/ @return table - Duplicate trades detected
checkDuplicates:{[exchange;sym]
  / Check if trade table exists
  if[not `trade in tables[];
    :0#trade
  ];

  / Get trades for this exchange/symbol
  trades:select from trade where exchange=exchange, sym=sym;

  / Group by tradeId and find duplicates
  grouped:select count i by tradeId from trades;
  duplicates:select from grouped where x > 1;

  / If duplicates found, get details
  if[count duplicates;
    duplicateIds:exec tradeId from duplicates;
    select from trades where tradeId in duplicateIds
  ] else [(0#trade)]
 };

/ ============================================================================
/ PRICE OUTLIER DETECTION
/ ============================================================================

/ Calculate percent change between consecutive prices
/ @param prevPrice float
/ @param currPrice float
/ @return float - Percent change
calcPriceChangePercent:{[prevPrice;currPrice]
  abs[((currPrice - prevPrice) % prevPrice) * 100.0]
 };

/ Check for price outliers (large price changes)
/ @param exchange symbol
/ @param sym symbol
/ @param maxChangePercent float - Max allowed % change
/ @return table - Outlier trades
checkPriceOutliers:{[exchange;sym;maxChangePercent]
  / Check if trade table exists
  if[not `trade in tables[];
    :0#([] time:`timestamp$(); exchange:`symbol$(); sym:`symbol$(); price:`float$(); prevPrice:`float$(); changePercent:`float$())
  ];

  / Get trades for this exchange/symbol, ordered by time
  trades:select from trade where exchange=exchange, sym=sym;
  trades:`time xasc trades;

  / If fewer than 2 trades, can't detect outliers
  if[2 > count trades;
    :0#([] time:`timestamp$(); exchange:`symbol$(); sym:`symbol$(); price:`float$(); prevPrice:`float$(); changePercent:`float$())
  ];

  / Calculate previous price (shift)
  trades:update prevPrice:prev price from trades;

  / Calculate percent change (vectorized)
  trades:update changePercent:abs[((price - prevPrice) % prevPrice) * 100.0] from trades;

  / Find outliers (excluding first trade which has null prevPrice)
  outliers:select from trades where not null prevPrice, changePercent > maxChangePercent;

  select time, exchange, sym, price, prevPrice, changePercent from outliers
 };

/ ============================================================================
/ TIME GAP DETECTION
/ ============================================================================

/ Check for large time gaps between trades
/ @param exchange symbol
/ @param sym symbol
/ @param maxGapSec long - Max gap in seconds
/ @return table - Gaps detected
checkTimeGaps:{[exchange;sym;maxGapSec]
  / Check if trade table exists
  if[not `trade in tables[];
    :0#([] gapStart:`timestamp$(); gapEnd:`timestamp$(); gapSec:`long$(); exchange:`symbol$(); sym:`symbol$())
  ];

  / Get trades for this exchange/symbol, ordered by time
  trades:select time, exchange, sym from trade where exchange=exchange, sym=sym;
  trades:`time xasc trades;

  / If fewer than 2 trades, can't detect gaps
  if[2 > count trades;
    :0#([] gapStart:`timestamp$(); gapEnd:`timestamp$(); gapSec:`long$(); exchange:`symbol$(); sym:`symbol$())
  ];

  / Calculate time delta from previous trade
  trades:update prevTime:prev time from trades;
  trades:update gapNs:(`timestamp$time) - `timestamp$prevTime from trades;
  trades:update gapSec:`long$(gapNs % 1000000000) from trades;

  / Find gaps exceeding threshold
  gaps:select from trades where not null prevTime, gapSec > maxGapSec;

  / Format output
  select gapStart:prevTime, gapEnd:time, gapSec, exchange, sym from gaps
 };

/ ============================================================================
/ MAIN CHECK FUNCTION
/ ============================================================================

/ Run trade quality checks on all configured exchange/symbol pairs
/ @return symbol - `PASS or `FAIL
check:{[]
  / Check if trade table exists
  if[not `trade in tables[];
    .gds.alert.raise[`WARN;`trade;"Trade table does not exist";()!()];
    :`FAIL
  ];

  / Get config for each pair
  pairs:select exchange, sym from config;

  / Check each pair
  issueCount:0;

  {[ex;sy]
    / Get config for this pair
    cfg:exec first maxPriceChangePercent, first maxGapSec from config where exchange=ex, sym=sy;
    maxChangePercent:cfg 0;
    maxGapSec:cfg 1;

    / Check for duplicates
    duplicates:checkDuplicates[ex;sy];
    if[count duplicates;
      msg:"Duplicate trades detected: ",string[count duplicates]," duplicates";
      details:`exchange`sym`duplicateCount!(ex;sy;count duplicates);
      .gds.alert.raise[`WARN;`trade;msg;details];
      issueCount+:1;
    ];

    / Check for price outliers
    outliers:checkPriceOutliers[ex;sy;maxChangePercent];
    if[count outliers;
      msg:"Price outliers detected: ",string[count outliers]," outliers";
      details:`exchange`sym`outlierCount`maxChangePercent!(ex;sy;count outliers;maxChangePercent);
      .gds.alert.raise[`WARN;`trade;msg;details];
      issueCount+:1;
    ];

    / Check for time gaps
    gaps:checkTimeGaps[ex;sy;maxGapSec];
    if[count gaps;
      msg:"Time gaps detected: ",string[count gaps]," gaps";
      details:`exchange`sym`gapCount`maxGapSec!(ex;sy;count gaps;maxGapSec);
      .gds.alert.raise[`WARN;`trade;msg;details];
      issueCount+:1;
    ];
  } ./: flip (pairs`exchange; pairs`sym);

  / Return status
  $[issueCount > 0; `FAIL; `PASS]
 };

/ ============================================================================
/ CONFIGURATION HELPERS
/ ============================================================================

/ Set thresholds for specific exchange/symbol
/ @param exchange symbol
/ @param sym symbol
/ @param maxPriceChangePercent float - Max % price change
/ @param maxGapSec long - Max time gap in seconds
/ @return null
setThresholds:{[exchange;sym;maxPriceChangePercent;maxGapSec]
  `.gds.trade.config upsert (exchange;sym;maxPriceChangePercent;maxGapSec);
  -1 "Set trade thresholds for ",string[exchange]," ",string[sym],": maxChange=",string[maxPriceChangePercent],"%, maxGap=",string[maxGapSec],"s";
 };

/ Get current config
/ @return table - Current configuration
getConfig:{[] config};

-1 ".gds.trade namespace loaded: init, check, setThresholds";

\d .
