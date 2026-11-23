"""Yield curve construction and interpolation.

Implements linear/cubic interpolation, Nelson-Siegel curve fitting,
and zero curve bootstrapping from par bonds.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

import numpy as np
import pandas as pd
from loguru import logger
from numpy.typing import NDArray

try:
    from scipy import optimize
    from scipy.interpolate import CubicSpline, interp1d

    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    logger.warning("scipy not available - yield curve features disabled")


@dataclass
class YieldCurve:
    """Yield curve representation.

    Attributes:
        tenors: Tenor points in years (e.g., [0.25, 0.5, 1, 2, 5, 10, 30]).
        rates: Zero rates at each tenor (annual, as decimals).
    """

    tenors: NDArray[np.float64]
    rates: NDArray[np.float64]

    def __post_init__(self) -> None:
        """Validate curve data."""
        if len(self.tenors) != len(self.rates):
            raise ValueError("Tenors and rates must have same length")
        if not np.all(self.tenors[:-1] <= self.tenors[1:]):
            raise ValueError("Tenors must be sorted in ascending order")
        self.tenors = np.asarray(self.tenors, dtype=float)
        self.rates = np.asarray(self.rates, dtype=float)

    def interpolate(
        self,
        tenor: float,
        method: str = "linear",
    ) -> float:
        """Interpolate rate at given tenor.

        Args:
            tenor: Target tenor in years.
            method: Interpolation method ('linear' or 'cubic').

        Returns:
            Interpolated rate (annual, as decimal).

        Raises:
            ImportError: If scipy not available and cubic interpolation requested.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for yield curve interpolation")

        if tenor < self.tenors[0] or tenor > self.tenors[-1]:
            # Flat extrapolation
            if tenor < self.tenors[0]:
                return float(self.rates[0])
            return float(self.rates[-1])

        if method == "linear":
            interpolator = interp1d(self.tenors, self.rates, kind="linear")
        elif method == "cubic":
            interpolator = CubicSpline(self.tenors, self.rates)
        else:
            raise ValueError(f"Unknown interpolation method: {method}")

        return float(interpolator(tenor))

    def discount_factor(self, tenor: float) -> float:
        r"""Calculate discount factor at given tenor.

        .. math::

            DF(t) = e^{-r(t) \cdot t}

        Args:
            tenor: Tenor in years.

        Returns:
            Discount factor.
        """
        rate = self.interpolate(tenor)
        return float(np.exp(-rate * tenor))

    def forward_rate(self, t1: float, t2: float) -> float:
        r"""Calculate forward rate between two tenors.

        .. math::

            f(t_1, t_2) = \frac{r(t_2) \cdot t_2 - r(t_1) \cdot t_1}{t_2 - t_1}

        Args:
            t1: Start tenor in years.
            t2: End tenor in years.

        Returns:
            Forward rate (annual, as decimal).
        """
        if t2 <= t1:
            raise ValueError("t2 must be greater than t1")

        r1 = self.interpolate(t1)
        r2 = self.interpolate(t2)

        # Forward rate from zero rates
        return (r2 * t2 - r1 * t1) / (t2 - t1)


@dataclass
class NelsonSiegelCurve:
    r"""Nelson-Siegel yield curve parametrization.

    The Nelson-Siegel model represents the yield curve as:

    .. math::

        y(t) = \beta_0 + \beta_1 \frac{1-e^{-t/\tau}}{t/\tau}
               + \beta_2 \left( \frac{1-e^{-t/\tau}}{t/\tau} - e^{-t/\tau} \right)

    where:
    - β0 = long-term rate (level)
    - β1 = short-term component (slope)
    - β2 = medium-term component (curvature)
    - τ = decay parameter

    Attributes:
        beta0: Level parameter.
        beta1: Slope parameter.
        beta2: Curvature parameter.
        tau: Decay parameter.
    """

    beta0: float
    beta1: float
    beta2: float
    tau: float

    def rate(self, tenor: float) -> float:
        """Calculate rate at given tenor.

        Args:
            tenor: Tenor in years.

        Returns:
            Yield (annual, as decimal).
        """
        if tenor <= 0:
            return self.beta0 + self.beta1

        t_tau = tenor / self.tau
        exp_term = np.exp(-t_tau)

        # Component 1: level
        level = self.beta0

        # Component 2: slope
        if t_tau < 1e-6:
            # Taylor expansion for small t/tau to avoid 0/0
            slope_factor = 1.0
        else:
            slope_factor = (1 - exp_term) / t_tau

        slope = self.beta1 * slope_factor

        # Component 3: curvature
        curvature = self.beta2 * (slope_factor - exp_term)

        return float(level + slope + curvature)

    @classmethod
    def fit(
        cls,
        curve: YieldCurve,
        initial_tau: float = 1.0,
    ) -> NelsonSiegelCurve:
        """Fit Nelson-Siegel parameters to observed yield curve.

        Uses scipy.optimize.minimize to find optimal β0, β1, β2, τ.

        Args:
            curve: Observed yield curve.
            initial_tau: Initial guess for tau parameter.

        Returns:
            Fitted Nelson-Siegel curve.

        Raises:
            ImportError: If scipy not available.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for Nelson-Siegel fitting")

        def objective(params: NDArray[np.float64]) -> float:
            """Sum of squared errors."""
            beta0, beta1, beta2, tau = params
            if tau <= 0:
                return 1e10  # Penalize invalid tau

            fitted = cls(beta0, beta1, beta2, tau)
            predicted = np.array([fitted.rate(t) for t in curve.tenors])
            return float(np.sum((predicted - curve.rates) ** 2))

        # Initial guesses
        initial_beta0 = float(curve.rates[-1])  # Long-term rate
        initial_beta1 = float(curve.rates[0] - curve.rates[-1])  # Slope
        initial_beta2 = 0.0  # Curvature
        x0 = [initial_beta0, initial_beta1, initial_beta2, initial_tau]

        # Optimize
        result = optimize.minimize(
            objective,
            x0,
            method="L-BFGS-B",
            bounds=[
                (0, None),  # beta0 >= 0
                (None, None),  # beta1 unbounded
                (None, None),  # beta2 unbounded
                (0.01, 10),  # tau in reasonable range
            ],
        )

        if not result.success:
            logger.warning(f"Nelson-Siegel fitting did not converge: {result.message}")

        beta0, beta1, beta2, tau = (float(value) for value in result.x)
        logger.info(
            f"Nelson-Siegel fit: β0={beta0:.4f}, β1={beta1:.4f}, "
            f"β2={beta2:.4f}, τ={tau:.4f}, SSE={result.fun:.6f}"
        )

        return cls(beta0, beta1, beta2, tau)


class YieldCurveBootstrapper:
    """Bootstrap zero curve from par bond yields."""

    @staticmethod
    def bootstrap(par_bonds: pd.DataFrame, max_age_seconds: int = 300) -> YieldCurve:
        """Bootstrap zero rates from par bonds with staleness validation.

        Args:
            par_bonds: DataFrame with columns:
                - tenor: Maturity in years
                - rate: Par yield (annual, as decimal)
                - frequency: Coupon frequency (1, 2, or 4)
                - timestamp: (optional) Data timestamp for freshness validation
            max_age_seconds: Maximum data age in seconds (default: 300 = 5 minutes)

        Returns:
            Bootstrapped zero curve.

        Raises:
            ValueError: If par_bonds is empty, missing required columns, or data is stale.
        """
        required_cols = {"tenor", "rate", "frequency"}
        if not required_cols.issubset(par_bonds.columns):
            raise ValueError(f"par_bonds must have columns: {required_cols}")

        if par_bonds.empty:
            raise ValueError("par_bonds cannot be empty")

        # Validate data freshness if timestamp column exists
        if "timestamp" in par_bonds.columns:
            now = datetime.now(UTC)
            oldest = pd.to_datetime(par_bonds["timestamp"]).min()

            # Convert to timezone-aware if needed
            if oldest.tzinfo is None:
                oldest = oldest.replace(tzinfo=UTC)

            age_seconds = (now - oldest).total_seconds()

            if age_seconds > max_age_seconds:
                raise ValueError(
                    f"Treasury rates are stale (age: {age_seconds:.0f}s, "
                    f"max allowed: {max_age_seconds}s). "
                    "Refusing to bootstrap curve with outdated data."
                )
            logger.debug(f"Data age: {age_seconds:.0f}s (within {max_age_seconds}s threshold)")
        else:
            logger.warning("Treasury rates missing timestamp column — cannot validate freshness")

        # Sort by tenor
        bonds = par_bonds.sort_values("tenor").reset_index(drop=True)

        zero_rates: list[float] = []
        tenors_out: list[float] = []

        for _, bond in bonds.iterrows():
            tenor = bond["tenor"]
            par_rate = bond["rate"]
            frequency = int(bond["frequency"])

            # Coupon payment per period (as percentage of 100 face value)
            coupon = par_rate / frequency

            # Payment dates (in years)
            payment_dates = np.arange(1 / frequency, tenor + 1e-6, 1 / frequency)

            # Discount all coupons
            pv_coupons = 0.0
            for t in payment_dates:
                # Find zero rate at this tenor (interpolate if needed)
                if len(zero_rates) == 0:
                    # First bond: use simple approximation for all intermediate points
                    zero_rate = par_rate
                else:
                    # Linear interpolation from existing zero rates
                    zero_rate = float(np.interp(t, tenors_out, zero_rates))

                pv_coupons += 100 * coupon * np.exp(-zero_rate * t)

            # Add face value payment at maturity
            # 100 = PV(coupons) + 100 * exp(-z * T)
            # z = -ln((100 - PV(coupons)) / 100) / T
            numerator = 100 - pv_coupons
            if numerator <= 0:
                raise ValueError(f"Invalid cash flows for tenor {tenor}")

            zero_rate = -np.log(numerator / 100) / tenor

            zero_rates.append(zero_rate)
            tenors_out.append(tenor)

        logger.info(f"Bootstrapped {len(zero_rates)} zero rates")
        return YieldCurve(np.array(tenors_out), np.array(zero_rates))
