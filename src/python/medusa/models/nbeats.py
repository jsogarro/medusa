"""N-BEATS model wrapper using pytorch-forecasting."""

from __future__ import annotations

from typing import Any

from loguru import logger


class NBEATSModel:
    """N-BEATS wrapper for univariate time series forecasting.

    Decomposes time series into interpretable trend and seasonality
    components using a pure deep learning architecture.
    """

    def __init__(self, dataset: Any, **kwargs: Any) -> None:
        """Initialize N-BEATS from a TimeSeriesDataSet.

        Args:
            dataset: pytorch_forecasting.data.TimeSeriesDataSet instance.
            **kwargs: Override default hyperparameters.
        """
        self.dataset = dataset
        self._model: Any = None
        self._kwargs = {
            "learning_rate": 1e-3,
            "widths": [256, 512],
            "backcast_loss_ratio": 0.1,
            **kwargs,
        }

    def build(self) -> Any:
        """Build N-BEATS model from dataset."""
        try:
            from pytorch_forecasting import NBeats

            self._model = NBeats.from_dataset(
                self.dataset,
                **self._kwargs,
            )
            logger.info("N-BEATS model built from dataset")
            return self._model
        except ImportError:
            logger.warning("pytorch-forecasting not installed")
            return None

    def train(self, trainer: Any) -> None:
        """Train with a Lightning Trainer."""
        if self._model is None:
            self.build()
        if self._model is not None:
            trainer.fit(self._model, train_dataloaders=self.dataset)
            logger.info("N-BEATS training complete")

    @property
    def model(self) -> Any:
        if self._model is None:
            self.build()
        return self._model
