"""Shared test fixtures for Medusa test suite."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest


@pytest.fixture
def sample_ohlcv() -> pd.DataFrame:
    """Generate realistic OHLCV data for testing."""
    np.random.seed(42)
    n = 500
    dates = pd.date_range(start="2024-01-01", periods=n, freq="1h")

    # Random walk price
    returns = np.random.normal(0.0001, 0.01, n)
    close = 100 * np.exp(np.cumsum(returns))

    # Realistic OHLCV from close
    high = close * (1 + np.abs(np.random.normal(0, 0.005, n)))
    low = close * (1 - np.abs(np.random.normal(0, 0.005, n)))
    open_price = close * (1 + np.random.normal(0, 0.003, n))
    volume = np.random.lognormal(10, 1, n)

    df = pd.DataFrame({
        "open": open_price,
        "high": high,
        "low": low,
        "close": close,
        "volume": volume,
    }, index=dates)
    df.index.name = "timestamp"
    return df


@pytest.fixture
def sample_price(sample_ohlcv: pd.DataFrame) -> pd.Series:
    """Close price series from sample OHLCV."""
    return sample_ohlcv["close"]


@pytest.fixture
def sample_returns(sample_price: pd.Series) -> pd.Series:
    """Daily returns from sample price."""
    return sample_price.pct_change().dropna()


@pytest.fixture
def multi_asset_returns() -> pd.DataFrame:
    """Returns for multiple assets."""
    np.random.seed(123)
    n = 252
    dates = pd.date_range(start="2024-01-01", periods=n, freq="B")

    data = {}
    for asset in ["BTC", "ETH", "SOL", "AVAX"]:
        data[asset] = np.random.normal(0.0005, 0.02, n)

    return pd.DataFrame(data, index=dates)


@pytest.fixture
def tmp_csv(tmp_path, sample_ohlcv: pd.DataFrame):
    """Write sample OHLCV to a temp CSV and return the path."""
    csv_path = tmp_path / "test_data.csv"
    df = sample_ohlcv.reset_index()
    df.to_csv(csv_path, index=False)
    return csv_path


@pytest.fixture
def tmp_parquet(tmp_path, sample_ohlcv: pd.DataFrame):
    """Write sample OHLCV to a temp Parquet and return the path."""
    parquet_path = tmp_path / "test_data.parquet"
    df = sample_ohlcv.reset_index()
    df.to_parquet(parquet_path)
    return parquet_path
