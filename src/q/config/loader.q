/ Configuration Loader with Hierarchical Merging

\d .conf.loader

/ Load environment variables matching pattern
/ prefix: "MEDUSA"
/ section: `strategy
loadEnvVars:{[prefix;section]
  / Get all environment variables
  envVars:system "env";

  / Filter by prefix and section
  pattern:prefix,"_",upper string section,"_";
  matching:envVars where {[pattern;x] pattern~(count pattern)#x}[pattern] each envVars;

  / Parse into dictionary
  config:()!();
  config:{[config;pattern;envLine]
    parts:"="vs envLine;
    if[2<>count parts; :config];

    / Extract key (remove prefix)
    fullKey:first parts;
    key:`$lower (count pattern)_fullKey;
    val:last parts;

    config[key]:val;
    config
  }[;pattern]/[config; matching];

  config
 };

/ Merge two configuration dictionaries
/ override takes precedence
merge:{[base;override]
  result:base;

  / Merge each section in override
  result:{[result;override;section]
    if[not section in key result;
      result[section]:()!()
    ];

    / Merge keys within section
    overrideSection:override[section];
    result:{[result;section;overrideSection;k]
      result[section][k]:overrideSection[k];
      result
    }[;section;overrideSection]/[result; key overrideSection];

    result
  }[;override]/[result; key override];

  result
 };

/ Load configuration with hierarchy
/ configPath: path to .conf file
/ defaults: default configuration dictionary
/ schema: validation schema (optional, can be null)
load:{[configPath;defaults;schema]
  / Start with defaults
  config:defaults;

  / Load file if exists
  if[not ()~configPath;
    fileExists:@[{hclose hopen hsym `$x; 1b}; configPath; {0b}];
    if[fileExists;
      / File exists, parse it
      fileConfig:.conf.parser.parseFile[configPath];
      config:merge[config; fileConfig]
    ]
  ];

  / Load environment variable overrides for each section (vectorized)
  sections:key config;
  envConfigs:{loadEnvVars["MEDUSA"; x]} each sections;
  config:{[config;section;envConfig]
    if[count envConfig;
      config:merge[config; (enlist section)!(enlist envConfig)]
    ];
    config
  }[;;]/[config; sections; envConfigs];

  / Validate if schema provided
  if[not null schema;
    {[schema;config;section]
      if[section in key schema;
        errors:.conf.validator.validate[schema[section]; config[section]];
        if[count errors;
          -1 "Configuration validation errors for section ",string[section],":";
          -1 .Q.s errors;
          'ValidationError
        ]
      ]
    }[schema;config] each key config
  ];

  config
 };

\d .
