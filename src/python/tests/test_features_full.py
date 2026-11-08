"""Comprehensive tests for feature engineering modules."""

import numpy as np
import pandas as pd
import pytest

from medusa.features.cross_asset_features import cointegration_test, spread, z_score_spread
from medusa.features.microstructure_features import effective_spread, realized_spread
from medusa.features.order_flow_features import trade_imbalance, vpin
from medusa.features.technical import (
    atr,
    bollinger_bands,
    macd,
    rsi,
)


@pytest.fixture
def sample_prices():
    """Generate sample price series."""
    np.random.seed(42)
    dates = pd.date_range("2024-01-01", periods=100, freq="D")
    return pd.Series(100 + np.cumsum(np.random.randn(100) * 2), index=dates)


@pytest.fixture
def sample_ohlcv():
    """Generate sample OHLCV data."""
    np.random.seed(42)
    dates = pd.date_range("2024-01-01", periods=100, freq="D")

    close = 100 + np.cumsum(np.random.randn(100) * 2)
    high = close + np.abs(np.random.randn(100) * 1.5)
    low = close - np.abs(np.random.randn(100) * 1.5)
    open_price = close + np.random.randn(100) * 0.5
    volume = np.random.uniform(1_000_000, 10_000_000, 100)

    return pd.DataFrame(
        {"open": open_price, "high": high, "low": low, "close": close, "volume": volume},
        index=dates,
    )


class TestTechnicalIndicators:
    """Test technical indicator calculations."""

    def test_rsi_output_range(self, sample_prices):
        """Test that RSI output is in [0, 100] range."""
        rsi_values = rsi(sample_prices, period=14)  # Correct param name: period

        # After warmup, all valid RSI values should be in [0, 100]
        valid_rsi = rsi_values.dropna()
        assert (valid_rsi >= 0).all()
        assert (valid_rsi <= 100).all()

    def test_rsi_known_value(self):
        """Test RSI calculation with known values."""
        # Create price series with known RSI
        # Constant price → RSI = undefined (no gains or losses)
        prices = pd.Series([100.0] * 30)
        rsi_values = rsi(prices, period=14)

        # Constant price produces NaN (no change → no RSI)
        assert rsi_values.dropna().empty or rsi_values.isna().all()

    def test_rsi_window_parameter(self, sample_prices):
        """Test RSI with different period sizes."""
        rsi_14 = rsi(sample_prices, period=14)  # Correct param name: period
        rsi_28 = rsi(sample_prices, period=28)

        # Both should have same length as input
        assert len(rsi_14) == len(sample_prices)
        assert len(rsi_28) == len(sample_prices)
        # Longer period → more warmup NaNs
        assert rsi_28.isna().sum() > rsi_14.isna().sum()

    def test_macd_output_format(self, sample_prices):
        """Test MACD returns three series."""
        result = macd(sample_prices, fast=12, slow=26, signal=9)

        assert "macd" in result.columns
        assert "signal" in result.columns
        assert "histogram" in result.columns
        assert len(result) == len(sample_prices)

    def test_macd_histogram_is_difference(self, sample_prices):
        """Test that MACD histogram = MACD - Signal."""
        result = macd(sample_prices, fast=12, slow=26, signal=9)

        # After warmup period, histogram should equal macd - signal
        valid_idx = ~result["macd"].isna() & ~result["signal"].isna()
        if valid_idx.any():
            diff = result.loc[valid_idx, "macd"] - result.loc[valid_idx, "signal"]
            hist = result.loc[valid_idx, "histogram"]
            np.testing.assert_array_almost_equal(diff.values, hist.values, decimal=6)

    def test_bollinger_bands_output_format(self, sample_prices):
        """Test Bollinger Bands returns three series."""
        result = bollinger_bands(sample_prices, period=20, num_std=2)  # Correct: period

        assert "bb_upper" in result.columns
        assert "bb_middle" in result.columns
        assert "bb_lower" in result.columns
        assert len(result) == len(sample_prices)

    def test_bollinger_bands_ordering(self, sample_prices):
        """Test that upper > middle > lower."""
        result = bollinger_bands(sample_prices, period=20, num_std=2)  # Correct: period

        # After warmup, upper should be >= middle >= lower
        valid_idx = ~result["bb_upper"].isna()
        assert valid_idx.any(), "No valid Bollinger values after warmup"
        assert (result.loc[valid_idx, "bb_upper"] >= result.loc[valid_idx, "bb_middle"]).all()
        assert (result.loc[valid_idx, "bb_middle"] >= result.loc[valid_idx, "bb_lower"]).all()

    def test_atr_positive_values(self, sample_ohlcv):
        """Test that ATR values are positive."""
        atr_values = atr(sample_ohlcv, period=14)  # Correct: period

        # ATR should always be positive or NaN (during warmup)
        valid_values = atr_values.dropna()
        assert valid_values.empty or (valid_values > 0).all()

    def test_atr_window_parameter(self, sample_ohlcv):
        """Test ATR with different period sizes."""
        atr_14 = atr(sample_ohlcv, period=14)  # Correct: period
        atr_28 = atr(sample_ohlcv, period=28)

        assert len(atr_14) == len(sample_ohlcv)
        assert len(atr_28) == len(sample_ohlcv)
        # Longer period → more warmup NaNs
        assert atr_28.isna().sum() >= atr_14.isna().sum()


class TestCrossAssetFeatures:
    """Test cross-asset features (cointegration, spreads)."""

    @pytest.fixture
    def cointegrated_pair(self):
        """Generate cointegrated asset pair."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=100, freq="D")

        # Generate cointegrated series
        base = 100 + np.cumsum(np.random.randn(100) * 1.0)
        asset1 = base + np.random.randn(100) * 0.5
        asset2 = base * 1.5 + np.random.randn(100) * 0.7

        return pd.Series(asset1, index=dates), pd.Series(asset2, index=dates)

    def test_cointegration_test_output(self, cointegrated_pair):
        """Test cointegration test returns valid result."""
        asset1, asset2 = cointegrated_pair
        result = cointegration_test(asset1, asset2)

        # Check result attributes exist
        assert hasattr(result, "is_cointegrated")
        assert hasattr(result, "p_value")
        assert hasattr(result, "hedge_ratio")
        # P-value must be in [0, 1]
        assert 0 <= result.p_value <= 1
        # Hedge ratio must be finite
        assert np.isfinite(result.hedge_ratio)

    def test_spread_calculation(self, cointegrated_pair):
        """Test spread calculation."""
        asset1, asset2 = cointegrated_pair
        spread_series = spread(asset1, asset2, hedge_ratio=1.5)

        assert len(spread_series) == len(asset1)
        assert spread_series.isna().sum() == 0

    def test_spread_hedge_ratio_validation(self, cointegrated_pair):
        """Test that invalid hedge ratio raises error."""
        asset1, asset2 = cointegrated_pair

        # NaN hedge ratio should raise
        with pytest.raises(ValueError, match="hedge_ratio"):
            spread(asset1, asset2, hedge_ratio=np.nan)

        # Inf hedge ratio should raise
        with pytest.raises(ValueError, match="hedge_ratio"):
            spread(asset1, asset2, hedge_ratio=np.inf)

    def test_z_score_spread_output_range(self, cointegrated_pair):
        """Test z-score spread is normalized."""
        asset1, asset2 = cointegrated_pair
        # First compute the spread, then z-score it
        spread_series = spread(asset1, asset2, hedge_ratio=1.5)
        z_scores = z_score_spread(spread_series, window=60)

        # After warmup, z-scores should mostly be in [-3, 3] range
        valid_z = z_scores.dropna()
        assert len(valid_z) > 0, "No valid z-scores after warmup"
        # Most values should be within ±5 standard deviations (99.99%)
        assert (valid_z.abs() < 5).sum() / len(valid_z) > 0.95

    def test_z_score_spread_window_parameter(self, cointegrated_pair):
        """Test z-score spread with different window sizes."""
        asset1, asset2 = cointegrated_pair

        # Compute spread first
        spread_series = spread(asset1, asset2, hedge_ratio=1.5)
        z_30 = z_score_spread(spread_series, window=30)
        z_60 = z_score_spread(spread_series, window=60)

        assert len(z_30) == len(asset1)
        assert len(z_60) == len(asset1)
        # Longer window → more warmup NaNs
        assert z_60.isna().sum() >= z_30.isna().sum()


class TestOrderFlowFeatures:
    """Test order flow features (VPIN, imbalance)."""

    @pytest.fixture
    def sample_trade_data(self):
        """Generate sample trade data."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=1000, freq="min")  # Minute bars

        return pd.DataFrame(
            {
                "price": 100 + np.cumsum(np.random.randn(1000) * 0.1),
                "volume": np.random.uniform(100, 10000, 1000),
                "buy_volume": np.random.uniform(50, 5000, 1000),
                "sell_volume": np.random.uniform(50, 5000, 1000),
            },
            index=dates,
        )

    def test_vpin_output_range(self, sample_trade_data):
        """Test that VPIN output is in [0, 1] range."""
        vpin_values = vpin(
            sample_trade_data,
            volume_bucket_size=50,
            window=50,
        )

        # VPIN should be between 0 and 1
        valid_vpin = vpin_values.dropna()
        assert not valid_vpin.empty
        assert (valid_vpin >= 0).all()
        assert (valid_vpin <= 1).all()

    def test_vpin_volume_bucket_size(self, sample_trade_data):
        """Test VPIN with different bucket sizes."""
        vpin_25 = vpin(sample_trade_data, volume_bucket_size=25, window=50)
        vpin_50 = vpin(sample_trade_data, volume_bucket_size=50, window=50)

        assert len(vpin_25) == len(sample_trade_data)
        assert len(vpin_50) == len(sample_trade_data)

    def test_trade_imbalance_calculation(self, sample_trade_data):
        """Test trade imbalance calculation."""
        # trade_imbalance takes DataFrame, returns buy_volume / total_volume
        imbalance = trade_imbalance(sample_trade_data, window=20)

        # Imbalance = buy_volume / total_volume, should be in [0, 1]
        valid_imb = imbalance.dropna()
        if not valid_imb.empty:
            assert (valid_imb >= 0).all()
            assert (valid_imb <= 1).all()

    def test_trade_imbalance_extremes(self):
        """Test trade imbalance at extremes."""
        # Test requires buy_volume column - create synthetic data
        dates = pd.date_range("2024-01-01", periods=50, freq="min")

        # All buy orders → imbalance = 1 (buy_volume = volume)
        df_all_buy = pd.DataFrame(
            {
                "close": 100.0,
                "volume": [100, 200, 300] + [100] * 47,
                "buy_volume": [100, 200, 300] + [100] * 47,  # All buy
            },
            index=dates,
        )
        imb_all_buy = trade_imbalance(df_all_buy, window=20)
        # After warmup, imbalance should be 1.0
        valid_buy = imb_all_buy.dropna()
        assert not valid_buy.empty
        np.testing.assert_array_almost_equal(valid_buy.values, 1.0, decimal=6)

        # All sell orders → imbalance = 0 (buy_volume = 0)
        df_all_sell = pd.DataFrame(
            {
                "close": 100.0,
                "volume": [100, 200, 300] + [100] * 47,
                "buy_volume": 0,  # All sell
            },
            index=dates,
        )
        imb_all_sell = trade_imbalance(df_all_sell, window=20)
        valid_sell = imb_all_sell.dropna()
        assert not valid_sell.empty
        np.testing.assert_array_almost_equal(valid_sell.values, 0.0, decimal=6)

    def test_trade_imbalance_balanced(self):
        """Test trade imbalance when buy = 50% of total."""
        # 50/50 buy/sell → imbalance = 0.5
        dates = pd.date_range("2024-01-01", periods=50, freq="min")
        df_balanced = pd.DataFrame(
            {
                "close": 100.0,
                "volume": [200, 400, 600] + [200] * 47,
                "buy_volume": [100, 200, 300] + [100] * 47,  # 50% buy
            },
            index=dates,
        )
        imb_balanced = trade_imbalance(df_balanced, window=20)
        valid_bal = imb_balanced.dropna()
        assert not valid_bal.empty
        np.testing.assert_array_almost_equal(valid_bal.values, 0.5, decimal=6)


class TestMicrostructureFeatures:
    """Test market microstructure features."""

    @pytest.fixture
    def sample_trades(self):
        """Generate sample trade data with bid/ask."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=100, freq="min")

        mid_price = 100.0
        spread = 0.1

        return pd.DataFrame(
            {
                "price": mid_price + np.random.randn(100) * 0.05,
                "bid": mid_price - spread / 2,
                "ask": mid_price + spread / 2,
                "volume": np.random.uniform(100, 1000, 100),
            },
            index=dates,
        )

    def test_effective_spread_positive(self, sample_trades):
        """Test that effective spread is positive."""
        eff_spread = effective_spread(
            price=sample_trades["price"],
            mid_price=(sample_trades["bid"] + sample_trades["ask"]) / 2,
        )

        # Effective spread should be positive
        assert (eff_spread >= 0).all()

    def test_realized_spread_calculation(self, sample_trades):
        """Test realized spread calculation."""
        mid_price = (sample_trades["bid"] + sample_trades["ask"]) / 2

        real_spread = realized_spread(
            price=sample_trades["price"],
            mid_price=mid_price,
            lag=5,
        )

        # Realized spread can be positive or negative
        assert len(real_spread) == len(sample_trades)
