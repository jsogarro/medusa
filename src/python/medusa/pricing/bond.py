"""Bond pricing and analytics engine.

Implements present value, yield to maturity, duration, convexity, and DV01
calculations for fixed-rate bonds with multiple day count conventions.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum
from typing import Literal

from loguru import logger


class DayCountConvention(Enum):
    """Day count conventions for bond calculations."""

    THIRTY_360 = "30/360"
    ACT_ACT = "ACT/ACT"
    ACT_360 = "ACT/360"
    ACT_365 = "ACT/365"

    def __str__(self) -> str:
        return self.value


@dataclass
class Bond:
    """Fixed-rate bond specification.

    Attributes:
        cusip: CUSIP identifier (9-character alphanumeric).
        coupon_rate: Annual coupon rate as decimal (e.g., 0.05 for 5%).
        maturity_date: Bond maturity date.
        face_value: Par value (default: 100).
        coupon_frequency: Number of coupon payments per year (1, 2, or 4).
        day_count: Day count convention for accrued interest.
        issue_date: Bond issue date.
    """

    cusip: str
    coupon_rate: float
    maturity_date: date
    face_value: float = 100.0
    coupon_frequency: Literal[1, 2, 4] = 2
    day_count: DayCountConvention = DayCountConvention.THIRTY_360
    issue_date: date | None = None

    def __post_init__(self) -> None:
        """Validate bond parameters."""
        if len(self.cusip) != 9:
            raise ValueError(f"CUSIP must be 9 characters, got: {self.cusip}")
        if self.coupon_rate < 0:
            raise ValueError(f"Coupon rate must be non-negative, got: {self.coupon_rate}")
        if self.face_value <= 0:
            raise ValueError(f"Face value must be positive, got: {self.face_value}")
        if self.coupon_frequency not in (1, 2, 4):
            raise ValueError(f"Coupon frequency must be 1, 2, or 4, got: {self.coupon_frequency}")


class BondPricer:
    """Bond pricing and analytics engine."""

    @staticmethod
    def _is_leap_year(year: int) -> bool:
        """Check if a year is a leap year.

        Args:
            year: Year to check.

        Returns:
            True if leap year, False otherwise.
        """
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

    @staticmethod
    def _day_count_fraction(
        start: date,
        end: date,
        convention: DayCountConvention,
    ) -> float:
        """Calculate day count fraction between two dates.

        Args:
            start: Start date.
            end: End date.
            convention: Day count convention.

        Returns:
            Day count fraction (e.g., 0.5 for half a year).
        """
        if convention == DayCountConvention.THIRTY_360:
            # 30/360 US: each month = 30 days, year = 360 days
            d1, m1, y1 = start.day, start.month, start.year
            d2, m2, y2 = end.day, end.month, end.year
            if d1 == 31:
                d1 = 30
            if d2 == 31 and d1 >= 30:
                d2 = 30
            days = 360 * (y2 - y1) + 30 * (m2 - m1) + (d2 - d1)
            return days / 360.0

        elif convention == DayCountConvention.ACT_ACT:
            # ACT/ACT ISDA: split by calendar year, handle leap years properly
            days = (end - start).days

            if start.year == end.year:
                # Same year: simple calculation
                days_in_year = 366 if BondPricer._is_leap_year(start.year) else 365
                return days / days_in_year

            # Multi-year: sum contributions from each year
            fraction = 0.0
            current = start

            while current.year < end.year:
                year_end = date(current.year, 12, 31)
                days_in_current_year = (year_end - current).days + 1
                days_in_year = 366 if BondPricer._is_leap_year(current.year) else 365
                fraction += days_in_current_year / days_in_year
                current = date(current.year + 1, 1, 1)

            # Final year
            days_in_final_year = (end - current).days
            days_in_year = 366 if BondPricer._is_leap_year(end.year) else 365
            fraction += days_in_final_year / days_in_year

            return fraction

        elif convention == DayCountConvention.ACT_360:
            # Actual/360: actual days / 360
            days = (end - start).days
            return days / 360.0

        elif convention == DayCountConvention.ACT_365:
            # Actual/365: actual days / 365
            days = (end - start).days
            return days / 365.0

        raise ValueError(f"Unknown day count convention: {convention}")

    @staticmethod
    def _coupon_dates(
        bond: Bond,
        settlement_date: date,
    ) -> list[date]:
        """Generate future coupon payment dates.

        Args:
            bond: Bond specification.
            settlement_date: Settlement date.

        Returns:
            List of future coupon dates from settlement to maturity.
        """
        months_per_period = 12 // bond.coupon_frequency
        dates = []
        current = bond.maturity_date

        # Work backwards from maturity
        while current > settlement_date:
            dates.append(current)
            year_offset = months_per_period // 12
            month_offset = months_per_period % 12

            if current.month <= month_offset:
                new_month = 12 + current.month - month_offset
                new_year = current.year - year_offset - 1
            else:
                new_month = current.month - month_offset
                new_year = current.year - year_offset

            current = current.replace(year=new_year, month=new_month)

        return sorted(dates)

    @staticmethod
    def present_value(
        bond: Bond,
        ytm: float,
        settlement_date: date,
    ) -> float:
        r"""Calculate bond present value (clean price).

        Uses standard bond pricing formula:

        .. math::

            PV = \sum_{t=1}^{n} \frac{C}{(1+y/f)^{t}} + \frac{F}{(1+y/f)^{n}}

        where:
        - C = coupon payment per period
        - F = face value
        - y = yield to maturity (annual)
        - f = coupon frequency
        - n = number of periods to maturity

        Args:
            bond: Bond specification.
            ytm: Yield to maturity (annual, as decimal).
            settlement_date: Settlement date.

        Returns:
            Present value (clean price).
        """
        coupon_dates = BondPricer._coupon_dates(bond, settlement_date)
        if not coupon_dates:
            # Bond has matured
            return 0.0

        coupon_payment = bond.face_value * bond.coupon_rate / bond.coupon_frequency
        discount_rate = 1 + ytm / bond.coupon_frequency

        pv = 0.0
        for i, coupon_date in enumerate(coupon_dates, start=1):
            # Time to coupon in periods
            time_fraction = BondPricer._day_count_fraction(
                settlement_date, coupon_date, bond.day_count
            )
            periods = time_fraction * bond.coupon_frequency

            # Discount coupon payment
            pv += coupon_payment / (discount_rate**periods)

        # Add discounted face value at maturity
        maturity_periods = (
            BondPricer._day_count_fraction(settlement_date, bond.maturity_date, bond.day_count)
            * bond.coupon_frequency
        )
        pv += bond.face_value / (discount_rate**maturity_periods)

        logger.debug(f"PV({bond.cusip}): ytm={ytm:.4f}, settlement={settlement_date}, pv={pv:.4f}")
        return float(pv)

    @staticmethod
    def yield_to_maturity(
        bond: Bond,
        price: float,
        settlement_date: date,
        tol: float = 1e-6,
        max_iter: int = 100,
    ) -> float:
        """Calculate yield to maturity using Newton-Raphson.

        Solves for y in: price = PV(y)

        Args:
            bond: Bond specification.
            price: Market price (clean).
            settlement_date: Settlement date.
            tol: Convergence tolerance.
            max_iter: Maximum iterations.

        Returns:
            Yield to maturity (annual, as decimal).

        Raises:
            ValueError: If Newton-Raphson fails to converge.
        """
        # Initial guess: current yield = coupon / price
        ytm_guess = (bond.coupon_rate * bond.face_value) / price

        for iteration in range(max_iter):
            pv = BondPricer.present_value(bond, ytm_guess, settlement_date)
            diff = pv - price

            if abs(diff) < tol:
                logger.debug(
                    f"YTM({bond.cusip}) converged in {iteration + 1} iterations: {ytm_guess:.6f}"
                )
                return ytm_guess

            # Derivative: dPV/dy (modified duration * -PV)
            mod_dur = BondPricer.modified_duration(bond, ytm_guess, settlement_date)
            derivative = -mod_dur * pv

            if abs(derivative) < 1e-12:
                raise ValueError("Newton-Raphson derivative too small")

            # Newton-Raphson step
            ytm_guess = ytm_guess - diff / derivative

            # Bound ytm to reasonable range
            ytm_guess = max(0.0001, min(ytm_guess, 1.0))

        raise ValueError(f"YTM calculation did not converge after {max_iter} iterations")

    @staticmethod
    def macaulay_duration(
        bond: Bond,
        ytm: float,
        settlement_date: date,
    ) -> float:
        r"""Calculate Macaulay duration.

        Weighted average time to cash flows:

        .. math::

            D_{Mac} = \frac{1}{PV} \sum_{t=1}^{n} t \cdot \frac{CF_t}{(1+y/f)^{t}}

        Args:
            bond: Bond specification.
            ytm: Yield to maturity (annual).
            settlement_date: Settlement date.

        Returns:
            Macaulay duration in years.
        """
        coupon_dates = BondPricer._coupon_dates(bond, settlement_date)
        if not coupon_dates:
            return 0.0

        pv = BondPricer.present_value(bond, ytm, settlement_date)
        if pv == 0:
            return 0.0

        coupon_payment = bond.face_value * bond.coupon_rate / bond.coupon_frequency
        discount_rate = 1 + ytm / bond.coupon_frequency

        weighted_time = 0.0
        for coupon_date in coupon_dates:
            time_fraction = BondPricer._day_count_fraction(
                settlement_date, coupon_date, bond.day_count
            )
            periods = time_fraction * bond.coupon_frequency

            # Weight = time * PV(cashflow)
            cf = (
                coupon_payment
                if coupon_date != bond.maturity_date
                else coupon_payment + bond.face_value
            )
            weighted_time += time_fraction * cf / (discount_rate**periods)

        return weighted_time / pv

    @staticmethod
    def modified_duration(
        bond: Bond,
        ytm: float,
        settlement_date: date,
    ) -> float:
        r"""Calculate modified duration.

        Measures price sensitivity to yield changes:

        .. math::

            D_{Mod} = \frac{D_{Mac}}{1 + y/f}

        Args:
            bond: Bond specification.
            ytm: Yield to maturity (annual).
            settlement_date: Settlement date.

        Returns:
            Modified duration in years.
        """
        mac_dur = BondPricer.macaulay_duration(bond, ytm, settlement_date)
        return mac_dur / (1 + ytm / bond.coupon_frequency)

    @staticmethod
    def convexity(
        bond: Bond,
        ytm: float,
        settlement_date: date,
    ) -> float:
        r"""Calculate convexity.

        Second derivative of price with respect to yield:

        .. math::

            C = \frac{1}{PV \cdot (1+y/f)^2} \sum_{t=1}^{n} t(t+1) \cdot \frac{CF_t}{(1+y/f)^{t}}

        Args:
            bond: Bond specification.
            ytm: Yield to maturity (annual).
            settlement_date: Settlement date.

        Returns:
            Convexity.
        """
        coupon_dates = BondPricer._coupon_dates(bond, settlement_date)
        if not coupon_dates:
            return 0.0

        pv = BondPricer.present_value(bond, ytm, settlement_date)
        if pv == 0:
            return 0.0

        coupon_payment = bond.face_value * bond.coupon_rate / bond.coupon_frequency
        discount_rate = 1 + ytm / bond.coupon_frequency

        convexity_sum = 0.0
        for coupon_date in coupon_dates:
            time_fraction = BondPricer._day_count_fraction(
                settlement_date, coupon_date, bond.day_count
            )
            periods = time_fraction * bond.coupon_frequency

            cf = (
                coupon_payment
                if coupon_date != bond.maturity_date
                else coupon_payment + bond.face_value
            )

            # t*(t+1) term in periods
            time_weight = periods * (periods + 1)
            # CORRECTED: divide by (discount_rate ** periods), not (periods + 2)
            convexity_sum += time_weight * cf / (discount_rate**periods)

        # CORRECTED: denominator is PV * (1+y/f)^2, not PV * f^2
        return convexity_sum / (pv * (discount_rate**2))

    @staticmethod
    def dv01(
        bond: Bond,
        ytm: float,
        settlement_date: date,
    ) -> float:
        """Calculate DV01 (dollar value of one basis point).

        Price change for 1 bp yield increase.

        Args:
            bond: Bond specification.
            ytm: Yield to maturity (annual).
            settlement_date: Settlement date.

        Returns:
            DV01 (positive value).
        """
        mod_dur = BondPricer.modified_duration(bond, ytm, settlement_date)
        pv = BondPricer.present_value(bond, ytm, settlement_date)
        # 1 bp = 0.0001
        return mod_dur * pv * 0.0001

    @staticmethod
    def accrued_interest(
        bond: Bond,
        settlement_date: date,
    ) -> float:
        """Calculate accrued interest since last coupon.

        Args:
            bond: Bond specification.
            settlement_date: Settlement date.

        Returns:
            Accrued interest amount.
        """
        if settlement_date >= bond.maturity_date:
            return 0.0

        # Generate all coupon dates from issue/start to maturity
        months_per_period = 12 // bond.coupon_frequency
        all_dates = []
        current = bond.maturity_date

        # Work backwards from maturity to generate all coupon dates
        while current >= (bond.issue_date if bond.issue_date else settlement_date):
            all_dates.append(current)
            year_offset = months_per_period // 12
            month_offset = months_per_period % 12

            if current.month <= month_offset:
                new_month = 12 + current.month - month_offset
                new_year = current.year - year_offset - 1
            else:
                new_month = current.month - month_offset
                new_year = current.year - year_offset

            current = current.replace(year=new_year, month=new_month)

        all_dates = sorted(all_dates)

        # Find last and next coupon dates
        last_coupon = None
        next_coupon = None
        for d in all_dates:
            if d <= settlement_date:
                last_coupon = d
            elif d > settlement_date and next_coupon is None:
                next_coupon = d
                break

        if last_coupon is None or next_coupon is None:
            return 0.0

        # Fraction of period elapsed
        days_since_last = BondPricer._day_count_fraction(
            last_coupon, settlement_date, bond.day_count
        )
        days_in_period = BondPricer._day_count_fraction(last_coupon, next_coupon, bond.day_count)

        if days_in_period == 0:
            return 0.0

        fraction_elapsed = days_since_last / days_in_period
        coupon_payment = bond.face_value * bond.coupon_rate / bond.coupon_frequency

        return coupon_payment * fraction_elapsed
