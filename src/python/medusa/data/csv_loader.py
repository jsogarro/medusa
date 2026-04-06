"""CSV data loader for research datasets."""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from loguru import logger

REQUIRED_OHLCV_COLS = ["open", "high", "low", "close", "volume"]


class CsvDataLoader:
    """Load OHLCV data from CSV files."""

    @staticmethod
    def load_ohlcv(
        csv_path: Path | str,
        timestamp_col: str = "timestamp",
    ) -> pd.DataFrame:
        """Load OHLCV data from CSV.

        Args:
            csv_path: Path to CSV file.
            timestamp_col: Name of the timestamp column.

        Returns:
            DataFrame indexed by timestamp with OHLCV columns.

        Raises:
            FileNotFoundError: If csv_path does not exist.
            ValueError: If required columns are missing.
        """
        path = Path(csv_path)
        if not path.exists():
            raise FileNotFoundError(f"CSV file not found: {path}")

        df = pd.read_csv(path, parse_dates=[timestamp_col])
        df = df.set_index(timestamp_col).sort_index()

        missing = [c for c in REQUIRED_OHLCV_COLS if c not in df.columns]
        if missing:
            raise ValueError(f"CSV missing required columns: {missing}")

        logger.info(f"Loaded {len(df)} rows from {path.name}")
        return df
