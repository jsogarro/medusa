"""Data loading from kdb+ and other sources."""

from __future__ import annotations

import pandas as pd


class DataLoader:
    """Load historical market data for backtesting."""

    def __init__(self, kdb_host: str = "localhost", kdb_port: int = 5000) -> None:
        self.kdb_host = kdb_host
        self.kdb_port = kdb_port

    def load_ohlcv(self, symbol: str, start: str, end: str) -> pd.DataFrame:
        """Load OHLCV data for a symbol.

        Args:
            symbol: Trading pair (e.g., "BTCUSD").
            start: Start date (ISO format).
            end: End date (ISO format).

        Returns:
            DataFrame with columns: timestamp, open, high, low, close, volume.
        """
        raise NotImplementedError("kdb+ data loading not yet implemented")
