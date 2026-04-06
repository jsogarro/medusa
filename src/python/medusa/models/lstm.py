"""LSTM model for time series price prediction."""

from __future__ import annotations

import torch
from torch import nn

from medusa.models.base import LightningAlphaModel


class LSTMModel(LightningAlphaModel):
    """LSTM model for alpha signal generation.

    Predicts next-bar return or signal strength from a sequence
    of feature vectors.
    """

    def __init__(
        self,
        input_size: int,
        hidden_size: int = 128,
        num_layers: int = 2,
        dropout: float = 0.2,
        output_size: int = 1,
        learning_rate: float = 1e-3,
    ) -> None:
        super().__init__(learning_rate=learning_rate)

        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            dropout=dropout if num_layers > 1 else 0.0,
            batch_first=True,
        )
        self.fc = nn.Linear(hidden_size, output_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass.

        Args:
            x: (batch, seq_len, input_size)

        Returns:
            Predictions of shape (batch, output_size)
        """
        lstm_out, _ = self.lstm(x)
        last_hidden = lstm_out[:, -1, :]
        return self.fc(last_hidden)
