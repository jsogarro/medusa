# Configuration System — Quick Reference

## Load the Module

```q
\l config/config.q
```

## Initialize Configuration

```q
/ With defaults only
defaults:(`strategy)!(enlist `tick_sleep`max_notional!(100;5000));
.conf.init[(); defaults; ()];

/ With config file
.conf.init["configs/strategies/example_strategy.conf"; defaults; ()];

/ With validation schema
schema:(`strategy)!(enlist `tick_sleep!(enlist `type`validator!(`int;{x>0})));
.conf.init["configs/strategy.conf"; defaults; schema];

/ With reload support
.conf.initWithReload["configs/strategy.conf"; defaults; ()];
```

## Get Configuration Values

```q
/ Raw string value with default
value:.conf.get[`strategy; `tick_sleep; "100"];

/ Typed value (auto-coercion)
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
enabled:.conf.getTyped[`strategy; `enabled; `bool; 0b];
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
exchange:.conf.getTyped[`exchange; `name; `symbol; `kraken];
```

## Set Configuration Values

```q
/ Runtime override (does not persist to disk)
.conf.set[`strategy; `tick_sleep; 50];
```

## Reload Configuration

```q
/ Re-read file and environment variables
.conf.reload[];
```

## Supported Types

| Type | Example Input | Example Output |
|------|---------------|----------------|
| `int` | `"42"` | `42` |
| `float` | `"3.14"` | `3.14f` |
| `symbol` | `"kraken"` | `` `kraken`` |
| `bool` | `"true"` / `"false"` | `1b` / `0b` |
| `list` | `"1,2,3"` or `"[1,2,3]"` | `1 2 3` |
| `string` | `"text"` | `"text"` |

## Configuration File Format

```conf
# Comments start with #

[section_name]
key1=value1
key2=value2

[another_section]
key3=value3
```

## Environment Variable Overrides

Set environment variables to override config file values:

```bash
export MEDUSA_STRATEGY_TICK_SLEEP=50
export MEDUSA_EXCHANGE_NAME=binance
```

Pattern: `MEDUSA_{SECTION}_{KEY}` (uppercase)

## Common Patterns

### Strategy Configuration

```q
/ Load strategy config
.conf.init["configs/strategies/my_strategy.conf"; defaults; ()];

/ Get strategy parameters
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
max_notional:.conf.getTyped[`strategy; `max_notional; `int; 10000];

/ Use in strategy
.strategy.tick:{[]
  / ... trading logic using config values
 };

system "t ",string tick_sleep;  / Set tick interval
```

### Exchange Configuration

```q
/ Load exchange config
.conf.init["configs/exchanges/kraken.conf"; defaults; ()];

/ Get exchange parameters
name:.conf.getTyped[`exchange; `name; `symbol; `kraken];
api_url:.conf.getTyped[`exchange; `api_url; `string; ""];
rate_limit:.conf.getTyped[`exchange; `rate_limit; `int; 10];
```

### Multiple Sections

```q
/ Access different sections
strategy_tick:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
exchange_name:.conf.getTyped[`exchange; `name; `symbol; `kraken];
hdb_path:.conf.getTyped[`database; `hdb_path; `string; "/data/hdb"];
log_level:.conf.getTyped[`logging; `level; `symbol; `INFO];
```

### Validation

```q
/ Define schema with validators
schema:()!();
schema[`strategy]:()!();

/ Positive integer validator
schema[`strategy][`tick_sleep]:(`type`validator!(`int; {x>0}));

/ Value in list validator
schema[`exchange][`name]:(`type`validator!(`symbol; {x in `kraken`coinbase`binance}));

/ URL format validator
schema[`exchange][`api_url]:(`type`validator!(`string; {0~("http" ss x)}));

/ Initialize with validation (throws error if invalid)
.conf.init["configs/strategy.conf"; defaults; schema];
```

## Testing

```bash
# Run individual test suites
q tests/q/test_parser.q
q tests/q/test_validator.q
q tests/q/test_loader.q
q tests/q/test_config.q

# Run all tests
q tests/q/test_config_all.q

# Run usage examples
q src/q/config/example_usage.q
```

## File Locations

| File | Purpose |
|------|---------|
| `src/q/config/config.q` | Main API module |
| `src/q/config/parser.q` | .conf file parser |
| `src/q/config/validator.q` | Type coercion |
| `src/q/config/loader.q` | Hierarchical loading |
| `configs/defaults.conf` | System defaults |
| `configs/strategies/*.conf` | Strategy configs |
| `configs/exchanges/*.conf` | Exchange configs |

## Common Errors

### File not found
```
/ Check file path relative to working directory
/ Or use absolute path
.conf.init["/full/path/to/config.conf"; defaults; ()];
```

### Type coercion failure
```
/ Returns null on failure: 0Ni, 0Nf, 0Nb
/ Check input format matches expected type
```

### Validation error
```
/ Schema validation throws error with message
/ Check validator function and input value
```

### Environment variable not working
```bash
# Ensure variable is exported
export MEDUSA_STRATEGY_TICK_SLEEP=50

# Check it's set
echo $MEDUSA_STRATEGY_TICK_SLEEP

# Verify pattern: MEDUSA_{SECTION}_{KEY} (uppercase)
```

## Tips

- **Always use `.conf.getTyped`** for automatic type coercion
- **Provide defaults** to `.conf.get` and `.conf.getTyped` for safety
- **Use environment variables** for secrets (never commit to git)
- **Call `.conf.reload[]`** to hot-reload without restart
- **Define schemas** for critical configuration to catch errors early
- **Use `.conf.initWithReload`** in development for easy reloading

## Full Documentation

See `README.md` in this directory for complete documentation.

## Example: Complete Strategy

```q
/ Load configuration
\l config/config.q

/ Define defaults
defaults:()!();
defaults[`strategy]:()!();
defaults[`strategy][`tick_sleep]:"100";
defaults[`strategy][`symbols]:"AAPL,GOOG,MSFT";
defaults[`strategy][`max_notional]:"10000";

/ Initialize
.conf.initWithReload["configs/strategies/my_strategy.conf"; defaults; ()];

/ Get configuration
.strategy.config.tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
.strategy.config.symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
.strategy.config.max_notional:.conf.getTyped[`strategy; `max_notional; `int; 10000];

/ Strategy logic
.strategy.tick:{[]
  / Use .strategy.config.* values
  -1 "Tick at ",string .z.t," for symbols: ",.Q.s .strategy.config.symbols;
 };

/ Start strategy
system "t ",string .strategy.config.tick_sleep;

/ Later: hot reload
.conf.reload[];
/ Update strategy config
.strategy.config.tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 100];
system "t ",string .strategy.config.tick_sleep;
```
