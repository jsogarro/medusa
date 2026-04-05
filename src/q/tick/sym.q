/ ============================================================================
/ sym.q - Medusa Tickerplant Schema
/ ============================================================================
/
/ Defines all tables managed by the Tickerplant process.
/ Published by Rust GDS subscribers via .u.upd IPC calls.
/
/ Usage:
/   q tick.q tick/sym.q -p 5010
/ ============================================================================

\d .

/ Orderbook snapshots (published by gds-orderbook-subscriber)
/ Each row is a full L2 snapshot at a given time
/ bids/asks format: (priceList;sizeList) where both are float lists
orderbook:([]
  time:`timestamp$();      / Exchange timestamp of snapshot
  exchange:`symbol$();     / Exchange identifier (e.g., `kraken, `coinbase)
  sym:`symbol$();          / Trading pair (e.g., `BTCUSD, `ETHUSD)
  bids:();                 / Nested pair: (float list; float list) = (prices; sizes)
  asks:();                 / Nested pair: (float list; float list) = (prices; sizes)
  sequence:`long$();       / Exchange sequence number for ordering
  mid:`float$()            / Mid price: (best bid + best ask) / 2
 );

/ Trade events (published by gds-trade-subscriber)
/ Each row is a single executed trade on the exchange
trade:([]
  time:`timestamp$();      / Exchange timestamp of trade execution
  exchange:`symbol$();     / Exchange identifier
  sym:`symbol$();          / Trading pair
  tradeId:`symbol$();      / Exchange trade ID (unique per exchange)
  price:`float$();         / Execution price
  size:`float$();          / Trade size (volume)
  side:`symbol$();         / Trade side: `buy or `sell
  value:`float$()          / Notional value: price * size
 );

/ GDS alerts (published by Rust gds-auditor or q auditors)
/ Critical data quality alerts for monitoring
gds_alert:([]
  time:`timestamp$();      / Alert generation timestamp
  severity:`symbol$();     / Alert severity: `INFO, `WARN, `CRITICAL
  source:`symbol$();       / Alert source: e.g., `heartbeat, `orderbook, `trade
  message:();              / Human-readable alert description
  exchange:`symbol$();     / Affected exchange (null if N/A)
  sym:`symbol$()           / Affected symbol (null if N/A)
 );

-1 "Tickerplant schema loaded: orderbook, trade, gds_alert";
-1 "Columns:";
-1 "  orderbook: time exchange sym bids asks sequence mid";
-1 "  trade: time exchange sym tradeId price size side value";
-1 "  gds_alert: time severity source message exchange sym";
