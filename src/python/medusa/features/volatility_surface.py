"""Volatility surface construction and analysis.

Builds implied volatility surfaces from option quotes using RBF interpolation
and provides volatility skew and term structure analysis.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
from loguru import logger

try:
    from scipy.interpolate import RBFInterpolator

    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    logger.warning("scipy not available - volatility surface features disabled")


@dataclass
class VolatilitySurface:
    """Volatility surface representation.

    Attributes:
        strikes: Array of strike prices.
        expiries: Array of expiration times in years.
        ivs: 2D array of implied volatilities (shape: [len(strikes), len(expiries)]).
        underlying_price: Current underlying price.
    """

    strikes: np.ndarray
    expiries: np.ndarray
    ivs: np.ndarray
    underlying_price: float

    def __post_init__(self) -> None:
        """Validate surface data."""
        if self.ivs.shape != (len(self.strikes), len(self.expiries)):
            raise ValueError(
                f"IV array shape {self.ivs.shape} does not match "
                f"strikes x expiries ({len(self.strikes)}, {len(self.expiries)})"
            )
        self.strikes = np.asarray(self.strikes, dtype=float)
        self.expiries = np.asarray(self.expiries, dtype=float)
        self.ivs = np.asarray(self.ivs, dtype=float)

    def interpolate(self, strike: float, expiry: float) -> float:
        """Interpolate IV at given strike and expiry.

        Args:
            strike: Strike price.
            expiry: Expiration time in years.

        Returns:
            Interpolated implied volatility.

        Raises:
            ImportError: If scipy not available.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for volatility surface interpolation")

        # Flatten surface to 1D for RBF interpolation
        points = []
        values = []
        for i, k in enumerate(self.strikes):
            for j, t in enumerate(self.expiries):
                if not np.isnan(self.ivs[i, j]):
                    points.append([k, t])
                    values.append(self.ivs[i, j])

        if not points:
            raise ValueError("No valid IV points for interpolation")

        points = np.array(points)
        values = np.array(values)

        # RBF interpolation
        interpolator = RBFInterpolator(points, values, kernel="thin_plate_spline")
        result = interpolator([[strike, expiry]])
        return float(result[0])


class VolatilitySurfaceBuilder:
    """Build volatility surfaces from option quotes."""

    @staticmethod
    def from_quotes(
        quotes: pd.DataFrame,
        underlying_price: float,
    ) -> VolatilitySurface:
        """Build volatility surface from option quote data.

        Args:
            quotes: DataFrame with columns:
                - strike: Strike price
                - expiry: Expiration time in years
                - iv: Implied volatility (as decimal)
            underlying_price: Current underlying price.

        Returns:
            Volatility surface.

        Raises:
            ImportError: If scipy not available.
            ValueError: If quotes missing required columns.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for volatility surface building")

        required_cols = {"strike", "expiry", "iv"}
        if not required_cols.issubset(quotes.columns):
            raise ValueError(f"Quotes must have columns: {required_cols}")

        if quotes.empty:
            raise ValueError("Quotes DataFrame is empty")

        # Get unique strikes and expiries
        strikes = sorted(quotes["strike"].unique())
        expiries = sorted(quotes["expiry"].unique())

        # Build 2D grid
        ivs = np.full((len(strikes), len(expiries)), np.nan)

        for _, row in quotes.iterrows():
            strike_idx = strikes.index(row["strike"])
            expiry_idx = expiries.index(row["expiry"])
            ivs[strike_idx, expiry_idx] = row["iv"]

        # Interpolate missing values using RBF
        known_points = []
        known_values = []
        for i, k in enumerate(strikes):
            for j, t in enumerate(expiries):
                if not np.isnan(ivs[i, j]):
                    known_points.append([k, t])
                    known_values.append(ivs[i, j])

        if len(known_points) < 3:
            logger.warning("Insufficient points for interpolation, using raw data")
            return VolatilitySurface(
                np.array(strikes),
                np.array(expiries),
                ivs,
                underlying_price,
            )

        interpolator = RBFInterpolator(
            np.array(known_points),
            np.array(known_values),
            kernel="thin_plate_spline",
        )

        # Fill missing values
        for i, k in enumerate(strikes):
            for j, t in enumerate(expiries):
                if np.isnan(ivs[i, j]):
                    ivs[i, j] = interpolator([[k, t]])[0]

        logger.info(f"Built volatility surface: {len(strikes)} strikes x {len(expiries)} expiries")
        return VolatilitySurface(
            np.array(strikes),
            np.array(expiries),
            ivs,
            underlying_price,
        )

    @staticmethod
    def analyze_skew(
        surface: VolatilitySurface,
        expiry_index: int,
    ) -> dict[str, float]:
        """Analyze volatility skew for a specific expiry.

        Args:
            surface: Volatility surface.
            expiry_index: Index of expiry to analyze.

        Returns:
            Dictionary with skew metrics:
                - put_skew: IV(90% strike) - IV(ATM)
                - call_skew: IV(110% strike) - IV(ATM)
                - risk_reversal: IV(110% call) - IV(90% put)
                - butterfly: (IV(90% put) + IV(110% call)) / 2 - IV(ATM)
        """
        if expiry_index < 0 or expiry_index >= len(surface.expiries):
            raise ValueError(f"Invalid expiry_index: {expiry_index}")

        atm_strike = surface.underlying_price
        put_strike = atm_strike * 0.9
        call_strike = atm_strike * 1.1

        # Find closest strikes
        strikes = surface.strikes
        atm_idx = np.argmin(np.abs(strikes - atm_strike))
        put_idx = np.argmin(np.abs(strikes - put_strike))
        call_idx = np.argmin(np.abs(strikes - call_strike))

        atm_iv = surface.ivs[atm_idx, expiry_index]
        put_iv = surface.ivs[put_idx, expiry_index]
        call_iv = surface.ivs[call_idx, expiry_index]

        return {
            "put_skew": float(put_iv - atm_iv),
            "call_skew": float(call_iv - atm_iv),
            "risk_reversal": float(call_iv - put_iv),
            "butterfly": float((put_iv + call_iv) / 2 - atm_iv),
        }


class VolatilityAnalyzer:
    """Analyze volatility metrics and regimes."""

    @staticmethod
    def calculate_iv_rank(
        current_iv: float,
        historical_ivs: pd.Series,
        window: int = 252,
    ) -> float:
        """Calculate IV rank (percentile within lookback window).

        Args:
            current_iv: Current implied volatility.
            historical_ivs: Historical IV time series.
            window: Lookback window in days.

        Returns:
            IV rank (0-100).
        """
        recent = historical_ivs.tail(window)
        if recent.empty:
            return 50.0  # Default to median

        min_iv = recent.min()
        max_iv = recent.max()

        if max_iv == min_iv:
            return 50.0

        rank = 100 * (current_iv - min_iv) / (max_iv - min_iv)
        return float(rank)

    @staticmethod
    def calculate_iv_percentile(
        current_iv: float,
        historical_ivs: pd.Series,
        window: int = 252,
    ) -> float:
        """Calculate IV percentile within lookback window.

        Args:
            current_iv: Current implied volatility.
            historical_ivs: Historical IV time series.
            window: Lookback window in days.

        Returns:
            IV percentile (0-100).
        """
        recent = historical_ivs.tail(window)
        if recent.empty:
            return 50.0

        percentile = (recent < current_iv).sum() / len(recent) * 100
        return float(percentile)
