"""XGBoost model for tabular feature-based alpha signals."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd
from loguru import logger
from sklearn.model_selection import TimeSeriesSplit


class XGBoostSignalModel:
    """XGBoost for feature-based signal generation.

    Often outperforms deep learning on tabular financial data.
    Uses time-series-aware cross-validation.
    """

    def __init__(
        self,
        objective: str = "reg:squarederror",
        max_depth: int = 6,
        learning_rate: float = 0.1,
        n_estimators: int = 100,
        **kwargs: Any,
    ) -> None:
        import xgboost as xgb

        self.model = xgb.XGBRegressor(
            objective=objective,
            max_depth=max_depth,
            learning_rate=learning_rate,
            n_estimators=n_estimators,
            random_state=42,
            **kwargs,
        )

    def train(self, x: pd.DataFrame, y: pd.Series) -> None:
        """Train the model.

        Args:
            x: Feature DataFrame.
            y: Target series.
        """
        self.model.fit(x, y)
        logger.info(f"XGBoost trained on {len(x)} samples")

    def predict(self, x: pd.DataFrame) -> pd.Series:
        """Generate predictions.

        Args:
            x: Feature DataFrame.

        Returns:
            Prediction series with same index.
        """
        preds = self.model.predict(x)
        return pd.Series(preds, index=x.index, name="prediction")

    def cross_validate(
        self,
        x: pd.DataFrame,
        y: pd.Series,
        n_splits: int = 5,
    ) -> pd.DataFrame:
        """Walk-forward time series cross-validation.

        Args:
            x: Feature DataFrame.
            y: Target series.
            n_splits: Number of CV folds.

        Returns:
            DataFrame with per-fold MSE results.
        """
        tscv = TimeSeriesSplit(n_splits=n_splits)
        results: list[dict[str, Any]] = []

        for fold, (train_idx, val_idx) in enumerate(tscv.split(x)):
            x_train, x_val = x.iloc[train_idx], x.iloc[val_idx]
            y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

            self.model.fit(x_train, y_train)
            y_pred = self.model.predict(x_val)
            mse = float(((y_val - y_pred) ** 2).mean())
            results.append({"fold": fold, "mse": mse, "val_size": len(x_val)})
            logger.info(f"Fold {fold}: MSE={mse:.6f}")

        return pd.DataFrame(results)

    def save(self, path: Path | str) -> None:
        self.model.save_model(str(path))
        logger.info(f"Model saved to {path}")

    def load(self, path: Path | str) -> None:
        self.model.load_model(str(path))
        logger.info(f"Model loaded from {path}")

    @property
    def feature_importance(self) -> pd.Series:
        """Get feature importance scores."""
        return pd.Series(
            self.model.feature_importances_,
            index=self.model.get_booster().feature_names,
            name="importance",
        ).sort_values(ascending=False)
