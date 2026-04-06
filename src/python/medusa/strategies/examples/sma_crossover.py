"""Simple SMA crossover strategy for VectorBT research."""

from __future__ import annotations

from typing import Any

import pandas as pd

from medusa.strategies.base import BaseStrategy


def sma_crossover_signals(
    price: pd.Series,
    fast_period: int = 10,
    slow_period: int = 50,
) -> tuple[pd.Series, pd.Series]:
    """Generate SMA crossover entry/exit signals.

    Args:
        price: Price series (typically close prices).
        fast_period: Fast SMA lookback.
        slow_period: Slow SMA lookback.

    Returns:
        Tuple of (entries, exits) as boolean Series.
    """
    fast_sma = price.rolling(fast_period).mean()
    slow_sma = price.rolling(slow_period).mean()

    entries = (fast_sma > slow_sma) & (fast_sma.shift(1) <= slow_sma.shift(1))
    exits = (fast_sma < slow_sma) & (fast_sma.shift(1) >= slow_sma.shift(1))

    return entries.fillna(False), exits.fillna(False)


class SMACrossoverStrategy(BaseStrategy):
    """SMA crossover strategy implementation."""

    def __init__(self, fast_period: int = 10, slow_period: int = 50) -> None:
        self.fast_period = fast_period
        self.slow_period = slow_period

    def generate_signals(
        self, data: pd.DataFrame
    ) -> tuple[pd.Series, pd.Series]:
        price = data["close"] if "close" in data.columns else data.iloc[:, 0]
        return sma_crossover_signals(price, self.fast_period, self.slow_period)

    def generate_signal(self, data: pd.DataFrame) -> dict[str, Any] | None:
        if len(data) < self.slow_period + 1:
            return None

        price = data["close"] if "close" in data.columns else data.iloc[:, 0]
        fast = price.rolling(self.fast_period).mean()
        slow = price.rolling(self.slow_period).mean()

        if fast.iloc[-1] > slow.iloc[-1] and fast.iloc[-2] <= slow.iloc[-2]:
            return {"action": "buy", "price": float(price.iloc[-1]), "size": 1.0}
        if fast.iloc[-1] < slow.iloc[-1] and fast.iloc[-2] >= slow.iloc[-2]:
            return {"action": "sell", "price": float(price.iloc[-1]), "size": 1.0}

        return None
