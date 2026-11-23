"""Cross-exchange and multi-leg arbitrage detection for crypto markets.

Implements:
- Triangular arbitrage (3-leg synthetic rate vs. direct rate)
- Cross-exchange spread arbitrage
- Stablecoin depeg arbitrage
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger


class TriangularArbModel:
    """Triangular arbitrage detection for crypto trading pairs.

    Example: BTC/USD, ETH/USD, BTC/ETH
    If BTC/USD * ETH/BTC != ETH/USD, arbitrage exists.

    Synthetic ETH/USD = (BTC/USD) * (ETH/BTC)
    Profit if |synthetic - direct| > fees.
    """

    @staticmethod
    def calculate_synthetic_rate(
        rate_ab: float,
        rate_bc: float,
        rate_ca: float | None = None,
    ) -> float:
        """Calculate synthetic exchange rate for triangular path.

        For A -> B -> C:
        Synthetic A/C = (A/B) * (B/C)

        Args:
            rate_ab: Exchange rate A/B (e.g., BTC/USD).
            rate_bc: Exchange rate B/C (e.g., ETH/BTC).
            rate_ca: Optional direct rate C/A for validation.

        Returns:
            Synthetic rate A/C.
        """
        synthetic = rate_ab * rate_bc
        if rate_ca is not None:
            # Cross-check: synthetic should approximately equal 1/rate_ca
            expected_ca = 1.0 / synthetic if synthetic != 0 else np.inf
            deviation = abs(expected_ca - rate_ca) / rate_ca if rate_ca != 0 else np.inf
            if deviation > 0.01:  # >1% deviation
                logger.warning(
                    f"Triangular rate deviation: synthetic={synthetic:.6f}, "
                    f"direct={1 / rate_ca if rate_ca != 0 else np.inf:.6f}"
                )
        return synthetic

    @staticmethod
    def detect_opportunity(
        rates: dict[str, float],
        fee_rate: float = 0.001,
    ) -> dict[str, float | str]:
        """Detect triangular arbitrage opportunity.

        Args:
            rates: Dictionary with 'AB', 'BC', 'AC' keys (e.g., {'AB': 50000, 'BC': 0.06, 'AC': 3000}).
            fee_rate: Trading fee per leg (default: 0.1% = 0.001).

        Returns:
            Dictionary with synthetic_rate, direct_rate, profit_pct, profitable.
        """
        if "AB" not in rates or "BC" not in rates or "AC" not in rates:
            raise ValueError("rates must contain 'AB', 'BC', 'AC' keys")

        synthetic_ac = TriangularArbModel.calculate_synthetic_rate(rates["AB"], rates["BC"])
        direct_ac = rates["AC"]

        # Profit calculation with COMPOUND fees (3 legs, each applies fee multiplicatively)
        # Effective synthetic after fees: synthetic * (1 - fee)^3
        synthetic_after_fees = synthetic_ac * ((1 - fee_rate) ** 3)
        # Profit = (synthetic_after_fees / direct - 1) * 100
        raw_profit_pct = abs(synthetic_ac - direct_ac) / direct_ac if direct_ac != 0 else 0.0
        net_profit_pct = (
            (synthetic_after_fees - direct_ac) / direct_ac * 100 if direct_ac != 0 else 0.0
        )

        profitable = net_profit_pct > 0

        logger.info(
            f"Triangular arbitrage: synthetic={synthetic_ac:.2f}, direct={direct_ac:.2f}, "
            f"net_profit={net_profit_pct:.4%}, profitable={profitable}"
        )

        return {
            "synthetic_rate": synthetic_ac,
            "direct_rate": direct_ac,
            "raw_profit_pct": raw_profit_pct,
            "net_profit_pct": net_profit_pct,
            "profitable": profitable,
        }


class CrossExchangeSpreadModel:
    """Cross-exchange arbitrage detection (spatial arbitrage).

    Buy on exchange with lowest price, sell on exchange with highest price.
    Profit must exceed transfer cost (withdrawal fees + slippage).
    """

    @staticmethod
    def detect_arbitrage(
        prices: dict[str, float],
        transfer_cost: float = 0.002,
    ) -> list[dict[str, float | str]]:
        """Detect profitable cross-exchange spreads.

        Args:
            prices: Dictionary of {exchange: price}.
            transfer_cost: Cost to transfer funds between exchanges (default: 0.2% = 0.002).

        Returns:
            List of arbitrage opportunities (buy_exchange, sell_exchange, profit_pct).
        """
        if len(prices) < 2:
            raise ValueError("Need at least 2 exchanges for cross-exchange arbitrage")

        opportunities = []
        exchanges = list(prices.keys())

        for i, buy_ex in enumerate(exchanges):
            for sell_ex in exchanges[i + 1 :]:
                buy_price = prices[buy_ex]
                sell_price = prices[sell_ex]

                # Calculate profit in both directions
                # Direction 1: Buy on buy_ex, sell on sell_ex
                profit_pct_1 = (sell_price - buy_price) / buy_price - transfer_cost
                # Direction 2: Buy on sell_ex, sell on buy_ex
                profit_pct_2 = (buy_price - sell_price) / sell_price - transfer_cost

                if profit_pct_1 > 0:
                    opportunities.append(
                        {
                            "buy_exchange": buy_ex,
                            "sell_exchange": sell_ex,
                            "buy_price": buy_price,
                            "sell_price": sell_price,
                            "profit_pct": profit_pct_1,
                        }
                    )
                if profit_pct_2 > 0:
                    opportunities.append(
                        {
                            "buy_exchange": sell_ex,
                            "sell_exchange": buy_ex,
                            "buy_price": sell_price,
                            "sell_price": buy_price,
                            "profit_pct": profit_pct_2,
                        }
                    )

        logger.info(f"Found {len(opportunities)} cross-exchange arbitrage opportunities")
        return opportunities


class StablecoinDepegModel:
    """Stablecoin depeg arbitrage detection.

    When a stablecoin (e.g., USDC, USDT) depegs from $1.00, arbitrage exists:
    - If price < $1.00: buy stablecoin, wait for repeg or redeem
    - If price > $1.00: sell/short stablecoin, buy back at $1.00

    Risk: Depeg may be permanent (e.g., UST collapse). Use with stop-loss.
    """

    @staticmethod
    def calculate_depeg(price: float, peg_value: float = 1.0) -> float:
        """Calculate depeg percentage.

        Args:
            price: Current stablecoin price.
            peg_value: Target peg value (default: $1.00).

        Returns:
            Depeg percentage (e.g., -0.05 = -5% below peg).
        """
        return (price - peg_value) / peg_value

    @staticmethod
    def generate_signals(
        df: pd.DataFrame,
        threshold: float = 0.005,
        stop_loss: float = 0.02,
    ) -> pd.DataFrame:
        """Generate stablecoin depeg arbitrage signals.

        Strategy:
        - Buy signal: price < (1 - threshold), expect mean reversion
        - Sell signal: price > (1 + threshold), expect mean reversion
        - Stop-loss: depeg > stop_loss (e.g., 2%), exit to prevent collapse risk

        Args:
            df: DataFrame with 'price' column.
            threshold: Minimum depeg to trigger signal (default: 0.5% = 0.005).
            stop_loss: Maximum depeg before exiting (default: 2% = 0.02).

        Returns:
            DataFrame with depeg, signal, stop_loss_triggered columns.
        """
        if "price" not in df.columns:
            raise ValueError("DataFrame must contain 'price' column")

        result = df.copy()
        result["depeg"] = result["price"].apply(StablecoinDepegModel.calculate_depeg)

        # Signal: 1 (buy) if depeg < -threshold, -1 (sell) if depeg > +threshold
        result["signal"] = 0
        result.loc[result["depeg"] < -threshold, "signal"] = 1
        result.loc[result["depeg"] > threshold, "signal"] = -1

        # Stop-loss trigger: absolute depeg > stop_loss
        result["stop_loss_triggered"] = result["depeg"].abs() > stop_loss

        logger.info(
            f"Generated depeg signals: {(result['signal'] == 1).sum()} buy, "
            f"{(result['signal'] == -1).sum()} sell, "
            f"{result['stop_loss_triggered'].sum()} stop-loss triggers"
        )
        return result[["depeg", "signal", "stop_loss_triggered"]]
