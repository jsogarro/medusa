"""Technical indicator calculations for feature engineering."""

from __future__ import annotations

import numpy as np
import pandas as pd


def sma(series: pd.Series, period: int) -> pd.Series:
    """Simple Moving Average."""
    return series.rolling(period).mean()


def ema(series: pd.Series, period: int) -> pd.Series:
    """Exponential Moving Average."""
    return series.ewm(span=period, adjust=False).mean()


def rsi(series: pd.Series, period: int = 14) -> pd.Series:
    """Relative Strength Index."""
    delta = series.diff()
    gain = delta.where(delta > 0, 0.0).rolling(period).mean()
    loss = (-delta.where(delta < 0, 0.0)).rolling(period).mean()
    rs = gain / loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def macd(
    series: pd.Series,
    fast: int = 12,
    slow: int = 26,
    signal: int = 9,
) -> pd.DataFrame:
    """MACD indicator.

    Returns:
        DataFrame with columns: macd, signal, histogram.
    """
    fast_ema = ema(series, fast)
    slow_ema = ema(series, slow)
    macd_line = fast_ema - slow_ema
    signal_line = ema(macd_line, signal)
    histogram = macd_line - signal_line

    return pd.DataFrame({
        "macd": macd_line,
        "signal": signal_line,
        "histogram": histogram,
    })


def bollinger_bands(
    series: pd.Series,
    period: int = 20,
    num_std: float = 2.0,
) -> pd.DataFrame:
    """Bollinger Bands.

    Returns:
        DataFrame with columns: upper, middle, lower, bandwidth, pct_b.
    """
    middle = sma(series, period)
    std = series.rolling(period).std()
    upper = middle + num_std * std
    lower = middle - num_std * std
    bandwidth = (upper - lower) / middle
    pct_b = (series - lower) / (upper - lower)

    return pd.DataFrame({
        "bb_upper": upper,
        "bb_middle": middle,
        "bb_lower": lower,
        "bb_bandwidth": bandwidth,
        "bb_pct_b": pct_b,
    })


def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Average True Range.

    Args:
        df: DataFrame with 'high', 'low', 'close' columns.
        period: ATR period.
    """
    high_low = df["high"] - df["low"]
    high_close = (df["high"] - df["close"].shift(1)).abs()
    low_close = (df["low"] - df["close"].shift(1)).abs()
    true_range = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    return true_range.rolling(period).mean()


def vwap(df: pd.DataFrame) -> pd.Series:
    """Volume-Weighted Average Price (cumulative intraday).

    Args:
        df: DataFrame with 'close' (or 'high','low') and 'volume'.
    """
    typical_price = (df["high"] + df["low"] + df["close"]) / 3
    cum_vol = df["volume"].cumsum()
    cum_tp_vol = (typical_price * df["volume"]).cumsum()
    return cum_tp_vol / cum_vol.replace(0, np.nan)


def returns(series: pd.Series, periods: int = 1) -> pd.Series:
    """Log returns over N periods."""
    return np.log(series / series.shift(periods))


def volatility(series: pd.Series, window: int = 20) -> pd.Series:
    """Rolling realized volatility (annualized from log returns)."""
    log_ret = returns(series)
    return log_ret.rolling(window).std() * np.sqrt(252)


def add_all_indicators(
    df: pd.DataFrame,
    price_col: str = "close",
) -> pd.DataFrame:
    """Add a comprehensive set of technical indicators to an OHLCV DataFrame.

    Args:
        df: OHLCV DataFrame.
        price_col: Column name for the price series.

    Returns:
        DataFrame with indicator columns appended.
    """
    result = df.copy()
    price = result[price_col]

    # Moving averages
    for p in [10, 20, 50, 200]:
        result[f"sma_{p}"] = sma(price, p)
        result[f"ema_{p}"] = ema(price, p)

    # RSI
    result["rsi_14"] = rsi(price, 14)

    # MACD
    macd_df = macd(price)
    result = pd.concat([result, macd_df], axis=1)

    # Bollinger Bands
    bb_df = bollinger_bands(price)
    result = pd.concat([result, bb_df], axis=1)

    # ATR
    if all(c in result.columns for c in ["high", "low", "close"]):
        result["atr_14"] = atr(result, 14)

    # Returns
    result["return_1"] = returns(price, 1)
    result["return_5"] = returns(price, 5)
    result["return_20"] = returns(price, 20)

    # Volatility
    result["volatility_20"] = volatility(price, 20)

    return result
