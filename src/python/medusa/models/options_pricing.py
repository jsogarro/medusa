"""Black-Scholes options pricing engine.

Implements European option pricing, Greeks calculation, and implied volatility
solver using the Black-Scholes-Merton model.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import numpy as np
from loguru import logger

try:
    from scipy.stats import norm

    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    logger.warning("scipy not available - options pricing disabled")


class OptionType(Enum):
    """Option type enumeration."""

    CALL = "call"
    PUT = "put"

    def __str__(self) -> str:
        return self.value


@dataclass
class OptionParams:
    """Black-Scholes option parameters.

    Attributes:
        spot: Current underlying price.
        strike: Strike price.
        time_to_expiry: Time to expiration in years.
        risk_free_rate: Risk-free interest rate (annual, as decimal).
        volatility: Implied volatility (annual, as decimal).
        option_type: 'call' or 'put'.
        dividend_yield: Continuous dividend yield (annual, as decimal).
    """

    spot: float
    strike: float
    time_to_expiry: float
    risk_free_rate: float
    volatility: float
    option_type: OptionType = OptionType.CALL
    dividend_yield: float = 0.0

    def __post_init__(self) -> None:
        """Validate parameters."""
        if self.spot <= 0:
            raise ValueError(f"Spot must be positive, got: {self.spot}")
        if self.strike <= 0:
            raise ValueError(f"Strike must be positive, got: {self.strike}")
        if self.time_to_expiry < 0:
            raise ValueError(f"Time to expiry must be non-negative, got: {self.time_to_expiry}")
        if self.volatility < 0:
            raise ValueError(f"Volatility must be non-negative, got: {self.volatility}")


class BlackScholesEngine:
    """Black-Scholes option pricing engine."""

    @staticmethod
    def _d1(params: OptionParams) -> float:
        r"""Calculate d1 parameter.

        .. math::

            d_1 = \frac{\ln(S/K) + (r - q + \sigma^2/2) \cdot T}{\sigma \sqrt{T}}

        Args:
            params: Option parameters.

        Returns:
            d1 value.
        """
        if params.time_to_expiry == 0:
            return np.inf if params.spot >= params.strike else -np.inf

        numerator = (
            np.log(params.spot / params.strike)
            + (params.risk_free_rate - params.dividend_yield + 0.5 * params.volatility**2)
            * params.time_to_expiry
        )

        denominator = params.volatility * np.sqrt(params.time_to_expiry)
        return numerator / denominator

    @staticmethod
    def _d2(params: OptionParams) -> float:
        r"""Calculate d2 parameter.

        .. math::

            d_2 = d_1 - \sigma \sqrt{T}

        Args:
            params: Option parameters.

        Returns:
            d2 value.
        """
        d1 = BlackScholesEngine._d1(params)
        if params.time_to_expiry == 0:
            return d1
        return d1 - params.volatility * np.sqrt(params.time_to_expiry)

    @staticmethod
    def price(params: OptionParams) -> float:
        r"""Calculate option price using Black-Scholes formula.

        Call option:

        .. math::

            C = S \cdot e^{-qT} \cdot N(d_1) - K \cdot e^{-rT} \cdot N(d_2)

        Put option:

        .. math::

            P = K \cdot e^{-rT} \cdot N(-d_2) - S \cdot e^{-qT} \cdot N(-d_1)

        Args:
            params: Option parameters.

        Returns:
            Option price.

        Raises:
            ImportError: If scipy not available.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for Black-Scholes pricing")

        if params.time_to_expiry == 0:
            # At expiration: intrinsic value
            if params.option_type == OptionType.CALL:
                return max(params.spot - params.strike, 0.0)
            return max(params.strike - params.spot, 0.0)

        d1 = BlackScholesEngine._d1(params)
        d2 = BlackScholesEngine._d2(params)

        discount_factor = np.exp(-params.risk_free_rate * params.time_to_expiry)
        dividend_factor = np.exp(-params.dividend_yield * params.time_to_expiry)

        if params.option_type == OptionType.CALL:
            price = params.spot * dividend_factor * norm.cdf(
                d1
            ) - params.strike * discount_factor * norm.cdf(d2)
        else:  # PUT
            price = params.strike * discount_factor * norm.cdf(
                -d2
            ) - params.spot * dividend_factor * norm.cdf(-d1)

        return float(price)

    @staticmethod
    def greeks(params: OptionParams) -> dict[str, float]:
        """Calculate option Greeks.

        Returns:
            Dictionary with delta, gamma, vega, theta, rho.

        Raises:
            ImportError: If scipy not available.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for Greeks calculation")

        if params.time_to_expiry == 0:
            # At expiration
            if params.option_type == OptionType.CALL:
                delta = 1.0 if params.spot > params.strike else 0.0
            else:
                delta = -1.0 if params.spot < params.strike else 0.0

            return {
                "delta": delta,
                "gamma": 0.0,
                "vega": 0.0,
                "theta": 0.0,
                "rho": 0.0,
            }

        d1 = BlackScholesEngine._d1(params)
        d2 = BlackScholesEngine._d2(params)

        discount_factor = np.exp(-params.risk_free_rate * params.time_to_expiry)
        dividend_factor = np.exp(-params.dividend_yield * params.time_to_expiry)
        sqrt_t = np.sqrt(params.time_to_expiry)

        # Delta
        if params.option_type == OptionType.CALL:
            delta = dividend_factor * norm.cdf(d1)
        else:
            delta = -dividend_factor * norm.cdf(-d1)

        # Gamma (same for call and put)
        gamma = dividend_factor * norm.pdf(d1) / (params.spot * params.volatility * sqrt_t)

        # Vega (same for call and put)
        vega = params.spot * dividend_factor * norm.pdf(d1) * sqrt_t / 100  # per 1%

        # Theta
        term1 = -params.spot * dividend_factor * norm.pdf(d1) * params.volatility / (2 * sqrt_t)
        if params.option_type == OptionType.CALL:
            term2 = params.dividend_yield * params.spot * dividend_factor * norm.cdf(d1)
            term3 = -params.risk_free_rate * params.strike * discount_factor * norm.cdf(d2)
            theta = (term1 + term2 + term3) / 365  # per day
        else:
            term2 = -params.dividend_yield * params.spot * dividend_factor * norm.cdf(-d1)
            term3 = params.risk_free_rate * params.strike * discount_factor * norm.cdf(-d2)
            theta = (term1 + term2 + term3) / 365  # per day

        # Rho
        if params.option_type == OptionType.CALL:
            rho = (
                params.strike
                * params.time_to_expiry
                * discount_factor
                * norm.cdf(d2)
                / 100  # per 1%
            )
        else:
            rho = (
                -params.strike
                * params.time_to_expiry
                * discount_factor
                * norm.cdf(-d2)
                / 100  # per 1%
            )

        return {
            "delta": float(delta),
            "gamma": float(gamma),
            "vega": float(vega),
            "theta": float(theta),
            "rho": float(rho),
        }

    @staticmethod
    def implied_volatility(
        price: float,
        params: OptionParams,
        max_iter: int = 100,
        tolerance: float = 1e-5,
    ) -> float:
        """Calculate implied volatility using Newton-Raphson.

        Args:
            price: Market option price.
            params: Option parameters (with initial volatility guess).
            max_iter: Maximum iterations.
            tolerance: Convergence tolerance.

        Returns:
            Implied volatility (annual, as decimal).

        Raises:
            ImportError: If scipy not available.
            ValueError: If solver fails to converge.
        """
        if not SCIPY_AVAILABLE:
            raise ImportError("scipy required for implied volatility calculation")

        # Initial guess
        vol_guess = params.volatility if params.volatility > 0 else 0.2

        for iteration in range(max_iter):
            # Create params with current volatility guess
            test_params = OptionParams(
                spot=params.spot,
                strike=params.strike,
                time_to_expiry=params.time_to_expiry,
                risk_free_rate=params.risk_free_rate,
                volatility=vol_guess,
                option_type=params.option_type,
                dividend_yield=params.dividend_yield,
            )

            # Calculate price and vega
            calculated_price = BlackScholesEngine.price(test_params)
            greeks = BlackScholesEngine.greeks(test_params)
            vega = greeks["vega"] * 100  # Convert from per 1% to per 1.0

            # Check convergence
            price_diff = calculated_price - price
            if abs(price_diff) < tolerance:
                logger.debug(f"IV converged in {iteration + 1} iterations: {vol_guess:.6f}")
                return vol_guess

            # Newton-Raphson step
            if abs(vega) < 1e-10:
                raise ValueError("Vega too small for Newton-Raphson")

            vol_guess = vol_guess - price_diff / vega

            # Bound volatility to reasonable range
            vol_guess = max(0.0001, min(vol_guess, 5.0))

        raise ValueError(f"Implied volatility did not converge after {max_iter} iterations")
