/ Configuration Type Validator and Coercer

\d .conf

/ Helper: trim whitespace (vectorized)
validator.ltrim:{$[10h=type x; $[count x; $[" "=first x; validator.ltrim 1_x; x]; x]; x]};
validator.rtrim:{$[10h=type x; $[count x; $[" "=last x; validator.rtrim -1_x; x]; x]; x]};
validator.trim:{validator.rtrim validator.ltrim x};

/ Coerce string to integer
validator.coerceInt:{[val]
  / Try to parse as integer
  res:@[{"J"$x}; val; {(`error; x)}];
  $[`error~first res; 0Ni; res]
 };

/ Coerce string to float
validator.coerceFloat:{[val]
  / Try to parse as float
  res:@[{"F"$x}; val; {(`error; x)}];
  $[`error~first res; 0Nf; res]
 };

/ Coerce string to symbol
validator.coerceSymbol:{[val]
  / Convert to symbol
  `$val
 };

/ Coerce string to boolean
validator.coerceBool:{[val]
  / Parse boolean
  lowerVal:lower val;
  $[(lowerVal~"true") or (lowerVal~"1") or (lowerVal~"yes") or (lowerVal~"on"); 1b;
    (lowerVal~"false") or (lowerVal~"0") or (lowerVal~"no") or (lowerVal~"off"); 0b;
    0N]
 };

/ Coerce string to list
validator.coerceList:{[val]
  / Parse JSON-style list: "[1,2,3]" or "1,2,3"
  / Remove brackets if present
  val:validator.trim val;
  if["["=first val; val:1_val];
  if["]"=last val; val:-1_val];

  / Split by comma
  items:","vs val;
  items:validator.trim each items;

  / Try to infer type from first element
  if[0=count items; :()];

  first_item:first items;

  / Try int
  if[not null validator.coerceInt[first_item];
    :validator.coerceInt each items
  ];

  / Try float
  if[not null validator.coerceFloat[first_item];
    :validator.coerceFloat each items
  ];

  / Default to symbols
  validator.coerceSymbol each items
 };

/ Coerce value to specified type
/ typeName: `int`float`symbol`bool`string`list
/ val: string value to coerce
validator.coerce:{[typeName;val]
  $[
    `int~typeName; validator.coerceInt[val];
    `float~typeName; validator.coerceFloat[val];
    `symbol~typeName; validator.coerceSymbol[val];
    `bool~typeName; validator.coerceBool[val];
    `list~typeName; validator.coerceList[val];
    `string~typeName; val;
    / Default: return as-is
    val
  ]
 };

/ Validate config against schema
/ schema: dict of key -> dict with `type and optional `validator
/ config: dict of key -> value
validator.validate:{[schema;config]
  errors:();

  / Check required keys
  requiredKeys:key schema;
  missingKeys:requiredKeys where not requiredKeys in key config;
  if[count missingKeys;
    errors,:enlist (`missing_keys; missingKeys)
  ];

  / Validate each key
  {[schema;config;errors;k]
    if[not k in key config; :errors];  / Already handled above

    schemaEntry:schema[k];
    expectedType:schemaEntry[`type];
    validatorFn:schemaEntry[`validator];

    val:config[k];

    / Coerce to expected type
    coerced:validator.coerce[expectedType; val];

    / Run custom validator if provided
    if[not null validatorFn;
      validRes:validatorFn[coerced];
      if[not validRes;
        errors,:enlist (`validation_failed; k; val)
      ]
    ];

    errors
  }[schema;config;]/[errors; requiredKeys];

  errors
 };

\d .conf
