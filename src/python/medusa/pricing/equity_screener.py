"""Equity screening and ranking system for alpha generation."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import pandas as pd
from loguru import logger


class EquityScreener:
    """Multi-criteria equity screener."""

    @staticmethod
    def screen(
        universe: pd.DataFrame,
        criteria: dict[str, tuple[str, Any]],
    ) -> pd.DataFrame:
        """Apply screening criteria to filter universe.

        Args:
            universe: DataFrame with one row per asset.
            criteria: Dictionary of column_name -> (operator, threshold).
                Operators: '>', '>=', '<', '<=', '==', '!=', 'in', 'not_in'.

        Returns:
            Filtered DataFrame containing only assets passing all criteria.

        Example:
            >>> universe = pd.DataFrame({
            ...     "symbol": ["AAPL", "MSFT", "GOOGL", "TSLA"],
            ...     "market_cap": [2800, 2500, 1800, 800],
            ...     "pe_ratio": [28, 32, 25, 150],
            ...     "roe": [0.40, 0.35, 0.28, 0.10],
            ... })
            >>> criteria = {
            ...     "market_cap": (">=", 1000),
            ...     "pe_ratio": ("<", 30),
            ...     "roe": (">", 0.20),
            ... }
            >>> result = EquityScreener.screen(universe, criteria)
            >>> print(result["symbol"].tolist())  # ['AAPL', 'GOOGL']
        """
        if universe.empty:
            logger.warning("Universe is empty, returning empty DataFrame")
            return pd.DataFrame()

        result = universe.copy()

        for column, (operator, threshold) in criteria.items():
            if column not in result.columns:
                raise ValueError(f"Column '{column}' not found in universe")

            initial_count = len(result)

            if operator == ">":
                result = result[result[column] > threshold]
            elif operator == ">=":
                result = result[result[column] >= threshold]
            elif operator == "<":
                result = result[result[column] < threshold]
            elif operator == "<=":
                result = result[result[column] <= threshold]
            elif operator == "==":
                result = result[result[column] == threshold]
            elif operator == "!=":
                result = result[result[column] != threshold]
            elif operator == "in":
                if not isinstance(threshold, (list, set, tuple)):
                    raise ValueError(f"'in' operator requires list/set, got: {type(threshold)}")
                result = result[result[column].isin(threshold)]
            elif operator == "not_in":
                if not isinstance(threshold, (list, set, tuple)):
                    raise ValueError(f"'not_in' operator requires list/set, got: {type(threshold)}")
                result = result[~result[column].isin(threshold)]
            else:
                raise ValueError(f"Unsupported operator: {operator}")

            filtered_count = initial_count - len(result)
            logger.debug(
                f"Filter {column} {operator} {threshold}: "
                f"removed {filtered_count} assets, {len(result)} remaining"
            )

        logger.info(f"Screening complete: {len(result)}/{len(universe)} assets passed all criteria")

        return result

    @staticmethod
    def multi_stage_screen(
        universe: pd.DataFrame,
        stages: list[dict[str, tuple[str, Any]]],
    ) -> tuple[pd.DataFrame, list[int]]:
        """Apply multi-stage screening with funnel tracking.

        Args:
            universe: Initial universe DataFrame.
            stages: List of criteria dictionaries (one per stage).

        Returns:
            Tuple of (final_result, counts_per_stage).

        Example:
            >>> stages = [
            ...     {"market_cap": (">=", 1000)},  # Stage 1: Large cap
            ...     {"pe_ratio": ("<", 30), "roe": (">", 0.20)},  # Stage 2: Value + Quality
            ... ]
            >>> result, counts = EquityScreener.multi_stage_screen(universe, stages)
            >>> print(counts)  # [4, 2] (4 after stage 1, 2 after stage 2)
        """
        result = universe.copy()
        counts = []

        for i, criteria in enumerate(stages, start=1):
            result = EquityScreener.screen(result, criteria)
            counts.append(len(result))
            logger.info(f"Stage {i}: {len(result)} assets remaining")

        return result, counts


class AlphaRanker:
    """Ranking system for alpha generation."""

    @staticmethod
    def rank_universe(
        universe: pd.DataFrame,
        scorer: Callable[[pd.Series], float],
        top_n: int = 50,
    ) -> pd.DataFrame:
        """Rank universe using a custom scoring function.

        Args:
            universe: DataFrame with one row per asset.
            scorer: Function that takes a row (pd.Series) and returns a score (float).
            top_n: Number of top-ranked assets to return.

        Returns:
            DataFrame with top N assets, sorted by score descending.
            Includes 'alpha_score' and 'rank' columns.

        Example:
            >>> def value_quality_scorer(row):
            ...     # Lower P/E is better, higher ROE is better
            ...     return -row["pe_ratio"] + 100 * row["roe"]
            >>> top_stocks = AlphaRanker.rank_universe(universe, value_quality_scorer, top_n=10)
        """
        if universe.empty:
            logger.warning("Universe is empty, returning empty DataFrame")
            return pd.DataFrame()

        # Apply scorer to each row
        scores = universe.apply(scorer, axis=1)

        # Add scores to universe
        result = universe.copy()
        result["alpha_score"] = scores
        result["rank"] = scores.rank(ascending=False)

        # Sort and select top N
        result = result.sort_values("alpha_score", ascending=False).head(top_n)

        logger.info(
            f"Ranked {len(universe)} assets, returning top {top_n}: "
            f"best score={result['alpha_score'].max():.2f}, "
            f"worst score={result['alpha_score'].min():.2f}"
        )

        return result

    @staticmethod
    def rank_by_metrics(
        universe: pd.DataFrame,
        metrics: dict[str, str],
        top_n: int = 50,
    ) -> pd.DataFrame:
        """Rank universe by multiple metrics with equal weighting.

        Args:
            universe: DataFrame with one row per asset.
            metrics: Dictionary of metric_name -> direction ('asc' or 'desc').
                'asc' = lower is better (e.g., P/E ratio).
                'desc' = higher is better (e.g., ROE).
            top_n: Number of top-ranked assets to return.

        Returns:
            DataFrame with top N assets, sorted by composite rank.

        Example:
            >>> metrics = {
            ...     "pe_ratio": "asc",  # Lower P/E is better
            ...     "roe": "desc",       # Higher ROE is better
            ...     "debt_to_equity": "asc",  # Lower debt is better
            ... }
            >>> top_stocks = AlphaRanker.rank_by_metrics(universe, metrics, top_n=20)
        """
        if not all(col in universe.columns for col in metrics.keys()):
            missing = [col for col in metrics.keys() if col not in universe.columns]
            raise ValueError(f"Missing columns in universe: {missing}")

        result = universe.copy()
        rank_columns = []

        # Calculate individual ranks for each metric
        for metric, direction in metrics.items():
            ascending = direction == "asc"
            rank_col = f"{metric}_rank"
            result[rank_col] = result[metric].rank(ascending=ascending)
            rank_columns.append(rank_col)

        # Composite rank = average of individual ranks
        result["composite_rank"] = result[rank_columns].mean(axis=1)

        # Sort by composite rank
        result = result.sort_values("composite_rank").head(top_n)

        # Add final rank
        result["rank"] = range(1, len(result) + 1)

        logger.info(f"Ranked by {len(metrics)} metrics, returning top {top_n} assets")

        return result
