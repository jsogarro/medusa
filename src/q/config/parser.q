/ Configuration File Parser
/ Parses .conf files into nested dictionaries

\d .conf

/ Helper: trim whitespace from string (vectorized)
parser.ltrim:{$[10h=type x; $[count x; $[" "=first x; parser.ltrim 1_x; x]; x]; x]};
parser.rtrim:{$[10h=type x; $[count x; $[" "=last x; parser.rtrim -1_x; x]; x]; x]};
parser.trim:{parser.rtrim parser.ltrim x};

/ Parse a single line from .conf file
parser.parseLine:{[line]
  / Trim whitespace
  line:parser.trim line;

  / Skip empty lines and comments
  if[(0=count line) or "#"=first line; :()];

  / Section header: [section_name]
  if["["=first line;
    :(`section; `$parser.trim 1_-1_line)
  ];

  / Key-value pair: key=value
  parts:"="vs line;
  if[2<>count parts; :(`;`;`error)];  / Invalid line

  confKey:`$parser.trim first parts;
  confVal:parser.trim last parts;

  :(`kv; confKey; confVal)
 };

/ Parse .conf file into nested dictionary
parser.parseFile:{[filepath]
  / Read file line by line
  lines:read0 hsym `$filepath;

  / Initialize state
  config:()!();
  currentSection:`global;

  / Process each line with fold
  result:{[state;line]
    config:state 0;
    currentSection:state 1;
    parsed:parser.parseLine[line];

    / Handle different parse results
    $[
      `section~first parsed;
        / New section
        [currentSection:parsed 1; config];
      `kv~first parsed;
        / Key-value pair
        [
          confKey:parsed 1;
          confVal:parsed 2;

          / Initialize section if needed
          if[not currentSection in key config;
            config[currentSection]:()!()
          ];

          / Add to section
          sectionConfig:config currentSection;
          sectionConfig[confKey]:confVal;
          config[currentSection]:sectionConfig;
          config
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

\d .conf
