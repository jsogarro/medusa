"""Equity data loader from kdb+ HDB using PyKX."""

from __future__ import annotations

import random
import re
import time
from datetime import datetime
from typing import Any

import pandas as pd
from loguru import logger

from medusa.data.q_safe import TIMEFRAMES, q_choice
from medusa.utils.config import KdbConfig, get_settings

_SYMBOL_RE = re.compile(r"[A-Z]{1,5}")  # Equity symbols: 1-5 uppercase letters


def _validate_equity_symbol(symbol: str) -> str:
    """Validate symbol is a valid US equity ticker."""
    if not _SYMBOL_RE.fullmatch(symbol):
        raise ValueError(
            f"Invalid equity symbol format: {symbol!r}. "
            "Must be 1-5 uppercase letters (e.g., AAPL, MSFT, SPY)"
        )
    # Additional defense: ensure symbol contains only alphabetic characters
    if not symbol.isalpha():
        raise ValueError(f"Symbol contains non-alphabetic characters: {symbol!r}")
    return symbol.upper()


class ResilientKdbConnection:
    """Wrapper around PyKX connection with auto-reconnect and query retry."""

    def __init__(
        self,
        host: str = "localhost",
        port: int = 5011,
        username: str | None = None,
        password: str | None = None,
        timeout: float = 5.0,
        max_retries: int = 3,
    ):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.timeout = timeout
        self.max_retries = max_retries
        self._conn: Any = None

    def connect(self) -> None:
        """Establish connection with retry."""
        for attempt in range(self.max_retries):
            try:
                import pykx as kx

                self._conn = kx.QConnection(
                    host=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    timeout=self.timeout,
                )
                logger.info(f"Connected to kdb+ at {self.host}:{self.port}")
                return
            except Exception as e:
                wait = 2**attempt + random.uniform(0, 1)
                logger.warning(
                    f"kdb+ connection failed (attempt {attempt + 1}/{self.max_retries}): {e}, "
                    f"retrying in {wait:.1f}s"
                )
                time.sleep(wait)
        raise ConnectionError(
            f"Failed to connect to kdb+ at {self.host}:{self.port} after {self.max_retries} attempts"
        )

    def disconnect(self) -> None:
        """Close connection."""
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.info("Disconnected from kdb+")

    def query(self, expr: str) -> Any:
        """Execute query with auto-reconnect on failure."""
        if self._conn is None:
            self.connect()
        try:
            return self._conn(expr)
        except Exception:
            logger.warning("kdb+ connection lost, reconnecting...")
            self._conn = None
            self.connect()
            return self._conn(expr)


class EquityKdbLoader:
    """Load equity data from kdb+ HDB via PyKX."""

    def __init__(self, config: KdbConfig | None = None) -> None:
        """Initialize kdb+ connection configuration.

        Args:
            config: KdbConfig instance (defaults to settings from config file)
        """
        self.config = config or get_settings().kdb
        self._resilient_conn: ResilientKdbConnection | None = None

    def connect(self, port: int | None = None) -> None:
        """Establish PyKX connection to kdb+ HDB.

        Args:
            port: Override port (defaults to hdb_port from config)
        """
        target_port = port or self.config.hdb_port
        self._resilient_conn = ResilientKdbConnection(
            host=self.config.host,
            port=target_port,
            username=self.config.username,
            password=self.config.password.get_secret_value(),
            timeout=self.config.timeout / 1000.0,
        )
        self._resilient_conn.connect()

    def disconnect(self) -> None:
        """Close kdb+ connection."""
        if self._resilient_conn is not None:
            self._resilient_conn.disconnect()
            self._resilient_conn = None

    def _ensure_connected(self) -> None:
        """Ensure connection is established."""
        if self._resilient_conn is None:
            self.connect()

    def query(self, q_expr: str) -> Any:
        """Execute a q expression and return PyKX result.

        Args:
            q_expr: q expression string

        Returns:
            PyKX result object
        """
        self._ensure_connected()
        assert self._resilient_conn is not None
        return self._resilient_conn.query(q_expr)

    def load_bars(
        self,
        symbol: str,
        start: str,
        end: str,
        timeframe: str = "1Day",
    ) -> pd.DataFrame:
        """Load equity bars from kdb+ equityBar table.

        Args:
            symbol: Stock symbol (e.g., "AAPL")
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)
            timeframe: Timeframe symbol (e.g., "1Min", "5Min", "1Hour", "1Day")

        Returns:
            DataFrame with columns: timestamp, open, high, low, close, volume, vwap, trade_count
        """
        _validate_equity_symbol(symbol)
        q_choice(timeframe, TIMEFRAMES, "timeframe")

        # Convert date strings to q date format (YYYY.MM.DD)
        start_dt = datetime.fromisoformat(start)
        end_dt = datetime.fromisoformat(end)
        sd = start_dt.strftime("%Y.%m.%d")
        ed = end_dt.strftime("%Y.%m.%d")

        # Construct q query
        # Note: equityBar schema has timestamp but no date column
        # Use timestamp.date for date filtering
        q_expr = (
            f"select timestamp, open, high, low, close, volume, vwap, tradeCount "
            f"from .schema.equityBar "
            f"where timestamp.date within ({sd};{ed}), sym=`{symbol}, timeframe=`{timeframe}"
        )

        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if df.empty:
            logger.warning(f"No bar data found for {symbol} ({start} to {end}, {timeframe})")
            return pd.DataFrame()

        # Rename columns to match Python naming conventions
        df = df.rename(columns={"tradeCount": "trade_count"})

        logger.info(f"Loaded {len(df)} bars for {symbol} ({timeframe})")
        return df

    def load_quotes(
        self,
        symbol: str,
        start: str,
        end: str,
    ) -> pd.DataFrame:
        """Load equity quotes from kdb+ equityQuote table.

        Args:
            symbol: Stock symbol
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)

        Returns:
            DataFrame with columns: timestamp, bid_price, bid_size, ask_price, ask_size, tape, conditions
        """
        _validate_equity_symbol(symbol)

        start_dt = datetime.fromisoformat(start)
        end_dt = datetime.fromisoformat(end)
        sd = start_dt.strftime("%Y.%m.%d")
        ed = end_dt.strftime("%Y.%m.%d")

        q_expr = (
            f"select timestamp, bidPrice, bidSize, askPrice, askSize, tape, conditions "
            f"from .schema.equityQuote "
            f"where timestamp.date within ({sd};{ed}), sym=`{symbol}"
        )

        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if df.empty:
            logger.warning(f"No quote data found for {symbol} ({start} to {end})")
            return pd.DataFrame()

        # Rename columns (convert camelCase to snake_case)
        df = df.rename(
            columns={
                "bidPrice": "bid_price",
                "bidSize": "bid_size",
                "askPrice": "ask_price",
                "askSize": "ask_size",
            }
        )

        logger.info(f"Loaded {len(df)} quotes for {symbol}")
        return df

    def load_trades(
        self,
        symbol: str,
        start: str,
        end: str,
    ) -> pd.DataFrame:
        """Load equity trades from kdb+ equityTrade table.

        Args:
            symbol: Stock symbol
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)

        Returns:
            DataFrame with columns: timestamp, price, size, trade_exchange, tape, conditions
        """
        _validate_equity_symbol(symbol)

        start_dt = datetime.fromisoformat(start)
        end_dt = datetime.fromisoformat(end)
        sd = start_dt.strftime("%Y.%m.%d")
        ed = end_dt.strftime("%Y.%m.%d")

        q_expr = (
            f"select timestamp, price, size, tradeExchange, tape, conditions "
            f"from .schema.equityTrade "
            f"where timestamp.date within ({sd};{ed}), sym=`{symbol}"
        )

        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if df.empty:
            logger.warning(f"No trade data found for {symbol} ({start} to {end})")
            return pd.DataFrame()

        # Rename columns
        df = df.rename(columns={"tradeExchange": "trade_exchange"})

        logger.info(f"Loaded {len(df)} trades for {symbol}")
        return df

    def load_metadata(self, symbol: str) -> dict[str, Any]:
        """Load company metadata from kdb+ equityMetadata table.

        Args:
            symbol: Stock symbol

        Returns:
            Dictionary with metadata fields
        """
        _validate_equity_symbol(symbol)

        q_expr = f"first select from .schema.equityMetadata where sym=`{symbol}"

        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if df.empty:
            logger.warning(f"No metadata found for {symbol}")
            return {}

        # Convert to dict (first row)
        metadata = df.iloc[0].to_dict()

        # Rename camelCase keys to snake_case
        metadata = {
            "symbol": metadata.get("sym"),
            "name": metadata.get("name"),
            "asset_class": metadata.get("assetClass"),
            "exchange": metadata.get("exchange"),
            "sector": metadata.get("sector"),
            "industry": metadata.get("industry"),
            "market_cap": metadata.get("marketCap"),
            "dividend_yield": metadata.get("dividendYield"),
            "pe_ratio": metadata.get("peRatio"),
            "beta": metadata.get("beta"),
            "avg_volume_30d": metadata.get("avgVolume30d"),
            "updated_at": metadata.get("updatedAt"),
        }

        logger.info(f"Loaded metadata for {symbol}")
        return metadata

    def load_positions(self) -> pd.DataFrame:
        """Load all equity positions from kdb+ equityPosition table.

        Returns:
            DataFrame with columns: sym, quantity, avg_entry_price, market_value,
                                    unrealized_pnl, side, margin_used, updated_at
        """
        q_expr = "select from .schema.equityPosition"

        result = self.query(q_expr)
        df: pd.DataFrame = result.pd()

        if df.empty:
            logger.info("No equity positions found")
            return pd.DataFrame()

        # Rename columns
        df = df.rename(
            columns={
                "sym": "symbol",
                "avgEntryPrice": "avg_entry_price",
                "marketValue": "market_value",
                "unrealizedPnL": "unrealized_pnl",
                "marginUsed": "margin_used",
                "updatedAt": "updated_at",
            }
        )

        logger.info(f"Loaded {len(df)} equity positions")
        return df
