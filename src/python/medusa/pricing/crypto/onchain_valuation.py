"""On-chain valuation models for cryptocurrency pricing.

Implements fundamental crypto valuation frameworks based on on-chain metrics:
- NVT (Network Value to Transactions): P/E ratio analogue for crypto
- MVRV (Market Value to Realized Value): profit/loss ratio for holders
- Stock-to-Flow: scarcity-based fair value model for Bitcoin
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger


class NVTModel:
    """Network Value to Transactions ratio model.

    NVT is analogous to a P/E ratio for cryptocurrencies, measuring network value
    (market cap) relative to transaction volume. High NVT suggests overvaluation;
    low NVT suggests undervaluation.

    Reference: Willy Woo (2017), "NVT Ratio — Bitcoin's 'PE Ratio'"
    """

    @staticmethod
    def calculate_nvt(df: pd.DataFrame) -> pd.Series:
        """Calculate NVT ratio.

        Args:
            df: DataFrame with 'market_cap' and 'tx_volume_usd' columns.

        Returns:
            Series with NVT values.
        """
        if "market_cap" not in df.columns or "tx_volume_usd" not in df.columns:
            raise ValueError("DataFrame must contain 'market_cap' and 'tx_volume_usd' columns")

        # NVT = Market Cap / Daily Transaction Volume
        # Use 7-day MA of tx volume to smooth daily fluctuations
        tx_volume_ma = df["tx_volume_usd"].rolling(7, min_periods=1).mean()
        nvt = df["market_cap"] / tx_volume_ma.replace(0, np.nan)

        logger.info(f"Calculated NVT ratio (mean={nvt.mean():.2f}, std={nvt.std():.2f})")
        return nvt

    @staticmethod
    def generate_signals(df: pd.DataFrame, lookback: int = 365) -> pd.DataFrame:
        """Generate buy/sell signals from NVT ratio.

        Strategy: Buy when NVT < -1 std, sell when NVT > +1 std (over lookback period).

        Args:
            df: DataFrame with 'market_cap' and 'tx_volume_usd'.
            lookback: Window for calculating mean/std (default: 365 days).

        Returns:
            DataFrame with columns: nvt, nvt_mean, nvt_std, zscore, signal.
        """
        result = df.copy()
        result["nvt"] = NVTModel.calculate_nvt(df)

        # Z-score over lookback period
        result["nvt_mean"] = result["nvt"].rolling(lookback, min_periods=30).mean()
        result["nvt_std"] = result["nvt"].rolling(lookback, min_periods=30).std()
        result["zscore"] = (result["nvt"] - result["nvt_mean"]) / result["nvt_std"].replace(
            0, np.nan
        )

        # Signal: 1 (buy) when NVT < -1 std, -1 (sell) when NVT > +1 std
        result["signal"] = 0
        result.loc[result["zscore"] < -1.0, "signal"] = 1
        result.loc[result["zscore"] > 1.0, "signal"] = -1

        logger.info(
            f"Generated NVT signals: {(result['signal'] == 1).sum()} buys, "
            f"{(result['signal'] == -1).sum()} sells"
        )
        return result[["nvt", "nvt_mean", "nvt_std", "zscore", "signal"]]


class MVRVModel:
    """Market Value to Realized Value ratio model.

    MVRV measures the ratio of market cap to realized cap (average cost basis of all coins).
    High MVRV indicates holders are in profit (potential distribution zone); low MVRV
    indicates holders are at a loss (potential accumulation zone).

    Reference: Murad Mahmudov & David Puell (2018), "Realized Cap & MVRV"
    """

    @staticmethod
    def calculate_mvrv(df: pd.DataFrame) -> pd.Series:
        """Calculate MVRV ratio.

        Args:
            df: DataFrame with 'market_cap' and 'realized_cap' columns.

        Returns:
            Series with MVRV values.
        """
        if "market_cap" not in df.columns or "realized_cap" not in df.columns:
            raise ValueError("DataFrame must contain 'market_cap' and 'realized_cap' columns")

        # MVRV = Market Cap / Realized Cap
        mvrv = df["market_cap"] / df["realized_cap"].replace(0, np.nan)

        logger.info(f"Calculated MVRV ratio (mean={mvrv.mean():.2f}, std={mvrv.std():.2f})")
        return mvrv

    @staticmethod
    def generate_signals(df: pd.DataFrame) -> pd.DataFrame:
        """Generate buy/sell signals from MVRV ratio.

        Strategy:
        - MVRV > 3.5: Strong sell signal (historically marks local tops)
        - MVRV < 1.0: Strong buy signal (market trading below cost basis)

        Args:
            df: DataFrame with 'market_cap' and 'realized_cap'.

        Returns:
            DataFrame with columns: mvrv, signal.
        """
        result = df.copy()
        result["mvrv"] = MVRVModel.calculate_mvrv(df)

        # Signal: 1 (buy) when MVRV < 1.0, -1 (sell) when MVRV > 3.5
        result["signal"] = 0
        result.loc[result["mvrv"] < 1.0, "signal"] = 1
        result.loc[result["mvrv"] > 3.5, "signal"] = -1

        logger.info(
            f"Generated MVRV signals: {(result['signal'] == 1).sum()} buys, "
            f"{(result['signal'] == -1).sum()} sells"
        )
        return result[["mvrv", "signal"]]


class StockToFlowModel:
    """Stock-to-Flow model for Bitcoin valuation.

    S2F measures the ratio of existing supply (stock) to annual production (flow).
    Higher S2F indicates greater scarcity. The model uses a power law regression
    to estimate fair value from S2F.

    Reference: PlanB (2019), "Modeling Bitcoin's Value with Scarcity"

    Regression: ln(price) = a + b * ln(S2F)
    Empirical coefficients (PlanB 2019-2023): a ≈ 14.6, b ≈ 3.0
    """

    # Empirical coefficients from PlanB's model (updated 2023)
    REGRESSION_INTERCEPT = 14.6
    REGRESSION_SLOPE = 3.0

    @staticmethod
    def calculate_s2f(supply: float, annual_production: float) -> float:
        """Calculate Stock-to-Flow ratio.

        Args:
            supply: Current circulating supply.
            annual_production: Expected annual new supply (flow).

        Returns:
            Stock-to-Flow ratio.
        """
        if annual_production <= 0:
            raise ValueError("Annual production must be positive")

        return supply / annual_production

    @staticmethod
    def predict_fair_value(s2f: float) -> float:
        """Predict fair value using power law regression.

        Args:
            s2f: Stock-to-Flow ratio.

        Returns:
            Predicted fair value in USD.
        """
        # ln(price) = a + b * ln(S2F)
        # price = exp(a + b * ln(S2F)) = exp(a) * S2F^b
        log_price = (
            StockToFlowModel.REGRESSION_INTERCEPT + StockToFlowModel.REGRESSION_SLOPE * np.log(s2f)
        )
        return float(np.exp(log_price))

    @staticmethod
    def generate_signals(df: pd.DataFrame) -> pd.DataFrame:
        """Generate buy signals from Stock-to-Flow model.

        Strategy: Buy when price < 70% of S2F fair value (significant discount).

        Args:
            df: DataFrame with 'price', 'supply', 'annual_production' columns.

        Returns:
            DataFrame with columns: s2f, fair_value, price_to_fair_value, signal.
        """
        required = ["price", "supply", "annual_production"]
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise ValueError(f"Missing required columns: {missing}")

        result = df.copy()
        result["s2f"] = result.apply(
            lambda row: StockToFlowModel.calculate_s2f(row["supply"], row["annual_production"]),
            axis=1,
        )
        result["fair_value"] = result["s2f"].apply(StockToFlowModel.predict_fair_value)
        result["price_to_fair_value"] = result["price"] / result["fair_value"]

        # Signal: 1 (buy) when price < 70% of fair value
        result["signal"] = 0
        result.loc[result["price_to_fair_value"] < 0.7, "signal"] = 1

        logger.info(
            f"Generated S2F signals: {(result['signal'] == 1).sum()} buys, "
            f"mean price/fair_value={result['price_to_fair_value'].mean():.2f}"
        )
        return result[["s2f", "fair_value", "price_to_fair_value", "signal"]]
