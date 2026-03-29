/ Configuration File Parser
/ Parses .conf files into nested dictionaries

\d .conf.parser

/ Helper: trim whitespace from string (vectorized)
ltrim:{$[10h=type x; $[count x; $[" "=first x; ltrim 1_x; x]; x]; x]};
rtrim:{$[10h=type x; $[count x; $[" "=last x; rtrim -1_x; x]; x]; x]};
trim:{rtrim ltrim x};

/ Parse a single line from .conf file
parseLine:{[line]
  / Trim whitespace
  line:trim line;

  / Skip empty lines and comments
  if[(0=count line) or "#"=first line; :()];

  / Section header: [section_name]
  if["["=first line;
    :(`section; `$trim 1_-1_line)
  ];

  / Key-value pair: key=value
  parts:"="vs line;
  if[2<>count parts; :(`;`;`error)];  / Invalid line

  key:`$trim first parts;
  val:trim last parts;

  :(`kv; key; val)
 };

/ Parse .conf file into nested dictionary
parseFile:{[filepath]
  / Read file line by line
  lines:read0 hsym `$filepath;

  / Initialize state
  config:()!();
  currentSection:`global;

  / Process each line with fold
  result:{[state;line]
    config:state 0;
    currentSection:state 1;
    parsed:parseLine[line];

    / Handle different parse results
    $[
      `section~first parsed;
        / New section
        [currentSection:parsed 1; config];
      `kv~first parsed;
        / Key-value pair
        [
          key:parsed 1;
          val:parsed 2;

          / Initialize section if needed
          if[not currentSection in key config;
            config[currentSection]:()!()
          ];

          / Add to section
          config[currentSection][key]:val
        ];
      / else: skip invalid lines
      config
    ];

    / Return updated state
    (config;currentSection)
  }/[(config;currentSection);lines];

  / Return final config (drop currentSection from fold result)
  first result
 };

\d .
