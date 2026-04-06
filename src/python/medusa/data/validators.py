"""Data validation utilities for market data."""

from __future__ import annotations

from typing import Any

import pandas as pd
from loguru import logger

REQUIRED_OHLCV = ["open", "high", "low", "close", "volume"]


def validate_ohlcv(df: pd.DataFrame) -> None:
    """Validate OHLCV DataFrame.

    Checks required columns, NaN in OHLC, High >= Low, Volume >= 0,
    and monotonic timestamp index.

    Raises:
        ValueError: If any validation check fails.
    """
    missing = [c for c in REQUIRED_OHLCV if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    ohlc = df[["open", "high", "low", "close"]]
    if ohlc.isna().any().any():
        nan_counts = ohlc.isna().sum()
        raise ValueError(f"OHLC columns contain NaN values: {nan_counts.to_dict()}")

    violations = df["high"] < df["low"]
    if violations.any():
        raise ValueError(f"High < Low in {violations.sum()} rows")

    neg_vol = df["volume"] < 0
    if neg_vol.any():
        raise ValueError(f"Negative volume in {neg_vol.sum()} rows")

    if hasattr(df.index, "is_monotonic_increasing"):
        if not df.index.is_monotonic_increasing:
            raise ValueError("Index is not sorted (monotonic increasing)")

    logger.info(f"OHLCV validation passed ({len(df)} rows)")


def check_data_quality(df: pd.DataFrame) -> dict[str, Any]:
    """Generate data quality report.

    Returns:
        Dictionary with quality metrics.
    """
    report: dict[str, Any] = {
        "rows": len(df),
        "columns": list(df.columns),
        "start": df.index[0] if len(df) > 0 else None,
        "end": df.index[-1] if len(df) > 0 else None,
        "missing_values": df.isna().sum().to_dict(),
        "duplicate_index": int(df.index.duplicated().sum()),
    }

    if "close" in df.columns:
        report["price_range"] = (float(df["close"].min()), float(df["close"].max()))

    if "volume" in df.columns:
        report["mean_volume"] = float(df["volume"].mean())
        report["zero_volume_bars"] = int((df["volume"] == 0).sum())

    return report
