/ Configuration Type Validator and Coercer

\d .conf.validator

/ Helper: trim whitespace (vectorized)
ltrim:{$[10h=type x; $[count x; $[" "=first x; ltrim 1_x; x]; x]; x]};
rtrim:{$[10h=type x; $[count x; $[" "=last x; rtrim -1_x; x]; x]; x]};
trim:{rtrim ltrim x};

/ Coerce string to integer
coerceInt:{[val]
  / Try to parse as integer
  res:@[{"J"$x}; val; {(`error; x)}];
  $[`error~first res; 0Ni; res]
 };

/ Coerce string to float
coerceFloat:{[val]
  / Try to parse as float
  res:@[{"F"$x}; val; {(`error; x)}];
  $[`error~first res; 0Nf; res]
 };

/ Coerce string to symbol
coerceSymbol:{[val]
  / Convert to symbol
  `$val
 };

/ Coerce string to boolean
coerceBool:{[val]
  / Parse boolean
  lower:.Q.lc val;
  $[lower in ("true";"1";"yes";"on"); 1b;
    lower in ("false";"0";"no";"off"); 0b;
    0Nb]
 };

/ Coerce string to list
coerceList:{[val]
  / Parse JSON-style list: "[1,2,3]" or "1,2,3"
  / Remove brackets if present
  val:trim val;
  if["["=first val; val:1_val];
  if["]"=last val; val:-1_val];

  / Split by comma
  items:","vs val;
  items:trim each items;

  / Try to infer type from first element
  if[0=count items; :()];

  first_item:first items;

  / Try int
  if[not null coerceInt[first_item];
    :coerceInt each items
  ];

  / Try float
  if[not null coerceFloat[first_item];
    :coerceFloat each items
  ];

  / Default to symbols
  coerceSymbol each items
 };

/ Coerce value to specified type
/ typeName: `int`float`symbol`bool`string`list
/ val: string value to coerce
coerce:{[typeName;val]
  $[
    `int~typeName; coerceInt[val];
    `float~typeName; coerceFloat[val];
    `symbol~typeName; coerceSymbol[val];
    `bool~typeName; coerceBool[val];
    `list~typeName; coerceList[val];
    `string~typeName; val;
    / Default: return as-is
    val
  ]
 };

/ Validate config against schema
/ schema: dict of key -> dict with `type and optional `validator
/ config: dict of key -> value
validate:{[schema;config]
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
    coerced:coerce[expectedType; val];

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

\d .
