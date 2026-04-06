"""Live signal testing with tickerplant data (paper trading)."""

from __future__ import annotations

from typing import Any

import pandas as pd
from loguru import logger

from medusa.live.tick_subscriber import TickSubscriber
from medusa.strategies.base import BaseStrategy


class LiveSignalTester:
    """Test trading signals on live tickerplant data.

    Subscribes to marketData, buffers recent prices, and generates
    signals using a Medusa strategy. Signals are logged (paper trading)
    rather than submitted as real orders.
    """

    def __init__(
        self,
        strategy: BaseStrategy,
        tp_host: str | None = None,
        tp_port: int | None = None,
        buffer_size: int = 1000,
    ) -> None:
        """Initialize live signal tester.

        Args:
            strategy: Trading strategy to test.
            tp_host: Tickerplant host.
            tp_port: Tickerplant port.
            buffer_size: Max rows to keep per symbol in buffer.
        """
        self.strategy = strategy
        self.subscriber = TickSubscriber(tp_host, tp_port)
        self.buffer_size = buffer_size
        self._price_buffer: dict[str, pd.DataFrame] = {}
        self._signal_log: list[dict[str, Any]] = []

    def on_market_data(self, df: pd.DataFrame) -> None:
        """Handle market data updates from tickerplant.

        Args:
            df: New market data rows.
        """
        for sym in df["sym"].unique():
            sym_data = df[df["sym"] == sym].copy()
            sym_str = str(sym)

            if sym_str not in self._price_buffer:
                self._price_buffer[sym_str] = sym_data
            else:
                self._price_buffer[sym_str] = pd.concat(
                    [self._price_buffer[sym_str], sym_data]
                ).tail(self.buffer_size)

            signal = self.strategy.generate_signal(self._price_buffer[sym_str])
            if signal is not None:
                signal["symbol"] = sym_str
                self._signal_log.append(signal)
                logger.info(f"Signal: {sym_str} {signal}")

    def run(self, symbols: list[str]) -> None:
        """Start live signal testing (blocking).

        Args:
            symbols: Symbols to subscribe to.
        """
        logger.info(f"Starting live signal test: {symbols}")
        self.subscriber.subscribe("marketData", symbols=symbols)
        self.subscriber.register_handler("marketData", self.on_market_data)
        self.subscriber.start()

    @property
    def signals(self) -> list[dict[str, Any]]:
        """All signals generated during the session."""
        return self._signal_log
