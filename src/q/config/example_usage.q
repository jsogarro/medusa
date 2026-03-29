/ Example usage of Medusa configuration system
/ This script demonstrates how to use the configuration API

/ Load configuration module
\l config.q

-1 "";
-1 "========================================";
-1 "  Configuration System Usage Example";
-1 "========================================";
-1 "";

/ ============================================
/ Example 1: Basic initialization with defaults
/ ============================================
-1 "Example 1: Basic initialization with defaults";
-1 "----------------------------------------------";

/ Define defaults
defaults:()!();
defaults[`strategy]:()!();
defaults[`strategy][`tick_sleep]:"100";
defaults[`strategy][`max_notional]:"10000";
defaults[`strategy][`enabled]:"true";

/ Initialize with defaults only (no file)
.conf.init[(); defaults; ()];

/ Get values
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 0];
max_notional:.conf.getTyped[`strategy; `max_notional; `int; 0];
enabled:.conf.getTyped[`strategy; `enabled; `bool; 0b];

-1 "tick_sleep (int): ", string tick_sleep;
-1 "max_notional (int): ", string max_notional;
-1 "enabled (bool): ", string enabled;
-1 "";

/ ============================================
/ Example 2: Loading from configuration file
/ ============================================
-1 "Example 2: Loading from configuration file";
-1 "-------------------------------------------";

/ Initialize with file (overrides defaults)
.conf.init["../../../configs/strategies/example_strategy.conf"; defaults; ()];

/ Get values (now from file)
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 0];
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
paper_trading:.conf.getTyped[`strategy; `paper_trading; `bool; 0b];

-1 "tick_sleep (from file): ", string tick_sleep;
-1 "symbols (list): ", .Q.s symbols;
-1 "paper_trading (bool): ", string paper_trading;
-1 "";

/ ============================================
/ Example 3: Runtime override with .conf.set
/ ============================================
-1 "Example 3: Runtime override with .conf.set";
-1 "--------------------------------------------";

/ Set new value at runtime
.conf.set[`strategy; `tick_sleep; 25];

/ Get updated value
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 0];
-1 "tick_sleep (after runtime override): ", string tick_sleep;
-1 "";

/ ============================================
/ Example 4: Schema validation
/ ============================================
-1 "Example 4: Schema validation";
-1 "-----------------------------";

/ Define schema with validators
schema:()!();
schema[`strategy]:()!();
schema[`strategy][`tick_sleep]:(`type`validator!(`int; {x>0}));
schema[`strategy][`max_notional]:(`type`validator!(`int; {x>=1000}));

/ Reinitialize with validation
.conf.init["../../../configs/strategies/example_strategy.conf"; defaults; schema];

-1 "✓ Configuration validated successfully";
-1 "";

/ ============================================
/ Example 5: Default values for missing keys
/ ============================================
-1 "Example 5: Default values for missing keys";
-1 "--------------------------------------------";

/ Get nonexistent key with default
nonexistent:.conf.get[`strategy; `nonexistent_key; "default_value"];
-1 "nonexistent_key (with default): ", nonexistent;

/ Get typed value with default
missing_int:.conf.getTyped[`strategy; `missing_int; `int; 999];
-1 "missing_int (with default): ", string missing_int;
-1 "";

/ ============================================
/ Example 6: Multiple sections
/ ============================================
-1 "Example 6: Multiple sections";
-1 "-----------------------------";

/ Add exchange section to defaults
defaults[`exchange]:()!();
defaults[`exchange][`name]:"kraken";
defaults[`exchange][`api_url]:"https://api.kraken.com";

/ Initialize
.conf.init["../../../configs/strategies/example_strategy.conf"; defaults; ()];

/ Get values from different sections
strategy_tick:.conf.getTyped[`strategy; `tick_sleep; `int; 0];
exchange_name:.conf.getTyped[`exchange; `name; `symbol; `];

-1 "strategy.tick_sleep: ", string strategy_tick;
-1 "exchange.name: ", string exchange_name;
-1 "";

/ ============================================
/ Example 7: Working with lists
/ ============================================
-1 "Example 7: Working with lists";
-1 "------------------------------";

/ Get list of symbols
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
-1 "symbols (count): ", string count symbols;
-1 "symbols: ", .Q.s symbols;

/ Check if specific symbol is in config
if[`AAPL in symbols; -1 "✓ AAPL is in the trading list"];
if[`TSLA in symbols; -1 "✓ TSLA is in the trading list"; -1 "✗ TSLA is not in the trading list"];
-1 "";

/ ============================================
/ Example 8: Type coercion examples
/ ============================================
-1 "Example 8: Type coercion examples";
-1 "----------------------------------";

/ Integer
tick_sleep:.conf.getTyped[`strategy; `tick_sleep; `int; 0];
-1 "Integer: ", string[tick_sleep], " (type: ", string[type tick_sleep], ")";

/ Float
stop_loss:.conf.getTyped[`strategy; `stop_loss; `float; 0.0];
-1 "Float: ", string[stop_loss], " (type: ", string[type stop_loss], ")";

/ Symbol
exchange_name:.conf.getTyped[`exchange; `name; `symbol; `];
-1 "Symbol: ", string[exchange_name], " (type: ", string[type exchange_name], ")";

/ Boolean
paper_trading:.conf.getTyped[`strategy; `paper_trading; `bool; 0b];
-1 "Boolean: ", string[paper_trading], " (type: ", string[type paper_trading], ")";

/ List
symbols:.conf.getTyped[`strategy; `symbols; `list; ()];
-1 "List: ", .Q.s[symbols], " (type: ", string[type symbols], ")";
-1 "";

/ ============================================
/ Example 9: Configuration introspection
/ ============================================
-1 "Example 9: Configuration introspection";
-1 "---------------------------------------";

-1 "Available sections: ", .Q.s key .conf.current;
-1 "Strategy keys: ", .Q.s key .conf.current[`strategy];
-1 "";

/ ============================================
/ Example 10: Using initWithReload for development
/ ============================================
-1 "Example 10: Using initWithReload for development";
-1 "------------------------------------------------";

/ Initialize with reload support
.conf.initWithReload["../../../configs/strategies/example_strategy.conf"; defaults; ()];

-1 "✓ Configuration loaded with reload support";
-1 "You can now call .conf.reload[] to hot-reload from disk";
-1 "";

-1 "========================================";
-1 "  Configuration System Examples Complete";
-1 "========================================";
-1 "";

/ Show final configuration
-1 "Current configuration:";
-1 .Q.s .conf.current;
-1 "";

exit 0
