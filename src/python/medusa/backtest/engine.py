"""Core backtesting engine."""

from __future__ import annotations

from typing import Protocol

import pandas as pd


class Strategy(Protocol):
    """Protocol defining the strategy interface for backtesting.

    Any strategy class must implement the generate_signals method to be
    compatible with the Backtester.
    """

    def generate_signals(self, data: pd.DataFrame) -> pd.DataFrame:
        """Generate trading signals from market data.

        Args:
            data: Historical price data (OHLCV format).

        Returns:
            DataFrame with trading signals (timestamp, signal, size).
        """
        ...


class Backtester:
    """Backtest trading strategies against historical data.

    The backtester simulates trading a strategy against historical OHLCV data,
    tracking capital, positions, and performance metrics. Designed to handle
    large DataFrames efficiently (millions of rows).

    Attributes:
        initial_capital: Starting capital in USD.
        current_capital: Current available capital after all trades.
        positions: Current holdings by symbol (symbol -> quantity).
    """

    def __init__(self, initial_capital: float = 100_000.0) -> None:
        """Initialize backtester with starting capital.

        Args:
            initial_capital: Starting capital in USD (default: $100,000).
        """
        self.initial_capital = initial_capital
        self.current_capital = initial_capital
        self.positions: dict[str, float] = {}

    def run(self, data: pd.DataFrame, strategy: Strategy) -> pd.DataFrame:
        """Run backtest on historical data.

        Args:
            data: Historical price data with columns: timestamp, open, high,
                low, close, volume. Must be sorted by timestamp.
            strategy: Strategy instance implementing generate_signals().

        Returns:
            DataFrame with backtest results including: timestamp, capital,
            positions, trades, pnl, and performance metrics.

        Raises:
            NotImplementedError: Full backtesting logic implemented in Wave 8.
        """
        raise NotImplementedError("Backtesting engine not yet implemented")
