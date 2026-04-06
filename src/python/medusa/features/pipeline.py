"""Feature engineering pipeline orchestrator."""

from __future__ import annotations

from typing import Any

import pandas as pd
from loguru import logger

from medusa.features.preprocessing import FeatureScaler, train_test_split_temporal
from medusa.features.technical import add_all_indicators


class FeaturePipeline:
    """Orchestrates feature engineering for backtesting and ML training.

    Steps:
    1. Add technical indicators
    2. Drop NaN rows from indicator warm-up
    3. Select feature columns
    4. Create target variable
    5. Scale features
    6. Split train/test
    """

    def __init__(
        self,
        target_col: str = "return_1",
        train_ratio: float = 0.8,
        extra_indicators: list[dict[str, Any]] | None = None,
    ) -> None:
        """Initialize pipeline.

        Args:
            target_col: Column name for the prediction target.
            train_ratio: Train/test split ratio.
            extra_indicators: Additional indicator configs (future use).
        """
        self.target_col = target_col
        self.train_ratio = train_ratio
        self.extra_indicators = extra_indicators or []
        self.scaler = FeatureScaler()
        self._feature_columns: list[str] = []

    def run(
        self,
        df: pd.DataFrame,
        feature_cols: list[str] | None = None,
    ) -> dict[str, Any]:
        """Run the full feature pipeline.

        Args:
            df: OHLCV DataFrame.
            feature_cols: Specific feature columns to use.
                If None, uses all numeric columns except target.

        Returns:
            Dictionary with keys: x_train, x_test, y_train, y_test,
            feature_columns, scaler.
        """
        # Step 1: Add indicators
        enriched = add_all_indicators(df)
        logger.info(f"Added indicators: {enriched.shape[1]} columns")

        # Step 2: Drop NaN
        enriched = enriched.dropna()
        logger.info(f"After dropna: {len(enriched)} rows")

        if len(enriched) == 0:
            raise ValueError("No data remaining after dropping NaN")

        # Step 3: Determine target
        if self.target_col not in enriched.columns:
            raise ValueError(f"Target column '{self.target_col}' not found")

        target = enriched[self.target_col]

        # Step 4: Select features
        if feature_cols:
            self._feature_columns = feature_cols
        else:
            exclude = {self.target_col, "timestamp"}
            self._feature_columns = [
                c
                for c in enriched.select_dtypes(include="number").columns
                if c not in exclude
            ]

        features = enriched[self._feature_columns]

        # Step 5: Train/test split (before scaling to avoid leakage)
        train_feat, test_feat = train_test_split_temporal(features, self.train_ratio)
        train_target, test_target = train_test_split_temporal(
            target.to_frame(), self.train_ratio
        )

        # Step 6: Scale
        x_train = self.scaler.fit_transform(train_feat)
        x_test = self.scaler.transform(test_feat)

        logger.info(
            f"Pipeline complete: train={len(x_train)}, test={len(x_test)}, "
            f"features={len(self._feature_columns)}"
        )

        return {
            "x_train": x_train,
            "x_test": x_test,
            "y_train": train_target.iloc[:, 0],
            "y_test": test_target.iloc[:, 0],
            "feature_columns": self._feature_columns,
            "scaler": self.scaler,
        }
