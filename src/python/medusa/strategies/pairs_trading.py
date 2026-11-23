"""Cointegration-based pairs trading strategy.

Entry: Z-score of spread > 2.0 (short) or < -2.0 (long)
Exit: Z-score crosses zero (mean reversion)
Pairs: BTC/ETH, SOL/AVAX, or user-defined

Reference:
    "Statistical Arbitrage in Cryptocurrencies" by Johnny Tung
    Ernest Chan's "Algorithmic Trading"
"""

from __future__ import annotations

from typing import Any

import pandas as pd

from medusa.features.cross_asset_features import (
    cointegration_test,
    spread,
    z_score_spread,
)
from medusa.strategies.base import BaseStrategy


class PairsTradingStrategy(BaseStrategy):
    """Cointegration-based pairs trading strategy.

    Identifies cointegrated asset pairs and trades mean reversion of the spread.
    """

    def __init__(
        self,
        asset1: str,
        asset2: str,
        entry_zscore: float = 2.0,
        exit_zscore: float = 0.0,
        stop_zscore: float = 3.0,
        lookback: int = 252,
        spread_window: int = 60,
        retest_period: int = 30,
    ) -> None:
        """Initialize pairs trading strategy.

        Args:
            asset1: First asset symbol.
            asset2: Second asset symbol.
            entry_zscore: Z-score threshold for entry (±). Default 2.0.
            exit_zscore: Z-score for mean reversion exit. Default 0.0.
            stop_zscore: Z-score for stop loss (±). Default 3.0.
            lookback: Days of history for cointegration test. Default 252.
            spread_window: Rolling window for spread z-score. Default 60.
            retest_period: Days between cointegration re-tests. Default 30.
        """
        self.asset1 = asset1
        self.asset2 = asset2
        self.entry_zscore = entry_zscore
        self.exit_zscore = exit_zscore
        self.stop_zscore = stop_zscore
        self.lookback = lookback
        self.spread_window = spread_window
        self.retest_period = retest_period

        self._hedge_ratio: float | None = None
        self._last_retest_date: pd.Timestamp | None = None
        self._is_cointegrated = False

    def _update_cointegration(
        self,
        price1: pd.Series,
        price2: pd.Series,
    ) -> None:
        """Run cointegration test and update hedge ratio.

        Args:
            price1: First asset price series.
            price2: Second asset price series.
        """
        result = cointegration_test(price1, price2, significance=0.05)
        self._is_cointegrated = result.is_cointegrated
        self._hedge_ratio = result.hedge_ratio if result.is_cointegrated else None
        self._last_retest_date = price1.index[-1]

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate entry/exit signals from dual-asset data.

        Args:
            data: DataFrame with MultiIndex columns (asset, field).
                  Example: columns = [('BTC', 'close'), ('ETH', 'close')]
                  OR DataFrame with 'close_asset1', 'close_asset2' columns.

        Returns:
            Tuple of (entries, exits) as boolean Series.
        """
        # Extract price series for both assets
        if isinstance(data.columns, pd.MultiIndex):
            price1 = data[(self.asset1, "close")]
            price2 = data[(self.asset2, "close")]
        else:
            # Fallback: assume columns are 'close_asset1', 'close_asset2'
            price1 = data.get(f"close_{self.asset1}", data.get("close_1"))
            price2 = data.get(f"close_{self.asset2}", data.get("close_2"))

        # Guard against missing columns
        if price1 is None or price2 is None:
            return (
                pd.Series(False, index=data.index),
                pd.Series(False, index=data.index),
            )

        # Test cointegration if not tested or retest period elapsed
        should_retest = (
            self._hedge_ratio is None
            or self._last_retest_date is None
            or (price1.index[-1] - self._last_retest_date).days >= self.retest_period
        )

        if should_retest and len(price1) >= self.lookback:
            self._update_cointegration(
                price1.iloc[-self.lookback :],
                price2.iloc[-self.lookback :],
            )

        # If not cointegrated, no trading
        if not self._is_cointegrated or self._hedge_ratio is None:
            return (
                pd.Series(False, index=data.index),
                pd.Series(False, index=data.index),
            )

        # Calculate spread and z-score
        spread_series = spread(price1, price2, self._hedge_ratio)
        zscore = z_score_spread(spread_series, window=self.spread_window)

        # Entry signals
        # Long spread (buy asset1, sell asset2) when z < -entry_zscore
        long_spread_entry = zscore < -self.entry_zscore
        # Short spread (sell asset1, buy asset2) when z > +entry_zscore
        short_spread_entry = zscore > self.entry_zscore

        entries = long_spread_entry | short_spread_entry

        # Exit signals
        # Mean reversion: z-score crosses zero
        mean_reversion = zscore.abs() < self.exit_zscore
        # Stop loss: z-score exceeds stop threshold (cointegration breakdown)
        stop_loss = zscore.abs() > self.stop_zscore

        exits = mean_reversion | stop_loss

        return entries, exits

    def generate_signal(
        self,
        data: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """Generate a single signal from the latest data (for live use).

        Args:
            data: Recent market data buffer for both assets.

        Returns:
            Signal dict with keys: action, price, size, side, or None if no signal.
        """
        if len(data) < self.lookback + self.spread_window:
            return None  # Not enough data

        entries, exits = self.generate_signals(data)

        # Extract latest prices
        if isinstance(data.columns, pd.MultiIndex):
            latest_price1 = data[(self.asset1, "close")].iloc[-1]
            latest_price2 = data[(self.asset2, "close")].iloc[-1]
        else:
            latest_price1 = data.get(f"close_{self.asset1}", data.get("close_1")).iloc[-1]
            latest_price2 = data.get(f"close_{self.asset2}", data.get("close_2")).iloc[-1]

        # Get spread z-score
        if isinstance(data.columns, pd.MultiIndex):
            price1 = data[(self.asset1, "close")]
            price2 = data[(self.asset2, "close")]
        else:
            price1 = data.get(f"close_{self.asset1}", data.get("close_1"))
            price2 = data.get(f"close_{self.asset2}", data.get("close_2"))

        if self._hedge_ratio is None:
            return None

        spread_series = spread(price1, price2, self._hedge_ratio)
        zscore = z_score_spread(spread_series, window=self.spread_window)
        latest_zscore = zscore.iloc[-1]

        latest_entry = entries.iloc[-1]
        latest_exit = exits.iloc[-1]

        if latest_entry and not latest_exit:
            # Determine direction based on z-score
            if latest_zscore < -self.entry_zscore:
                # Long spread: buy asset1, sell asset2
                return {
                    "action": "LONG_SPREAD",
                    "asset1": self.asset1,
                    "asset2": self.asset2,
                    "price1": latest_price1,
                    "price2": latest_price2,
                    "hedge_ratio": self._hedge_ratio,
                    "zscore": latest_zscore,
                }
            elif latest_zscore > self.entry_zscore:
                # Short spread: sell asset1, buy asset2
                return {
                    "action": "SHORT_SPREAD",
                    "asset1": self.asset1,
                    "asset2": self.asset2,
                    "price1": latest_price1,
                    "price2": latest_price2,
                    "hedge_ratio": self._hedge_ratio,
                    "zscore": latest_zscore,
                }
        elif latest_exit:
            return {
                "action": "CLOSE_SPREAD",
                "asset1": self.asset1,
                "asset2": self.asset2,
                "zscore": latest_zscore,
            }

        return None
