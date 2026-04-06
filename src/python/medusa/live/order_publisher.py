"""Publish order events to Medusa tickerplant from Python."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from loguru import logger

from medusa.utils.config import get_settings


class OrderPublisher:
    """Publish order events to the Medusa tickerplant via PyKX."""

    def __init__(
        self,
        tp_host: str | None = None,
        tp_port: int | None = None,
    ) -> None:
        config = get_settings().kdb
        self.tp_host = tp_host or config.host
        self.tp_port = tp_port or config.tp_port
        self._conn: Any = None

    def connect(self) -> None:
        import pykx as kx

        self._conn = kx.QConnection(host=self.tp_host, port=self.tp_port)
        logger.info(f"OrderPublisher connected to TP at {self.tp_host}:{self.tp_port}")

    def disconnect(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.info("OrderPublisher disconnected from TP")

    def publish_order(
        self,
        order_id: int,
        exchange: str,
        symbol: str,
        side: str,
        order_type: str,
        price: int,
        volume: int,
        actor: str,
    ) -> None:
        """Publish an order event to the tickerplant.

        Args:
            order_id: Internal order ID.
            exchange: Target exchange (e.g. 'coinbase').
            symbol: Trading pair (e.g. 'BTCUSD').
            side: 'buy' or 'sell'.
            order_type: 'market' or 'limit'.
            price: Price in fixed-precision long format.
            volume: Volume in fixed-precision long format.
            actor: Strategy name submitting the order.
        """
        if self._conn is None:
            self.connect()

        try:
            now = datetime.now(UTC).strftime("%Y.%m.%dD%H:%M:%S.%f")
            q_expr = (
                f".u.upd[`orderEvent; "
                f"({now}; {order_id}j; `; `{exchange}; `{symbol}; "
                f"`{side}; `{order_type}; {price}j; {volume}j; "
                f"`pending; `{actor})]"
            )
            self._conn(q_expr)
            logger.info(
                f"Published order {order_id}: {symbol} {side} {order_type} "
                f"@ {price} vol={volume} actor={actor}"
            )
        except Exception as e:
            logger.error(f"Failed to publish order {order_id}: {e}")
            raise

    def __enter__(self) -> OrderPublisher:
        self.connect()
        return self

    def __exit__(self, *args: Any) -> None:
        self.disconnect()
