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

import numpy as np
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
            retest_period: Bars between cointegration re-fits. Default 30.
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

    def _rolling_hedge_ratio(self, price1: pd.Series, price2: pd.Series) -> pd.Series:
        """Walk-forward hedge ratio: each bar uses only data before it.

        The cointegration test is refit every ``retest_period`` bars on the
        trailing ``lookback`` bars; the result applies from the next bar on.
        Bars before the first fit, and bars in a non-cointegrated segment, are NaN.
        """
        ratio = pd.Series(np.nan, index=price1.index)
        step = max(self.retest_period, 1)
        for end in range(self.lookback, len(price1), step):
            result = cointegration_test(
                price1.iloc[end - self.lookback : end],
                price2.iloc[end - self.lookback : end],
                significance=0.05,
            )
            self._is_cointegrated = result.is_cointegrated
            self._last_retest_date = price1.index[end - 1]
            if result.is_cointegrated:
                ratio.iloc[end : end + step] = result.hedge_ratio
        return ratio

    def _spread_signals(
        self, data: pd.DataFrame
    ) -> tuple[pd.Series, pd.Series, pd.Series, pd.Series]:
        """Return (long entries, long exits, short entries, short exits) for the spread.

        Long spread (buy asset1) opens at z < -entry; short spread (sell asset1) at z > +entry.
        A position always has a way out: whenever the spread is undefined (no hedge ratio,
        e.g. cointegration broke) both exit series fire.
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
            none = pd.Series(False, index=data.index)
            return none, none, none, none

        hedge_ratio = self._rolling_hedge_ratio(price1, price2)
        valid = hedge_ratio.notna()
        self._hedge_ratio = float(hedge_ratio[valid].iloc[-1]) if valid.any() else None

        # If never cointegrated, no trading
        if not valid.any():
            none = pd.Series(False, index=data.index)
            return none, none, none, none

        # Spread uses the hedge ratio in force at each bar (no look-ahead)
        spread_series = price1 - hedge_ratio * price2
        zscore = z_score_spread(spread_series, window=self.spread_window)

        undefined = zscore.isna()
        # Stop loss: z-score beyond the stop threshold (cointegration breakdown); no entry there
        stop_loss = zscore.abs() > self.stop_zscore
        tradable = valid & ~undefined & ~stop_loss

        long_entries = (zscore < -self.entry_zscore) & tradable
        short_entries = (zscore > self.entry_zscore) & tradable
        # Mean reversion: z-score is back at the exit level (zero by default) from its entry side
        long_exits = (zscore >= -self.exit_zscore) | stop_loss | undefined
        short_exits = (zscore <= self.exit_zscore) | stop_loss | undefined

        return long_entries, long_exits, short_entries, short_exits

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate long-spread entry/exit signals from dual-asset data.

        Args:
            data: DataFrame with MultiIndex columns (asset, field).
                  Example: columns = [('BTC', 'close'), ('ETH', 'close')]
                  OR DataFrame with 'close_asset1', 'close_asset2' columns.

        Returns:
            Tuple of (long entries, long exits) as boolean Series. Short-spread signals
            come from ``generate_short_signals``.
        """
        long_entries, long_exits, _, _ = self._spread_signals(data)
        return long_entries, long_exits

    def generate_short_signals(self, data: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
        """Short-spread (sell asset1) entry/exit signals, for ``short_entries``/``short_exits``."""
        _, _, short_entries, short_exits = self._spread_signals(data)
        return short_entries, short_exits

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

        long_entries, long_exits, short_entries, short_exits = self._spread_signals(data)

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

        def fired(exits: pd.Series) -> bool:
            return bool(exits.iloc[-1] and not exits.iloc[-2])

        # Exit signals are levels (true whenever flat-side z is past the exit); close only
        # on the bar one flips on, or when the spread is stopped out / undefined.
        close = (
            (long_exits.iloc[-1] and short_exits.iloc[-1])
            or fired(long_exits)
            or fired(short_exits)
        )

        if long_entries.iloc[-1]:
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
        if short_entries.iloc[-1]:
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
        if close:
            return {
                "action": "CLOSE_SPREAD",
                "asset1": self.asset1,
                "asset2": self.asset2,
                "zscore": latest_zscore,
            }

        return None
