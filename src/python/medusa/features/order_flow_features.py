"""Order flow and microstructure features for high-frequency trading analysis."""

from __future__ import annotations

import numpy as np
import pandas as pd


def vpin(
    df: pd.DataFrame,
    volume_bucket_size: int = 50,
    window: int = 50,
) -> pd.Series:
    """Volume-synchronized Probability of Informed Trading (VPIN).

    Measures order flow toxicity by detecting informed trading activity.

    Args:
        df: DataFrame with 'close', 'volume' columns (and optionally 'buy_volume').
        volume_bucket_size: Number of bars per volume bucket.
        window: Rolling window of buckets for VPIN calculation.

    Returns:
        Series with VPIN values (0-1, higher = more toxic flow).
    """
    # If buy_volume not available, estimate via tick rule
    if "buy_volume" in df.columns:
        buy_vol = df["buy_volume"]
        sell_vol = df["volume"] - buy_vol
    else:
        # Tick rule: if price went up, assume buyer-initiated
        price_change = df["close"].diff()
        buy_vol = df["volume"].where(price_change > 0, 0.0)
        sell_vol = df["volume"].where(price_change < 0, 0.0)

    # Create volume buckets
    cum_volume = df["volume"].cumsum()
    bucket_idx = (cum_volume // volume_bucket_size).astype(int)

    # Aggregate by bucket
    bucket_buy = buy_vol.groupby(bucket_idx).sum()
    bucket_sell = sell_vol.groupby(bucket_idx).sum()
    bucket_total = (buy_vol + sell_vol).groupby(bucket_idx).sum()

    # VPIN = rolling average of |buy - sell| / total
    order_imbalance = (bucket_buy - bucket_sell).abs()
    vpin_vals = (order_imbalance / bucket_total.replace(0, np.nan)).rolling(window).mean()

    # Map back to bars. A bar's own bucket is still filling, so it only sees
    # the VPIN of the previous (completed) bucket - never a later bar's volume.
    vpin_series = bucket_idx.map(vpin_vals.shift(1)).astype(float)

    # VPIN is a probability metric — clip to [0, 1]
    return vpin_series.clip(0, 1).ffill()


def trade_imbalance(
    df: pd.DataFrame,
    window: int = 20,
) -> pd.Series:
    """Trade imbalance: buy volume / total volume over rolling window.

    Args:
        df: DataFrame with 'close', 'volume'.
        window: Rolling window size.

    Returns:
        Series with trade imbalance (0-1, 0.5=neutral, >0.5=buy pressure).
    """
    # Estimate buy volume via tick rule if not present
    if "buy_volume" in df.columns:
        buy_vol = df["buy_volume"]
    else:
        price_change = df["close"].diff()
        buy_vol = df["volume"].where(price_change > 0, df["volume"] * 0.5)

    rolling_buy = buy_vol.rolling(window).sum()
    rolling_total = df["volume"].rolling(window).sum()

    return rolling_buy / rolling_total.replace(0, np.nan)


def order_flow_toxicity(
    df: pd.DataFrame,
    window: int = 20,
) -> pd.Series:
    """Order flow toxicity metric based on volume-weighted price impact.

    Higher values indicate informed trading (adverse selection risk).

    Args:
        df: DataFrame with 'close', 'volume'.
        window: Rolling window size.

    Returns:
        Series with toxicity scores.
    """
    # Price impact per unit volume
    returns = df["close"].pct_change()
    volume_normalized = df["volume"] / df["volume"].rolling(window).mean()

    # Toxicity = |return| / volume (informed traders move price with less volume)
    toxicity = returns.abs() / volume_normalized.replace(0, np.nan)

    return toxicity.rolling(window).mean()


def kyle_lambda(
    df: pd.DataFrame,
    window: int = 20,
) -> pd.Series:
    """Kyle's lambda: price impact coefficient.

    Measures how much price moves per unit of order flow.
    Higher lambda = lower liquidity / higher impact cost.

    Args:
        df: DataFrame with 'close', 'volume'.
        window: Rolling regression window.

    Returns:
        Series with lambda values (price impact per volume).
    """
    returns = df["close"].pct_change()
    signed_volume = df["volume"] * np.sign(returns)  # Signed by direction

    lambda_vals = pd.Series(index=df.index, dtype=float)

    for i in range(window, len(df)):
        y = returns.iloc[i - window : i].values
        x = signed_volume.iloc[i - window : i].values

        # OLS: returns ~ lambda * signed_volume
        if np.std(x) > 0:
            lambda_vals.iloc[i] = np.cov(x, y)[0, 1] / np.var(x)

    return lambda_vals


def volume_clock_sampling(
    df: pd.DataFrame,
    volume_per_bar: int = 1000,
) -> pd.DataFrame:
    """Resample data by cumulative volume (volume clock) instead of time.

    Args:
        df: OHLCV DataFrame with 'volume' column.
        volume_per_bar: Target volume per sampled bar.

    Returns:
        DataFrame resampled by volume clock (each bar has ~equal volume).
    """
    cum_volume = df["volume"].cumsum()
    bar_idx = (cum_volume // volume_per_bar).astype(int)

    # Aggregate OHLCV by volume bars
    agg_dict = {
        "open": "first",
        "high": "max",
        "low": "min",
        "close": "last",
        "volume": "sum",
    }

    resampled = df.groupby(bar_idx).agg(agg_dict)
    return resampled


def add_order_flow_features(
    df: pd.DataFrame,
    vpin_window: int = 50,
    imbalance_window: int = 20,
) -> pd.DataFrame:
    """Add all order flow features to an OHLCV DataFrame.

    Args:
        df: OHLCV DataFrame with 'close', 'volume'.
        vpin_window: Window for VPIN calculation.
        imbalance_window: Window for trade imbalance and toxicity.

    Returns:
        DataFrame with order flow features appended.
    """
    result = df.copy()

    result["vpin"] = vpin(result, window=vpin_window)
    result["trade_imbalance"] = trade_imbalance(result, window=imbalance_window)
    result["flow_toxicity"] = order_flow_toxicity(result, window=imbalance_window)
    result["kyle_lambda"] = kyle_lambda(result, window=imbalance_window)

    return result
