"""Triple-Barrier ML with Meta-Labeling strategy.

Triple barrier: take-profit (2%), stop-loss (1%), max holding period (24h)
Primary model: LSTM or XGBoost for direction
Meta-label: secondary model predicts bet sizing (0-1 confidence)

Reference:
    "Advances in Financial Machine Learning" by Marcos López de Prado
    https://hudsonthames.org/does-meta-labeling-add-to-signal-efficacy-triple-barrier-method/
"""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from medusa.strategies.base import BaseStrategy


class MLMetaLabelingStrategy(BaseStrategy):
    """ML strategy with triple-barrier labeling and meta-labeling for position sizing.

    Uses a primary model for direction and a secondary model for confidence/sizing.
    """

    def __init__(
        self,
        primary_model: Any,
        meta_model: Any | None = None,
        take_profit_pct: float = 0.02,
        stop_loss_pct: float = 0.01,
        max_holding_bars: int = 24,
        meta_threshold: float = 0.6,
    ) -> None:
        """Initialize ML meta-labeling strategy.

        Args:
            primary_model: Trained model with predict(features) -> {-1, 0, 1}.
            meta_model: Trained model with predict_proba(features) -> [0, 1].
                       If None, uses primary model only.
            take_profit_pct: Take-profit barrier percentage. Default 0.02 (2%).
            stop_loss_pct: Stop-loss barrier percentage. Default 0.01 (1%).
            max_holding_bars: Maximum holding period in bars. Default 24.
            meta_threshold: Minimum meta-model confidence for entry. Default 0.6.
        """
        self.primary_model = primary_model
        self.meta_model = meta_model
        self.take_profit_pct = take_profit_pct
        self.stop_loss_pct = stop_loss_pct
        self.max_holding_bars = max_holding_bars
        self.meta_threshold = meta_threshold

    def _create_triple_barrier_labels(
        self,
        prices: pd.Series,
        side: pd.Series,
    ) -> pd.Series:
        """Create triple-barrier labels for training.

        Args:
            prices: Price series.
            side: Direction signal (-1, 0, 1) from primary model.

        Returns:
            Labels: 1 = hit take-profit, -1 = hit stop-loss, 0 = time-out.
        """
        labels = pd.Series(0, index=prices.index)
        values = prices.to_numpy(dtype=float)
        sides = side.to_numpy()

        for i in range(len(prices) - self.max_holding_bars):
            if sides[i] == 0:
                continue  # No trade

            # Signed return of the position over the holding window
            window = values[i + 1 : i + self.max_holding_bars + 1]
            ret = sides[i] * (window / values[i] - 1)
            hit_tp = ret >= self.take_profit_pct
            hit_sl = ret <= -self.stop_loss_pct

            first_tp = hit_tp.argmax() if hit_tp.any() else len(window)
            first_sl = hit_sl.argmax() if hit_sl.any() else len(window)

            if first_tp == first_sl == len(window):
                labels.iloc[i] = np.sign(ret[-1])  # Time-out: sign of final return
            elif first_tp < first_sl:
                labels.iloc[i] = 1  # Take-profit first
            else:
                labels.iloc[i] = -1  # Stop-loss first (ties resolve conservatively)

        return labels

    def _extract_features(
        self,
        data: pd.DataFrame,
    ) -> pd.DataFrame:
        """Extract features from OHLCV data for model input.

        Args:
            data: OHLCV DataFrame.

        Returns:
            Features DataFrame ready for model.predict().
        """
        # This is a placeholder - should be customized based on model requirements
        features = pd.DataFrame(index=data.index)

        # Returns
        features["return_1d"] = data["close"].pct_change()
        features["return_5d"] = data["close"].pct_change(5)
        features["return_20d"] = data["close"].pct_change(20)

        # Volatility
        features["volatility_20d"] = data["close"].pct_change().rolling(20).std()

        # Volume
        features["volume_norm"] = data["volume"] / data["volume"].rolling(20).mean()

        # Technical indicators (if available in data)
        if "rsi" in data.columns:
            features["rsi"] = data["rsi"]
        if "macd" in data.columns:
            features["macd"] = data["macd"]

        return features.dropna()

    def generate_signals(
        self,
        data: pd.DataFrame,
    ) -> tuple[pd.Series, pd.Series]:
        """Generate entry/exit signals using primary + meta models.

        Args:
            data: OHLCV DataFrame with features.

        Returns:
            Tuple of (long entries, long exits) as boolean Series.
        """
        features = self._extract_features(data)

        # Primary model prediction (direction: -1, 0, 1)
        primary_pred = self.primary_model.predict(features)
        primary_series = pd.Series(primary_pred, index=features.index)

        # Meta-model prediction (confidence: 0-1)
        if self.meta_model is not None:
            meta_proba = self.meta_model.predict_proba(features)
            # Assume binary classifier, take probability of class 1 (success)
            if meta_proba.ndim > 1:
                meta_confidence = pd.Series(meta_proba[:, 1], index=features.index)
            else:
                meta_confidence = pd.Series(meta_proba, index=features.index)

            # Filter: only enter if meta-model is confident
            meta_filter = meta_confidence >= self.meta_threshold
        else:
            # No meta-model: always take primary signals
            meta_filter = pd.Series(True, index=features.index)

        # Long-only: a short primary signal must never open a long position.
        # Short signals come from generate_short_signals().
        entries = (primary_series == 1) & meta_filter

        # Exits: primary no longer says long, or meta confidence drops
        exits = primary_series != 1
        if self.meta_model is not None:
            exits = exits | (meta_confidence < (self.meta_threshold * 0.8))

        # Reindex to match original data
        entries = entries.reindex(data.index, fill_value=False)
        exits = exits.reindex(data.index, fill_value=False)

        return entries, exits

    def generate_short_signals(self, data: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
        """Short entry/exit signals, for the engine's ``short_entries``/``short_exits``.

        Mirror of the long side: enter on primary == -1 (and meta-confident); exit when the
        primary no longer says short, or meta confidence drops.
        """
        features = self._extract_features(data)
        primary_series = pd.Series(self.primary_model.predict(features), index=features.index)
        entries = primary_series == -1
        exits = primary_series != -1
        if self.meta_model is not None:
            proba = self.meta_model.predict_proba(features)
            conf = pd.Series(proba[:, 1] if proba.ndim > 1 else proba, index=features.index)
            entries = entries & (conf >= self.meta_threshold)
            exits = exits | (conf < (self.meta_threshold * 0.8))
        return (
            entries.reindex(data.index, fill_value=False),
            exits.reindex(data.index, fill_value=False),
        )

    def generate_short_entries(self, data: pd.DataFrame) -> pd.Series:
        """Short entry signals (primary == -1 and meta-confident)."""
        return self.generate_short_signals(data)[0]

    def generate_signal(
        self,
        data: pd.DataFrame,
    ) -> dict[str, Any] | None:
        """Generate a single signal from the latest data (for live use).

        Args:
            data: Recent market data buffer.

        Returns:
            Signal dict with keys: action, price, size, confidence, or None.
        """
        features = self._extract_features(data)
        if len(features) == 0:
            return None

        # Latest feature row
        latest_features = features.iloc[-1:].values

        # Primary prediction
        primary_pred = self.primary_model.predict(latest_features)[0]

        # Meta prediction (confidence)
        if self.meta_model is not None:
            meta_proba = self.meta_model.predict_proba(latest_features)
            confidence = float(meta_proba[0, 1]) if meta_proba.ndim > 1 else float(meta_proba[0])
        else:
            confidence = 1.0

        # Check threshold
        if confidence < self.meta_threshold:
            return None  # Not confident enough

        latest_price = data["close"].iloc[-1]

        if primary_pred == 1:
            return {
                "action": "BUY",
                "price": latest_price,
                "size": confidence,  # Scale position by confidence
                "confidence": confidence,
            }
        elif primary_pred == -1:
            return {
                "action": "SELL",
                "price": latest_price,
                "size": confidence,
                "confidence": confidence,
            }

        return None

    def train_meta_model(
        self,
        historical_data: pd.DataFrame,
        meta_model_class: Any,
        **meta_model_kwargs: Any,
    ) -> None:
        """Train the meta-labeling model on historical data.

        Args:
            historical_data: Historical OHLCV data for training.
            meta_model_class: Class to instantiate meta-model (e.g., XGBoost, LSTM).
            **meta_model_kwargs: Kwargs for meta_model_class constructor.
        """
        features = self._extract_features(historical_data)
        primary_pred = self.primary_model.predict(features)
        primary_series = pd.Series(primary_pred, index=features.index)

        # Create triple-barrier labels
        labels = self._create_triple_barrier_labels(
            historical_data["close"].reindex(features.index),
            primary_series,
        )

        # Binary meta-labels: 1 if triple-barrier was profitable, 0 otherwise
        meta_labels = (labels == 1).astype(int)

        # Train meta-model
        self.meta_model = meta_model_class(**meta_model_kwargs)
        self.meta_model.fit(features, meta_labels)
