/ Actor management for trade association
/ Load order: 7 - actor.q (standalone)

\d .engine

/ Actor registry - maps actor symbol to metadata
actor.registry:()!()

/ Register an actor
/ @param actor symbol - actor identifier
/ @param metadata dict - actor metadata (name, description, etc.)
actor.register:{[actor;metadata]
  / Check if already registered
  if[actor in key actor.registry;
    -1"[ACTOR] Warning: Actor already registered, updating: ",string actor;
  ];

  / Add default fields if not provided
  if[not `registeredAt in key metadata;
    metadata[`registeredAt]:.z.p;
  ];
  if[not `tradeCount in key metadata;
    metadata[`tradeCount]:0;
  ];

  / Register actor
  actor.registry[actor]:metadata;

  / Log registration
  -1"[ACTOR] Registered: ",string actor;

  actor
 }

/ Get actor metadata
/ @param actor symbol - actor identifier
/ @return dict - actor metadata
actor.get:{[actor]
  / Check if registered
  if[not actor in key actor.registry;
    '"Actor not registered: ",string actor;
  ];

  actor.registry[actor]
 }

/ Associate a trade with an actor
/ @param tradeId long - trade identifier (from trades table)
/ @param actor symbol - actor identifier
actor.associateTrade:{[tradeId;actor]
  / Check if actor is registered
  if[not actor in key actor.registry;
    '"Actor not registered: ",string actor;
  ];

  / Update trades table to associate with actor
  / Assumes trades table exists in root namespace with actor column
  / This would be: update actor:a from `trades where id=tid
  / For now, we just increment the trade count in actor metadata

  actor.registry[actor;`tradeCount]:actor.registry[actor;`tradeCount]+1;

  / Log association
  -1"[ACTOR] Trade ",string[tradeId]," associated with actor: ",string actor;

  actor
 }

/ Get all trades for an actor
/ @param actor symbol - actor identifier
/ @return table - trades associated with actor
actor.getTrades:{[actor]
  / Check if actor is registered
  if[not actor in key actor.registry;
    '"Actor not registered: ",string actor;
  ];

  / Query trades table
  / This would be: select from trades where actor=a
  / For now, return empty table since we don't have access to global trades table
  ([]id:();timestamp:();exchange:();asset:();side:();price:();volume:();actor:())
 }

/ List all registered actors
/ @return table - all actors with metadata
actor.list:{
  / Convert registry dict to table
  actors:key actor.registry;
  metadata:value actor.registry;

  / Extract common fields
  registeredAt:metadata[;`registeredAt];
  tradeCount:metadata[;`tradeCount];

  ([]actor:actors;registeredAt:registeredAt;tradeCount:tradeCount)
 }

/ Unregister an actor
/ @param actor symbol - actor identifier
actor.unregister:{[actor]
  / Check if registered
  if[not actor in key actor.registry;
    '"Actor not registered: ",string actor;
  ];

  / Remove from registry
  actor.registry:actor.registry _ actor;

  / Log unregistration
  -1"[ACTOR] Unregistered: ",string actor;

  actor
 }

\d .
