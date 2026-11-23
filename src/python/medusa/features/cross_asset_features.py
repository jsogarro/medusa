"""Cross-asset and portfolio features for multi-asset strategies."""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import stats  # type: ignore
from statsmodels.tsa.stattools import coint  # type: ignore


@dataclass
class CointegrationResult:
    """Results from Engle-Granger cointegration test."""

    t_stat: float
    p_value: float
    is_cointegrated: bool
    hedge_ratio: float


def rolling_correlation(
    series1: pd.Series,
    series2: pd.Series,
    window: int = 60,
    min_periods: int | None = None,
) -> pd.Series:
    """Rolling correlation between two price/return series.

    Args:
        series1: First time series.
        series2: Second time series.
        window: Rolling window size.
        min_periods: Minimum observations required.

    Returns:
        Series with rolling correlation values (-1 to 1).
    """
    return series1.rolling(window, min_periods=min_periods).corr(series2)


def lead_lag_correlation(
    series1: pd.Series,
    series2: pd.Series,
    max_lag: int = 10,
) -> pd.DataFrame:
    """Cross-correlation at different lags to detect lead-lag relationships.

    Args:
        series1: First series.
        series2: Second series (potentially lagged).
        max_lag: Maximum lag to test (both positive and negative).

    Returns:
        DataFrame with columns: lag, correlation.
    """
    results = []

    for lag in range(-max_lag, max_lag + 1):
        if lag < 0:
            # series1 leads series2 by |lag|
            aligned1 = series1.iloc[:lag]
            aligned2 = series2.iloc[-lag:]
        elif lag > 0:
            # series2 leads series1 by lag
            aligned1 = series1.iloc[lag:]
            aligned2 = series2.iloc[:-lag]
        else:
            aligned1 = series1
            aligned2 = series2

        # Align indices
        common_idx = aligned1.index.intersection(aligned2.index)
        if len(common_idx) > 2:
            corr = aligned1.loc[common_idx].corr(aligned2.loc[common_idx])
            results.append({"lag": lag, "correlation": corr})

    return pd.DataFrame(results)


def cointegration_test(
    series1: pd.Series,
    series2: pd.Series,
    significance: float = 0.05,
) -> CointegrationResult:
    """Engle-Granger cointegration test for pairs trading.

    Args:
        series1: First price series.
        series2: Second price series.
        significance: Significance level for the test.

    Returns:
        CointegrationResult with t_stat, p_value, is_cointegrated, hedge_ratio.
    """
    # Drop NaN and align
    aligned = pd.DataFrame({"s1": series1, "s2": series2}).dropna()

    if len(aligned) < 10:
        return CointegrationResult(
            t_stat=np.nan,
            p_value=np.nan,
            is_cointegrated=False,
            hedge_ratio=np.nan,
        )

    # Engle-Granger test
    t_stat, p_value, _ = coint(aligned["s1"], aligned["s2"])

    # Hedge ratio (OLS slope)
    slope, _, _, _, _ = stats.linregress(aligned["s2"], aligned["s1"])

    return CointegrationResult(
        t_stat=float(t_stat),
        p_value=float(p_value),
        is_cointegrated=bool(p_value < significance),
        hedge_ratio=float(slope),
    )


def rolling_beta(
    asset_returns: pd.Series,
    market_returns: pd.Series,
    window: int = 60,
) -> pd.Series:
    """Rolling beta (market sensitivity) of an asset.

    Args:
        asset_returns: Asset return series.
        market_returns: Market/benchmark return series.
        window: Rolling window size.

    Returns:
        Series with rolling beta values.
    """
    # Beta = Cov(asset, market) / Var(market)
    cov = asset_returns.rolling(window).cov(market_returns)
    var = market_returns.rolling(window).var()

    return cov / var.replace(0, np.nan)


def rolling_alpha(
    asset_returns: pd.Series,
    market_returns: pd.Series,
    risk_free_rate: float = 0.0,
    window: int = 60,
) -> pd.Series:
    """Rolling alpha (excess return over CAPM).

    Args:
        asset_returns: Asset return series.
        market_returns: Market return series.
        risk_free_rate: Annual risk-free rate.
        window: Rolling window size.

    Returns:
        Series with rolling alpha values.
    """
    beta = rolling_beta(asset_returns, market_returns, window)

    # Alpha = asset_return - (rf + beta * (market_return - rf))
    daily_rf = risk_free_rate / 252
    excess_market = market_returns - daily_rf
    expected_return = daily_rf + beta * excess_market

    return asset_returns - expected_return


def spread(
    series1: pd.Series,
    series2: pd.Series,
    hedge_ratio: float = 1.0,
) -> pd.Series:
    """Price spread for pairs trading.

    Args:
        series1: First asset price series.
        series2: Second asset price series.
        hedge_ratio: Hedge ratio (from cointegration test).

    Returns:
        Series with spread = series1 - hedge_ratio * series2.

    Raises:
        ValueError: If hedge_ratio is not finite (NaN or infinite).
    """
    if not math.isfinite(hedge_ratio):
        raise ValueError(f"hedge_ratio must be finite, got {hedge_ratio}")
    return series1 - hedge_ratio * series2


def z_score_spread(
    spread_series: pd.Series,
    window: int = 20,
) -> pd.Series:
    """Z-score of spread for mean-reversion signals.

    Args:
        spread_series: Spread series (from spread() function).
        window: Rolling window for mean/std calculation.

    Returns:
        Series with z-scores (positive = series1 expensive, negative = cheap).
    """
    rolling_mean = spread_series.rolling(window).mean()
    rolling_std = spread_series.rolling(window).std()

    return (spread_series - rolling_mean) / rolling_std.replace(0, np.nan)


def add_cross_asset_features(
    df1: pd.DataFrame,
    df2: pd.DataFrame,
    price_col: str = "close",
    window: int = 60,
) -> pd.DataFrame:
    """Add cross-asset features between two assets.

    Args:
        df1: First asset OHLCV DataFrame.
        df2: Second asset OHLCV DataFrame (must have aligned index).
        price_col: Column name for price.
        window: Rolling window for correlation/beta.

    Returns:
        df1 with cross-asset features appended.

    Note:
        Requires df1 and df2 to have overlapping datetime index.
    """
    result = df1.copy()

    price1 = df1[price_col]
    price2 = df2[price_col]

    # Rolling correlation
    result["corr_asset2"] = rolling_correlation(price1, price2, window)

    # Returns for beta/alpha
    ret1 = price1.pct_change()
    ret2 = price2.pct_change()

    result["beta_asset2"] = rolling_beta(ret1, ret2, window)
    result["alpha_asset2"] = rolling_alpha(ret1, ret2, window=window)

    # Cointegration (single test on full history)
    coint_result = cointegration_test(price1, price2)
    hedge_ratio = coint_result.hedge_ratio

    # Spread and z-score
    spread_series = spread(price1, price2, hedge_ratio)
    result["spread_asset2"] = spread_series
    result["spread_z_score"] = z_score_spread(spread_series, window=20)

    return result
