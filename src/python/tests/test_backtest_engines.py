"""Tests for backtesting engines (VectorBT, NautilusTrader, Optuna optimizer)."""

import numpy as np
import pandas as pd
import pytest

from medusa.backtest.vectorbt_engine import VectorBTEngine


@pytest.fixture
def sample_price_series():
    """Generate sample price series for backtesting."""
    np.random.seed(42)
    dates = pd.date_range("2024-01-01", periods=252, freq="D", tz="UTC")
    # Generate realistic price series with trend + noise
    trend = np.linspace(100, 110, 252)
    noise = np.random.randn(252) * 2
    prices = pd.Series(trend + noise, index=dates, name="close")
    return prices


@pytest.fixture
def equity_price_series():
    """Generate equity price series with DatetimeIndex (for market hours filtering)."""
    np.random.seed(42)
    # 5 days of intraday data (hourly bars)
    dates = pd.date_range("2024-01-02 09:30", periods=5 * 7, freq="H", tz="US/Eastern")
    prices = pd.Series(100 + np.cumsum(np.random.randn(len(dates)) * 0.5), index=dates)
    return prices


@pytest.fixture
def simple_signals(sample_price_series):
    """Generate simple entry/exit signals."""
    # Buy at start, sell at end
    entries = pd.Series(False, index=sample_price_series.index)
    exits = pd.Series(False, index=sample_price_series.index)
    entries.iloc[0] = True
    exits.iloc[-1] = True
    return entries, exits


class TestVectorBTEngine:
    """Test VectorBT backtesting engine."""

    def test_init_default(self):
        """Test engine initialization with defaults."""
        engine = VectorBTEngine()
        assert engine.initial_capital == 100_000.0  # From config
        assert engine.commission >= 0.0
        assert engine.slippage >= 0.0

    def test_init_custom_capital(self):
        """Test engine initialization with custom capital."""
        engine = VectorBTEngine(initial_capital=50_000.0)
        assert engine.initial_capital == 50_000.0

    def test_init_equity_mode(self):
        """Test equity mode uses zero commission."""
        engine = VectorBTEngine(asset_class="equity")
        assert engine.commission == 0.0
        assert engine.slippage == 0.0002  # 2 bps

    def test_init_crypto_mode(self):
        """Test crypto mode uses default commission."""
        engine = VectorBTEngine(asset_class="crypto")
        assert engine.commission > 0.0  # From config

    def test_run_signals_basic(self, sample_price_series, simple_signals):
        """Test running backtest from signals."""
        engine = VectorBTEngine()
        entries, exits = simple_signals
        pf = engine.run_signals(sample_price_series, entries, exits)

        # Check that backtest ran successfully
        assert pf is not None
        total_return = pf.total_return()
        assert not np.isnan(total_return)
        assert not np.isinf(total_return)

    def test_run_signals_with_returns(self, sample_price_series):
        """Test backtest generates positive returns with profitable signals."""
        engine = VectorBTEngine()

        # Generate winning signals: buy low, sell high
        entries = pd.Series(False, index=sample_price_series.index)
        exits = pd.Series(False, index=sample_price_series.index)

        # Buy at minimum price point
        min_idx = sample_price_series.idxmin()
        entries.loc[min_idx] = True

        # Sell at maximum price point (after buy)
        max_idx = sample_price_series[sample_price_series.index > min_idx].idxmax()
        exits.loc[max_idx] = True

        pf = engine.run_signals(sample_price_series, entries, exits)
        assert pf.total_return() > 0.0  # Should be profitable

    def test_filter_market_hours_equity(self, equity_price_series):
        """Test equity market hours filtering."""
        engine = VectorBTEngine(asset_class="equity")

        # Generate signals at all hours
        signals = pd.Series(True, index=equity_price_series.index)

        # Filter for regular hours (9:30-16:00 ET)
        filtered = engine._filter_market_hours(signals, extended_hours=False)

        # Check that pre-market and after-hours signals are False
        assert not filtered.all()  # Some should be filtered out

        # Extract hours in ET timezone
        hours = equity_price_series.index.tz_convert("US/Eastern").hour
        # Regular hours: 9-15 (9:30-16:00)
        regular_hours_mask = (hours >= 9) & (hours < 16)

        # Verify signals outside regular hours are False
        assert not filtered[~regular_hours_mask].any()

    def test_filter_market_hours_extended(self, equity_price_series):
        """Test extended hours market filtering."""
        engine = VectorBTEngine(asset_class="equity")

        signals = pd.Series(True, index=equity_price_series.index)
        filtered = engine._filter_market_hours(signals, extended_hours=True)

        # Extended hours (4:00-20:00 ET) should allow more signals
        hours = equity_price_series.index.tz_convert("US/Eastern").hour
        extended_mask = (hours >= 4) & (hours < 20)

        # Signals within extended hours should be True
        assert filtered[extended_mask].sum() > 0

    def test_filter_market_hours_crypto_no_filtering(self, sample_price_series):
        """Test crypto mode does not filter market hours (24/7 trading)."""
        engine = VectorBTEngine(asset_class="crypto")

        signals = pd.Series(True, index=sample_price_series.index)
        filtered = engine._filter_market_hours(signals)

        # Should return unchanged (no filtering for crypto)
        pd.testing.assert_series_equal(filtered, signals)

    def test_run_orders_basic(self, sample_price_series):
        """Test running backtest from order sizes."""
        engine = VectorBTEngine()

        # Buy 1 unit at start, sell 1 unit at end
        sizes = pd.Series(0.0, index=sample_price_series.index)
        sizes.iloc[0] = 1.0  # Buy 1
        sizes.iloc[-1] = -1.0  # Sell 1

        pf = engine.run_orders(sample_price_series, sizes)
        assert pf is not None
        assert not np.isnan(pf.total_return())

    def test_optimize_params_basic(self, sample_price_series):
        """Test parameter optimization grid search."""
        engine = VectorBTEngine()

        # Simple SMA crossover signal function
        def signal_func(price, fast_period, slow_period):
            fast_ma = price.rolling(fast_period).mean()
            slow_ma = price.rolling(slow_period).mean()
            entries = fast_ma > slow_ma
            exits = fast_ma < slow_ma
            return entries, exits

        param_grid = {
            "fast_period": [10, 20],
            "slow_period": [50, 100],
        }

        best_params, results_df = engine.optimize_params(
            sample_price_series,
            signal_func,
            param_grid,
            metric="sharpe_ratio",
        )

        # Check results
        assert "fast_period" in best_params
        assert "slow_period" in best_params
        assert len(results_df) == 4  # 2 x 2 grid
        assert "sharpe_ratio" in results_df.columns

    def test_optimize_params_best_selected(self, sample_price_series):
        """Test that optimization selects best params by metric."""
        engine = VectorBTEngine()

        # Signal function with known best params
        def signal_func(price, threshold):
            # Lower threshold = more trades = higher sharpe (up to a point)
            entries = price.pct_change() > threshold
            exits = price.pct_change() < -threshold
            return entries, exits

        param_grid = {"threshold": [0.01, 0.02, 0.05]}

        best_params, results_df = engine.optimize_params(
            sample_price_series,
            signal_func,
            param_grid,
            metric="total_return",
        )

        # Verify best params match max metric
        best_idx = results_df["total_return"].idxmax()
        assert best_params["threshold"] == results_df.loc[best_idx, "threshold"]

    def test_optimize_params_invalid_metric(self, sample_price_series):
        """Test that invalid metric raises error."""
        engine = VectorBTEngine()

        def signal_func(price, period):
            ma = price.rolling(period).mean()
            return price > ma, price < ma

        param_grid = {"period": [10, 20]}

        # Invalid metric should raise ValueError
        with pytest.raises((ValueError, KeyError), match="Unknown metric|invalid_metric"):
            engine.optimize_params(
                sample_price_series,
                signal_func,
                param_grid,
                metric="invalid_metric",
            )


class TestOptunaOptimizer:
    """Test Optuna Bayesian optimizer."""

    @pytest.fixture
    def engine(self):
        """Create VectorBT engine for optimizer."""
        return VectorBTEngine(initial_capital=100_000.0)

    @pytest.fixture
    def sample_price(self):
        """Sample price series."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=100, freq="D")
        return pd.Series(100 + np.cumsum(np.random.randn(100) * 0.5), index=dates)

    def test_optimizer_init(self, engine):
        """Test Optuna optimizer initialization."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(engine, n_trials=10)
        assert optimizer.n_trials == 10
        assert optimizer.study_name == "medusa_optimization"

    def test_optimizer_tpe_sampler(self, engine):
        """Test TPE sampler initialization."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(engine, sampler="tpe")
        from optuna.samplers import TPESampler

        assert isinstance(optimizer.sampler, TPESampler)

    def test_optimizer_cmaes_sampler(self, engine):
        """Test CMA-ES sampler initialization."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(engine, sampler="cmaes")
        from optuna.samplers import CmaEsSampler

        assert isinstance(optimizer.sampler, CmaEsSampler)

    def test_optimizer_invalid_sampler(self, engine):
        """Test invalid sampler raises error."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        with pytest.raises(ValueError, match="Unknown sampler"):
            OptunaOptimizer(engine, sampler="invalid")

    def test_optimize_strategy_basic(self, engine, sample_price):
        """Test basic strategy optimization."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(engine, n_trials=5, study_name="test_study")

        def signal_func(price, fast, slow):
            fast_ma = price.rolling(fast).mean()
            slow_ma = price.rolling(slow).mean()
            return fast_ma > slow_ma, fast_ma < slow_ma

        param_space = {
            "fast": {"type": "int", "low": 5, "high": 20},
            "slow": {"type": "int", "low": 20, "high": 50},
        }

        best_params = optimizer.optimize_strategy(
            sample_price,
            signal_func,
            param_space,
            metric="sharpe_ratio",
            direction="maximize",
        )

        assert "fast" in best_params
        assert "slow" in best_params
        assert 5 <= best_params["fast"] <= 20
        assert 20 <= best_params["slow"] <= 50

    def test_optimize_strategy_returns_best_params(self, engine, sample_price):
        """Test that optimizer returns valid best params."""
        pytest.importorskip("optuna")
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(engine, n_trials=3)

        def signal_func(price, threshold):
            entries = price.pct_change() > threshold
            exits = price.pct_change() < -threshold
            return entries, exits

        param_space = {"threshold": {"type": "float", "low": 0.01, "high": 0.1}}

        best_params = optimizer.optimize_strategy(
            sample_price,
            signal_func,
            param_space,
            metric="total_return",
        )

        # Verify study was created
        assert optimizer.study is not None
        assert optimizer.study.best_params == best_params


class TestNautilusEngine:
    """Test NautilusTrader engine integration."""

    def test_init_without_nautilus(self):
        """Test graceful handling when NautilusTrader not installed."""
        # This should not raise, just log warning
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine()
        # If NAUTILUS_AVAILABLE is False, methods should handle gracefully
        assert engine is not None

    @pytest.mark.skipif(
        not pytest.importorskip("nautilus_trader", reason="NautilusTrader not installed"),
        reason="NautilusTrader required",
    )
    def test_init_with_nautilus(self, tmp_path):
        """Test engine initialization when NautilusTrader is available."""
        from medusa.backtest.nautilus_engine import NautilusEngine

        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(catalog_path=catalog_path, initial_capital=50_000.0)

        assert engine.initial_capital == 50_000.0
        assert engine.catalog_path == catalog_path
        assert catalog_path.exists()

    @pytest.mark.skipif(
        not pytest.importorskip("nautilus_trader", reason="NautilusTrader not installed"),
        reason="NautilusTrader required",
    )
    def test_exchange_config_binance(self):
        """Test Binance exchange configuration."""
        from medusa.backtest.nautilus_engine import EXCHANGE_CONFIGS

        config = EXCHANGE_CONFIGS["BINANCE"]
        assert config.name == "BINANCE"
        assert config.rest_latency_ms == 50
        assert config.ws_latency_ms == 5

    @pytest.mark.skipif(
        not pytest.importorskip("nautilus_trader", reason="NautilusTrader not installed"),
        reason="NautilusTrader required",
    )
    def test_get_catalog(self, tmp_path):
        """Test catalog creation."""
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine(catalog_path=tmp_path / "catalog")
        catalog = engine.get_catalog()

        assert catalog is not None
