/ Order Flow Risk Monitoring
/ Tracks order rate, rejection rate, fill rate, pending exposure

\d .risk

/ ═══════════════════════════════════════════════════════════════════
/ Order Flow Tables
/ ═══════════════════════════════════════════════════════════════════

/ Order flow metrics (rolling 1-minute window)
orderFlowMetrics:([]
  windowStart:`timestamp$();
  windowEnd:`timestamp$();
  ordersSubmitted:`int$();
  ordersAccepted:`int$();
  ordersRejected:`int$();
  ordersCancelled:`int$();
  ordersFilled:`int$();
  ordersPerSecond:`float$();
  rejectionRate:`float$();
  fillRate:`float$();
  cancelReplaceRatio:`float$();
  pendingOrderExposure:`float$();
  lastUpdate:`timestamp$()
 );

/ Order flow by exchange (keyed table)
orderFlowByExchange:([exchange:`symbol$()]
  ordersPerSecond:`float$();
  rejectionRate:`float$();
  fillRate:`float$();
  lastUpdate:`timestamp$()
 );

/ Order flow alert thresholds (single-row table)
orderFlowThresholds:([]
  maxOrdersPerSecond:enlist 100.0;
  maxRejectionRate:enlist 20.0;
  maxCancelReplaceRatio:enlist 3.0;
  maxPendingExposure:enlist 100000.0
 );

/ ═══════════════════════════════════════════════════════════════════
/ Initialization
/ ═══════════════════════════════════════════════════════════════════

initOrderFlowRisk:{[]
  / Clear tables
  delete from `.risk.orderFlowMetrics;
  delete from `.risk.orderFlowByExchange;

  / Set default thresholds
  `.risk.orderFlowThresholds set ([] maxOrdersPerSecond:enlist 100.0;
                                     maxRejectionRate:enlist 20.0;
                                     maxCancelReplaceRatio:enlist 3.0;
                                     maxPendingExposure:enlist 100000.0);

  -1 "  Order flow risk initialized";
 };

/ ═══════════════════════════════════════════════════════════════════
/ Order Flow Calculation
/ ═══════════════════════════════════════════════════════════════════

/ Update order flow metrics (run every 1 second via .z.ts)
updateOrderFlowMetrics:{[]
  / Calculate metrics for last 60 seconds
  windowEnd:.z.p;
  windowStart:windowEnd - 00:01:00;

  / Query orders in window
  orders:select from .schema.order where time_created within (windowStart;windowEnd);

  / Count orders by status
  submitted:count orders;
  accepted:sum exec status in `accepted`open`partiallyFilled`filled from orders;
  rejected:sum exec status = `rejected from orders;
  cancelled:sum exec status = `cancelled from orders;
  filled:sum exec status in `filled`partiallyFilled from orders;

  / Calculate rates
  ordersPerSec:submitted % 60.0;
  rejectionRate:$[submitted > 0; 100.0 * rejected % submitted; 0.0];
  fillRate:$[submitted > 0; 100.0 * filled % submitted; 0.0];

  / Calculate cancel/replace ratio
  / (For simplicity, assume cancel/replace ratio = cancelled % submitted)
  cancelReplaceRatio:$[submitted > 0; cancelled % submitted; 0.0];

  / Calculate pending order exposure
  pendingOrders:select from .schema.order where status in `open`partiallyFilled;
  pendingExposure:sum exec quantity * price from pendingOrders;

  / Insert metrics
  `.risk.orderFlowMetrics insert (windowStart;windowEnd;submitted;accepted;rejected;cancelled;filled;
                                    ordersPerSec;rejectionRate;fillRate;cancelReplaceRatio;pendingExposure;.z.p);

  / Update exchange-level metrics
  updateOrderFlowByExchange[orders];

  / Check thresholds
  checkOrderFlowThresholds[];
 };

/ Update order flow by exchange
updateOrderFlowByExchange:{[orders]
  / Clear table
  delete from `.risk.orderFlowByExchange;

  / Group by exchange
  byExchange:select
    submitted:count i,
    rejected:sum status = `rejected,
    filled:sum status in `filled`partiallyFilled
    by exchange from orders;

  / Calculate rates
  byExchange:update ordersPerSecond:submitted % 60.0 from byExchange;
  byExchange:update rejectionRate:?[submitted > 0; 100.0 * rejected % submitted; 0.0] from byExchange;
  byExchange:update fillRate:?[submitted > 0; 100.0 * filled % submitted; 0.0] from byExchange;
  byExchange:update lastUpdate:.z.p from byExchange;

  / Upsert
  `.risk.orderFlowByExchange set 1!select exchange, ordersPerSecond, rejectionRate, fillRate, lastUpdate from byExchange;
 };

/ Check order flow thresholds
checkOrderFlowThresholds:{[]
  / Get latest metrics
  latest:first -1#select from .risk.orderFlowMetrics;
  if[()~latest; :()];

  thresholds:first .risk.orderFlowThresholds;

  / Check orders/sec
  if[latest[`ordersPerSecond] > thresholds`maxOrdersPerSecond;
    .risk.logRiskEvent[.z.p;`orderFlowExcessive;`;`;`;enlist[`ordersPerSec]!enlist latest`ordersPerSecond;`warn;`warning];
  ];

  / Check rejection rate
  if[latest[`rejectionRate] > thresholds`maxRejectionRate;
    .risk.logRiskEvent[.z.p;`orderRejectionHigh;`;`;`;enlist[`rejectionRate]!enlist latest`rejectionRate;`warn;`warning];
  ];

  / Check cancel/replace ratio
  if[latest[`cancelReplaceRatio] > thresholds`maxCancelReplaceRatio;
    .risk.logRiskEvent[.z.p;`cancelReplaceHigh;`;`;`;enlist[`ratio]!enlist latest`cancelReplaceRatio;`warn;`warning];
  ];

  / Check pending exposure
  if[latest[`pendingOrderExposure] > thresholds`maxPendingExposure;
    .risk.logRiskEvent[.z.p;`pendingExposureHigh;`;`;`;enlist[`exposure]!enlist latest`pendingOrderExposure;`warn;`warning];
  ];
 };

/ ═══════════════════════════════════════════════════════════════════
/ Query Functions (for UI)
/ ═══════════════════════════════════════════════════════════════════

/ Get latest order flow metrics
orderFlow.current:{[]
  first -1#select from .risk.orderFlowMetrics
 };

/ Get orders per second
orderFlow.ordersPerSecond:{[]
  first -1#exec ordersPerSecond from .risk.orderFlowMetrics
 };

/ Get rejection rate
orderFlow.rejectionRate:{[]
  first -1#exec rejectionRate from .risk.orderFlowMetrics
 };

/ Get fill rate
orderFlow.fillRate:{[]
  first -1#exec fillRate from .risk.orderFlowMetrics
 };

/ Get pending exposure
orderFlow.pendingExposure:{[]
  first -1#exec pendingOrderExposure from .risk.orderFlowMetrics
 };

/ Get order flow by exchange
orderFlow.byExchange:{[]
  select from .risk.orderFlowByExchange
 };

\d .
