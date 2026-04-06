# Medusa Testing Guide

## Test Pyramid

```
        /\
       /  \   E2E: Full system (TP + strategies + exchange sim)
      /----\  (planned — Wave 10)
     /      \
    /--------\ Integration: Component interactions
   /          \ (Python: CSV→features→backtest→risk, LSTM pipeline)
  /            \
 /--------------\ Unit: Individual functions and classes
/________________\ (Python: 65 tests, Rust: cargo test, q: test scripts)
```

## Running Tests

### All Tests
```bash
make test
```

### Python (pytest)
```bash
cd src/python
source .venv/bin/activate

# All tests (skip XGBoost on macOS arm64)
pytest tests/ -v -k "not XGBoost"

# Specific test modules
pytest tests/test_features.py -v     # Feature engineering
pytest tests/test_risk.py -v         # Risk analytics
pytest tests/test_strategies.py -v   # Trading strategies
pytest tests/test_models.py -v -k "not XGBoost"  # ML models
pytest tests/test_integration.py -v  # End-to-end workflows

# With coverage
pytest tests/ -v --cov=medusa --cov-report=html -k "not XGBoost"
```

### Rust (cargo)
```bash
cd src/rust
cargo test --workspace
cargo test -p exchange-connector   # Single crate
cargo test -p kdb-ipc             # IPC protocol tests
```

### q
```bash
# Run q test suite (if available)
q tests/q/run_all.q -q

# Manual testing with q REPL
rlwrap q src/q/init.q
```

## Test Modules (Python)

| Module | Tests | Coverage |
|--------|-------|----------|
| test_config.py | 5 | Config defaults, overrides, settings factory |
| test_data_loaders.py | 11 | CSV/Parquet loading, validation, error handling |
| test_features.py | 17 | Technical indicators, preprocessing, feature pipeline |
| test_strategies.py | 7 | SMA crossover signals, strategy interface |
| test_risk.py | 8 | Sharpe, Sortino, VaR, CVaR, full risk report |
| test_models.py | 7 | LSTM, Transformer shapes; XGBoost (skip-guarded) |
| test_integration.py | 3 | CSV→backtest, feature pipeline, LSTM pipeline |
| test_placeholder.py | 11 | Package structure, imports, type annotations |

## Writing New Tests

### Python test conventions
- Place in `src/python/tests/test_<module>.py`
- Use fixtures from `conftest.py` (`sample_ohlcv`, `sample_price`, `sample_returns`)
- Mark tests requiring kdb+ connection: `@pytest.mark.skipif(True, reason="Requires kdb+")`
- Mark tests requiring XGBoost: use `pytest.importorskip` or subprocess check

### Rust test conventions
- Unit tests in `#[cfg(test)]` modules within source files
- Integration tests in `tests/` directory per crate
- Use `tokio::test` for async tests

## Known Test Issues

1. **XGBoost segfaults** on macOS arm64 + numpy 2.x — skip-guarded via subprocess check
2. **kdb+ integration tests** require running TP/RDB/HDB — skipped by default
3. **NautilusTrader tests** not implemented (skeleton module)
