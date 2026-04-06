"""Legacy data loader — DEPRECATED. Use kdb_loader.py instead."""

from __future__ import annotations

from datetime import datetime

import pandas as pd


class DataLoader:
    """Load historical market data for backtesting.

    Connects to a kdb+ tick database via PyKX (Wave 8 implementation) to
    retrieve historical OHLCV data. Designed for efficient loading of large
    datasets (millions of rows).

    Attributes:
        kdb_host: Hostname or IP of the kdb+ server.
        kdb_port: Port number for kdb+ IPC connection.
    """

    def __init__(self, kdb_host: str = "localhost", kdb_port: int = 5000) -> None:
        """Initialize data loader with kdb+ connection parameters.

        Args:
            kdb_host: Hostname or IP of kdb+ server (default: localhost).
            kdb_port: Port number for kdb+ IPC (default: 5000).
        """
        self.kdb_host = kdb_host
        self.kdb_port = kdb_port

    def load_ohlcv(
        self,
        symbol: str,
        start: datetime | str,
        end: datetime | str,
    ) -> pd.DataFrame:
        """Load OHLCV data for a symbol within a date range.

        Args:
            symbol: Trading pair symbol (e.g., "BTCUSD", "ETHUSD").
            start: Start datetime (datetime object or ISO 8601 string).
            end: End datetime (datetime object or ISO 8601 string).

        Returns:
            DataFrame with columns: timestamp (datetime64[ns]), open (float64),
            high (float64), low (float64), close (float64), volume (float64).
            Sorted ascending by timestamp. Empty DataFrame if no data found.

        Raises:
            NotImplementedError: PyKX integration implemented in Wave 8.
            ValueError: If start >= end or symbol format is invalid.
            ConnectionError: If kdb+ connection fails (Wave 8).

        Note:
            When implemented, this will use PyKX's q() interface to execute
            kdb+ queries against the HDB (Historical Database) for the
            specified symbol and date range.
        """
        raise NotImplementedError("kdb+ data loading not yet implemented")
