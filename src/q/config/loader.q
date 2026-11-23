/ Configuration Loader with Hierarchical Merging

\d .conf

/ Load environment variables matching pattern
/ prefix: "MEDUSA"
/ section: `strategy
loader.loadEnvVars:{[prefix;section]
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
    confKey:`$lower (count pattern)_fullKey;
    confVal:last parts;

    config[confKey]:confVal;
    config
  }[;pattern]/[config; matching];

  config
 };

/ Merge two configuration dictionaries
/ override takes precedence
loader.toDict:{[sectionConfig]
  sectionKeys:key sectionConfig;
  sectionValues:value sectionConfig;
  if[0=count sectionKeys; :()!()];
  if[0>type sectionValues; sectionValues:enlist sectionValues];
  sectionKeys!sectionValues
 };

loader.merge:{[base;override]
  sections:distinct (key base),key override;
  if[0=count sections; :()!()];

  configs:{[base;override;section]
    baseSection:$[section in key base; loader.toDict base section; ()!()];
    overrideSection:$[section in key override; loader.toDict override section; ()!()];
    mergedKeys:distinct (key baseSection),key overrideSection;
    if[0=count mergedKeys; :()!()];
    mergedVals:{[baseSection;overrideSection;k]
      $[k in key overrideSection; overrideSection k; baseSection k]
    }[baseSection;overrideSection] each mergedKeys;
    mergedKeys!mergedVals
  }[base;override] each sections;

  sections!configs
 };

/ Load configuration with hierarchy
/ configPath: path to .conf file
/ defaults: default configuration dictionary
/ schema: validation schema (optional, can be null)
loader.load:{[configPath;defaults;schema]
  / Start with defaults
  config:defaults;

  / Load file if exists
  if[not ()~configPath;
    fileExists:@[{hclose hopen hsym `$x; 1b}; configPath; {0b}];
    if[fileExists;
      / File exists, parse it
      fileConfig:.conf.parser.parseFile[configPath];
      config:loader.merge[config; fileConfig]
    ]
  ];

  / Load environment variable overrides for each section (vectorized)
  sections:key config;
  envConfigs:{loader.loadEnvVars["MEDUSA"; x]} each sections;
  config:{[config;section;envConfig]
    if[count envConfig;
      config:loader.merge[config; (enlist section)!(enlist envConfig)]
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

\d .conf
