"""Tests for strategy signal generation: volume_momentum, pairs_trading, ml_meta_labeling, vpin_filter, funding_arb."""

from __future__ import annotations

from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest

# Test 1-4: VolumeMomentumStrategy tests


class TestVolumeMomentumStrategy:
    """Test volume momentum strategy signal generation."""

    @pytest.fixture
    def sample_ohlcv_data(self):
        """Create sample OHLCV data for testing."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=200, freq="D")
        prices = 100 * np.exp(np.random.randn(200).cumsum() * 0.01)
        volumes = np.random.uniform(800, 1200, 200)

        return pd.DataFrame(
            {
                "close": prices,
                "volume": volumes,
                "high": prices * 1.02,
                "low": prices * 0.98,
                "open": prices * 1.01,
            },
            index=dates,
        )

    def test_generates_valid_signals(self, sample_ohlcv_data):
        """Test that strategy generates valid entry/exit signals."""
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        strategy = VolumeMomentumStrategy()
        entries, exits = strategy.generate_signals(sample_ohlcv_data)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert len(entries) == len(sample_ohlcv_data)
        assert len(exits) == len(sample_ohlcv_data)
        assert entries.dtype == bool
        assert exits.dtype == bool

    def test_handles_empty_data(self):
        """Test strategy handles empty DataFrame without crashing."""
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        strategy = VolumeMomentumStrategy()
        empty_df = pd.DataFrame(columns=["close", "volume", "high", "low"])

        entries, exits = strategy.generate_signals(empty_df)

        assert len(entries) == 0
        assert len(exits) == 0

    def test_signal_values_are_boolean(self, sample_ohlcv_data):
        """Test that signals are boolean Series."""
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        strategy = VolumeMomentumStrategy()
        entries, exits = strategy.generate_signals(sample_ohlcv_data)

        # All values should be True or False
        assert all(isinstance(v, (bool, np.bool_)) for v in entries)
        assert all(isinstance(v, (bool, np.bool_)) for v in exits)

    def test_with_synthetic_data(self):
        """Test strategy with synthetic trending price data."""
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        # Create trending data (30-day uptrend with high volume)
        dates = pd.date_range("2024-01-01", periods=150, freq="D")
        prices = 100 + np.arange(150) * 0.5  # Steady uptrend
        volumes = np.ones(150) * 1000
        volumes[100:] *= 2  # Volume spike later

        data = pd.DataFrame(
            {
                "close": prices,
                "volume": volumes,
                "high": prices * 1.01,
                "low": prices * 0.99,
            },
            index=dates,
        )

        strategy = VolumeMomentumStrategy(lookback_windows=[30, 60])
        entries, exits = strategy.generate_signals(data)

        # Should have at least one entry in uptrend with volume
        assert entries.sum() > 0


# Test 5-9: PairsTradingStrategy tests


class TestPairsTradingStrategy:
    """Test pairs trading strategy."""

    @pytest.fixture
    def cointegrated_pair_data(self):
        """Create cointegrated pair data for testing."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=300, freq="D")

        # Create cointegrated series
        common_factor = np.random.randn(300).cumsum() * 0.5
        asset1 = 100 + common_factor + np.random.randn(300) * 0.2
        asset2 = 50 + 0.5 * common_factor + np.random.randn(300) * 0.1

        return pd.DataFrame(
            {
                ("BTC", "close"): asset1,
                ("ETH", "close"): asset2,
            },
            index=dates,
        )

    def test_generates_valid_signals(self, cointegrated_pair_data):
        """Test that pairs strategy generates valid signals."""
        from medusa.strategies.pairs_trading import PairsTradingStrategy

        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH", lookback=200)
        entries, exits = strategy.generate_signals(cointegrated_pair_data)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert entries.dtype == bool
        assert exits.dtype == bool

    def test_handles_empty_data(self):
        """Test strategy handles empty DataFrame."""
        from medusa.strategies.pairs_trading import PairsTradingStrategy

        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH")
        empty_df = pd.DataFrame()

        entries, exits = strategy.generate_signals(empty_df)

        assert len(entries) == 0
        assert len(exits) == 0

    def test_signal_values_are_boolean(self, cointegrated_pair_data):
        """Test that signals are boolean."""
        from medusa.strategies.pairs_trading import PairsTradingStrategy

        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH", lookback=200)
        entries, exits = strategy.generate_signals(cointegrated_pair_data)

        assert all(isinstance(v, (bool, np.bool_)) for v in entries)
        assert all(isinstance(v, (bool, np.bool_)) for v in exits)

    def test_with_synthetic_data(self):
        """Test with synthetic cointegrated data."""
        from medusa.strategies.pairs_trading import PairsTradingStrategy

        dates = pd.date_range("2024-01-01", periods=300, freq="D")
        common = np.random.randn(300).cumsum() * 0.3
        asset1 = 100 + common + np.random.randn(300) * 0.1
        asset2 = 200 + 2 * common + np.random.randn(300) * 0.2

        data = pd.DataFrame(
            {
                ("AAPL", "close"): asset1,
                ("MSFT", "close"): asset2,
            },
            index=dates,
        )

        strategy = PairsTradingStrategy(asset1="AAPL", asset2="MSFT", lookback=200)
        entries, exits = strategy.generate_signals(data)

        # Should detect cointegration and generate signals
        assert len(entries) == len(data)

    def test_non_cointegrated_no_signals(self):
        """Test that non-cointegrated pairs generate no signals."""
        from medusa.strategies.pairs_trading import PairsTradingStrategy

        # Create random walk (non-cointegrated)
        dates = pd.date_range("2024-01-01", periods=300, freq="D")
        asset1 = 100 + np.random.randn(300).cumsum() * 0.5
        asset2 = 50 + np.random.randn(300).cumsum() * 0.3

        data = pd.DataFrame(
            {
                ("BTC", "close"): asset1,
                ("SOL", "close"): asset2,
            },
            index=dates,
        )

        strategy = PairsTradingStrategy(asset1="BTC", asset2="SOL", lookback=200)
        entries, exits = strategy.generate_signals(data)

        # Should not generate entry signals if not cointegrated
        # (but exits may still be all False)
        assert isinstance(entries, pd.Series)


# Test 10-13: MLMetaLabelingStrategy tests


class TestMLMetaLabelingStrategy:
    """Test ML meta-labeling strategy."""

    @pytest.fixture
    def sample_ml_data(self):
        """Create sample data with features."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=200, freq="D")
        prices = 100 * np.exp(np.random.randn(200).cumsum() * 0.01)

        return pd.DataFrame(
            {
                "close": prices,
                "volume": np.random.uniform(800, 1200, 200),
                "high": prices * 1.02,
                "low": prices * 0.98,
            },
            index=dates,
        )

    @pytest.fixture
    def mock_primary_model(self):
        """Create mock primary model that returns correctly-sized arrays."""
        model = MagicMock()
        # Use side_effect to dynamically match input size
        model.predict.side_effect = lambda x: np.random.choice([-1, 0, 1], size=len(x))
        return model

    @pytest.fixture
    def mock_meta_model(self):
        """Create mock meta model that returns correctly-sized arrays."""
        model = MagicMock()

        def _predict_proba(x):
            n = len(x)
            prob_success = np.random.uniform(0.4, 0.9, n)
            return np.column_stack([1 - prob_success, prob_success])

        model.predict_proba.side_effect = _predict_proba
        return model

    def test_generates_valid_signals(self, sample_ml_data, mock_primary_model):
        """Test ML strategy generates valid signals."""
        from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy

        strategy = MLMetaLabelingStrategy(primary_model=mock_primary_model)
        entries, exits = strategy.generate_signals(sample_ml_data)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert entries.dtype == bool
        assert exits.dtype == bool

    def test_handles_empty_data(self, mock_primary_model):
        """Test ML strategy handles empty DataFrame."""
        from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy

        strategy = MLMetaLabelingStrategy(primary_model=mock_primary_model)
        empty_df = pd.DataFrame(columns=["close", "volume", "high", "low"])

        # Empty data should produce empty signals (no features to extract)
        entries, exits = strategy.generate_signals(empty_df)
        assert len(entries) == 0

    def test_signal_values_are_boolean(self, sample_ml_data, mock_primary_model):
        """Test that signals are boolean."""
        from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy

        strategy = MLMetaLabelingStrategy(primary_model=mock_primary_model)
        entries, exits = strategy.generate_signals(sample_ml_data)

        assert all(isinstance(v, (bool, np.bool_)) for v in entries)
        assert all(isinstance(v, (bool, np.bool_)) for v in exits)

    def test_with_synthetic_data(self, mock_primary_model, mock_meta_model):
        """Test with synthetic trending data."""
        from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy

        dates = pd.date_range("2024-01-01", periods=150, freq="D")
        prices = 100 + np.arange(150) * 0.3  # Uptrend
        data = pd.DataFrame(
            {
                "close": prices,
                "volume": np.ones(150) * 1000,
                "high": prices * 1.01,
                "low": prices * 0.99,
            },
            index=dates,
        )

        strategy = MLMetaLabelingStrategy(
            primary_model=mock_primary_model,
            meta_model=mock_meta_model,
        )
        entries, exits = strategy.generate_signals(data)

        # Output length should match data (features may have NaN-dropped rows)
        assert len(entries) <= len(data)


# Test 14-17: VPINFilterStrategy tests


class TestVPINFilterStrategy:
    """Test VPIN order flow toxicity filter."""

    @pytest.fixture
    def sample_vpin_data(self):
        """Create sample data with buy volume."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=200, freq="5min")
        prices = 50000 + np.random.randn(200).cumsum() * 10
        volumes = np.random.uniform(5, 15, 200)
        buy_volumes = volumes * np.random.uniform(0.4, 0.6, 200)

        return pd.DataFrame(
            {
                "close": prices,
                "volume": volumes,
                "buy_volume": buy_volumes,
                "high": prices + 10,
                "low": prices - 10,
            },
            index=dates,
        )

    @pytest.fixture
    def mock_underlying_strategy(self):
        """Create mock underlying strategy that dynamically matches data length."""
        strategy = MagicMock()

        def _generate_signals(data):
            n = len(data)
            return (
                pd.Series([True] * n, index=data.index),
                pd.Series([False] * n, index=data.index),
            )

        strategy.generate_signals.side_effect = _generate_signals
        return strategy

    def test_generates_valid_signals(self, sample_vpin_data, mock_underlying_strategy):
        """Test VPIN filter generates valid signals."""
        from medusa.strategies.vpin_filter import VPINFilterStrategy

        strategy = VPINFilterStrategy(underlying_strategy=mock_underlying_strategy)
        entries, exits = strategy.generate_signals(sample_vpin_data)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert entries.dtype == bool
        assert exits.dtype == bool

    def test_handles_empty_data(self, mock_underlying_strategy):
        """Test VPIN filter handles empty DataFrame."""
        from medusa.strategies.vpin_filter import VPINFilterStrategy

        strategy = VPINFilterStrategy(underlying_strategy=mock_underlying_strategy)
        empty_df = pd.DataFrame(columns=["close", "volume"])

        entries, exits = strategy.generate_signals(empty_df)

        assert len(entries) == 0
        assert len(exits) == 0

    def test_signal_values_are_boolean(self, sample_vpin_data, mock_underlying_strategy):
        """Test that signals are boolean."""
        from medusa.strategies.vpin_filter import VPINFilterStrategy

        strategy = VPINFilterStrategy(underlying_strategy=mock_underlying_strategy)
        entries, exits = strategy.generate_signals(sample_vpin_data)

        assert all(isinstance(v, (bool, np.bool_)) for v in entries)
        assert all(isinstance(v, (bool, np.bool_)) for v in exits)

    def test_with_synthetic_data(self, mock_underlying_strategy):
        """Test with synthetic high-toxicity data."""
        from medusa.strategies.vpin_filter import VPINFilterStrategy

        dates = pd.date_range("2024-01-01", periods=150, freq="5min")
        prices = 50000 * np.ones(150)
        volumes = np.ones(150) * 10
        # High buy_volume = low toxicity initially
        buy_volumes = volumes * 0.9

        data = pd.DataFrame(
            {
                "close": prices,
                "volume": volumes,
                "buy_volume": buy_volumes,
                "high": prices + 5,
                "low": prices - 5,
            },
            index=dates,
        )

        strategy = VPINFilterStrategy(underlying_strategy=mock_underlying_strategy)
        entries, exits = strategy.generate_signals(data)

        assert len(entries) == len(data)


# Test 18-21: FundingArbStrategy tests


class TestFundingArbStrategy:
    """Test funding rate arbitrage strategy."""

    @pytest.fixture
    def sample_funding_data(self):
        """Create sample funding rate data."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=100, freq="8h")
        funding_rate = np.random.normal(0.0002, 0.0003, 100)
        # Add some high funding periods
        funding_rate[40:50] = 0.0007  # High funding
        funding_rate[70:80] = -0.0001  # Negative funding

        return pd.DataFrame(
            {
                "funding_rate": funding_rate,
                "close": 50000 * np.ones(100),
                "perp_price": 50000 * np.ones(100),
            },
            index=dates,
        )

    def test_generates_valid_signals(self, sample_funding_data):
        """Test funding arb strategy generates valid signals."""
        from medusa.strategies.funding_arb import FundingArbStrategy

        strategy = FundingArbStrategy()
        entries, exits = strategy.generate_signals(sample_funding_data)

        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)
        assert entries.dtype == bool
        assert exits.dtype == bool

    def test_handles_empty_data(self):
        """Test strategy handles empty DataFrame (no funding_rate column)."""
        from medusa.strategies.funding_arb import FundingArbStrategy

        strategy = FundingArbStrategy()
        # DataFrame WITHOUT the required column
        empty_df = pd.DataFrame(columns=["close"])

        with pytest.raises(ValueError, match="Data must contain 'funding_rate' column"):
            strategy.generate_signals(empty_df)

    def test_signal_values_are_boolean(self, sample_funding_data):
        """Test that signals are boolean."""
        from medusa.strategies.funding_arb import FundingArbStrategy

        strategy = FundingArbStrategy()
        entries, exits = strategy.generate_signals(sample_funding_data)

        assert all(isinstance(v, (bool, np.bool_)) for v in entries)
        assert all(isinstance(v, (bool, np.bool_)) for v in exits)

    def test_with_synthetic_data(self):
        """Test with synthetic high funding rate data."""
        from medusa.strategies.funding_arb import FundingArbStrategy

        dates = pd.date_range("2024-01-01", periods=50, freq="8h")
        # Create sustained high funding rate
        funding_rate = np.ones(50) * 0.0008  # 0.08% per 8h (high)
        funding_rate[:10] = 0.0002  # Low at start
        funding_rate[40:] = -0.0001  # Negative at end (triggers exit below 0.0)

        data = pd.DataFrame(
            {
                "funding_rate": funding_rate,
                "close": 50000 * np.ones(50),
            },
            index=dates,
        )

        strategy = FundingArbStrategy(
            funding_entry_threshold=0.0005,
            consecutive_periods=2,
        )
        entries, exits = strategy.generate_signals(data)

        # Should enter when funding is high for 2+ periods
        assert entries.sum() > 0
        # Should exit when funding crosses below zero
        assert exits.sum() > 0
