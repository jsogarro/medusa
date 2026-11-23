"""Multi-factor alpha model for cryptocurrency portfolios.

Implements a quantitative factor model with six crypto-specific factors:
1. Momentum: 1-month and 3-month price momentum
2. Volatility: realized volatility (mean-reversion signal)
3. Liquidity: trading volume and bid-ask spread
4. Network Activity: on-chain metrics (active addresses, tx volume)
5. Sentiment: social media mentions, Google Trends
6. Market Correlation: correlation to BTC (diversification signal)

Combines factors into alpha scores and portfolio weights.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger


class CryptoFactorModel:
    """Multi-factor alpha model for crypto portfolios.

    Generates alpha scores by combining six fundamental crypto factors:
    - Momentum (trend following)
    - Volatility (mean reversion)
    - Liquidity (execution quality)
    - Network Activity (fundamental health)
    - Sentiment (crowd psychology)
    - Correlation (diversification)

    Each factor is z-scored and weighted equally by default.
    """

    # Factor weights (sum to 1.0)
    FACTOR_WEIGHTS = {
        "momentum": 0.20,
        "volatility": 0.15,
        "liquidity": 0.15,
        "network": 0.20,
        "sentiment": 0.15,
        "correlation": 0.15,
    }

    @staticmethod
    def _zscore(series: pd.Series) -> pd.Series:
        """Calculate z-score (standardize to mean=0, std=1)."""
        mean = series.mean()
        std = series.std()
        return (series - mean) / std if std > 0 else pd.Series(0, index=series.index)

    @staticmethod
    def calculate_momentum_factor(df: pd.DataFrame) -> pd.Series:
        """Calculate momentum factor (1-month and 3-month returns).

        Args:
            df: DataFrame with 'price' column and DatetimeIndex.

        Returns:
            Z-scored momentum factor.
        """
        if "price" not in df.columns:
            raise ValueError("DataFrame must contain 'price' column")

        # 1-month and 3-month log returns
        returns_1m = np.log(df["price"] / df["price"].shift(21))  # ~21 trading days
        returns_3m = np.log(df["price"] / df["price"].shift(63))  # ~63 trading days

        # Equal weight average
        momentum = (returns_1m + returns_3m) / 2
        return CryptoFactorModel._zscore(momentum)

    @staticmethod
    def calculate_volatility_factor(df: pd.DataFrame, window: int = 20) -> pd.Series:
        """Calculate volatility factor (mean-reversion signal).

        High volatility assets tend to mean-revert, so we invert the signal.

        Args:
            df: DataFrame with 'price' column.
            window: Rolling window for volatility calculation.

        Returns:
            Z-scored volatility factor (inverted: low vol = positive signal).
        """
        if "price" not in df.columns:
            raise ValueError("DataFrame must contain 'price' column")

        log_returns = np.log(df["price"] / df["price"].shift(1))
        volatility = log_returns.rolling(window).std() * np.sqrt(252)  # Annualized

        # Invert: low volatility = positive signal
        return CryptoFactorModel._zscore(-volatility)

    @staticmethod
    def calculate_liquidity_factor(df: pd.DataFrame) -> pd.Series:
        """Calculate liquidity factor (volume and spread).

        Higher volume and tighter spreads indicate better liquidity.

        Args:
            df: DataFrame with 'volume' and optional 'spread' columns.

        Returns:
            Z-scored liquidity factor.
        """
        if "volume" not in df.columns:
            raise ValueError("DataFrame must contain 'volume' column")

        # Volume z-score
        volume_zscore = CryptoFactorModel._zscore(df["volume"])

        if "spread" in df.columns:
            # Spread z-score (inverted: low spread = positive signal)
            spread_zscore = CryptoFactorModel._zscore(-df["spread"])
            # Average volume and spread signals
            liquidity = (volume_zscore + spread_zscore) / 2
        else:
            liquidity = volume_zscore

        return liquidity

    @staticmethod
    def calculate_network_factor(df: pd.DataFrame) -> pd.Series:
        """Calculate network activity factor (on-chain metrics).

        Higher active addresses and tx volume indicate stronger network health.

        Args:
            df: DataFrame with 'active_addresses' and 'tx_volume_usd' columns.

        Returns:
            Z-scored network factor.
        """
        if "active_addresses" not in df.columns or "tx_volume_usd" not in df.columns:
            raise ValueError(
                "DataFrame must contain 'active_addresses' and 'tx_volume_usd' columns"
            )

        # Z-score both metrics and average
        addresses_zscore = CryptoFactorModel._zscore(df["active_addresses"])
        tx_volume_zscore = CryptoFactorModel._zscore(df["tx_volume_usd"])
        return (addresses_zscore + tx_volume_zscore) / 2

    @staticmethod
    def calculate_sentiment_factor(df: pd.DataFrame) -> pd.Series:
        """Calculate sentiment factor (social media, search trends).

        Args:
            df: DataFrame with 'sentiment_score' column (e.g., Twitter mentions, Google Trends).

        Returns:
            Z-scored sentiment factor.
        """
        if "sentiment_score" not in df.columns:
            raise ValueError("DataFrame must contain 'sentiment_score' column")

        return CryptoFactorModel._zscore(df["sentiment_score"])

    @staticmethod
    def calculate_correlation_factor(df: pd.DataFrame, btc_returns: pd.Series) -> pd.Series:
        """Calculate correlation factor (diversification from BTC).

        Lower correlation to BTC provides portfolio diversification.

        Args:
            df: DataFrame with 'price' column.
            btc_returns: Series of BTC returns (aligned index).

        Returns:
            Z-scored correlation factor (inverted: low correlation = positive signal).
        """
        if "price" not in df.columns:
            raise ValueError("DataFrame must contain 'price' column")

        # Calculate rolling 30-day correlation to BTC
        returns = np.log(df["price"] / df["price"].shift(1))
        rolling_corr = returns.rolling(30).corr(btc_returns)

        # Invert: low correlation = positive signal (diversification benefit)
        return CryptoFactorModel._zscore(-rolling_corr)

    @staticmethod
    def calculate_alpha_score(
        factors: pd.DataFrame,
        weights: dict[str, float] | None = None,
    ) -> pd.Series:
        """Combine factors into alpha score.

        Args:
            factors: DataFrame with factor columns (each z-scored).
            weights: Factor weights (default: equal weights).

        Returns:
            Series with alpha scores.
        """
        if weights is None:
            weights = CryptoFactorModel.FACTOR_WEIGHTS

        # Validate weights sum to 1.0
        total_weight = sum(weights.values())
        if not np.isclose(total_weight, 1.0):
            raise ValueError(f"Factor weights must sum to 1.0, got {total_weight}")

        # Weighted sum of factors
        alpha = pd.Series(0.0, index=factors.index)
        for factor_name, weight in weights.items():
            if factor_name in factors.columns:
                alpha += weight * factors[factor_name]
            else:
                logger.warning(f"Factor '{factor_name}' not found in DataFrame, skipping")

        logger.info(f"Calculated alpha scores (mean={alpha.mean():.3f}, std={alpha.std():.3f})")
        return alpha

    @staticmethod
    def generate_portfolio_weights(
        alpha_scores: pd.Series,
        long_only: bool = False,
    ) -> pd.Series:
        """Convert alpha scores to portfolio weights.

        Args:
            alpha_scores: Series of alpha scores (one per asset).
            long_only: If True, only positive weights (default: long-short).

        Returns:
            Series of portfolio weights (sum to 1.0 for long positions).
        """
        if long_only:
            # Long-only: normalize positive alphas to sum to 1.0
            positive_alphas = alpha_scores.clip(lower=0)
            total = positive_alphas.sum()
            weights = positive_alphas / total if total > 0 else alpha_scores * 0
        else:
            # Long-short: rank-based dollar-neutral portfolio
            # Positive alphas -> long (sum to +1), negative alphas -> short (sum to -1)
            positive_alphas = alpha_scores.clip(lower=0)
            negative_alphas = alpha_scores.clip(upper=0)

            pos_sum = positive_alphas.sum()
            neg_sum = negative_alphas.abs().sum()

            if pos_sum > 0 and neg_sum > 0:
                # Normalize longs to +1, shorts to -1
                weights = positive_alphas / pos_sum - negative_alphas.abs() / neg_sum
            elif pos_sum > 0:
                # Only longs
                weights = positive_alphas / pos_sum
            elif neg_sum > 0:
                # Only shorts
                weights = -negative_alphas.abs() / neg_sum
            else:
                weights = alpha_scores * 0

        logger.info(
            f"Generated portfolio weights: {(weights > 0).sum()} longs, "
            f"{(weights < 0).sum()} shorts, sum={weights.sum():.3f}"
        )
        return weights
