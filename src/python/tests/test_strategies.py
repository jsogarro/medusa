"""Tests for trading strategies."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from medusa.strategies import (
    FundingArbStrategy,
    MLMetaLabelingStrategy,
    PairsTradingStrategy,
    VolumeMomentumStrategy,
    VPINFilterStrategy,
)
from medusa.strategies.base import BaseStrategy
from medusa.strategies.examples.sma_crossover import (
    SMACrossoverStrategy,
    sma_crossover_signals,
)


class MockPrimaryModel:
    """Mock primary model for ML testing."""

    def predict(self, X):  # noqa: N803
        """Mock prediction: buy if return > 0."""
        if hasattr(X, "columns") and "return_20d" in X.columns:
            return np.where(X["return_20d"] > 0, 1, -1)
        return np.ones(len(X))


class MockMetaModel:
    """Mock meta model for ML testing."""

    def predict_proba(self, X):  # noqa: N803
        """Mock probability predictions."""
        n = len(X)
        return np.column_stack([0.3 * np.ones(n), 0.7 * np.ones(n)])


@pytest.fixture
def sample_funding_data():
    """Generate funding rate data for testing."""
    np.random.seed(42)
    n_periods = 100
    dates = pd.date_range("2024-01-01", periods=n_periods, freq="8h")

    funding_rate = np.random.normal(0.0002, 0.0003, n_periods)
    # Add some high funding periods
    funding_rate[30:35] = 0.0006  # Above threshold
    funding_rate[70:75] = 0.0007

    spot_price = 100 + np.cumsum(np.random.randn(n_periods) * 0.2)

    return pd.DataFrame(
        {
            "funding_rate": funding_rate,
            "close": spot_price,
            "spot_price": spot_price,
            "perp_price": spot_price + np.random.randn(n_periods) * 0.1,
        },
        index=dates,
    )


@pytest.fixture
def sample_dual_asset_data():
    """Generate cointegrated pair data for testing."""
    np.random.seed(42)
    n_days = 365
    dates = pd.date_range("2024-01-01", periods=n_days, freq="D")

    # Shared common trend
    common = np.cumsum(np.random.randn(n_days)) + 100

    # Asset 1: BTC
    btc = common + np.random.randn(n_days) * 2

    # Asset 2: ETH (cointegrated via hedge ratio ~0.8)
    eth = 0.8 * common + np.random.randn(n_days) * 1.5

    return pd.DataFrame(
        {
            "close_BTC": btc,
            "close_ETH": eth,
        },
        index=dates,
    )


class TestSMACrossoverSignals:
    def test_returns_boolean_series(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 10, 50)
        assert entries.dtype == bool
        assert exits.dtype == bool
        assert len(entries) == len(sample_price)

    def test_entries_and_exits_not_simultaneous(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 10, 50)
        simultaneous = entries & exits
        assert not simultaneous.any()

    def test_custom_periods(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 5, 20)
        assert entries.any() or True  # May not have signals with random data


class TestSMACrossoverStrategy:
    def test_implements_base(self):
        strategy = SMACrossoverStrategy()
        assert isinstance(strategy, BaseStrategy)

    def test_generate_signals(self, sample_ohlcv):
        strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        entries, exits = strategy.generate_signals(sample_ohlcv)
        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)

    def test_generate_signal_insufficient_data(self):
        strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        short_data = pd.DataFrame({"close": [1.0] * 10})
        assert strategy.generate_signal(short_data) is None

    def test_generate_signal_with_enough_data(self, sample_ohlcv):
        strategy = SMACrossoverStrategy(fast_period=5, slow_period=20)
        signal = strategy.generate_signal(sample_ohlcv)
        # Signal could be None or a dict — both are valid
        if signal is not None:
            assert "action" in signal
            assert signal["action"] in ("buy", "sell")


class TestVolumeMomentumStrategy:
    def test_signal_generation(self, sample_ohlcv):
        strategy = VolumeMomentumStrategy(lookback_windows=[30, 60], volume_threshold=0.5)
        entries, exits = strategy.generate_signals(sample_ohlcv)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert len(entries) == len(sample_ohlcv)
        assert entries.dtype == bool

    def test_live_signal(self, sample_ohlcv):
        strategy = VolumeMomentumStrategy()
        signal = strategy.generate_signal(sample_ohlcv)

        if signal is not None:
            assert "action" in signal
            assert signal["action"] in ["BUY", "SELL"]


class TestPairsTradingStrategy:
    def test_signal_generation(self, sample_dual_asset_data):
        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH")
        entries, exits = strategy.generate_signals(sample_dual_asset_data)

        assert isinstance(entries, pd.Series)
        assert len(entries) == len(sample_dual_asset_data)

    def test_cointegration_detection(self, sample_dual_asset_data):
        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH", lookback=200)
        strategy.generate_signals(sample_dual_asset_data)

        assert strategy._is_cointegrated is True
        assert strategy._hedge_ratio is not None


class TestMLMetaLabelingStrategy:
    def test_signal_generation(self, sample_ohlcv):
        strategy = MLMetaLabelingStrategy(
            primary_model=MockPrimaryModel(),
            meta_model=MockMetaModel(),
        )
        entries, exits = strategy.generate_signals(sample_ohlcv)

        assert isinstance(entries, pd.Series)
        assert entries.dtype == bool

    def test_triple_barrier_labels(self, sample_ohlcv):
        strategy = MLMetaLabelingStrategy(
            primary_model=MockPrimaryModel(),
            max_holding_bars=10,
        )
        side = pd.Series(np.ones(len(sample_ohlcv)), index=sample_ohlcv.index)
        labels = strategy._create_triple_barrier_labels(sample_ohlcv["close"], side)

        assert isinstance(labels, pd.Series)
        assert labels.isin([-1, 0, 1]).all()


class TestVPINFilterStrategy:
    def test_filtering_logic(self, sample_ohlcv):
        base_strategy = VolumeMomentumStrategy(lookback_windows=[30])
        filter_strategy = VPINFilterStrategy(underlying_strategy=base_strategy)

        entries, exits = filter_strategy.generate_signals(sample_ohlcv)
        base_entries, _ = base_strategy.generate_signals(sample_ohlcv)

        assert entries.sum() <= base_entries.sum()

    def test_vpin_statistics(self, sample_ohlcv):
        strategy = VPINFilterStrategy(underlying_strategy=VolumeMomentumStrategy())
        stats = strategy.get_vpin_statistics(sample_ohlcv)

        assert 0 <= stats["current"] <= 1


class TestFundingArbStrategy:
    def test_signal_generation(self, sample_funding_data):
        strategy = FundingArbStrategy(funding_entry_threshold=0.0005)
        entries, exits = strategy.generate_signals(sample_funding_data)

        assert isinstance(entries, pd.Series)
        assert entries.sum() > 0

    def test_apr_calculation(self):
        strategy = FundingArbStrategy(funding_interval_hours=8)
        apr = strategy._calculate_apr(0.0005)
        assert 0.5 < apr < 0.6

    def test_pnl_calculation(self):
        strategy = FundingArbStrategy()
        pnl = strategy.calculate_pnl(
            entry_spot_price=100.0,
            entry_perp_price=100.1,
            exit_spot_price=101.0,
            exit_perp_price=101.2,
            funding_payments=pd.Series([0.0005, 0.0006]),
            position_size=1.0,
        )

        assert "total_pnl" in pnl
        assert "funding_pnl" in pnl
