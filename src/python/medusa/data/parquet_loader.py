"""Parquet data loader using Polars for high-performance reads."""

from __future__ import annotations

from pathlib import Path

import polars as pl
from loguru import logger

REQUIRED_OHLCV_COLS = ["timestamp", "open", "high", "low", "close", "volume"]


class ParquetDataLoader:
    """Load OHLCV data from Parquet files using Polars."""

    @staticmethod
    def load_ohlcv(parquet_path: Path | str) -> pl.DataFrame:
        """Load OHLCV data from Parquet.

        Args:
            parquet_path: Path to Parquet file.

        Returns:
            Polars DataFrame sorted by timestamp.

        Raises:
            FileNotFoundError: If parquet_path does not exist.
            ValueError: If required columns are missing.
        """
        path = Path(parquet_path)
        if not path.exists():
            raise FileNotFoundError(f"Parquet file not found: {path}")

        df = pl.read_parquet(path)

        missing = [c for c in REQUIRED_OHLCV_COLS if c not in df.columns]
        if missing:
            raise ValueError(f"Parquet missing required columns: {missing}")

        df = df.sort("timestamp")
        logger.info(f"Loaded {len(df)} rows from {path.name}")
        return df
