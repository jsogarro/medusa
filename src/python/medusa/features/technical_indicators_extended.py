"""Extended technical indicators using pandas-ta (with ta-lib fallback)."""

from __future__ import annotations

import numpy as np
import pandas as pd

# Try ta-lib first (C library, faster), fall back to pandas-ta
try:
    import talib  # type: ignore

    HAS_TALIB = True
except ImportError:
    HAS_TALIB = False

try:
    import pandas_ta as ta  # type: ignore

    HAS_PANDAS_TA = True
except ImportError:
    HAS_PANDAS_TA = False


def _ensure_series(data: pd.DataFrame | pd.Series, col: str = "close") -> pd.Series:
    """Extract series from DataFrame or return Series as-is."""
    if isinstance(data, pd.DataFrame):
        if col not in data.columns:
            raise ValueError(f"Column '{col}' not found in DataFrame")
        return data[col]
    return data


def adx(df: pd.DataFrame, period: int = 14) -> pd.DataFrame:
    """Average Directional Index (ADX) for trend strength.

    Args:
        df: DataFrame with 'high', 'low', 'close'.
        period: ADX period.

    Returns:
        DataFrame with columns: adx, plus_di, minus_di.
    """
    if HAS_TALIB:
        adx_val = talib.ADX(df["high"], df["low"], df["close"], timeperiod=period)
        plus_di = talib.PLUS_DI(df["high"], df["low"], df["close"], timeperiod=period)
        minus_di = talib.MINUS_DI(df["high"], df["low"], df["close"], timeperiod=period)
        return pd.DataFrame({"adx": adx_val, "plus_di": plus_di, "minus_di": minus_di})
    elif HAS_PANDAS_TA:
        result = ta.adx(df["high"], df["low"], df["close"], length=period)
        return result.rename(
            columns={
                f"ADX_{period}": "adx",
                f"DMP_{period}": "plus_di",
                f"DMN_{period}": "minus_di",
            }
        )
    else:
        raise ImportError("Neither talib nor pandas-ta is installed")


def stochastic(df: pd.DataFrame, k_period: int = 14, d_period: int = 3) -> pd.DataFrame:
    """Stochastic Oscillator.

    Args:
        df: DataFrame with 'high', 'low', 'close'.
        k_period: %K period.
        d_period: %D smoothing period.

    Returns:
        DataFrame with columns: stoch_k, stoch_d.
    """
    if HAS_TALIB:
        slowk, slowd = talib.STOCH(
            df["high"],
            df["low"],
            df["close"],
            fastk_period=k_period,
            slowk_period=d_period,
            slowd_period=d_period,
        )
        return pd.DataFrame({"stoch_k": slowk, "stoch_d": slowd})
    elif HAS_PANDAS_TA:
        result = ta.stoch(df["high"], df["low"], df["close"], k=k_period, d=d_period)
        return result.rename(
            columns={
                f"STOCHk_{k_period}_{d_period}_{d_period}": "stoch_k",
                f"STOCHd_{k_period}_{d_period}_{d_period}": "stoch_d",
            }
        )
    else:
        # Fallback: manual calculation
        low_min = df["low"].rolling(k_period).min()
        high_max = df["high"].rolling(k_period).max()
        stoch_k = 100 * (df["close"] - low_min) / (high_max - low_min)
        stoch_d = stoch_k.rolling(d_period).mean()
        return pd.DataFrame({"stoch_k": stoch_k, "stoch_d": stoch_d})


def williams_r(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Williams %R momentum indicator.

    Args:
        df: DataFrame with 'high', 'low', 'close'.
        period: Lookback period.

    Returns:
        Series with Williams %R values (-100 to 0).
    """
    if HAS_TALIB:
        return talib.WILLR(df["high"], df["low"], df["close"], timeperiod=period)
    elif HAS_PANDAS_TA:
        result = ta.willr(df["high"], df["low"], df["close"], length=period)
        # pandas-ta returns a Series with name WILLR_{period}
        if isinstance(result, pd.Series):
            return result
        # Fallback if it returns DataFrame
        col_name = f"WILLR_{period}"
        if col_name in result.columns:
            return result[col_name]
        return result.iloc[:, 0]  # First column
    else:
        high_max = df["high"].rolling(period).max()
        low_min = df["low"].rolling(period).min()
        return -100 * (high_max - df["close"]) / (high_max - low_min)


def cci(df: pd.DataFrame, period: int = 20) -> pd.Series:
    """Commodity Channel Index (CCI).

    Args:
        df: DataFrame with 'high', 'low', 'close'.
        period: CCI period.

    Returns:
        Series with CCI values.
    """
    if HAS_TALIB:
        return talib.CCI(df["high"], df["low"], df["close"], timeperiod=period)
    elif HAS_PANDAS_TA:
        result = ta.cci(df["high"], df["low"], df["close"], length=period)
        if isinstance(result, pd.Series):
            return result
        # Try column name variants
        for col_name in [f"CCI_{period}_0.015", f"CCI_{period}"]:
            if col_name in result.columns:
                return result[col_name]
        return result.iloc[:, 0]
    else:
        typical = (df["high"] + df["low"] + df["close"]) / 3
        sma_tp = typical.rolling(period).mean()
        mad = (typical - sma_tp).abs().rolling(period).mean()
        return (typical - sma_tp) / (0.015 * mad)


def mfi(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Money Flow Index (MFI) - volume-weighted RSI.

    Args:
        df: DataFrame with 'high', 'low', 'close', 'volume'.
        period: MFI period.

    Returns:
        Series with MFI values (0-100).
    """
    if HAS_TALIB:
        return talib.MFI(df["high"], df["low"], df["close"], df["volume"], timeperiod=period)
    elif HAS_PANDAS_TA:
        result = ta.mfi(df["high"], df["low"], df["close"], df["volume"], length=period)
        if isinstance(result, pd.Series):
            return result
        col_name = f"MFI_{period}"
        if col_name in result.columns:
            return result[col_name]
        return result.iloc[:, 0]
    else:
        typical = (df["high"] + df["low"] + df["close"]) / 3
        money_flow = typical * df["volume"]
        delta = typical.diff()
        positive_flow = money_flow.where(delta > 0, 0.0).rolling(period).sum()
        negative_flow = money_flow.where(delta < 0, 0.0).abs().rolling(period).sum()
        mfi_ratio = positive_flow / negative_flow.replace(0, np.nan)
        return 100 - (100 / (1 + mfi_ratio))


def obv(df: pd.DataFrame) -> pd.Series:
    """On-Balance Volume (OBV).

    Args:
        df: DataFrame with 'close', 'volume'.

    Returns:
        Series with cumulative OBV values.
    """
    if HAS_TALIB:
        return talib.OBV(df["close"], df["volume"])
    elif HAS_PANDAS_TA:
        result = ta.obv(df["close"], df["volume"])
        if isinstance(result, pd.Series):
            return result
        if "OBV" in result.columns:
            return result["OBV"]
        return result.iloc[:, 0]
    else:
        direction = df["close"].diff().apply(lambda x: 1 if x > 0 else -1 if x < 0 else 0)
        return (direction * df["volume"]).cumsum()


def ichimoku(df: pd.DataFrame) -> pd.DataFrame:
    """Ichimoku Cloud indicator.

    Args:
        df: DataFrame with 'high', 'low', 'close'.

    Returns:
        DataFrame with columns: tenkan, kijun, senkou_a, senkou_b, chikou.
    """
    if HAS_PANDAS_TA:
        result = ta.ichimoku(df["high"], df["low"], df["close"])[0]
        return result.rename(
            columns={
                "ITS_9": "tenkan",
                "IKS_26": "kijun",
                "ISA_9": "senkou_a",
                "ISB_26": "senkou_b",
            }
        )
    else:
        # Manual calculation
        tenkan = (df["high"].rolling(9).max() + df["low"].rolling(9).min()) / 2  # Conversion line
        kijun = (df["high"].rolling(26).max() + df["low"].rolling(26).min()) / 2  # Base line
        senkou_a = ((tenkan + kijun) / 2).shift(26)  # Leading span A
        senkou_b = ((df["high"].rolling(52).max() + df["low"].rolling(52).min()) / 2).shift(26)
        chikou = df["close"].shift(-26)  # Lagging span

        return pd.DataFrame(
            {
                "tenkan": tenkan,
                "kijun": kijun,
                "senkou_a": senkou_a,
                "senkou_b": senkou_b,
                "chikou": chikou,
            }
        )


def all_extended_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Add all extended technical indicators to an OHLCV DataFrame.

    Args:
        df: OHLCV DataFrame with 'open', 'high', 'low', 'close', 'volume'.

    Returns:
        DataFrame with extended indicator columns appended.

    Note:
        Requires either ta-lib or pandas-ta. Install with:
        `pip install TA-Lib` (requires C library) or `pip install pandas-ta`
    """
    if not HAS_TALIB and not HAS_PANDAS_TA:
        raise ImportError(
            "Extended indicators require either TA-Lib or pandas-ta. "
            "Install with: pip install TA-Lib (or pandas-ta)"
        )

    result = df.copy()

    # ADX
    adx_df = adx(result)
    result = pd.concat([result, adx_df], axis=1)

    # Stochastic
    stoch_df = stochastic(result)
    result = pd.concat([result, stoch_df], axis=1)

    # Williams %R
    result["williams_r"] = williams_r(result)

    # CCI
    result["cci"] = cci(result)

    # MFI
    result["mfi"] = mfi(result)

    # OBV
    result["obv"] = obv(result)

    # Ichimoku Cloud
    ichimoku_df = ichimoku(result)
    result = pd.concat([result, ichimoku_df], axis=1)

    return result
