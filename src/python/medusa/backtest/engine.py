"""Core backtesting engine."""

from __future__ import annotations

from typing import Any

import pandas as pd


class Backtester:
    """Backtest trading strategies against historical data."""

    def __init__(self, initial_capital: float = 100_000.0) -> None:
        self.initial_capital = initial_capital
        self.current_capital = initial_capital
        self.positions: dict[str, float] = {}

    def run(self, data: pd.DataFrame, strategy: Any) -> pd.DataFrame:
        """Run backtest on historical data.

        Args:
            data: Historical price data (OHLCV).
            strategy: Strategy instance with generate_signals() method.

        Returns:
            DataFrame with backtest results.
        """
        raise NotImplementedError("Backtesting engine not yet implemented")
