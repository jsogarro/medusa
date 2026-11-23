"""Additional feature engineering tests to reach 90% coverage."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

# Test 1-5: Technical indicators edge cases


class TestTechnicalIndicatorsEdgeCases:
    """Test technical indicators edge cases."""

    @pytest.fixture
    def sample_price_data(self):
        """Create sample price data."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=200, freq="D")
        prices = 100 * np.exp(np.random.randn(200).cumsum() * 0.01)
        return pd.Series(prices, index=dates)

    def test_sma_returns_correct_shape(self, sample_price_data):
        """Test SMA returns correct shape."""
        from medusa.features.technical import sma

        sma_20 = sma(sample_price_data, period=20)

        assert len(sma_20) == len(sample_price_data)
        # First 19 values should be NaN
        assert sma_20.isna().sum() == 19

    def test_ema_returns_correct_shape(self, sample_price_data):
        """Test EMA returns correct shape."""
        from medusa.features.technical import ema

        ema_20 = ema(sample_price_data, period=20)

        assert len(ema_20) == len(sample_price_data)

    def test_rsi_bounds(self, sample_price_data):
        """Test RSI is bounded [0, 100]."""
        from medusa.features.technical import rsi

        rsi_14 = rsi(sample_price_data, period=14)

        # RSI should be between 0 and 100
        assert rsi_14.dropna().min() >= 0
        assert rsi_14.dropna().max() <= 100

    def test_macd_components(self, sample_price_data):
        """Test MACD returns all components."""
        from medusa.features.technical import macd

        result = macd(sample_price_data, fast=12, slow=26, signal=9)

        # Returns a DataFrame with macd, signal, histogram columns
        assert "macd" in result.columns
        assert "signal" in result.columns
        assert "histogram" in result.columns
        assert len(result) == len(sample_price_data)

        # Histogram = MACD - Signal
        expected_histogram = result["macd"] - result["signal"]
        assert np.allclose(
            result["histogram"].dropna(),
            expected_histogram.dropna(),
            rtol=0.001,
        )

    def test_bollinger_bands_width(self, sample_price_data):
        """Test Bollinger Bands width calculation."""
        from medusa.features.technical import bollinger_bands, sma

        result = bollinger_bands(sample_price_data, period=20, num_std=2)

        # Returns a DataFrame with bb_upper, middle, bb_lower columns
        upper = result["bb_upper"]
        lower = result["bb_lower"]

        # Upper should be above lower
        assert (upper.dropna() > lower.dropna()).all()

        # Middle should be SMA
        sma_20 = sma(sample_price_data, period=20)
        assert np.allclose(result["bb_middle"].dropna(), sma_20.dropna(), rtol=0.001)


# Test 6-10: Order flow features


class TestOrderFlowFeatures:
    """Test order flow features."""

    @pytest.fixture
    def sample_order_flow_data(self):
        """Create sample order flow data with enough bars for VPIN."""
        np.random.seed(42)
        n = 500  # Need enough data for volume bucketing
        dates = pd.date_range("2024-01-01", periods=n, freq="5min")
        prices = 50000 + np.random.randn(n).cumsum() * 10
        volumes = np.random.uniform(50, 150, n)
        buy_volumes = volumes * np.random.uniform(0.3, 0.7, n)

        return pd.DataFrame(
            {
                "close": prices,
                "volume": volumes,
                "buy_volume": buy_volumes,
            },
            index=dates,
        )

    def test_vpin_bounds(self, sample_order_flow_data):
        """Test VPIN is bounded [0, 1]."""
        from medusa.features.order_flow_features import vpin

        vpin_series = vpin(
            sample_order_flow_data,
            volume_bucket_size=50,
            window=10,  # Smaller window for test data
        )

        non_nan = vpin_series.dropna()
        if len(non_nan) > 0:
            assert non_nan.min() >= 0
            assert non_nan.max() <= 1

    def test_trade_imbalance_bounds(self, sample_order_flow_data):
        """Test trade imbalance is bounded [0, 1]."""
        from medusa.features.order_flow_features import trade_imbalance

        imbalance = trade_imbalance(sample_order_flow_data, window=20)

        non_nan = imbalance.dropna()
        if len(non_nan) > 0:
            # trade_imbalance returns buy_vol / total_vol ratio (0 to 1)
            assert non_nan.min() >= 0
            assert non_nan.max() <= 1

    def test_order_flow_toxicity(self, sample_order_flow_data):
        """Test order flow toxicity calculation."""
        from medusa.features.order_flow_features import order_flow_toxicity

        toxicity = order_flow_toxicity(sample_order_flow_data, window=20)

        non_nan = toxicity.dropna()
        if len(non_nan) > 0:
            # Toxicity should be non-negative
            assert non_nan.min() >= 0

    def test_effective_spread(self):
        """Test effective spread calculation."""
        from medusa.features.microstructure_features import effective_spread

        price = pd.Series([100.05] * 100)
        mid_price = pd.Series([100.0] * 100)

        spread = effective_spread(price, mid_price)

        # Effective spread should be positive
        assert (spread > 0).all()

    def test_realized_spread(self):
        """Test realized spread calculation."""
        from medusa.features.microstructure_features import realized_spread

        price = pd.Series([100.05] * 100)
        mid_price = pd.Series([100.03] * 100)

        spread = realized_spread(price, mid_price, lag=5)

        # Realized spread should be a Series
        assert isinstance(spread, pd.Series)


# Test 11-15: Cross-asset features


class TestCrossAssetFeatures:
    """Test cross-asset feature calculations."""

    @pytest.fixture
    def sample_asset_pair(self):
        """Create sample asset pair data."""
        np.random.seed(42)
        dates = pd.date_range("2024-01-01", periods=300, freq="D")

        # Create correlated assets
        common_factor = np.random.randn(300).cumsum() * 0.3
        asset1 = 100 + common_factor + np.random.randn(300) * 0.2
        asset2 = 200 + 2 * common_factor + np.random.randn(300) * 0.4

        return pd.Series(asset1, index=dates), pd.Series(asset2, index=dates)

    def test_rolling_correlation_bounds(self, sample_asset_pair):
        """Test rolling correlation is bounded [-1, 1]."""
        from medusa.features.cross_asset_features import rolling_correlation

        asset1, asset2 = sample_asset_pair

        corr = rolling_correlation(asset1, asset2, window=60)

        # Correlation should be between -1 and 1
        assert corr.dropna().min() >= -1
        assert corr.dropna().max() <= 1

    def test_spread_calculation(self, sample_asset_pair):
        """Test spread calculation."""
        from medusa.features.cross_asset_features import spread

        asset1, asset2 = sample_asset_pair
        hedge_ratio = 2.0

        spread_series = spread(asset1, asset2, hedge_ratio)

        # Spread should exist for all dates
        assert len(spread_series) == len(asset1)

    def test_z_score_spread_normalization(self, sample_asset_pair):
        """Test z-score normalization of spread."""
        from medusa.features.cross_asset_features import spread, z_score_spread

        asset1, asset2 = sample_asset_pair
        hedge_ratio = 2.0

        spread_series = spread(asset1, asset2, hedge_ratio)
        zscore = z_score_spread(spread_series, window=60)

        # Z-score should have mean ~ 0 and std ~ 1 (after window)
        zscore_recent = zscore.dropna().iloc[-100:]
        assert pytest.approx(zscore_recent.mean(), abs=0.5) == 0.0
        assert pytest.approx(zscore_recent.std(), abs=0.5) == 1.0

    def test_beta_calculation(self, sample_asset_pair):
        """Test beta calculation between two assets."""
        from medusa.features.cross_asset_features import rolling_beta

        asset1, asset2 = sample_asset_pair

        beta = rolling_beta(asset1, asset2, window=60)

        # Beta should exist
        assert len(beta.dropna()) > 0

    def test_cointegration_test(self, sample_asset_pair):
        """Test cointegration test."""
        from medusa.features.cross_asset_features import cointegration_test

        asset1, asset2 = sample_asset_pair

        result = cointegration_test(asset1, asset2, significance=0.05)

        # Result should have required fields
        assert hasattr(result, "is_cointegrated")
        assert hasattr(result, "p_value")
        assert hasattr(result, "hedge_ratio")

        # p_value should be between 0 and 1
        assert 0 <= result.p_value <= 1
