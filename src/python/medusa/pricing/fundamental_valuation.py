"""Fundamental valuation models for equity pricing.

Implements DCF (Discounted Cash Flow), Gordon Growth Model, and Comparable Valuation.
"""

from __future__ import annotations

from dataclasses import dataclass

import pandas as pd
from loguru import logger


@dataclass
class DCFInputs:
    """Inputs for DCF valuation model.

    Attributes:
        fcf_0: Most recent free cash flow (e.g., trailing twelve months).
        growth_rate_explicit: Growth rate during explicit forecast period (decimal, e.g., 0.15).
        years_explicit: Number of years in explicit forecast period (typically 5).
        growth_rate_terminal: Terminal growth rate (decimal, e.g., 0.03).
        wacc: Weighted average cost of capital (decimal, e.g., 0.10).
        shares_outstanding: Number of shares outstanding.
        net_debt: Net debt (total debt minus cash). Can be negative if cash exceeds debt.
    """

    fcf_0: float
    growth_rate_explicit: float
    years_explicit: int
    growth_rate_terminal: float
    wacc: float
    shares_outstanding: float
    net_debt: float = 0.0

    def __post_init__(self) -> None:
        """Validate DCF inputs."""
        if self.fcf_0 <= 0:
            raise ValueError(f"FCF must be positive, got: {self.fcf_0}")
        if self.growth_rate_explicit < 0 or self.growth_rate_explicit > 1:
            raise ValueError(
                f"Explicit growth rate must be in [0, 1], got: {self.growth_rate_explicit}"
            )
        if self.years_explicit <= 0:
            raise ValueError(f"Years explicit must be positive, got: {self.years_explicit}")
        if self.growth_rate_terminal < 0 or self.growth_rate_terminal > 0.10:
            raise ValueError(
                f"Terminal growth rate must be in [0, 0.10], got: {self.growth_rate_terminal}"
            )
        if self.wacc <= 0 or self.wacc > 1:
            raise ValueError(f"WACC must be in (0, 1], got: {self.wacc}")
        if self.wacc <= self.growth_rate_terminal:
            raise ValueError(
                f"WACC ({self.wacc}) must be > terminal growth ({self.growth_rate_terminal})"
            )
        if self.shares_outstanding <= 0:
            raise ValueError(f"Shares outstanding must be positive, got: {self.shares_outstanding}")


@dataclass
class DCFResult:
    """Results from DCF valuation calculation.

    Attributes:
        pv_explicit: Present value of explicit period cash flows.
        pv_terminal: Present value of terminal value.
        enterprise_value: Total enterprise value (PV explicit + PV terminal).
        equity_value: Equity value (enterprise value - net debt).
        fair_value_per_share: Fair value per share (equity value / shares outstanding).
        explicit_fcf: List of projected FCF during explicit period.
        terminal_fcf: First year terminal FCF.
    """

    pv_explicit: float
    pv_terminal: float
    enterprise_value: float
    equity_value: float
    fair_value_per_share: float
    explicit_fcf: list[float]
    terminal_fcf: float


class DCFValuation:
    """Discounted Cash Flow valuation model."""

    @staticmethod
    def calculate_fair_value(inputs: DCFInputs) -> DCFResult:
        r"""Calculate fair value using 2-stage DCF model.

        Two-stage model:
        1. Explicit forecast period: project FCF at explicit growth rate
        2. Terminal period: perpetual growth at terminal rate

        .. math::

            EV = \sum_{t=1}^{n} \frac{FCF_t}{(1+WACC)^t} + \frac{TV}{(1+WACC)^n}

        where terminal value:

        .. math::

            TV = \frac{FCF_{n+1}}{WACC - g_{terminal}}

        Args:
            inputs: DCF input parameters.

        Returns:
            DCFResult with fair value and components.
        """
        explicit_fcf = []
        pv_explicit = 0.0

        # Project explicit period cash flows
        fcf = inputs.fcf_0
        for year in range(1, inputs.years_explicit + 1):
            fcf *= 1 + inputs.growth_rate_explicit
            explicit_fcf.append(fcf)

            # Discount to present value
            discount_factor = (1 + inputs.wacc) ** year
            pv_explicit += fcf / discount_factor

        # Terminal value: perpetuity with terminal growth rate
        terminal_fcf = fcf * (1 + inputs.growth_rate_terminal)
        terminal_value = terminal_fcf / (inputs.wacc - inputs.growth_rate_terminal)

        # Discount terminal value to present
        pv_terminal = terminal_value / ((1 + inputs.wacc) ** inputs.years_explicit)

        # Enterprise value = PV of explicit + PV of terminal
        enterprise_value = pv_explicit + pv_terminal

        # Equity value = EV - net debt
        equity_value = enterprise_value - inputs.net_debt

        # Fair value per share
        fair_value_per_share = equity_value / inputs.shares_outstanding

        logger.debug(
            f"DCF: EV={enterprise_value:.2f}, Equity={equity_value:.2f}, "
            f"FV/share={fair_value_per_share:.2f}"
        )

        return DCFResult(
            pv_explicit=pv_explicit,
            pv_terminal=pv_terminal,
            enterprise_value=enterprise_value,
            equity_value=equity_value,
            fair_value_per_share=fair_value_per_share,
            explicit_fcf=explicit_fcf,
            terminal_fcf=terminal_fcf,
        )

    @staticmethod
    def sensitivity_analysis(
        inputs: DCFInputs,
        wacc_range: tuple[float, float],
        growth_range: tuple[float, float],
        steps: int = 5,
    ) -> pd.DataFrame:
        """Perform sensitivity analysis on WACC and terminal growth rate.

        Args:
            inputs: Base DCF inputs.
            wacc_range: (min, max) WACC values to test.
            growth_range: (min, max) terminal growth values to test.
            steps: Number of steps in each dimension.

        Returns:
            DataFrame with WACC as index, terminal growth as columns, fair value as values.
        """
        wacc_values = [
            wacc_range[0] + i * (wacc_range[1] - wacc_range[0]) / (steps - 1) for i in range(steps)
        ]
        growth_values = [
            growth_range[0] + i * (growth_range[1] - growth_range[0]) / (steps - 1)
            for i in range(steps)
        ]

        results = []
        for wacc in wacc_values:
            row = []
            for growth in growth_values:
                # Skip invalid combinations (WACC must be > terminal growth)
                if wacc <= growth:
                    row.append(float("nan"))
                    continue

                # Create modified inputs
                modified = DCFInputs(
                    fcf_0=inputs.fcf_0,
                    growth_rate_explicit=inputs.growth_rate_explicit,
                    years_explicit=inputs.years_explicit,
                    growth_rate_terminal=growth,
                    wacc=wacc,
                    shares_outstanding=inputs.shares_outstanding,
                    net_debt=inputs.net_debt,
                )

                try:
                    result = DCFValuation.calculate_fair_value(modified)
                    row.append(result.fair_value_per_share)
                except ValueError:
                    row.append(float("nan"))

            results.append(row)

        df = pd.DataFrame(
            results,
            index=[f"{w:.2%}" for w in wacc_values],
            columns=[f"{g:.2%}" for g in growth_values],
        )
        df.index.name = "WACC"
        df.columns.name = "Terminal Growth"

        logger.info(f"Sensitivity analysis: {steps}x{steps} grid computed")
        return df


class GordonGrowthModel:
    """Gordon Growth Model (perpetuity with constant growth)."""

    @staticmethod
    def calculate_fair_value(
        dividend: float,
        growth_rate: float,
        cost_of_equity: float,
    ) -> float:
        r"""Calculate fair value using Gordon Growth Model.

        .. math::

            P_0 = \frac{D_1}{r - g}

        where:
        - :math:`D_1` = next year's dividend
        - :math:`r` = required return (cost of equity)
        - :math:`g` = perpetual dividend growth rate

        Args:
            dividend: Next year's expected dividend per share.
            growth_rate: Perpetual dividend growth rate (decimal).
            cost_of_equity: Required return / cost of equity (decimal).

        Returns:
            Fair value per share.

        Raises:
            ValueError: If cost_of_equity <= growth_rate (model undefined).
        """
        if cost_of_equity <= growth_rate:
            raise ValueError(
                f"Cost of equity ({cost_of_equity}) must be > growth rate ({growth_rate})"
            )
        if dividend < 0:
            raise ValueError(f"Dividend must be non-negative, got: {dividend}")
        if growth_rate < 0:
            raise ValueError(f"Growth rate must be non-negative, got: {growth_rate}")
        if cost_of_equity <= 0:
            raise ValueError(f"Cost of equity must be positive, got: {cost_of_equity}")

        fair_value = dividend / (cost_of_equity - growth_rate)

        logger.debug(
            f"Gordon Growth: D={dividend:.2f}, g={growth_rate:.2%}, "
            f"r={cost_of_equity:.2%}, FV={fair_value:.2f}"
        )

        return fair_value


class ComparableValuation:
    """Valuation using comparable company multiples."""

    @staticmethod
    def implied_value_from_peers(
        target: pd.Series,
        peers: pd.DataFrame,
        multiple: str = "pe",
    ) -> float:
        """Calculate implied value from peer company multiples.

        Args:
            target: Series with target company's fundamentals (EPS, revenue, EBITDA, etc.).
            peers: DataFrame with peer companies' multiples (columns: pe, pb, ps, ev_ebitda).
            multiple: Multiple to use ("pe", "pb", "ps", "ev_ebitda").

        Returns:
            Implied value per share based on peer median multiple.

        Raises:
            ValueError: If multiple is not supported or data is missing.
        """
        supported_multiples = {
            "pe": ("earnings_per_share", "pe"),
            "pb": ("book_value_per_share", "pb"),
            "ps": ("revenue_per_share", "ps"),
            "ev_ebitda": ("ebitda_per_share", "ev_ebitda"),
        }

        if multiple not in supported_multiples:
            raise ValueError(
                f"Unsupported multiple: {multiple}. Supported: {list(supported_multiples.keys())}"
            )

        target_metric, peer_column = supported_multiples[multiple]

        if target_metric not in target:
            raise ValueError(f"Target missing '{target_metric}' field")
        if peer_column not in peers.columns:
            raise ValueError(f"Peers missing '{peer_column}' column")

        # Calculate median peer multiple
        peer_median = peers[peer_column].median()

        # Implied value = target metric × peer median multiple
        implied_value = target[target_metric] * peer_median

        logger.info(
            f"Comparable valuation ({multiple}): "
            f"target {target_metric}={target[target_metric]:.2f}, "
            f"peer median {peer_column}={peer_median:.2f}, "
            f"implied value={implied_value:.2f}"
        )

        return implied_value
