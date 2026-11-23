"""VPIN Order Flow Toxicity Filter.

Not a standalone strategy — wraps other strategies as a risk filter.
Block entries when VPIN > 0.7 (high toxicity = informed trading).
Allow entries when VPIN < 0.3 (low toxicity).

Reference:
    "Does Order Flow Toxicity Really Matter in Equity Trading?"
    Volume-Synchronized Probability of Informed Trading (VPIN)
"""

from __future__ import annotations

from typing import Any

import pandas as pd

from medusa.features.order_flow_features import vpin
from medusa.strategies.base import BaseStrategy


class VPINFilterStrategy(BaseStrategy):
    """VPIN-based order flow toxicity filter for existing strategies.

    This is a meta-strategy that wraps another strategy and filters its
    signals based on VPIN (order flow toxicity).
    """

    def __init__(
        self,
        underlying_strategy: BaseStrategy,
        vpin_high_threshold: float = 0.7,
        vpin_low_threshold: float = 0.3,
        volume_bucket_size: int = 50,
        vpin_window: int = 50,
    ) -> None:
        """Initialize VPIN filter strategy.

        Args:
            underlying_strategy: The strategy to filter (e.g., VolumeMomentumStrategy).
            vpin_high_threshold: Block entries above this VPIN. Default 0.7.
            vpin_low_threshold: Allow entries below this VPIN. Default 0.3.
            volume_bucket_size: Bars per volume bucket for VPIN. Default 50.
            vpin_window: Rolling window of buckets for VPIN. Default 50.
        """
        self.underlying_strategy = underlying_strategy
        self.vpin_high_threshold = vpin_high_threshold
        self.vpin_low_threshold = vpin_low_threshold
        self.volume_bucket_size = volume_bucket_size
        self.vpin_window = vpin_window

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate filtered entry/exit signals based on VPIN toxicity.

        Args:
            data: OHLCV DataFrame with 'close', 'volume' (and optionally 'buy_volume').

        Returns:
            Tuple of (entries, exits) as boolean Series.
        """
        # Get underlying strategy signals
        base_entries, base_exits = self.underlying_strategy.generate_signals(data)

        # Calculate VPIN
        vpin_series = vpin(
            data,
            volume_bucket_size=self.volume_bucket_size,
            window=self.vpin_window,
        )

        # Filter logic:
        # - Block entries when VPIN > high_threshold (toxic flow, informed traders)
        # - Allow entries when VPIN < low_threshold (clean flow)
        # - In between: maintain existing positions but no new entries

        high_toxicity = vpin_series > self.vpin_high_threshold
        low_toxicity = vpin_series < self.vpin_low_threshold

        # Filtered entries: only allow when VPIN is low (clean flow)
        filtered_entries = base_entries & low_toxicity

        # Exits: original exits OR high toxicity detected (emergency exit)
        filtered_exits = base_exits | high_toxicity

        return filtered_entries, filtered_exits

    def generate_signal(
        self,
        data: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """Generate a single filtered signal from the latest data (for live use).

        Args:
            data: Recent market data buffer.

        Returns:
            Signal dict with VPIN context added, or None if filtered out.
        """
        # Get underlying signal
        base_signal = self.underlying_strategy.generate_signal(data)

        # Calculate current VPIN
        vpin_series = vpin(
            data,
            volume_bucket_size=self.volume_bucket_size,
            window=self.vpin_window,
        )
        current_vpin = vpin_series.iloc[-1]

        # Filter logic
        if base_signal is None:
            return None

        action = base_signal["action"]

        # Block entries if VPIN is high (toxic flow)
        if action in ["BUY", "SELL", "LONG_SPREAD", "SHORT_SPREAD"]:
            if current_vpin > self.vpin_high_threshold:
                return None  # Blocked by VPIN filter
            elif current_vpin > self.vpin_low_threshold:
                # Marginal toxicity: reduce position size
                if "size" in base_signal:
                    toxicity_factor = (self.vpin_high_threshold - current_vpin) / (
                        self.vpin_high_threshold - self.vpin_low_threshold
                    )
                    base_signal["size"] *= toxicity_factor
                    base_signal["vpin_adjusted"] = True

        # Add VPIN context to signal
        base_signal["vpin"] = current_vpin
        base_signal["vpin_status"] = (
            "low"
            if current_vpin < self.vpin_low_threshold
            else "high"
            if current_vpin > self.vpin_high_threshold
            else "medium"
        )

        return base_signal

    def get_vpin_statistics(
        self,
        data: pd.DataFrame,
    ) -> dict[str, float]:
        """Get VPIN statistics for monitoring and analysis.

        Args:
            data: OHLCV DataFrame.

        Returns:
            Dict with VPIN stats: current, mean, std, min, max.
        """
        vpin_series = vpin(
            data,
            volume_bucket_size=self.volume_bucket_size,
            window=self.vpin_window,
        )

        return {
            "current": float(vpin_series.iloc[-1]),
            "mean": float(vpin_series.mean()),
            "std": float(vpin_series.std()),
            "min": float(vpin_series.min()),
            "max": float(vpin_series.max()),
            "pct_high_toxicity": float((vpin_series > self.vpin_high_threshold).mean()),
            "pct_low_toxicity": float((vpin_series < self.vpin_low_threshold).mean()),
        }
