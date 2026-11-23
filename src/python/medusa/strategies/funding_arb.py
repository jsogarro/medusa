"""Funding Rate Arbitrage for Crypto Perpetual Futures.

Entry: funding rate > 0.05% (annualized > 55%) for 2+ consecutive periods
Position: long spot + short perpetual (delta neutral)
Exit: funding rate crosses zero
P&L: collect funding payments

Reference:
    Crypto perpetual futures funding rate mechanics
    Market-neutral arbitrage strategy
"""

from __future__ import annotations

from typing import Any

import pandas as pd

from medusa.strategies.base import BaseStrategy


class FundingArbStrategy(BaseStrategy):
    """Funding rate arbitrage for crypto perpetual futures.

    Exploits high funding rates by going long spot and short perpetual,
    earning the funding payment while maintaining delta neutrality.
    """

    def __init__(
        self,
        funding_entry_threshold: float = 0.0005,
        funding_exit_threshold: float = 0.0,
        consecutive_periods: int = 2,
        max_position_pct: float = 0.5,
        funding_interval_hours: int = 8,
    ) -> None:
        """Initialize funding arbitrage strategy.

        Args:
            funding_entry_threshold: Min funding rate for entry (per period).
                                    Default 0.0005 (0.05% per 8h = ~55% APR).
            funding_exit_threshold: Funding rate for exit. Default 0.0.
            consecutive_periods: Require N periods above threshold. Default 2.
            max_position_pct: Max capital allocation. Default 0.5 (50%).
            funding_interval_hours: Hours between funding payments. Default 8.
        """
        self.funding_entry_threshold = funding_entry_threshold
        self.funding_exit_threshold = funding_exit_threshold
        self.consecutive_periods = consecutive_periods
        self.max_position_pct = max_position_pct
        self.funding_interval_hours = funding_interval_hours

    def _calculate_apr(
        self,
        funding_rate: float,
    ) -> float:
        """Convert funding rate to annualized percentage rate.

        Args:
            funding_rate: Funding rate per period (e.g., 0.0005 for 0.05%).

        Returns:
            Annualized rate (e.g., 0.55 for 55% APR).
        """
        periods_per_year = (365 * 24) / self.funding_interval_hours
        return funding_rate * periods_per_year

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate entry/exit signals based on funding rates.

        Args:
            data: DataFrame with 'funding_rate' column (per period, e.g., 8h).
                  Example: 0.0005 = 0.05% per 8h.
                  Assumes positive = longs pay shorts.

        Returns:
            Tuple of (entries, exits) as boolean Series.
        """
        if "funding_rate" not in data.columns:
            raise ValueError("Data must contain 'funding_rate' column")

        funding_rate = data["funding_rate"]

        # Entry: funding rate above threshold for consecutive periods
        above_threshold = funding_rate > self.funding_entry_threshold
        consecutive_count = (
            above_threshold.rolling(self.consecutive_periods).sum() >= self.consecutive_periods
        )

        entries = consecutive_count & ~consecutive_count.shift(1, fill_value=False)

        # Exit: funding rate crosses below exit threshold
        below_exit = funding_rate < self.funding_exit_threshold
        exits = below_exit & ~below_exit.shift(1, fill_value=False)

        return entries, exits

    def generate_signal(
        self,
        data: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """Generate a single signal from the latest data (for live use).

        Args:
            data: Recent market data buffer with 'funding_rate' and 'close'.

        Returns:
            Signal dict with keys: action, spot_price, perp_price, funding_rate,
            apr, size, or None if no signal.
        """
        if "funding_rate" not in data.columns:
            return None

        if len(data) < self.consecutive_periods:
            return None  # Not enough data

        entries, exits = self.generate_signals(data)

        latest_entry = entries.iloc[-1]
        latest_exit = exits.iloc[-1]
        latest_funding = data["funding_rate"].iloc[-1]
        latest_spot_price = data.get("close", data.get("spot_price", pd.Series([0.0]))).iloc[-1]
        latest_perp_price = data.get("perp_price", latest_spot_price).iloc[-1]  # Fallback to spot

        # Calculate APR for reporting
        apr = self._calculate_apr(latest_funding)

        if latest_entry:
            # Entry: long spot + short perp (delta neutral)
            return {
                "action": "ENTER_ARB",
                "spot_price": latest_spot_price,
                "perp_price": latest_perp_price,
                "funding_rate": latest_funding,
                "apr": apr,
                "size": self.max_position_pct,
                "legs": {
                    "spot": "BUY",
                    "perp": "SELL",
                },
            }
        elif latest_exit:
            # Exit: close both legs
            return {
                "action": "EXIT_ARB",
                "spot_price": latest_spot_price,
                "perp_price": latest_perp_price,
                "funding_rate": latest_funding,
                "apr": apr,
            }

        return None

    def calculate_pnl(
        self,
        entry_spot_price: float,
        entry_perp_price: float,
        exit_spot_price: float,
        exit_perp_price: float,
        funding_payments: pd.Series,
        position_size: float = 1.0,
    ) -> dict[str, float]:
        """Calculate P&L from a completed arbitrage trade.

        Args:
            entry_spot_price: Spot price at entry.
            entry_perp_price: Perp price at entry.
            exit_spot_price: Spot price at exit.
            exit_perp_price: Perp price at exit.
            funding_payments: Series of funding payments received (per period).
            position_size: Position size (e.g., 1.0 BTC).

        Returns:
            Dict with P&L components: spot_pnl, perp_pnl, funding_pnl, total_pnl.
        """
        # Spot P&L (long)
        spot_pnl = (exit_spot_price - entry_spot_price) * position_size

        # Perp P&L (short)
        perp_pnl = (entry_perp_price - exit_perp_price) * position_size

        # Funding P&L (collected from shorts)
        # Positive funding rate = longs pay shorts (we collect)
        funding_pnl = funding_payments.sum() * position_size

        # Total P&L
        total_pnl = spot_pnl + perp_pnl + funding_pnl

        return {
            "spot_pnl": spot_pnl,
            "perp_pnl": perp_pnl,
            "funding_pnl": funding_pnl,
            "total_pnl": total_pnl,
            "spot_return": spot_pnl / (entry_spot_price * position_size),
            "perp_return": perp_pnl / (entry_perp_price * position_size),
            "funding_return": funding_pnl / (entry_spot_price * position_size),
            "total_return": total_pnl / (entry_spot_price * position_size),
        }

    def estimate_carry(
        self,
        funding_rate: float,
        holding_days: int = 30,
    ) -> float:
        """Estimate carry (funding income) for a given holding period.

        Args:
            funding_rate: Current funding rate per period.
            holding_days: Expected holding period in days.

        Returns:
            Estimated carry as percentage return.
        """
        periods = (holding_days * 24) / self.funding_interval_hours
        total_carry = funding_rate * periods
        return total_carry
