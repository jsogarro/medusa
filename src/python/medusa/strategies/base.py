"""Base strategy interface for Medusa backtesting."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

import pandas as pd


class BaseStrategy(ABC):
    """Abstract base class for trading strategies."""

    @abstractmethod
    def generate_signals(
        self, data: pd.DataFrame
    ) -> tuple[pd.Series, pd.Series]:
        """Generate entry/exit signals from market data.

        Args:
            data: OHLCV DataFrame.

        Returns:
            Tuple of (entries, exits) as boolean Series.
        """
        ...

    @abstractmethod
    def generate_signal(self, data: pd.DataFrame) -> dict[str, Any] | None:
        """Generate a single signal from the latest data (for live use).

        Args:
            data: Recent market data buffer.

        Returns:
            Signal dict with keys: action, price, size, or None if no signal.
        """
        ...
