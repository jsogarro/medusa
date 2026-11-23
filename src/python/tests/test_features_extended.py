"""Tests for extended technical indicators."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

# Try to import the modules
try:
    from medusa.features.technical_indicators_extended import (
        HAS_PANDAS_TA,
        HAS_TALIB,
        adx,
        all_extended_indicators,
        cci,
        ichimoku,
        mfi,
        obv,
        stochastic,
        williams_r,
    )

    HAS_MODULE = True
except ImportError:
    HAS_MODULE = False


@pytest.fixture
def sample_ohlcv() -> pd.DataFrame:
    """Generate sample OHLCV data for testing."""
    np.random.seed(42)
    n = 100

    dates = pd.date_range("2023-01-01", periods=n, freq="1h")
    price = 100 + np.cumsum(np.random.normal(0, 1, n))

    df = pd.DataFrame(
        {
            "open": price + np.random.normal(0, 0.5, n),
            "high": price * 1.01,
            "low": price * 0.99,
            "close": price,
            "volume": np.random.randint(1000, 10000, n),
        },
        index=dates,
    )

    return df


@pytest.mark.skipif(
    not HAS_MODULE or (not HAS_TALIB and not HAS_PANDAS_TA),
    reason="Extended indicators module or dependencies not available",
)
class TestExtendedIndicators:
    """Test suite for extended technical indicators."""

    def test_adx(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test ADX calculation."""
        result = adx(sample_ohlcv, period=14)

        assert isinstance(result, pd.DataFrame)
        assert "adx" in result.columns
        assert "plus_di" in result.columns
        assert "minus_di" in result.columns
        assert len(result) == len(sample_ohlcv)
        assert result["adx"].notna().any()  # At least some non-NaN values

    def test_stochastic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Stochastic oscillator."""
        result = stochastic(sample_ohlcv, k_period=14, d_period=3)

        assert isinstance(result, pd.DataFrame)
        assert "stoch_k" in result.columns
        assert "stoch_d" in result.columns
        assert len(result) == len(sample_ohlcv)
        # Stochastic should be bounded [0, 100]
        valid_k = result["stoch_k"].dropna()
        if len(valid_k) > 0:
            assert (valid_k >= 0).all() and (valid_k <= 100).all()

    def test_williams_r(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Williams %R."""
        result = williams_r(sample_ohlcv, period=14)

        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        # Williams %R should be bounded [-100, 0]
        valid = result.dropna()
        if len(valid) > 0:
            assert (valid >= -100).all() and (valid <= 0).all()

    def test_cci(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Commodity Channel Index."""
        result = cci(sample_ohlcv, period=20)

        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        assert result.notna().any()

    def test_mfi(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Money Flow Index."""
        result = mfi(sample_ohlcv, period=14)

        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        # MFI should be bounded [0, 100]
        valid = result.dropna()
        if len(valid) > 0:
            assert (valid >= 0).all() and (valid <= 100).all()

    def test_obv(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test On-Balance Volume."""
        result = obv(sample_ohlcv)

        assert isinstance(result, pd.Series)
        assert len(result) == len(sample_ohlcv)
        # OBV is cumulative, should have values
        assert result.notna().any()

    def test_ichimoku(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Ichimoku Cloud."""
        result = ichimoku(sample_ohlcv)

        assert isinstance(result, pd.DataFrame)
        expected_cols = ["tenkan", "kijun", "senkou_a", "senkou_b"]
        for col in expected_cols:
            assert col in result.columns
        assert len(result) == len(sample_ohlcv)

    def test_all_extended_indicators(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test adding all extended indicators."""
        result = all_extended_indicators(sample_ohlcv)

        assert isinstance(result, pd.DataFrame)
        # Should have original columns plus new indicators
        assert len(result.columns) > len(sample_ohlcv.columns)
        # Check for key indicator columns
        assert "adx" in result.columns
        assert "stoch_k" in result.columns
        assert "williams_r" in result.columns
        assert "cci" in result.columns
        assert "mfi" in result.columns
        assert "obv" in result.columns


def test_import_error_handling() -> None:
    """Test that ImportError is raised when dependencies missing."""
    if not HAS_MODULE:
        pytest.skip("Module not available")

    if not HAS_TALIB and not HAS_PANDAS_TA:
        # Create minimal DataFrame
        df = pd.DataFrame(
            {
                "open": [100],
                "high": [101],
                "low": [99],
                "close": [100],
                "volume": [1000],
            }
        )

        with pytest.raises(ImportError, match="Extended indicators require"):
            all_extended_indicators(df)
