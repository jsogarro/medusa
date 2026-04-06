"""PyKX Tickerplant subscriber for real-time market data."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import pandas as pd
from loguru import logger

from medusa.utils.config import get_settings


class TickSubscriber:
    """Subscribe to Medusa tickerplant for real-time data via PyKX."""

    def __init__(
        self,
        tp_host: str | None = None,
        tp_port: int | None = None,
    ) -> None:
        config = get_settings().kdb
        self.tp_host = tp_host or config.host
        self.tp_port = tp_port or config.tp_port
        self._conn: Any = None
        self._handlers: dict[str, Callable[[pd.DataFrame], None]] = {}

    def connect(self) -> None:
        """Establish connection to tickerplant."""
        import pykx as kx

        self._conn = kx.QConnection(host=self.tp_host, port=self.tp_port)
        logger.info(f"Connected to TP at {self.tp_host}:{self.tp_port}")

    def disconnect(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.info("Disconnected from TP")

    def subscribe(
        self,
        table: str,
        symbols: list[str] | None = None,
    ) -> None:
        """Subscribe to a tickerplant table.

        Args:
            table: Table name (e.g. 'marketData', 'tradeEvent').
            symbols: Symbols to subscribe (None = all).
        """
        if self._conn is None:
            self.connect()

        if symbols:
            sym_str = "`" + "` `".join(symbols)
            self._conn(f".u.sub[`{table}; `{sym_str}]")
        else:
            self._conn(f".u.sub[`{table}; `]")

        logger.info(f"Subscribed to {table}: {symbols or 'ALL'}")

    def register_handler(
        self,
        table: str,
        handler: Callable[[pd.DataFrame], None],
    ) -> None:
        """Register a callback for table updates.

        Args:
            table: Table name.
            handler: Callback receiving a pandas DataFrame of new rows.
        """
        self._handlers[table] = handler
        logger.info(f"Registered handler for {table}")

    def on_update(self, table: str, data: Any) -> None:
        """Handle incoming tickerplant update.

        Args:
            table: Updated table name.
            data: PyKX Table object with new rows.
        """
        if table in self._handlers:
            df: pd.DataFrame = data.pd()
            self._handlers[table](df)

    def start(self) -> None:
        """Start listening for updates (blocking).

        Press Ctrl+C to stop.
        """
        if self._conn is None:
            self.connect()

        logger.info("Listening for TP updates (Ctrl+C to stop)...")
        try:
            while True:
                try:
                    msg = self._conn.poll()
                    if msg is not None:
                        table_name, update_data = msg
                        self.on_update(str(table_name), update_data)
                except Exception as e:
                    logger.error(f"Error processing TP message: {e}")
        except KeyboardInterrupt:
            logger.info("Stopped TP listener")
            self.disconnect()
