"""Temporal Fusion Transformer wrapper using pytorch-forecasting."""

from __future__ import annotations

from typing import Any

from loguru import logger


class TFTModel:
    """Temporal Fusion Transformer wrapper.

    Uses pytorch-forecasting's built-in TFT for multi-horizon
    probabilistic forecasting with attention-based feature importance.
    """

    def __init__(self, dataset: Any, **kwargs: Any) -> None:
        """Initialize TFT from a TimeSeriesDataSet.

        Args:
            dataset: pytorch_forecasting.data.TimeSeriesDataSet instance.
            **kwargs: Override default TFT hyperparameters.
        """
        self.dataset = dataset
        self._model: Any = None
        self._kwargs = {
            "learning_rate": 1e-3,
            "hidden_size": 64,
            "attention_head_size": 4,
            "dropout": 0.1,
            "hidden_continuous_size": 16,
            "output_size": 7,
            **kwargs,
        }

    def build(self) -> Any:
        """Build TFT model from dataset.

        Returns:
            TemporalFusionTransformer instance, or None if not installed.
        """
        try:
            from pytorch_forecasting import TemporalFusionTransformer
            from pytorch_forecasting.metrics import QuantileLoss

            self._model = TemporalFusionTransformer.from_dataset(
                self.dataset,
                loss=QuantileLoss(),
                reduce_on_plateau_patience=4,
                **self._kwargs,
            )
            logger.info("TFT model built from dataset")
            return self._model
        except ImportError:
            logger.warning("pytorch-forecasting not installed")
            return None

    def train(self, trainer: Any) -> None:
        """Train with a Lightning Trainer.

        Args:
            trainer: lightning.Trainer instance.
        """
        if self._model is None:
            self.build()
        if self._model is not None:
            trainer.fit(self._model, train_dataloaders=self.dataset)
            logger.info("TFT training complete")

    @property
    def model(self) -> Any:
        """Access the underlying TFT model."""
        if self._model is None:
            self.build()
        return self._model
