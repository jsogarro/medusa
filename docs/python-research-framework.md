# Python Research Framework

Comprehensive guide to Medusa's Python research environment for backtesting, feature engineering, ML models, and analytics.

## Overview

The Python research framework provides a complete toolkit for quantitative strategy development:

- **Two-tier backtesting**: VectorBT (fast vectorized) + NautilusTrader (event-driven, planned)
- **ML models**: LSTM, Transformer, TFT, N-BEATS, XGBoost
- **PyKX integration**: Zero-copy data loading from kdb+ HDB/RDB
- **Feature engineering**: 10+ technical indicators, preprocessing pipeline
- **Analytics**: Risk metrics (Sharpe, VaR, CVaR), performance tearsheets, portfolio optimization
- **Live testing**: Subscribe to Tickerplant, test signals in real-time (paper trading)

## Installation

```bash
cd src/python
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

This installs the `medusa` package in editable mode with all development dependencies.

### Dependencies

| Category | Libraries |
|----------|-----------|
| Data | `pykx`, `pandas`, `polars`, `pyarrow` |
| Backtesting | `vectorbt`, `nautilus_trader` |
| ML | `torch`, `xgboost`, `scikit-learn` |
| Analytics | `quantstats`, `empyrical` |
| Indicators | `ta-lib`, `pandas_ta` |
| Utilities | `pydantic`, `loguru`, `click` |

## Data Loading

The framework supports three data sources: kdb+ (via PyKX), CSV, and Parquet.

### KdbDataLoader (Recommended)

Zero-copy data loading from kdb+ HDB or RDB.

```python
from medusa.data import KdbDataLoader

# Connect to HDB (historical data)
loader = KdbDataLoader(host="localhost", port=5012, user="", password="")

# Load OHLCV data
df = loader.load_ohlcv(
    symbol="BTCUSD",
    exchange="coinbase",
    start_date="2025-01-01",
    end_date="2025-01-31",
    timeframe="1h"
)

# Result: pandas DataFrame with columns [timestamp, open, high, low, close, volume]
```

#### Query Methods

```python
# Load orderbook snapshot
orderbook = loader.load_orderbook(symbol="BTCUSD", exchange="coinbase", timestamp="2025-01-15T12:00:00")

# Load trades
trades = loader.load_trades(symbol="BTCUSD", exchange="coinbase", start_date="2025-01-01", end_date="2025-01-02")

# Raw q query (advanced)
result = loader.query("select from trade where sym=`BTCUSD, date=2025.01.15")
```

#### Symbol Validation

The loader validates symbols before constructing q queries (prevents injection):

```python
# Valid: alphanumeric uppercase
loader.load_ohlcv("BTCUSD", ...)  # OK
loader.load_ohlcv("ETHUSD", ...)  # OK

# Invalid: raises ValueError
loader.load_ohlcv("BTC-USD", ...)  # Error: contains hyphen
loader.load_ohlcv("btcusd", ...)   # Error: lowercase
```

### CsvDataLoader

For CSV files with OHLCV data:

```python
from medusa.data import CsvDataLoader

loader = CsvDataLoader()
df = loader.load("data/btcusd_1h.csv")
```

Expected CSV format:
```csv
timestamp,open,high,low,close,volume
2025-01-01T00:00:00,50000.0,50100.0,49900.0,50050.0,100.5
2025-01-01T01:00:00,50050.0,50200.0,50000.0,50150.0,120.3
```

### ParquetDataLoader

For Parquet files (efficient columnar format):

```python
from medusa.data import ParquetDataLoader

loader = ParquetDataLoader()
df = loader.load("data/btcusd_1h.parquet")
```

### Data Validation

All loaders validate OHLCV data:

```python
from medusa.data import validate_ohlcv, check_data_quality

# Validate schema (raises ValueError if invalid)
validate_ohlcv(df)

# Check data quality (returns dict with issues)
quality_report = check_data_quality(df)
print(quality_report)
# {
#     "missing_values": 0,
#     "duplicate_timestamps": 0,
#     "negative_prices": 0,
#     "zero_volume_bars": 5,
#     "gaps": []
# }
```

## Backtesting Tutorial

### Step 1: Load Data

```python
from medusa.data import KdbDataLoader

loader = KdbDataLoader(host="localhost", port=5012)
df = loader.load_ohlcv("BTCUSD", "coinbase", "2025-01-01", "2025-01-31", "1h")
```

### Step 2: Generate Signals

Example: SMA crossover strategy (fast SMA crosses above slow SMA = buy signal).

```python
from medusa.strategies.examples import sma_crossover_signals

entries, exits = sma_crossover_signals(df["close"], fast_period=10, slow_period=30)

# entries: boolean array where True = enter long
# exits: boolean array where True = exit long
```

### Step 3: Run Backtest

```python
from medusa.backtest import VectorBTEngine

engine = VectorBTEngine(
    initial_cash=10000.0,
    commission=0.001,  # 0.1% per trade
    slippage=0.0005    # 0.05% slippage
)

portfolio = engine.run_signals(
    price=df["close"],
    entries=entries,
    exits=exits
)

print(portfolio.stats())
# Start                          2025-01-01 00:00:00
# End                            2025-01-31 23:00:00
# Duration                                744:00:00
# Start Value                                10000.0
# End Value                                  10523.4
# Total Return [%]                              5.23
# Sharpe Ratio                                  1.24
# Max Drawdown [%]                              -8.5
# Total Trades                                    12
```

### Step 4: Analyze Results

```python
from medusa.analytics import RiskAnalytics

returns = portfolio.returns()

# Full risk report
report = RiskAnalytics.full_report(returns)
print(report)
# {
#     "sharpe_ratio": 1.24,
#     "sortino_ratio": 1.67,
#     "max_drawdown": -0.085,
#     "var_95": -0.025,
#     "cvar_95": -0.032,
#     "calmar_ratio": 0.615,
#     "total_return": 0.0523,
#     "annualized_return": 0.214,
#     "annualized_volatility": 0.173
# }

# Generate HTML tearsheet
from medusa.analytics import PerformanceTearsheet

PerformanceTearsheet.generate_html(returns, output_path="reports/backtest.html")
```

### Step 5: Visualize

```python
import matplotlib.pyplot as plt

# Plot cumulative returns
portfolio.plot().show()

# Plot trades on price chart
portfolio.plot_trades().show()

# Plot underwater (drawdown) chart
portfolio.plot_underwater().show()
```

## Feature Engineering

### Technical Indicators

The framework provides 10+ technical indicators:

```python
from medusa.features import (
    sma, ema, rsi, macd, bollinger_bands, atr, vwap, volatility, returns
)

# Simple Moving Average
df["sma_20"] = sma(df["close"], period=20)

# Exponential Moving Average
df["ema_12"] = ema(df["close"], period=12)

# Relative Strength Index
df["rsi_14"] = rsi(df["close"], period=14)

# MACD (returns tuple: macd_line, signal_line, histogram)
df["macd"], df["macd_signal"], df["macd_hist"] = macd(df["close"])

# Bollinger Bands (returns tuple: upper, middle, lower)
df["bb_upper"], df["bb_middle"], df["bb_lower"] = bollinger_bands(df["close"], period=20, std=2.0)

# Average True Range (volatility)
df["atr_14"] = atr(df["high"], df["low"], df["close"], period=14)

# Volume Weighted Average Price
df["vwap"] = vwap(df["high"], df["low"], df["close"], df["volume"])

# Returns
df["returns"] = returns(df["close"])

# Historical volatility (rolling standard deviation)
df["volatility_20"] = volatility(df["close"], period=20)
```

### Add All Indicators

```python
from medusa.features import add_all_indicators

# Add all indicators with default parameters
df_with_features = add_all_indicators(df)

# Result: DataFrame with 30+ additional columns
# SMA (10, 20, 50, 200), EMA (12, 26), RSI (14), MACD, BB, ATR, VWAP, returns, etc.
```

### Feature Pipeline

For ML model training, use `FeaturePipeline`:

```python
from medusa.features import FeaturePipeline, add_all_indicators

# Create pipeline
pipeline = FeaturePipeline()

# Step 1: Add indicators
df_features = add_all_indicators(df)

# Step 2: Add custom features
pipeline.add_feature("price_momentum", lambda x: x["close"].pct_change(5))
pipeline.add_feature("volume_momentum", lambda x: x["volume"].pct_change(5))

# Step 3: Apply pipeline
df_features = pipeline.transform(df_features)

# Step 4: Scale features (for neural networks)
from medusa.features import FeatureScaler

scaler = FeatureScaler(method="standard")  # or "minmax"
features_scaled = scaler.fit_transform(df_features[["close", "volume", "rsi_14", "macd"]])
```

### Train/Test Split

Preserve temporal order (no lookahead bias):

```python
from medusa.features import train_test_split_temporal

train_df, test_df = train_test_split_temporal(df, test_size=0.2)

# Train set: first 80% of data
# Test set: last 20% of data
```

### Sequence Creation

For LSTM/Transformer models, create sequences:

```python
from medusa.features import create_sequences

X, y = create_sequences(
    df[["close", "volume", "rsi_14"]].values,
    sequence_length=60,  # 60 timesteps lookback
    target_column=0      # Predict close price
)

# X shape: (num_samples, 60, 3)
# y shape: (num_samples,)
```

## ML Models

All models inherit from `BaseModel` and follow a consistent API.

### LSTM (Long Short-Term Memory)

Time series forecasting with LSTM neural network:

```python
from medusa.models import LSTMModel
from medusa.features import create_sequences, FeatureScaler

# Prepare data
scaler = FeatureScaler(method="standard")
features_scaled = scaler.fit_transform(df[["close", "volume", "rsi_14"]])

X, y = create_sequences(features_scaled, sequence_length=60, target_column=0)

# Split
split_idx = int(len(X) * 0.8)
X_train, X_test = X[:split_idx], X[split_idx:]
y_train, y_test = y[:split_idx], y[split_idx:]

# Train LSTM
model = LSTMModel(input_dim=3, hidden_dim=128, num_layers=2, dropout=0.2)
model.fit(X_train, y_train, epochs=50, batch_size=32, validation_split=0.1)

# Predict
predictions = model.predict(X_test)

# Evaluate
mse = model.evaluate(X_test, y_test)
print(f"Test MSE: {mse:.4f}")
```

### Transformer

Attention-based time series model:

```python
from medusa.models import TransformerModel

model = TransformerModel(
    input_dim=3,
    d_model=128,
    nhead=8,
    num_layers=4,
    dropout=0.1
)

model.fit(X_train, y_train, epochs=50, batch_size=32)
predictions = model.predict(X_test)
```

### TFT (Temporal Fusion Transformer)

State-of-the-art multi-horizon forecasting:

```python
from medusa.models import TFTModel

model = TFTModel(
    input_dim=3,
    hidden_dim=128,
    num_heads=4,
    dropout=0.1
)

model.fit(X_train, y_train, epochs=50, batch_size=32)
predictions = model.predict(X_test)
```

### N-BEATS (Neural Basis Expansion Analysis)

Interpretable deep learning for time series:

```python
from medusa.models import NBEATSModel

model = NBEATSModel(
    input_dim=3,
    stack_types=["trend", "seasonality"],
    num_blocks_per_stack=3,
    hidden_layer_units=128
)

model.fit(X_train, y_train, epochs=50, batch_size=32)
predictions = model.predict(X_test)
```

### XGBoost

Gradient boosting for tabular features:

```python
from medusa.models import XGBoostModel

# No sequence needed - use raw features
X_train = df_train[["close", "volume", "rsi_14", "macd", "bb_upper"]].values
y_train = df_train["target"].values  # e.g., future return

model = XGBoostModel(
    n_estimators=100,
    max_depth=6,
    learning_rate=0.1,
    objective="reg:squarederror"
)

model.fit(X_train, y_train)
predictions = model.predict(X_test)
```

### Model Training Workflow

1. Load data
2. Engineer features (`add_all_indicators`)
3. Create target variable (e.g., future return, direction)
4. Train/test split (temporal)
5. Scale features (`FeatureScaler`)
6. Create sequences (for LSTM/Transformer)
7. Train model
8. Evaluate on test set
9. Save model (`model.save("models/lstm_v1.pth")`)
10. Load model (`model.load("models/lstm_v1.pth")`)

## Analytics

### Risk Metrics

```python
from medusa.analytics import RiskAnalytics

returns = portfolio.returns()

# Individual metrics
sharpe = RiskAnalytics.sharpe_ratio(returns, risk_free_rate=0.02)
sortino = RiskAnalytics.sortino_ratio(returns, target_return=0.0)
max_dd = RiskAnalytics.max_drawdown(returns)
var_95 = RiskAnalytics.value_at_risk(returns, confidence_level=0.95)
cvar_95 = RiskAnalytics.conditional_value_at_risk(returns, confidence_level=0.95)
calmar = RiskAnalytics.calmar_ratio(returns)

# Full report (all metrics)
report = RiskAnalytics.full_report(returns)
```

### Performance Tearsheet

Generate comprehensive HTML report:

```python
from medusa.analytics import PerformanceTearsheet

# Requires benchmark returns (e.g., BTC buy-and-hold)
benchmark_returns = df["close"].pct_change()

PerformanceTearsheet.generate_html(
    returns=returns,
    benchmark_returns=benchmark_returns,
    output_path="reports/tearsheet.html",
    title="BTCUSD SMA Crossover Strategy"
)
```

Tearsheet includes:

- Cumulative returns chart
- Drawdown chart
- Monthly returns heatmap
- Distribution of returns
- Risk metrics table
- Trade statistics
- Rolling Sharpe ratio
- Comparison to benchmark

### Portfolio Optimization

Mean-variance optimization (Markowitz):

```python
from medusa.analytics import PortfolioOptimizer

# Multiple asset returns (DataFrame with columns = asset symbols)
returns_df = pd.DataFrame({
    "BTCUSD": btc_returns,
    "ETHUSD": eth_returns,
    "SOLUSD": sol_returns
})

optimizer = PortfolioOptimizer(returns_df)

# Maximum Sharpe ratio portfolio
weights_sharpe = optimizer.max_sharpe_ratio(risk_free_rate=0.02)
print(weights_sharpe)
# {"BTCUSD": 0.45, "ETHUSD": 0.35, "SOLUSD": 0.20}

# Minimum volatility portfolio
weights_minvol = optimizer.min_volatility()

# Efficient frontier
frontier = optimizer.efficient_frontier(num_points=50)
# Returns list of (risk, return, weights) tuples
```

## Live Signal Testing

Test strategies in real-time by subscribing to the Tickerplant.

### TickSubscriber

Subscribe to real-time market data:

```python
from medusa.live import TickSubscriber

subscriber = TickSubscriber(host="localhost", port=5010, user="", password="")

# Subscribe to trades
subscriber.subscribe_trades(symbol="BTCUSD", exchange="coinbase")

# Callback on each trade
@subscriber.on_trade
def handle_trade(trade):
    print(f"Trade: {trade['price']} x {trade['quantity']}")

# Start subscriber loop
subscriber.run()
```

### LiveSignalTester

Paper trading with real-time signals:

```python
from medusa.live import LiveSignalTester
from medusa.strategies import BaseStrategy

class MyStrategy(BaseStrategy):
    def generate_signals(self, df):
        # Your strategy logic
        entries = df["sma_fast"] > df["sma_slow"]
        exits = df["sma_fast"] < df["sma_slow"]
        return entries, exits

tester = LiveSignalTester(
    strategy=MyStrategy(),
    initial_cash=10000.0,
    tp_host="localhost",
    tp_port=5010
)

# Subscribe to BTCUSD on Coinbase
tester.subscribe(symbol="BTCUSD", exchange="coinbase")

# Start paper trading
tester.run()

# Check current positions
positions = tester.get_positions()
print(positions)

# Check P&L
pnl = tester.get_pnl()
print(f"Current P&L: {pnl:.2f}")
```

## API Reference

### Data

- `DataLoader` — Abstract base class for all loaders
- `KdbDataLoader(host, port, user, password)` — Load from kdb+ via PyKX
  - `load_ohlcv(symbol, exchange, start_date, end_date, timeframe)`
  - `load_orderbook(symbol, exchange, timestamp)`
  - `load_trades(symbol, exchange, start_date, end_date)`
  - `query(q_expression)`
- `CsvDataLoader()` — Load from CSV files
  - `load(filepath)`
- `ParquetDataLoader()` — Load from Parquet files
  - `load(filepath)`
- `validate_ohlcv(df)` — Validate OHLCV DataFrame schema
- `check_data_quality(df)` — Check for missing values, duplicates, gaps

### Backtesting

- `Backtester` — Abstract base class for backtesting engines
- `VectorBTEngine(initial_cash, commission, slippage)` — Fast vectorized backtesting
  - `run_signals(price, entries, exits)`
  - `run_strategy(strategy, df)`
- `NautilusEngine()` — Event-driven backtesting (planned, skeleton only)
- `StrategyAdapter` — Adapter for custom strategies

### Strategies

- `BaseStrategy` — Abstract base class for strategies
  - `generate_signals(df)` — Returns (entries, exits) boolean arrays
- `sma_crossover_signals(price, fast_period, slow_period)` — SMA crossover example

### Models

- `BaseModel` — Abstract base class for ML models
  - `fit(X, y, epochs, batch_size)`
  - `predict(X)`
  - `evaluate(X, y)`
  - `save(path)`
  - `load(path)`
- `LSTMModel(input_dim, hidden_dim, num_layers, dropout)`
- `TransformerModel(input_dim, d_model, nhead, num_layers, dropout)`
- `TFTModel(input_dim, hidden_dim, num_heads, dropout)`
- `NBEATSModel(input_dim, stack_types, num_blocks_per_stack, hidden_layer_units)`
- `XGBoostModel(n_estimators, max_depth, learning_rate, objective)`

### Features

- `add_all_indicators(df)` — Add 30+ indicators to DataFrame
- `sma(series, period)`, `ema(series, period)`, `rsi(series, period)`
- `macd(series, fast, slow, signal)`, `bollinger_bands(series, period, std)`
- `atr(high, low, close, period)`, `vwap(high, low, close, volume)`
- `returns(series)`, `volatility(series, period)`
- `FeaturePipeline()` — Compose feature transformations
  - `add_feature(name, func)`
  - `transform(df)`
- `FeatureScaler(method)` — Scale features ("standard" or "minmax")
  - `fit_transform(df)`
  - `transform(df)`
- `create_sequences(data, sequence_length, target_column)` — Create LSTM sequences
- `train_test_split_temporal(df, test_size)` — Temporal train/test split

### Analytics

- `RiskAnalytics` — Risk metrics calculator
  - `sharpe_ratio(returns, risk_free_rate)`
  - `sortino_ratio(returns, target_return)`
  - `max_drawdown(returns)`
  - `value_at_risk(returns, confidence_level)`
  - `conditional_value_at_risk(returns, confidence_level)`
  - `calmar_ratio(returns)`
  - `full_report(returns)` — Dict with all metrics
- `PerformanceTearsheet` — HTML tearsheet generator
  - `generate_html(returns, benchmark_returns, output_path, title)`
- `PortfolioOptimizer(returns_df)` — Mean-variance optimization
  - `max_sharpe_ratio(risk_free_rate)`
  - `min_volatility()`
  - `efficient_frontier(num_points)`

### Live

- `TickSubscriber(host, port, user, password)` — Subscribe to Tickerplant
  - `subscribe_trades(symbol, exchange)`
  - `subscribe_orderbook(symbol, exchange)`
  - `on_trade(callback)`
  - `on_orderbook(callback)`
  - `run()`
- `LiveSignalTester(strategy, initial_cash, tp_host, tp_port)` — Paper trading
  - `subscribe(symbol, exchange)`
  - `run()`
  - `get_positions()`
  - `get_pnl()`

### Utilities

- `MedusaConfig` — Pydantic settings (reads from `MEDUSA_` env vars)
- `setup_logging(level)` — Configure loguru logger
