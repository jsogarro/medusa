/ Strategy configuration management
/ Load order: 3 - config.q (depends on types.q)

\d .engine

/ Base configuration schema (common to all strategies)
config.baseSchema:`tickInterval`maxPositionSize`stopLossPercent`takeProfitPercent`enableLogging!(
  100;      / tickInterval in ms
  10000;    / maxPositionSize (base currency units)
  0.02;     / stopLossPercent (2%)
  0.05;     / takeProfitPercent (5%)
  1b        / enableLogging
 )

/ Registry of strategy-specific configuration schemas
config.schemas:()!()

/ Register a strategy type's configuration schema
/ @param strategyType symbol - strategy type identifier
/ @param schema dict - configuration schema with defaults
config.register:{[strategyType;schema]
  config.schemas[strategyType]:schema;
 }

/ Load configuration from file (YAML stub - simplified for standalone operation)
/ @param strategyType symbol - strategy type identifier
/ @param configPath string - path to config file
/ @return dict - loaded and validated configuration
config.load:{[strategyType;configPath]
  / In a full implementation, this would call .config.loadYAML
  / For standalone operation, we simulate by reading and parsing
  / Here we'll just return base schema merged with registered schema

  / Get base defaults
  cfg:config.baseSchema;

  / Merge with strategy-specific defaults if registered
  if[strategyType in key config.schemas;
    cfg:cfg,config.schemas[strategyType];
  ];

  / In real implementation, would read file and merge overrides
  / For now, return merged defaults
  cfg
 }

/ Create configuration with overrides
/ @param strategyType symbol - strategy type identifier
/ @param overrides dict - configuration overrides
/ @return dict - validated configuration
config.create:{[strategyType;overrides]
  / Get base defaults
  cfg:config.baseSchema;

  / Merge with strategy-specific defaults if registered
  if[strategyType in key config.schemas;
    cfg:cfg,config.schemas[strategyType];
  ];

  / Apply overrides
  cfg:cfg,overrides;

  / Basic validation - check numeric ranges
  if[cfg[`stopLossPercent]<=0;
    '"stopLossPercent must be positive"];
  if[cfg[`takeProfitPercent]<=0;
    '"takeProfitPercent must be positive"];
  if[cfg[`maxPositionSize]<=0;
    '"maxPositionSize must be positive"];
  if[cfg[`tickInterval]<=0;
    '"tickInterval must be positive"];

  cfg
 }

/ Validate configuration against schema
/ @param cfg dict - configuration to validate
/ @param schema dict - schema with required keys and types
/ @return boolean - true if valid, signals error otherwise
config.validate:{[cfg;schema]
  / Check all schema keys are present
  missing:key[schema] except key cfg;
  if[count missing;
    '"Missing required config keys: ",", " sv string missing];

  / Type checking could go here
  / For now, just check presence
  1b
 }

/ Get default configuration for a strategy type
/ @param strategyType symbol - strategy type identifier
/ @return dict - default configuration
config.getDefaults:{[strategyType]
  cfg:config.baseSchema;
  if[strategyType in key config.schemas;
    cfg:cfg,config.schemas[strategyType];
  ];
  cfg
 }

\d .
