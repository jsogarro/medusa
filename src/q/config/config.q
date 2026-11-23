/ Main Configuration Module
/ Public API for Medusa configuration system

\d .conf

/ Load submodules
\l src/q/config/parser.q
\l src/q/config/validator.q
\l src/q/config/loader.q

\d .conf

/ Global configuration store
current:()!();

/ Store last init params for reload
lastPath:`;
lastDefaults:()!();
lastSchema:()!();

/ Initialize configuration system
/ configPath: path to .conf file (or null for defaults only)
/ defaults: default configuration dictionary
/ schema: validation schema (or null for no validation)
init:{[configPath;defaults;schema]
  current::.conf.loader.load[configPath; defaults; schema];

  -1 "Configuration loaded from: ",string configPath;
  -1 "Sections: ",.Q.s key current;

  current
 };

/ Initialize with reload support
/ Stores params for later reload
initWithReload:{[configPath;defaults;schema]
  lastPath::configPath;
  lastDefaults::defaults;
  lastSchema::schema;
  init[configPath; defaults; schema]
 };

/ Get configuration value with optional default
/ section: `strategy, `exchange, etc.
/ key: `tick_sleep, `name, etc.
/ default: value to return if not found
set[`.conf.get;{[section;confKey;default]
  if[not section in key current; :default];
  sectionConfig:current section;
  sectionKeys:key sectionConfig;
  if[not confKey in sectionKeys; :default];

  sectionValues:value sectionConfig;
  valueIndex:sectionKeys?confKey;
  $[0>type sectionValues; sectionValues; sectionValues valueIndex]
 }];

/ Get configuration value with type coercion
/ section: `strategy, `exchange, etc.
/ key: `tick_sleep, `name, etc.
/ typeName: `int, `float, `symbol, `bool, `string, `list
/ default: value to return if not found (already typed)
getTyped:{[section;confKey;typeName;default]
  val:.conf.get[section; confKey; default];
  if[val~default; :val];  / Not found, return default

  / Coerce if it's still a string
  if[10h~type val;
    val:.conf.validator.coerce[typeName; val]
  ];

  val
 };

/ Set configuration value (runtime override)
set[`.conf.set;{[section;confKey;confValue]
  if[not section in key current;
    current[section]::()!()
  ];

  sectionConfig:current section;
  sectionConfig[confKey]:confValue;
  current[section]::sectionConfig;

  confValue
 }];

/ Reload configuration from disk (re-reads file and env vars)
/ Useful for hot-reloading in development
reload:{[]
  -1 "Reloading configuration...";
  init[lastPath; lastDefaults; lastSchema]
 };

\d .
