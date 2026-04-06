"""Data preprocessing for ML model training."""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler


def create_sequences(
    features: np.ndarray | pd.DataFrame,
    target: np.ndarray | pd.Series,
    sequence_length: int = 60,
) -> tuple[np.ndarray, np.ndarray]:
    """Create sliding window sequences for time series models.

    Args:
        features: Feature array of shape (n_samples, n_features).
        target: Target array of shape (n_samples,).
        sequence_length: Number of lookback steps per sequence.

    Returns:
        Tuple of (X, y) where X has shape (n_sequences, seq_len, n_features)
        and y has shape (n_sequences,).
    """
    if isinstance(features, pd.DataFrame):
        features = features.values
    if isinstance(target, pd.Series):
        target = target.values

    n = len(features) - sequence_length
    if n <= 0:
        raise ValueError(
            f"Not enough data: {len(features)} rows for "
            f"sequence_length={sequence_length}"
        )

    x = np.array([features[i : i + sequence_length] for i in range(n)])
    y = target[sequence_length:]

    return x, y


def train_test_split_temporal(
    df: pd.DataFrame,
    train_ratio: float = 0.8,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split DataFrame by time (no shuffle — preserves temporal order).

    Args:
        df: DataFrame sorted by time index.
        train_ratio: Fraction for training set.

    Returns:
        Tuple of (train_df, test_df).
    """
    split_idx = int(len(df) * train_ratio)
    return df.iloc[:split_idx].copy(), df.iloc[split_idx:].copy()


class FeatureScaler:
    """Fit-transform scaler that avoids lookahead bias.

    Fits only on training data, transforms both train and test.
    """

    def __init__(self) -> None:
        self._scaler = StandardScaler()
        self._is_fitted = False

    def fit(self, df: pd.DataFrame) -> FeatureScaler:
        """Fit scaler on training data.

        Args:
            df: Training DataFrame (numeric columns only).

        Returns:
            self for chaining.
        """
        self._scaler.fit(df.values)
        self._is_fitted = True
        return self

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """Transform data using fitted scaler.

        Args:
            df: DataFrame to transform.

        Returns:
            Scaled DataFrame with same index and columns.
        """
        if not self._is_fitted:
            raise RuntimeError("Scaler not fitted. Call fit() first.")
        scaled = self._scaler.transform(df.values)
        return pd.DataFrame(scaled, index=df.index, columns=df.columns)

    def fit_transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """Fit and transform in one step."""
        return self.fit(df).transform(df)

    def inverse_transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """Inverse transform scaled data."""
        if not self._is_fitted:
            raise RuntimeError("Scaler not fitted.")
        inv = self._scaler.inverse_transform(df.values)
        return pd.DataFrame(inv, index=df.index, columns=df.columns)
