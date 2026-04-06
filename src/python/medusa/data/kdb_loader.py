"""kdb+ data loader using PyKX for zero-copy data transfer."""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

import pandas as pd
from loguru import logger

from medusa.utils.config import KdbConfig, get_settings

_SYMBOL_RE = re.compile(r"^[A-Za-z0-9._]{1,30}$")
_INTERVAL_WHITELIST = {"1m", "5m", "15m", "1h", "4h", "1d"}


def _validate_symbol(symbol: str) -> str:
    """Validate symbol contains only safe characters for q queries."""
    if not _SYMBOL_RE.match(symbol):
        raise ValueError(f"Invalid symbol format: {symbol!r}")
    return symbol


class KdbDataLoader:
    """Load historical data from kdb+ HDB/RDB using PyKX."""

    def __init__(self, config: KdbConfig | None = None) -> None:
        self.config = config or get_settings().kdb
        self._conn: Any = None

    def connect(self, port: int | None = None) -> None:
        """Establish PyKX connection to a kdb+ process.

        Args:
            port: Override port (defaults to hdb_port from config).
        """
        import pykx as kx

        target_port = port or self.config.hdb_port
        self._conn = kx.QConnection(
            host=self.config.host,
            port=target_port,
            username=self.config.username or None,
            password=self.config.password or None,
            timeout=self.config.timeout / 1000.0,
        )
        logger.info(f"Connected to kdb+ at {self.config.host}:{target_port}")

    def disconnect(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.info("Disconnected from kdb+")

    def _ensure_connected(self) -> None:
        if self._conn is None:
            self.connect()

    def query(self, q_expr: str) -> Any:
        """Execute a q expression and return the raw PyKX result."""
        self._ensure_connected()
        result = self._conn(q_expr)
        return result

    def load_trades(
        self,
        symbol: str,
        start_date: datetime,
        end_date: datetime,
    ) -> pd.DataFrame:
        """Load trade data from kdb+ HDB.

        Returns:
            DataFrame with columns: timestamp, price, size, side
        """
        _validate_symbol(symbol)
        sd = start_date.strftime("%Y.%m.%d")
        ed = end_date.strftime("%Y.%m.%d")
        q_expr = (
            f"select time, price, volume, side from tradeEvent "
            f"where date within ({sd};{ed}), sym=`{symbol}"
        )
        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()
        df = df.rename(columns={"time": "timestamp", "volume": "size"})
        logger.info(f"Loaded {len(df)} trades for {symbol}")
        return df

    def load_quotes(
        self,
        symbol: str,
        start_date: datetime,
        end_date: datetime,
    ) -> pd.DataFrame:
        """Load quote data from kdb+ HDB.

        Returns:
            DataFrame with columns: timestamp, bid_price, bid_size, ask_price, ask_size
        """
        _validate_symbol(symbol)
        sd = start_date.strftime("%Y.%m.%d")
        ed = end_date.strftime("%Y.%m.%d")
        q_expr = (
            f"select time, bid, bidSize, ask, askSize from marketData "
            f"where date within ({sd};{ed}), sym=`{symbol}"
        )
        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()
        df = df.rename(columns={
            "time": "timestamp",
            "bid": "bid_price",
            "bidSize": "bid_size",
            "ask": "ask_price",
            "askSize": "ask_size",
        })
        logger.info(f"Loaded {len(df)} quotes for {symbol}")
        return df

    def load_ohlcv(
        self,
        symbol: str,
        start_date: datetime,
        end_date: datetime,
        interval: str = "1m",
    ) -> pd.DataFrame:
        """Load OHLCV bars from kdb+ HDB.

        Args:
            symbol: Trading symbol (e.g. 'BTCUSDT').
            start_date: Start of date range.
            end_date: End of date range.
            interval: Bar interval ('1m', '5m', '15m', '1h', '1d').

        Returns:
            DataFrame with columns: timestamp, open, high, low, close, volume
        """
        _validate_symbol(symbol)
        interval_map = {
            "1m": "00:01:00",
            "5m": "00:05:00",
            "15m": "00:15:00",
            "1h": "01:00:00",
            "4h": "04:00:00",
        }
        if interval not in interval_map:
            raise ValueError(f"Unsupported interval: {interval!r}. Use one of: {sorted(interval_map)}")
        kdb_interval = interval_map[interval]

        sd = start_date.strftime("%Y.%m.%d")
        ed = end_date.strftime("%Y.%m.%d")

        q_expr = (
            f"select open: first price, high: max price, low: min price, "
            f"close: last price, volume: sum size "
            f"by timestamp: {kdb_interval} xbar time "
            f"from tradeEvent "
            f"where date within ({sd};{ed}), sym=`{symbol}"
        )
        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if "timestamp" not in df.columns and df.index.name == "timestamp":
            df = df.reset_index()

        logger.info(f"Loaded {len(df)} {interval} bars for {symbol}")
        return df

    def __enter__(self) -> KdbDataLoader:
        self.connect()
        return self

    def __exit__(self, *args: Any) -> None:
        self.disconnect()
