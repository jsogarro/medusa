/ Risk Management — Emergency Stop Controller (Kill Switch)
/ Halts all trading and cancels open orders

\d .risk

/ Activate emergency stop
activateEmergencyStop:{[r;user]
  / Log activation with structured logging
  if[`log in key `.;
    .log.event[`CRITICAL;`risk;`emergencyStopActivated;`user`reason!(user;r)]
  ];

  / Set emergency stop state
  emergencyStopState::update active:1b, activatedBy:user, activatedAt:.z.p, reason:r from emergencyStopState;

  / Log event
  .risk.logRiskEvent[.z.p;`emergencyStop;`;`;`;
    `activatedBy`reason!(user;r);
    `halt;`critical];

  -1 "EMERGENCY STOP ACTIVATED by ",string[user]," - Reason: ",string[r];

  / Cancel all open orders via coordinator (if available)
  / ROBUSTNESS: Check ALL required coordinator components before proceeding
  coordinatorReady:(not ()~key `.exchange.coordinator.cancelOrder) and (not ()~key `.exchange.coordinator.connections) and (not ()~key `.exchange.coordinator.orderRouting);

  if[coordinatorReady;
    / Protected evaluation: log errors but continue
    cancelErrors:();
    connectedExchanges:@[{exec exchange from .exchange.coordinator.connections where connected};::;{-1 "WARN: Failed to query connections: ",x; ()}];

    {[ex]
      openOrders:@[{exec orderId from .exchange.coordinator.orderRouting where exchange=x,status=`open};ex;{-1 "WARN: Failed to query orders for ",string[x],": ",y; ()}];
      {[ex;oid]
        / Protected cancel: catch errors and log
        result:@[{.exchange.coordinator.cancelOrder[x;y];1b};(ex;oid);{`$"Error: ",x}];
        if[not result~1b;
          cancelErrors,:enlist (ex;oid;result);
          -1 "WARN: Failed to cancel order ",string[oid]," on ",string[ex],": ",string[result];
        ];
      }[ex] each openOrders;
    } each connectedExchanges;
    / Log summary
    $[0=count cancelErrors;
      -1 "All open orders cancelled across exchanges";
      [-1 "Emergency stop: ",string[count cancelErrors]," cancel failures logged";
       .risk.logRiskEvent[.z.p;`emergencyStopCancelFailures;`;`;`;`failures`count!(cancelErrors;count cancelErrors);`warn;`warning]]
    ];
  ];

  1b
 };

/ Deactivate emergency stop (admin only)
deactivateEmergencyStop:{[user]
  / Log deactivation with structured logging
  if[`log in key `.;
    .log.event[`CRITICAL;`risk;`emergencyStopDeactivated;`user!(user)]
  ];

  emergencyStopState::update active:0b, activatedBy:user, activatedAt:.z.p, reason:`deactivated from emergencyStopState;

  .risk.logRiskEvent[.z.p;`emergencyStopDeactivated;`;`;`;
    (enlist `deactivatedBy)!enlist user;
    `resume;`warning];

  -1 "Emergency stop deactivated by ",string[user];
  1b
 };

/ Check if emergency stop is active (pre-trade)
/ Returns: (pass:boolean; reason:symbol)
checkEmergencyStop:{[]
  / ROBUSTNESS: Validate single-row table integrity
  if[1<>count .risk.emergencyStopState;
    -1 "CRITICAL: emergencyStopState table corrupted (row count: ",string[count .risk.emergencyStopState],")";
    / FAIL-SAFE: If state is corrupted, HALT trading
    :(0b;`emergencyStopStateCorrupted)
  ];

  active:first exec active from .risk.emergencyStopState;
  $[active;(0b;`emergencyStopActive);(1b;`)]
 };

\d .
