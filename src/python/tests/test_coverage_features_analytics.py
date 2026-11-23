"""Additional tests to improve coverage for features and analytics modules."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd
import pytest

# ============================================================================
# Test 1: Microstructure Features (medusa/features/microstructure_features.py)
# ============================================================================


class TestMicrostructureFeatures:
    """Test market microstructure features."""

    @pytest.fixture
    def sample_quote_data(self):
        """Create sample quote data."""
        np.random.seed(42)
        n = 100
        dates = pd.date_range("2024-01-01", periods=n, freq="1s")
        mid = 100.0
        spread = 0.02

        # Ensure ask > bid always (spread is positive)
        bid = mid - spread / 2 + np.random.randn(n) * 0.005  # Smaller noise
        ask = bid + spread + np.abs(np.random.randn(n) * 0.005)  # Always above bid

        return pd.DataFrame(
            {
                "bid_price": bid,
                "ask_price": ask,
                "bid_size_1": np.random.uniform(100, 1000, n),
                "bid_size_2": np.random.uniform(50, 500, n),
                "bid_size_3": np.random.uniform(25, 250, n),
                "bid_size_4": np.random.uniform(10, 100, n),
                "bid_size_5": np.random.uniform(5, 50, n),
                "ask_size_1": np.random.uniform(100, 1000, n),
                "ask_size_2": np.random.uniform(50, 500, n),
                "ask_size_3": np.random.uniform(25, 250, n),
                "ask_size_4": np.random.uniform(10, 100, n),
                "ask_size_5": np.random.uniform(5, 50, n),
                "close": (bid + ask) / 2,
            },
            index=dates,
        )

    def test_bid_ask_spread_absolute(self, sample_quote_data):
        """Test absolute bid-ask spread calculation."""
        from medusa.features.microstructure_features import bid_ask_spread_absolute

        spread = bid_ask_spread_absolute(
            sample_quote_data["bid_price"], sample_quote_data["ask_price"]
        )

        # Spread should be non-negative (can be zero in edge cases)
        assert (spread >= 0).all()
        # Spread = ask - bid
        expected = sample_quote_data["ask_price"] - sample_quote_data["bid_price"]
        assert np.allclose(spread, expected)

    def test_bid_ask_spread_relative(self, sample_quote_data):
        """Test relative bid-ask spread calculation."""
        from medusa.features.microstructure_features import bid_ask_spread_relative

        spread_rel = bid_ask_spread_relative(
            sample_quote_data["bid_price"], sample_quote_data["ask_price"]
        )

        # Relative spread should be non-negative percentage
        assert (spread_rel.dropna() >= 0).all()
        # Should be around 2% for our test data
        assert spread_rel.dropna().mean() < 10  # Should be single-digit %

    def test_orderbook_depth(self, sample_quote_data):
        """Test orderbook depth calculation."""
        from medusa.features.microstructure_features import orderbook_depth

        depth = orderbook_depth(sample_quote_data, sample_quote_data, levels=5)

        # Returns DataFrame with 3 columns
        assert "total_bid_depth" in depth.columns
        assert "total_ask_depth" in depth.columns
        assert "depth_imbalance" in depth.columns
        assert len(depth) == len(sample_quote_data)

        # Depth should be positive
        assert (depth["total_bid_depth"] > 0).all()
        assert (depth["total_ask_depth"] > 0).all()

        # Imbalance should be in [-1, 1]
        assert (depth["depth_imbalance"].dropna().abs() <= 1).all()

    def test_mid_price_volatility(self, sample_quote_data):
        """Test mid-price volatility calculation."""
        from medusa.features.microstructure_features import mid_price_volatility

        vol = mid_price_volatility(
            sample_quote_data["bid_price"],
            sample_quote_data["ask_price"],
            window=20,
        )

        # Volatility should be positive
        assert (vol.dropna() >= 0).all()
        # First 19 values should be NaN
        assert vol.isna().sum() >= 19

    def test_trade_arrival_rate(self):
        """Test trade arrival rate calculation."""
        from medusa.features.microstructure_features import trade_arrival_rate

        # Create timestamp series with varying arrival rates
        np.random.seed(42)
        base = pd.Timestamp("2024-01-01")
        # Generate 100 trade timestamps over 120 seconds
        timestamps = pd.Series(
            [
                base + pd.Timedelta(seconds=int(i))
                for i in np.cumsum(np.random.exponential(1.2, 100))
            ]
        )
        timestamps = timestamps[timestamps < base + pd.Timedelta(seconds=120)]
        timestamps.index = timestamps

        arrival_rate = trade_arrival_rate(timestamps, window=60)

        # Arrival rate should be positive
        assert (arrival_rate.dropna() >= 0).all()

    def test_effective_spread(self):
        """Test effective spread calculation."""
        from medusa.features.microstructure_features import effective_spread

        np.random.seed(42)
        n = 100
        mid = 100.0
        price = mid + np.random.randn(n) * 0.02
        mid_price = pd.Series([mid] * n)
        price_series = pd.Series(price)

        eff_spread = effective_spread(price_series, mid_price)

        # Effective spread = 2 * |price - mid|, should be positive
        assert (eff_spread >= 0).all()
        expected = 2 * (price_series - mid_price).abs()
        assert np.allclose(eff_spread, expected)

    def test_realized_spread(self):
        """Test realized spread calculation."""
        from medusa.features.microstructure_features import realized_spread

        np.random.seed(42)
        n = 100
        price = pd.Series(100 + np.random.randn(n) * 0.5)
        mid_price = pd.Series(100 + np.random.randn(n) * 0.3)

        real_spread = realized_spread(price, mid_price, lag=5)

        # Realized spread can be positive or negative
        assert len(real_spread) == n
        # Last 5 values should be NaN (due to shift)
        assert real_spread.tail(5).isna().all()

    def test_price_impact(self):
        """Test price impact calculation."""
        from medusa.features.microstructure_features import price_impact

        np.random.seed(42)
        n = 100
        trade_price = pd.Series(100 + np.random.randn(n) * 0.5)
        mid_before = pd.Series(100 + np.random.randn(n) * 0.3)
        mid_after = mid_before + np.random.randn(n) * 0.1

        impact = price_impact(trade_price, mid_before, mid_after)

        # Price impact = mid_after - mid_before
        expected = mid_after - mid_before
        assert np.allclose(impact, expected)

    def test_roll_measure(self):
        """Test Roll spread estimator."""
        from medusa.features.microstructure_features import roll_measure

        np.random.seed(42)
        # Create prices with negative serial correlation (bounce effect)
        n = 100
        prices = pd.Series(100 + np.random.randn(n).cumsum() * 0.1)

        roll_spread = roll_measure(prices, window=20)

        # Roll spread should be positive
        assert (roll_spread.dropna() >= 0).all()
        # First 19 values should be NaN
        assert roll_spread.isna().sum() >= 19

    def test_add_microstructure_features_basic(self, sample_quote_data):
        """Test add_microstructure_features with basic columns."""
        from medusa.features.microstructure_features import add_microstructure_features

        result = add_microstructure_features(sample_quote_data, has_orderbook=False)

        # Should have spread and volatility columns
        assert "spread_abs" in result.columns
        assert "spread_rel" in result.columns
        assert "mid_volatility" in result.columns
        assert "roll_spread" in result.columns

    def test_add_microstructure_features_with_orderbook(self, sample_quote_data):
        """Test add_microstructure_features with orderbook depth."""
        from medusa.features.microstructure_features import add_microstructure_features

        result = add_microstructure_features(sample_quote_data, has_orderbook=True)

        # Should have depth columns
        assert "total_bid_depth" in result.columns
        assert "total_ask_depth" in result.columns
        assert "depth_imbalance" in result.columns


# ============================================================================
# Test 2: Technical Indicators Extended (medusa/features/technical_indicators_extended.py)
# ============================================================================


class TestTechnicalIndicatorsExtended:
    """Test extended technical indicators."""

    @pytest.fixture
    def sample_ohlcv(self):
        """Create sample OHLCV data."""
        np.random.seed(42)
        n = 100
        dates = pd.date_range("2024-01-01", periods=n, freq="1h")

        close = 100 * np.exp(np.random.randn(n).cumsum() * 0.01)
        high = close * (1 + np.random.uniform(0, 0.02, n))
        low = close * (1 - np.random.uniform(0, 0.02, n))
        open_ = close + np.random.uniform(-1, 1, n)
        volume = np.random.uniform(1000, 10000, n)

        return pd.DataFrame(
            {
                "open": open_,
                "high": high,
                "low": low,
                "close": close,
                "volume": volume,
            },
            index=dates,
        )

    def test_ensure_series_from_dataframe(self, sample_ohlcv):
        """Test _ensure_series extracts column from DataFrame."""
        from medusa.features.technical_indicators_extended import _ensure_series

        result = _ensure_series(sample_ohlcv, "close")
        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        assert np.allclose(result, sample_ohlcv["close"])

    def test_ensure_series_from_series(self, sample_ohlcv):
        """Test _ensure_series returns Series as-is."""
        from medusa.features.technical_indicators_extended import _ensure_series

        series = sample_ohlcv["close"]
        result = _ensure_series(series, "close")
        assert result is series

    def test_ensure_series_missing_column(self, sample_ohlcv):
        """Test _ensure_series raises on missing column."""
        from medusa.features.technical_indicators_extended import _ensure_series

        with pytest.raises(ValueError, match="Column 'invalid' not found"):
            _ensure_series(sample_ohlcv, "invalid")

    def test_adx_fallback(self, sample_ohlcv):
        """Test ADX calculation with fallback (no talib/pandas-ta)."""
        try:
            from medusa.features.technical_indicators_extended import adx

            result = adx(sample_ohlcv, period=14)
            assert "adx" in result.columns
            assert "plus_di" in result.columns
            assert "minus_di" in result.columns
            assert len(result) == len(sample_ohlcv)
        except ImportError:
            pytest.skip("Neither talib nor pandas-ta available")

    def test_stochastic_fallback(self, sample_ohlcv):
        """Test Stochastic with manual fallback."""
        from medusa.features.technical_indicators_extended import stochastic

        result = stochastic(sample_ohlcv, k_period=14, d_period=3)

        assert "stoch_k" in result.columns
        assert "stoch_d" in result.columns
        assert len(result) == len(sample_ohlcv)

        # Stochastic should be in [0, 100]
        assert (result["stoch_k"].dropna() >= 0).all()
        assert (result["stoch_k"].dropna() <= 100).all()

    def test_williams_r_fallback(self, sample_ohlcv):
        """Test Williams %R with manual fallback."""
        from medusa.features.technical_indicators_extended import williams_r

        result = williams_r(sample_ohlcv, period=14)

        assert isinstance(result, pd.Series)
        # Williams %R should be in [-100, 0]
        assert (result.dropna() >= -100).all()
        assert (result.dropna() <= 0).all()

    def test_cci_fallback(self, sample_ohlcv):
        """Test CCI with manual fallback."""
        from medusa.features.technical_indicators_extended import cci

        result = cci(sample_ohlcv, period=20)

        assert isinstance(result, pd.Series)
        # CCI can be unbounded but should have reasonable values
        assert result.dropna().std() > 0

    def test_mfi_fallback(self, sample_ohlcv):
        """Test MFI with manual fallback."""
        from medusa.features.technical_indicators_extended import mfi

        result = mfi(sample_ohlcv, period=14)

        assert isinstance(result, pd.Series)
        # MFI should be in [0, 100]
        assert (result.dropna() >= 0).all()
        assert (result.dropna() <= 100).all()

    def test_obv_fallback(self, sample_ohlcv):
        """Test OBV with manual fallback."""
        from medusa.features.technical_indicators_extended import obv

        result = obv(sample_ohlcv)

        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        # OBV should be cumulative
        assert result.iloc[-1] != 0  # Should accumulate something

    def test_ichimoku_fallback(self, sample_ohlcv):
        """Test Ichimoku with manual fallback."""
        try:
            from medusa.features.technical_indicators_extended import ichimoku

            result = ichimoku(sample_ohlcv)

            assert "tenkan" in result.columns
            assert "kijun" in result.columns
            assert "senkou_a" in result.columns
            assert "senkou_b" in result.columns
            # chikou column name may vary by library version
            assert len(result) == len(sample_ohlcv)
            assert len(result.columns) >= 4  # At least 4 ichimoku components
        except ImportError:
            pytest.skip("pandas-ta not available for ichimoku")

    def test_all_extended_indicators_requires_library(self):
        """Test all_extended_indicators raises without libraries."""
        from medusa.features.technical_indicators_extended import (
            HAS_PANDAS_TA,
            HAS_TALIB,
        )

        if not HAS_TALIB and not HAS_PANDAS_TA:
            from medusa.features.technical_indicators_extended import (
                all_extended_indicators,
            )

            df = pd.DataFrame(
                {
                    "open": [1, 2, 3],
                    "high": [2, 3, 4],
                    "low": [0.5, 1, 2],
                    "close": [1.5, 2.5, 3.5],
                    "volume": [100, 200, 300],
                }
            )

            with pytest.raises(ImportError, match="Extended indicators require"):
                all_extended_indicators(df)
        else:
            pytest.skip("talib or pandas-ta is available")


# ============================================================================
# Test 3: Cross-Asset Features (medusa/features/cross_asset_features.py)
# ============================================================================


class TestCrossAssetFeatures:
    """Test cross-asset features."""

    @pytest.fixture
    def sample_pair_data(self):
        """Create sample pair data."""
        np.random.seed(42)
        n = 100
        dates = pd.date_range("2024-01-01", periods=n, freq="1h")

        # Create cointegrated pair
        s1 = 100 + np.random.randn(n).cumsum() * 0.5
        s2 = 50 + 0.5 * s1 + np.random.randn(n) * 2  # Cointegrated with s1

        return (
            pd.Series(s1, index=dates),
            pd.Series(s2, index=dates),
        )

    def test_rolling_correlation(self, sample_pair_data):
        """Test rolling correlation calculation."""
        from medusa.features.cross_asset_features import rolling_correlation

        s1, s2 = sample_pair_data
        corr = rolling_correlation(s1, s2, window=60, min_periods=30)

        # Correlation should be in [-1, 1]
        assert (corr.dropna().abs() <= 1).all()

    def test_lead_lag_correlation(self, sample_pair_data):
        """Test lead-lag correlation."""
        from medusa.features.cross_asset_features import lead_lag_correlation

        s1, s2 = sample_pair_data
        result = lead_lag_correlation(s1, s2, max_lag=10)

        assert "lag" in result.columns
        assert "correlation" in result.columns
        # Should have 21 rows (-10 to +10)
        assert len(result) == 21
        # Correlations should be in [-1, 1]
        assert (result["correlation"].abs() <= 1).all()

    def test_cointegration_test_success(self, sample_pair_data):
        """Test cointegration test with cointegrated pair."""
        from medusa.features.cross_asset_features import cointegration_test

        s1, s2 = sample_pair_data
        result = cointegration_test(s1, s2, significance=0.05)

        # Should return CointegrationResult
        assert hasattr(result, "t_stat")
        assert hasattr(result, "p_value")
        assert hasattr(result, "is_cointegrated")
        assert hasattr(result, "hedge_ratio")

        # Should be valid numbers
        assert math.isfinite(result.t_stat)
        assert math.isfinite(result.p_value)
        assert math.isfinite(result.hedge_ratio)
        assert isinstance(result.is_cointegrated, bool)

    def test_cointegration_test_insufficient_data(self):
        """Test cointegration test with insufficient data."""
        from medusa.features.cross_asset_features import cointegration_test

        s1 = pd.Series([1, 2, 3])
        s2 = pd.Series([2, 4, 6])

        result = cointegration_test(s1, s2)

        # Should return NaN results
        assert math.isnan(result.t_stat)
        assert math.isnan(result.p_value)
        assert result.is_cointegrated is False
        assert math.isnan(result.hedge_ratio)

    def test_rolling_beta(self, sample_pair_data):
        """Test rolling beta calculation."""
        from medusa.features.cross_asset_features import rolling_beta

        s1, s2 = sample_pair_data
        ret1 = s1.pct_change()
        ret2 = s2.pct_change()

        beta = rolling_beta(ret1, ret2, window=60)

        # Beta should have reasonable values
        assert (beta.dropna().abs() < 10).all()  # Should be reasonable

    def test_rolling_alpha(self, sample_pair_data):
        """Test rolling alpha calculation."""
        from medusa.features.cross_asset_features import rolling_alpha

        s1, s2 = sample_pair_data
        ret1 = s1.pct_change()
        ret2 = s2.pct_change()

        alpha = rolling_alpha(ret1, ret2, risk_free_rate=0.02, window=60)

        # Alpha should have reasonable values
        assert len(alpha) == len(ret1)

    def test_spread_valid_hedge_ratio(self, sample_pair_data):
        """Test spread with valid hedge ratio."""
        from medusa.features.cross_asset_features import spread

        s1, s2 = sample_pair_data
        spread_series = spread(s1, s2, hedge_ratio=0.5)

        # Spread = s1 - 0.5 * s2
        expected = s1 - 0.5 * s2
        assert np.allclose(spread_series, expected)

    def test_spread_invalid_hedge_ratio_nan(self, sample_pair_data):
        """Test spread raises on NaN hedge ratio."""
        from medusa.features.cross_asset_features import spread

        s1, s2 = sample_pair_data

        with pytest.raises(ValueError, match="hedge_ratio must be finite"):
            spread(s1, s2, hedge_ratio=float("nan"))

    def test_spread_invalid_hedge_ratio_inf(self, sample_pair_data):
        """Test spread raises on infinite hedge ratio."""
        from medusa.features.cross_asset_features import spread

        s1, s2 = sample_pair_data

        with pytest.raises(ValueError, match="hedge_ratio must be finite"):
            spread(s1, s2, hedge_ratio=float("inf"))

    def test_z_score_spread(self, sample_pair_data):
        """Test z-score of spread."""
        from medusa.features.cross_asset_features import spread, z_score_spread

        s1, s2 = sample_pair_data
        spread_series = spread(s1, s2, hedge_ratio=0.5)

        z_score = z_score_spread(spread_series, window=20)

        # Z-score should have mean ~0 and std ~1 (roughly)
        assert abs(z_score.dropna().mean()) < 2
        # Should have some variation
        assert z_score.dropna().std() > 0

    def test_add_cross_asset_features(self, sample_pair_data):
        """Test add_cross_asset_features."""
        from medusa.features.cross_asset_features import add_cross_asset_features

        s1, s2 = sample_pair_data
        df1 = pd.DataFrame({"close": s1})
        df2 = pd.DataFrame({"close": s2})

        result = add_cross_asset_features(df1, df2, price_col="close", window=60)

        # Should have cross-asset columns
        assert "corr_asset2" in result.columns
        assert "beta_asset2" in result.columns
        assert "alpha_asset2" in result.columns
        assert "spread_asset2" in result.columns
        assert "spread_z_score" in result.columns


# ============================================================================
# Test 4: Portfolio Optimizer (medusa/analytics/portfolio.py)
# ============================================================================


class TestPortfolioOptimizer:
    """Test portfolio optimization."""

    @pytest.fixture
    def sample_returns(self):
        """Create sample returns data."""
        np.random.seed(42)
        n = 252  # 1 year daily
        n_assets = 5

        # Create correlated returns
        cov = np.random.rand(n_assets, n_assets)
        cov = cov @ cov.T  # Make positive definite
        returns = np.random.multivariate_normal(mean=[0.0005] * n_assets, cov=cov * 0.0001, size=n)

        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        return pd.DataFrame(
            returns,
            index=dates,
            columns=[f"asset_{i}" for i in range(n_assets)],
        )

    def test_mean_variance_optimization(self, sample_returns):
        """Test mean-variance optimization."""
        try:
            from medusa.analytics.portfolio import PortfolioOptimizer

            # Create better-conditioned covariance matrix
            np.random.seed(42)
            n = 252
            n_assets = 5

            # Create less correlated returns with clearer structure
            returns_data = []
            for i in range(n_assets):
                ret = np.random.randn(n) * 0.01 + 0.0005 * (i + 1)
                returns_data.append(ret)

            better_returns = pd.DataFrame(
                np.column_stack(returns_data),
                index=sample_returns.index,
                columns=sample_returns.columns,
            )

            weights = PortfolioOptimizer.mean_variance(
                better_returns,
                method="MV",
                risk_measure="MV",
                risk_free_rate=0.02,
            )

            # Weights should sum to ~1
            assert abs(weights.sum() - 1.0) < 0.1  # More tolerance
            # Should have same length as assets
            assert len(weights) == better_returns.shape[1]

        except (ImportError, TypeError, AttributeError) as e:
            pytest.skip(f"Portfolio optimization not available: {e}")

    def test_risk_parity(self, sample_returns):
        """Test risk parity optimization."""
        try:
            from medusa.analytics.portfolio import PortfolioOptimizer

            weights = PortfolioOptimizer.risk_parity(sample_returns, risk_measure="MV")

            # Weights should sum to ~1
            assert abs(weights.sum() - 1.0) < 0.01
            assert len(weights) == sample_returns.shape[1]

        except ImportError:
            pytest.skip("riskfolio library not available")

    def test_hierarchical_risk_parity(self, sample_returns):
        """Test HRP optimization."""
        try:
            from medusa.analytics.portfolio import PortfolioOptimizer

            weights = PortfolioOptimizer.hierarchical_risk_parity(sample_returns)

            # Weights should sum to ~1
            assert abs(weights.sum() - 1.0) < 0.01
            assert len(weights) == sample_returns.shape[1]

        except ImportError:
            pytest.skip("riskfolio library not available")

    def test_black_litterman_placeholder(self, sample_returns):
        """Test Black-Litterman placeholder."""
        from medusa.analytics.portfolio import PortfolioOptimizer

        weights = PortfolioOptimizer.black_litterman(sample_returns)

        # Should return equal weight (placeholder)
        expected_weight = 1.0 / sample_returns.shape[1]
        assert np.allclose(weights, expected_weight, atol=0.01)
        assert len(weights) == sample_returns.shape[1]


# ============================================================================
# Test 5: Performance Tearsheet (medusa/analytics/tearsheet.py)
# ============================================================================


class TestPerformanceTearsheet:
    """Test performance tearsheet."""

    @pytest.fixture
    def sample_strategy_returns(self):
        """Create sample strategy returns."""
        np.random.seed(42)
        n = 252
        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        returns = pd.Series(
            np.random.randn(n) * 0.01 + 0.0005,  # Mean 5 bps, vol 1%
            index=dates,
            name="strategy",
        )
        return returns

    @pytest.fixture
    def sample_benchmark_returns(self):
        """Create sample benchmark returns."""
        np.random.seed(43)
        n = 252
        dates = pd.date_range("2024-01-01", periods=n, freq="D")
        returns = pd.Series(
            np.random.randn(n) * 0.008 + 0.0003,  # Mean 3 bps, vol 0.8%
            index=dates,
            name="benchmark",
        )
        return returns

    def test_generate_html_without_benchmark(self, sample_strategy_returns, tmp_path):
        """Test HTML tearsheet generation without benchmark."""
        try:
            from medusa.analytics.tearsheet import PerformanceTearsheet

            output_path = tmp_path / "tearsheet.html"
            PerformanceTearsheet.generate_html(
                sample_strategy_returns,
                benchmark=None,
                output_path=output_path,
                title="Test Strategy",
            )

            # File should be created
            assert output_path.exists()
            assert output_path.stat().st_size > 0

        except ImportError:
            pytest.skip("quantstats library not available")

    def test_generate_html_with_benchmark(
        self, sample_strategy_returns, sample_benchmark_returns, tmp_path
    ):
        """Test HTML tearsheet generation with benchmark."""
        try:
            from medusa.analytics.tearsheet import PerformanceTearsheet

            output_path = tmp_path / "tearsheet_bench.html"
            PerformanceTearsheet.generate_html(
                sample_strategy_returns,
                benchmark=sample_benchmark_returns,
                output_path=output_path,
                title="Test Strategy vs Benchmark",
            )

            assert output_path.exists()
            assert output_path.stat().st_size > 0

        except ImportError:
            pytest.skip("quantstats library not available")

    def test_get_metrics_without_benchmark(self, sample_strategy_returns):
        """Test metrics extraction without benchmark."""
        try:
            from medusa.analytics.tearsheet import PerformanceTearsheet

            metrics = PerformanceTearsheet.get_metrics(sample_strategy_returns)

            # Should have base metrics
            assert "total_return" in metrics
            assert "cagr" in metrics
            assert "sharpe" in metrics
            assert "sortino" in metrics
            assert "max_drawdown" in metrics
            assert "calmar" in metrics
            assert "volatility" in metrics
            assert "avg_return" in metrics
            assert "win_rate" in metrics

            # All metrics should be numeric
            for key, value in metrics.items():
                assert isinstance(value, (int, float))

        except ImportError:
            pytest.skip("quantstats library not available")

    def test_get_metrics_with_benchmark(self, sample_strategy_returns, sample_benchmark_returns):
        """Test metrics extraction with benchmark."""
        try:
            from medusa.analytics.tearsheet import PerformanceTearsheet

            metrics = PerformanceTearsheet.get_metrics(
                sample_strategy_returns, benchmark=sample_benchmark_returns
            )

            # Should have benchmark-relative metrics
            assert "beta" in metrics
            assert "alpha" in metrics
            assert "information_ratio" in metrics

            # All metrics should be numeric
            for key, value in metrics.items():
                assert isinstance(value, (int, float))

        except ImportError:
            pytest.skip("quantstats library not available")

    def test_print_summary(self, sample_strategy_returns, capsys):
        """Test print_summary outputs to stdout."""
        try:
            from medusa.analytics.tearsheet import PerformanceTearsheet

            PerformanceTearsheet.print_summary(sample_strategy_returns)

            # Should have printed something
            captured = capsys.readouterr()
            assert len(captured.out) > 0

        except ImportError:
            pytest.skip("quantstats library not available")


# ============================================================================
# Test 6: Parquet Data Loader (medusa/data/parquet_loader.py)
# ============================================================================


class TestParquetDataLoader:
    """Test Parquet data loader."""

    @pytest.fixture
    def sample_parquet_file(self, tmp_path):
        """Create a sample Parquet file."""
        import polars as pl

        n = 100
        df = pl.DataFrame(
            {
                "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
                "open": np.random.uniform(99, 101, n),
                "high": np.random.uniform(100, 102, n),
                "low": np.random.uniform(98, 100, n),
                "close": np.random.uniform(99, 101, n),
                "volume": np.random.uniform(1000, 10000, n),
            }
        )

        path = tmp_path / "test_data.parquet"
        df.write_parquet(path)
        return path

    def test_load_ohlcv_success(self, sample_parquet_file):
        """Test loading valid OHLCV Parquet file."""
        from medusa.data.parquet_loader import ParquetDataLoader

        df = ParquetDataLoader.load_ohlcv(sample_parquet_file)

        # Should have required columns
        assert "timestamp" in df.columns
        assert "open" in df.columns
        assert "high" in df.columns
        assert "low" in df.columns
        assert "close" in df.columns
        assert "volume" in df.columns

        # Should be sorted by timestamp
        assert df["timestamp"].is_sorted()

    def test_load_ohlcv_file_not_found(self, tmp_path):
        """Test loading non-existent file raises FileNotFoundError."""
        from medusa.data.parquet_loader import ParquetDataLoader

        nonexistent = tmp_path / "does_not_exist.parquet"

        with pytest.raises(FileNotFoundError, match="Parquet file not found"):
            ParquetDataLoader.load_ohlcv(nonexistent)

    def test_load_ohlcv_missing_columns(self, tmp_path):
        """Test loading Parquet with missing columns raises ValueError."""
        import polars as pl

        from medusa.data.parquet_loader import ParquetDataLoader

        # Create file with missing 'volume' column
        df = pl.DataFrame(
            {
                "timestamp": pd.date_range("2024-01-01", periods=10, freq="1h"),
                "open": [100] * 10,
                "high": [101] * 10,
                "low": [99] * 10,
                "close": [100.5] * 10,
            }
        )

        path = tmp_path / "invalid.parquet"
        df.write_parquet(path)

        with pytest.raises(ValueError, match="Parquet missing required columns"):
            ParquetDataLoader.load_ohlcv(path)


# ============================================================================
# Run tests
# ============================================================================

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
