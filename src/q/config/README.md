# Medusa Configuration System

Hierarchical configuration system for Medusa, modeled after Gryphon's ConfigurableObject pattern.

## Features

- **Hierarchical Merging**: Defaults → File → Environment Variables
- **Type Coercion**: Automatic conversion from strings to typed values
- **Validation**: Schema-based validation with custom validators
- **Hot Reload**: Reload configuration without restarting
- **Environment Overrides**: Override any setting via environment variables

## Quick Start

```q
/ Load configuration module
\l config/config.q

/ Define defaults
defaults:()!();
defaults[`strategy]:()!();
defaults[`strategy][`tick_sleep]:"100";
defaults[`strategy][`max_notional]:"5000";

/ Initialize
.conf.init["configs/strategies/example_strategy.conf"; defaults; ()];

/ Get values with type coercion
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];  / -> 100
enabled:.conf.getTyped[`strategy; `enabled; `bool; 1b];        / -> 1b

/ Runtime override
.conf.set[`strategy; `tick_sleep; 50];

/ Reload from disk
.conf.reload[];
```

## Configuration File Format

Configuration files use `.conf` format with simple `key=value` syntax:

```conf
# Comment lines start with #

[section_name]
key1=value1
key2=value2

[another_section]
key3=value3
```

Example:

```conf
[strategy]
tick_sleep=100
max_notional=5000
symbols=AAPL,GOOG,MSFT
enabled=true

[exchange]
name=kraken
api_url=https://api.kraken.com
```

## Type Coercion

The system automatically converts string values to typed q values:

| Type | Example Input | Example Output |
|------|---------------|----------------|
| `int` | `"42"` | `42` |
| `float` | `"3.14"` | `3.14f` |
| `symbol` | `"kraken"` | `` `kraken`` |
| `bool` | `"true"` / `"false"` | `1b` / `0b` |
| `list` | `"1,2,3"` or `"[1,2,3]"` | `1 2 3` |
| `string` | `"text"` | `"text"` |

## Environment Variable Overrides

Override any configuration value using environment variables:

**Pattern**: `MEDUSA_{SECTION}_{KEY}`

Examples:
```bash
export MEDUSA_STRATEGY_TICK_SLEEP=50
export MEDUSA_EXCHANGE_NAME=binance
export MEDUSA_DATABASE_HDB_PATH=/data/prod/hdb
```

These override values from the configuration file.

## API Reference

### `.conf.init[configPath; defaults; schema]`

Initialize the configuration system.

**Parameters**:
- `configPath`: Path to `.conf` file (or `` ` `` for defaults only)
- `defaults`: Dictionary of default values
- `schema`: Validation schema (or `()` for no validation)

**Returns**: Configuration dictionary

**Example**:
```q
defaults:(`strategy)!(enlist `tick_sleep`max_notional!(100;5000));
.conf.init["configs/strategy.conf"; defaults; ()];
```

### `.conf.get[section; key; default]`

Get configuration value with optional default.

**Parameters**:
- `section`: Section name (e.g., `` `strategy``)
- `key`: Configuration key (e.g., `` `tick_sleep``)
- `default`: Value to return if not found

**Returns**: Configuration value (as string) or default

**Example**:
```q
value:.conf.get[`strategy; `tick_sleep; "100"];
```

### `.conf.getTyped[section; key; typeName; default]`

Get configuration value with automatic type coercion.

**Parameters**:
- `section`: Section name
- `key`: Configuration key
- `typeName`: Type to coerce to (`` `int`float`symbol`bool`list`string``)
- `default`: Value to return if not found (already typed)

**Returns**: Typed configuration value or default

**Example**:
```q
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];  / Returns 100 (integer)
enabled:.conf.getTyped[`strategy; `enabled; `bool; 1b];        / Returns 1b (boolean)
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];        / Returns symbol list
```

### `.conf.set[section; key; value]`

Set configuration value at runtime (does not persist to disk).

**Parameters**:
- `section`: Section name
- `key`: Configuration key
- `value`: Value to set

**Returns**: The value that was set

**Example**:
```q
.conf.set[`strategy; `tick_sleep; 50];
```

### `.conf.reload[]`

Reload configuration from disk (re-reads file and environment variables).

**Parameters**: None

**Returns**: Updated configuration dictionary

**Example**:
```q
.conf.reload[];
```

### `.conf.initWithReload[configPath; defaults; schema]`

Initialize configuration with reload support. Stores parameters for later use with `.conf.reload[]`.

**Example**:
```q
.conf.initWithReload["configs/strategy.conf"; defaults; schema];
/ ... later ...
.conf.reload[];  / Re-reads the same file
```

## Validation

You can define a schema to validate configuration values:

```q
/ Define schema
schema:()!();
schema[`strategy]:()!();
schema[`strategy][`tick_sleep]:(`type`validator!(`int; {x>0}));
schema[`strategy][`max_notional]:(`type`validator!(`int; {x>0}));

/ Initialize with validation
.conf.init["configs/strategy.conf"; defaults; schema];
```

The validator function receives the coerced value and should return `1b` (valid) or `0b` (invalid).

## Configuration Files

### System Defaults: `configs/defaults.conf`

Contains system-wide defaults for all strategies and exchanges.

### Strategy Configs: `configs/strategies/*.conf`

Strategy-specific configurations that override defaults.

### Exchange Configs: `configs/exchanges/*.conf`

Exchange-specific configurations (API endpoints, fees, etc.).

## Testing

Run the test suite:

```bash
q tests/q/test_parser.q      # Parser tests
q tests/q/test_validator.q   # Validator tests
q tests/q/test_loader.q      # Loader tests
q tests/q/test_config.q      # Integration tests
q tests/q/test_config_all.q  # All tests
```

## Directory Structure

```
src/q/config/
├── config.q       # Main module (public API)
├── parser.q       # .conf file parser
├── validator.q    # Type validation and coercion
├── loader.q       # Hierarchical configuration loader
└── README.md      # This file

configs/
├── defaults.conf               # System defaults
├── strategies/
│   └── example_strategy.conf   # Strategy config
└── exchanges/
    └── kraken.conf             # Exchange config

tests/q/
├── test_parser.q      # Parser unit tests
├── test_validator.q   # Validator unit tests
├── test_loader.q      # Loader unit tests
├── test_config.q      # Integration tests
└── test_config_all.q  # Comprehensive test runner
```

## Integration with Medusa

The configuration system is loaded automatically when you run:

```bash
q src/q/init.q
```

It's available in the `.conf` namespace.

Example usage in a strategy:

```q
/ In your strategy module
.strategy.init:{[]
  / Load strategy configuration
  tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
  max_notional:.conf.getTyped[`strategy; `max_notional; `int; 10000];
  symbols:.conf.getTyped[`strategy; `symbols; `list; ()];

  / Use configuration values
  .z.ts:{[] .strategy.tick[]};
  system "t ",string tick_sleep;
 };
```

## Advanced Usage

### Multiple Configuration Files

Load base config, then override with environment-specific config:

```q
/ Load base defaults
base:.conf.parser.parseFile["configs/defaults.conf"];

/ Merge with environment config
env:.conf.parser.parseFile["configs/production.conf"];
config:.conf.loader.merge[base; env];

/ Initialize with merged config
.conf.current::config;
```

### Custom Validators

Create custom validators for complex rules:

```q
/ Validator: ensure value is positive
positiveInt:{x>0};

/ Validator: ensure value is in list
inList:{[allowed;x] x in allowed};

/ Validator: ensure URL is valid
validUrl:{[x] ("http" ss x)~0};

/ Define schema with custom validators
schema:()!();
schema[`strategy][`tick_sleep]:(`type`validator!(`int; positiveInt));
schema[`exchange][`name]:(`type`validator!(`symbol; inList[`kraken`coinbase`binance]));
schema[`exchange][`api_url]:(`type`validator!(`string; validUrl));
```

## Troubleshooting

### Configuration not loading

1. Check file path is correct (relative to working directory)
2. Ensure file has proper `.conf` extension
3. Verify file format (sections in `[brackets]`, `key=value` pairs)
4. Check for syntax errors (missing `=`, invalid section names)

### Type coercion failures

The coercion functions return null values on failure:
- `0Ni` for invalid integers
- `0Nf` for invalid floats
- `0Nb` for invalid booleans

Check your input strings are in the correct format.

### Environment variables not working

1. Ensure variables are exported: `export MEDUSA_SECTION_KEY=value`
2. Check variable name follows pattern: `MEDUSA_{SECTION}_{KEY}`
3. Variable names are case-sensitive (uppercase expected)
4. Test with: `system "env" | grep MEDUSA`

## Performance Considerations

- Configuration is loaded **once at startup** and cached in memory
- `.conf.get` and `.conf.getTyped` are O(1) dictionary lookups
- `.conf.reload` re-reads the file — use sparingly in production
- No disk I/O during normal operation (only at init/reload)

## Security

⚠️ **Never commit sensitive values to `.conf` files**

For API keys, secrets, and credentials:
1. Use environment variables: `export MEDUSA_EXCHANGE_API_KEY=secret`
2. Add comments in `.conf` files explaining how to set env vars
3. Add `.conf` files with secrets to `.gitignore`
4. Use a separate `secrets.conf` file (gitignored) that overrides defaults

Example:
```conf
[exchange]
# API credentials (set via environment variables)
# export MEDUSA_EXCHANGE_API_KEY=your_key
# export MEDUSA_EXCHANGE_API_SECRET=your_secret
```

## Future Enhancements

Planned features:
- JSON config file support (`.json` format)
- YAML config file support (`.yaml` format)
- Hot reload via file watcher (`.z.vs` handler)
- Configuration validation CLI tool
- Web UI for configuration management
- Configuration change audit log
- Configuration versioning and rollback

## License

MIT License (see project LICENSE file)
