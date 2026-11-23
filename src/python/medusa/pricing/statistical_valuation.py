"""Statistical valuation models based on mean reversion and composite scoring."""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger


class MeanReversionValuation:
    """Mean reversion-based valuation using historical ratios."""

    @staticmethod
    def calculate_z_score(
        current_ratio: float,
        historical_series: pd.Series,
    ) -> float:
        r"""Calculate z-score for a valuation ratio.

        .. math::

            z = \frac{x - \mu}{\sigma}

        where:
        - :math:`x` = current ratio
        - :math:`\mu` = historical mean
        - :math:`\sigma` = historical standard deviation

        Args:
            current_ratio: Current valuation ratio (e.g., P/E, P/B).
            historical_series: Historical values of the same ratio.

        Returns:
            Z-score (number of standard deviations from mean).
        """
        if len(historical_series) < 2:
            raise ValueError("Historical series must have at least 2 observations")

        mean = historical_series.mean()
        std = historical_series.std()

        if std == 0:
            logger.warning("Historical series has zero variance, returning z=0")
            return 0.0

        z_score = (current_ratio - mean) / std

        logger.debug(
            f"Z-score: current={current_ratio:.2f}, mean={mean:.2f}, std={std:.2f}, z={z_score:.2f}"
        )

        return z_score

    @staticmethod
    def implied_fair_value(
        current_ratio: float,
        target_ratio: float,
        metric: str,
        fundamentals: pd.Series,
    ) -> float:
        r"""Calculate implied fair value based on target ratio.

        .. math::

            FV = \frac{\text{metric}}{\text{target\_ratio}}

        For example, if target P/E = 15 and EPS = $2, then FV = $30.

        Args:
            current_ratio: Current valuation ratio (e.g., P/E = 20).
            target_ratio: Target/fair valuation ratio (e.g., P/E = 15).
            metric: Name of the fundamental metric (e.g., 'earnings_per_share').
            fundamentals: Series with fundamental data.

        Returns:
            Implied fair value per share.

        Raises:
            ValueError: If metric is not in fundamentals.
        """
        if metric not in fundamentals:
            raise ValueError(f"Metric '{metric}' not found in fundamentals")

        if target_ratio <= 0:
            raise ValueError(f"Target ratio must be positive, got: {target_ratio}")

        metric_value = fundamentals[metric]

        # Implied fair value = metric / target_ratio
        # Example: EPS / target P/E = fair price
        fair_value = metric_value / target_ratio

        logger.info(
            f"Mean reversion FV: current ratio={current_ratio:.2f}, "
            f"target ratio={target_ratio:.2f}, {metric}={metric_value:.2f}, "
            f"implied FV={fair_value:.2f}"
        )

        return fair_value


class CompositeValuationScore:
    """Composite alpha score combining multiple valuation signals."""

    @staticmethod
    def calculate_alpha_score(
        metrics: dict[str, float],
        weights: dict[str, float] | None = None,
    ) -> float:
        """Calculate composite alpha score from multiple signals.

        Combines z-scores from multiple metrics into a single score (0-100).

        Args:
            metrics: Dictionary of metric_name -> z_score.
            weights: Optional dictionary of metric_name -> weight (default: equal weight).

        Returns:
            Composite alpha score (0-100 scale, higher = more attractive).

        Example:
            >>> metrics = {
            ...     "value": -1.5,  # Cheap (negative z-score)
            ...     "quality": 2.0,  # High quality
            ...     "momentum": 1.0,  # Positive momentum
            ... }
            >>> score = CompositeValuationScore.calculate_alpha_score(metrics)
            >>> print(score)  # ~70 (attractive)
        """
        if not metrics:
            raise ValueError("metrics dictionary cannot be empty")

        # Default to equal weights
        if weights is None:
            weights = {k: 1.0 / len(metrics) for k in metrics.keys()}

        # Validate weights
        if set(weights.keys()) != set(metrics.keys()):
            raise ValueError("weights keys must match metrics keys")

        if not np.isclose(sum(weights.values()), 1.0):
            raise ValueError(f"weights must sum to 1.0, got: {sum(weights.values())}")

        # Weighted sum of z-scores
        weighted_z = sum(metrics[k] * weights[k] for k in metrics.keys())

        # Convert to 0-100 scale using cumulative normal distribution
        # z=0 -> 50, z=+2 -> ~98, z=-2 -> ~2
        from scipy.stats import norm

        score = norm.cdf(weighted_z) * 100

        logger.debug(f"Composite alpha score: weighted_z={weighted_z:.2f}, score={score:.1f}")

        return score

    @staticmethod
    def rank_universe(
        universe: pd.DataFrame,
        metric_columns: list[str],
        weights: dict[str, float] | None = None,
    ) -> pd.DataFrame:
        """Rank entire universe using composite alpha scores.

        Args:
            universe: DataFrame with one row per asset, columns = metric values.
            metric_columns: List of column names to include in scoring.
            weights: Optional dictionary of column_name -> weight.

        Returns:
            DataFrame with additional columns: 'alpha_score', 'alpha_rank'.
            Sorted by alpha_score descending.

        Example:
            >>> universe = pd.DataFrame({
            ...     "symbol": ["AAPL", "MSFT", "GOOGL"],
            ...     "pe_ratio": [25, 30, 20],
            ...     "roe": [0.40, 0.35, 0.30],
            ...     "momentum": [0.15, 0.10, 0.20],
            ... })
            >>> result = CompositeValuationScore.rank_universe(
            ...     universe, ["pe_ratio", "roe", "momentum"]
            ... )
        """
        if not all(col in universe.columns for col in metric_columns):
            missing = [col for col in metric_columns if col not in universe.columns]
            raise ValueError(f"Missing columns in universe: {missing}")

        # Calculate z-scores for each metric
        z_scores = pd.DataFrame(index=universe.index)
        for col in metric_columns:
            mean = universe[col].mean()
            std = universe[col].std()
            if std > 0:
                z_scores[col] = (universe[col] - mean) / std
            else:
                z_scores[col] = 0.0

        # Calculate alpha score for each asset
        scores = []
        for idx in universe.index:
            metrics = z_scores.loc[idx].to_dict()
            score = CompositeValuationScore.calculate_alpha_score(metrics, weights)
            scores.append(score)

        # Add scores to universe
        result = universe.copy()
        result["alpha_score"] = scores
        result["alpha_rank"] = result["alpha_score"].rank(ascending=False)

        # Sort by score
        result = result.sort_values("alpha_score", ascending=False)

        logger.info(
            f"Ranked {len(result)} assets: "
            f"top score={result['alpha_score'].max():.1f}, "
            f"bottom score={result['alpha_score'].min():.1f}"
        )

        return result
