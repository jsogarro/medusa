"""Base class for PyTorch Lightning alpha signal models."""

from __future__ import annotations

from abc import abstractmethod

import torch
from torch import nn

try:
    import lightning as lightning_module  # noqa: N812
except ImportError:
    lightning_module = None  # type: ignore[assignment]


class BaseAlphaModel:
    """Mixin defining the Medusa alpha model interface.

    All alpha models must implement forward().
    """

    @abstractmethod
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass producing alpha signals or predictions."""
        ...


if lightning_module is not None:

    class LightningAlphaModel(lightning_module.LightningModule, BaseAlphaModel):
        """PyTorch Lightning base for alpha models.

        Provides training_step, validation_step, and Adam optimizer.
        Subclasses only need to implement forward().
        """

        def __init__(self, learning_rate: float = 1e-3) -> None:
            super().__init__()
            self.learning_rate = learning_rate
            self.save_hyperparameters()

        def training_step(
            self, batch: tuple[torch.Tensor, torch.Tensor], batch_idx: int
        ) -> torch.Tensor:
            x, y = batch
            y_hat = self(x)
            loss = nn.functional.mse_loss(y_hat, y)
            self.log("train_loss", loss, prog_bar=True)
            return loss

        def validation_step(
            self, batch: tuple[torch.Tensor, torch.Tensor], batch_idx: int
        ) -> torch.Tensor:
            x, y = batch
            y_hat = self(x)
            loss = nn.functional.mse_loss(y_hat, y)
            self.log("val_loss", loss, prog_bar=True)
            return loss

        def configure_optimizers(self) -> torch.optim.Optimizer:
            return torch.optim.Adam(self.parameters(), lr=self.learning_rate)

else:
    # Fallback when Lightning is not installed
    class LightningAlphaModel(BaseAlphaModel):  # type: ignore[no-redef]
        """Stub when PyTorch Lightning is not available."""

        def __init__(self, learning_rate: float = 1e-3) -> None:
            self.learning_rate = learning_rate
