"""Volume-Weighted Time Series Momentum strategy.

Entry: 30-day momentum positive AND volume > 20-day average
Exit: momentum reversal or trailing stop 2%
Position sizing: volatility-scaled (ATR-based)

Reference:
    "Cryptocurrency Volume-Weighted Time Series Momentum"
    Huang, Sangiorgi & Urquhart (SSRN 4825389)
"""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from medusa.strategies.base import BaseStrategy


class VolumeMomentumStrategy(BaseStrategy):
    """Volume-weighted time series momentum strategy.

    Combines price momentum with volume confirmation to filter out
    low-quality signals. Positions are sized inversely to volatility.
    """

    def __init__(
        self,
        lookback_windows: list[int] | None = None,
        volume_threshold: float = 1.0,
        stop_loss_pct: float = 0.02,
        vol_target: float = 0.15,
        top_pct: float = 0.3,
        bottom_pct: float = 0.0,
    ) -> None:
        """Initialize volume momentum strategy.

        Args:
            lookback_windows: Momentum lookback periods (days). Default [30, 60, 90].
            volume_threshold: Minimum volume z-score for entry. Default 1.0.
            stop_loss_pct: Trailing stop loss percentage. Default 0.02 (2%).
            vol_target: Target annualized volatility for position sizing. Default 0.15.
            top_pct: Percentile threshold for long entries. Default 0.3 (top 30%).
            bottom_pct: Percentile for short entries. Default 0.0 (long-only).
        """
        self.lookback_windows = lookback_windows or [30, 60, 90]
        self.volume_threshold = volume_threshold
        self.stop_loss_pct = stop_loss_pct
        self.vol_target = vol_target
        self.top_pct = top_pct
        self.bottom_pct = bottom_pct

    def _calc_vw_return(
        self,
        prices: pd.Series,
        volumes: pd.Series,
        lookback: int,
    ) -> pd.Series:
        """Calculate volume-weighted return over lookback period.

        Args:
            prices: Price series.
            volumes: Volume series.
            lookback: Lookback window in bars.

        Returns:
            Volume-weighted returns.
        """
        returns = np.log(prices / prices.shift(1))
        vw_num = (returns * volumes).rolling(lookback).sum()
        vw_den = volumes.rolling(lookback).sum()
        return vw_num / vw_den.replace(0, np.nan)

    def _calc_volume_zscore(
        self,
        volumes: pd.Series,
        window: int = 30,
    ) -> pd.Series:
        """Calculate volume z-score relative to rolling average.

        Args:
            volumes: Volume series.
            window: Rolling window for mean/std calculation.

        Returns:
            Volume z-scores.
        """
        vol_mean = volumes.rolling(window).mean()
        vol_std = volumes.rolling(window).std()
        return (volumes - vol_mean) / vol_std.replace(0, np.nan)

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate entry/exit signals from OHLCV data.

        Args:
            data: OHLCV DataFrame with 'close', 'volume', 'high', 'low'.

        Returns:
            Tuple of (entries, exits) as boolean Series.
        """
        prices = data["close"]
        volumes = data["volume"]

        # Calculate volume-weighted returns for each lookback window
        vw_returns = {}
        for window in self.lookback_windows:
            vw_returns[window] = self._calc_vw_return(prices, volumes, window)

        # Ensemble: average VW returns across horizons
        avg_vw_return = pd.concat(vw_returns.values(), axis=1).mean(axis=1)

        # Volume filter: only trade when volume is elevated
        vol_zscore = self._calc_volume_zscore(volumes)
        volume_filter = vol_zscore > self.volume_threshold

        # Momentum signal: positive VW return
        momentum_signal = avg_vw_return > 0

        # Entry: momentum + volume confirmation
        entries = momentum_signal & volume_filter

        # Exit: momentum reversal OR trailing stop
        momentum_reversal = avg_vw_return < 0

        # Trailing stop: price drops more than stop_loss_pct from recent high
        rolling_high = prices.rolling(20).max()
        drawdown = (prices - rolling_high) / rolling_high
        stop_triggered = drawdown < -self.stop_loss_pct

        exits = momentum_reversal | stop_triggered

        return entries, exits

    def generate_signal(
        self,
        data: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """Generate a single signal from the latest data (for live use).

        Args:
            data: Recent market data buffer (OHLCV).

        Returns:
            Signal dict with keys: action, price, size, or None if no signal.
        """
        if len(data) < max(self.lookback_windows) + 30:
            return None  # Not enough data

        entries, exits = self.generate_signals(data)

        latest_entry = entries.iloc[-1]
        latest_exit = exits.iloc[-1]
        latest_price = data["close"].iloc[-1]

        # Calculate position size based on volatility targeting
        returns = data["close"].pct_change()
        current_vol = returns.rolling(20).std().iloc[-1] * np.sqrt(252)  # Annualized

        if current_vol > 0:
            position_size = min(1.0, self.vol_target / current_vol)
        else:
            position_size = 0.0

        if latest_entry and not latest_exit:
            return {
                "action": "BUY",
                "price": latest_price,
                "size": position_size,
            }
        elif latest_exit:
            return {
                "action": "SELL",
                "price": latest_price,
                "size": 1.0,  # Close full position
            }

        return None
