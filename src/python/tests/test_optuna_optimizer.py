"""Tests for Optuna optimizer."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
import pytest

try:
    import optuna

    from medusa.backtest.optimizer import OptunaOptimizer
    from medusa.backtest.vectorbt_engine import VectorBTEngine

    HAS_OPTUNA = True
except ImportError:
    HAS_OPTUNA = False


@pytest.fixture
def sample_price_series() -> pd.Series:
    """Generate sample price series."""
    np.random.seed(42)
    n = 200
    dates = pd.date_range("2023-01-01", periods=n, freq="1h")

    # Trending price with noise
    t = np.arange(n)
    trend = 0.1 * t
    noise = np.random.normal(0, 2, n)
    price = 100 + trend + noise

    return pd.Series(price, index=dates)


@pytest.fixture
def mock_signal_func() -> Any:
    """Create a mock signal function for testing."""

    def signal_func(
        price: pd.Series, fast_period: int = 10, slow_period: int = 20
    ) -> tuple[pd.Series, pd.Series]:
        """Simple SMA crossover signal function."""
        fast_sma = price.rolling(fast_period).mean()
        slow_sma = price.rolling(slow_period).mean()

        # Entry: fast crosses above slow
        entries = (fast_sma > slow_sma) & (fast_sma.shift(1) <= slow_sma.shift(1))
        # Exit: fast crosses below slow
        exits = (fast_sma < slow_sma) & (fast_sma.shift(1) >= slow_sma.shift(1))

        return entries.fillna(False), exits.fillna(False)

    return signal_func


@pytest.mark.skipif(not HAS_OPTUNA, reason="Optuna not installed")
class TestOptunaOptimizer:
    """Test suite for OptunaOptimizer."""

    def test_init(self) -> None:
        """Test optimizer initialization."""
        engine = VectorBTEngine()
        optimizer = OptunaOptimizer(
            engine=engine,
            n_trials=5,
            study_name="test_study",
            sampler="tpe",
            pruner="median",
        )

        assert optimizer.n_trials == 5
        assert optimizer.study_name == "test_study"
        assert isinstance(optimizer.sampler, optuna.samplers.TPESampler)
        assert isinstance(optimizer.pruner, optuna.pruners.MedianPruner)

    def test_init_cmaes_sampler(self) -> None:
        """Test initialization with CMA-ES sampler."""
        engine = VectorBTEngine()
        optimizer = OptunaOptimizer(engine=engine, n_trials=5, sampler="cmaes")

        assert isinstance(optimizer.sampler, optuna.samplers.CmaEsSampler)

    def test_init_invalid_sampler(self) -> None:
        """Test that invalid sampler raises error."""
        engine = VectorBTEngine()

        with pytest.raises(ValueError, match="Unknown sampler"):
            OptunaOptimizer(engine=engine, sampler="invalid")

    def test_init_invalid_pruner(self) -> None:
        """Test that invalid pruner raises error."""
        engine = VectorBTEngine()

        with pytest.raises(ValueError, match="Unknown pruner"):
            OptunaOptimizer(engine=engine, pruner="invalid")

    def test_optimize_strategy(self, sample_price_series: pd.Series, mock_signal_func: Any) -> None:
        """Test strategy parameter optimization."""
        import uuid

        engine = VectorBTEngine()
        # Use unique study name for test isolation
        unique_name = f"test_strategy_{uuid.uuid4().hex[:8]}"
        optimizer = OptunaOptimizer(
            engine=engine,
            n_trials=5,  # Small number for fast test
            study_name=unique_name,
        )

        param_space = {
            "fast_period": {"type": "int", "low": 5, "high": 20},
            "slow_period": {"type": "int", "low": 15, "high": 40},
        }

        best_params = optimizer.optimize_strategy(
            price=sample_price_series,
            signal_func=mock_signal_func,
            param_space=param_space,
            metric="sharpe_ratio",
            direction="maximize",
        )

        # Verify results
        assert isinstance(best_params, dict)
        assert "fast_period" in best_params
        assert "slow_period" in best_params
        assert 5 <= best_params["fast_period"] <= 20
        assert 15 <= best_params["slow_period"] <= 40
        assert optimizer.study is not None
        assert len(optimizer.study.trials) == 5

    def test_optimize_with_different_metrics(
        self, sample_price_series: pd.Series, mock_signal_func: Any
    ) -> None:
        """Test optimization with different metrics."""
        engine = VectorBTEngine()
        optimizer = OptunaOptimizer(engine=engine, n_trials=3)

        param_space = {
            "fast_period": {"type": "int", "low": 5, "high": 15},
            "slow_period": {"type": "int", "low": 10, "high": 30},
        }

        for metric in ["total_return", "sortino_ratio", "calmar_ratio"]:
            best_params = optimizer.optimize_strategy(
                price=sample_price_series,
                signal_func=mock_signal_func,
                param_space=param_space,
                metric=metric,
                direction="maximize",
            )

            assert isinstance(best_params, dict)
            assert optimizer.study is not None

    def test_get_trials_dataframe(
        self, sample_price_series: pd.Series, mock_signal_func: Any
    ) -> None:
        """Test retrieving trials as DataFrame."""
        import uuid

        engine = VectorBTEngine()
        # Use unique study name to avoid persistence issues
        unique_name = f"test_trials_{uuid.uuid4().hex[:8]}"
        optimizer = OptunaOptimizer(engine=engine, n_trials=5, study_name=unique_name)

        param_space = {
            "fast_period": {"type": "int", "low": 5, "high": 15},
            "slow_period": {"type": "int", "low": 10, "high": 30},
        }

        optimizer.optimize_strategy(
            price=sample_price_series,
            signal_func=mock_signal_func,
            param_space=param_space,
        )

        trials_df = optimizer.get_trials_dataframe()

        assert isinstance(trials_df, pd.DataFrame)
        assert len(trials_df) >= 5  # At least 5 trials
        assert "number" in trials_df.columns
        assert "value" in trials_df.columns
        assert "state" in trials_df.columns

    def test_no_study_error(self) -> None:
        """Test that methods raise error when no study exists."""
        engine = VectorBTEngine()
        optimizer = OptunaOptimizer(engine=engine, n_trials=5)

        with pytest.raises(ValueError, match="No study available"):
            optimizer.plot_optimization_history()

        with pytest.raises(ValueError, match="No study available"):
            optimizer.plot_param_importances()

        with pytest.raises(ValueError, match="No study available"):
            optimizer.get_trials_dataframe()


def test_optimizer_import_error() -> None:
    """Test that ImportError is raised when Optuna not installed."""
    if HAS_OPTUNA:
        pytest.skip("Optuna is installed")

    # This would fail at import, so we can't test it directly
    # Just verify the constant is set correctly
    assert not HAS_OPTUNA
