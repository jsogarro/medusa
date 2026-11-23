"""Derivatives pricing models for cryptocurrency futures and perpetuals.

Implements pricing and arbitrage detection for crypto derivatives:
- Perpetual swap funding rates and carry arbitrage
- Futures basis and cash-and-carry arbitrage
"""

from __future__ import annotations

import pandas as pd
from loguru import logger


class PerpetualFundingModel:
    """Perpetual futures funding rate analysis and carry arbitrage detection.

    Perpetual swaps have no expiry and use funding rates to anchor price to spot.
    Positive funding (longs pay shorts) indicates bullish sentiment; negative funding
    (shorts pay longs) indicates bearish sentiment. Large funding rates create
    carry arbitrage opportunities.

    Typical funding periods: 8 hours (3x per day).
    """

    @staticmethod
    def calculate_annualized_carry(funding_rate_8h: float) -> float:
        """Calculate annualized carry from 8-hour funding rate.

        Args:
            funding_rate_8h: Funding rate per 8-hour period (e.g., 0.0001 = 0.01%).

        Returns:
            Annualized carry rate (e.g., 0.109 = 10.9% APR).
        """
        # 3 funding periods per day × 365 days
        # Compound: (1 + r)^(3*365) - 1
        periods_per_year = 3 * 365
        annualized = (1 + funding_rate_8h) ** periods_per_year - 1
        return float(annualized)

    @staticmethod
    def detect_arbitrage(df: pd.DataFrame, threshold: float = 0.001) -> pd.DataFrame:
        """Detect funding rate carry arbitrage opportunities.

        Strategy:
        - If funding rate > threshold: short perp, long spot (collect funding)
        - If funding rate < -threshold: long perp, short spot (collect funding)

        Args:
            df: DataFrame with 'funding_rate' column (8-hour rate).
            threshold: Absolute funding rate threshold (default: 0.1% = 0.001).

        Returns:
            DataFrame with carry, annualized_carry, arbitrage_signal columns.
        """
        if "funding_rate" not in df.columns:
            raise ValueError("DataFrame must contain 'funding_rate' column")

        result = df.copy()
        result["carry"] = result["funding_rate"]
        result["annualized_carry"] = result["funding_rate"].apply(
            PerpetualFundingModel.calculate_annualized_carry
        )

        # Arbitrage signal: 1 (short perp) if funding > threshold, -1 (long perp) if < -threshold
        result["arbitrage_signal"] = 0
        result.loc[result["funding_rate"] > threshold, "arbitrage_signal"] = 1
        result.loc[result["funding_rate"] < -threshold, "arbitrage_signal"] = -1

        logger.info(
            f"Detected funding arbitrage: {(result['arbitrage_signal'] != 0).sum()} opportunities, "
            f"mean annualized carry={result['annualized_carry'].mean():.2%}"
        )
        return result[["carry", "annualized_carry", "arbitrage_signal"]]


class FuturesBasisModel:
    """Futures basis analysis and cash-and-carry arbitrage detection.

    Futures basis = Futures Price - Spot Price. Positive basis (contango) is normal
    due to time value of money. Excessive basis creates cash-and-carry arbitrage:
    buy spot, sell futures, hold to expiry.

    Basis is typically quoted as annualized percentage of spot price.
    """

    @staticmethod
    def calculate_basis(futures_price: float, spot_price: float) -> float:
        """Calculate raw basis (futures premium/discount to spot).

        Args:
            futures_price: Futures contract price.
            spot_price: Spot market price.

        Returns:
            Basis (futures_price - spot_price).
        """
        return futures_price - spot_price

    @staticmethod
    def annualize_basis(basis: float, spot: float, days_to_expiry: int) -> float:
        """Annualize basis as percentage of spot price.

        Args:
            basis: Raw basis (futures - spot).
            spot: Spot price.
            days_to_expiry: Days until futures expiry.

        Returns:
            Annualized basis as percentage (e.g., 0.05 = 5% APR).
        """
        if days_to_expiry <= 0:
            raise ValueError("Days to expiry must be positive")
        if spot <= 0:
            raise ValueError("Spot price must be positive")

        # (basis / spot) * (365 / days_to_expiry)
        return (basis / spot) * (365.0 / days_to_expiry)

    @staticmethod
    def detect_arbitrage(df: pd.DataFrame, cost_threshold: float = 0.05) -> pd.DataFrame:
        """Detect cash-and-carry arbitrage opportunities.

        Strategy: If annualized basis > cost_threshold (e.g., 5%), execute:
        - Buy spot (borrow if needed at borrowing rate)
        - Sell futures
        - Hold to expiry and deliver

        Args:
            df: DataFrame with 'futures_price', 'spot_price', 'days_to_expiry'.
            cost_threshold: Minimum annualized basis (as percentage) to signal arbitrage.

        Returns:
            DataFrame with basis, annualized_basis, arbitrage_signal columns.
        """
        required = ["futures_price", "spot_price", "days_to_expiry"]
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise ValueError(f"Missing required columns: {missing}")

        result = df.copy()

        # Calculate basis and annualized basis
        result["basis"] = result.apply(
            lambda row: FuturesBasisModel.calculate_basis(row["futures_price"], row["spot_price"]),
            axis=1,
        )
        result["annualized_basis"] = result.apply(
            lambda row: (
                FuturesBasisModel.annualize_basis(
                    row["basis"], row["spot_price"], int(row["days_to_expiry"])
                )
                if row["days_to_expiry"] > 0
                else 0.0
            ),
            axis=1,
        )

        # Arbitrage signal: 1 if annualized basis > threshold (contango arbitrage)
        # -1 if annualized basis < -threshold (backwardation arbitrage, rare in crypto)
        result["arbitrage_signal"] = 0
        result.loc[result["annualized_basis"] > cost_threshold, "arbitrage_signal"] = 1
        result.loc[result["annualized_basis"] < -cost_threshold, "arbitrage_signal"] = -1

        logger.info(
            f"Detected futures arbitrage: {(result['arbitrage_signal'] == 1).sum()} contango, "
            f"{(result['arbitrage_signal'] == -1).sum()} backwardation, "
            f"mean annualized basis={result['annualized_basis'].mean():.2%}"
        )
        return result[["basis", "annualized_basis", "arbitrage_signal"]]
