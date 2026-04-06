"""Custom Transformer for multi-asset cross-attention signals."""

from __future__ import annotations

import math

import torch
from torch import nn

from medusa.models.base import LightningAlphaModel


class PositionalEncoding(nn.Module):
    """Sinusoidal positional encoding."""

    def __init__(self, d_model: int, max_len: int = 5000, dropout: float = 0.1) -> None:
        super().__init__()
        self.dropout = nn.Dropout(p=dropout)

        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(
            torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model)
        )
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        pe = pe.unsqueeze(0)
        self.register_buffer("pe", pe)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.pe[:, : x.size(1)]
        return self.dropout(x)


class MultiAssetTransformer(LightningAlphaModel):
    """Transformer for multi-asset cross-attention alpha signals.

    Learns relationships between assets via self-attention for
    pairs trading, sector rotation, and relative value strategies.
    """

    def __init__(
        self,
        input_size: int,
        num_assets: int = 1,
        d_model: int = 128,
        nhead: int = 8,
        num_layers: int = 4,
        dropout: float = 0.1,
        output_size: int = 1,
        learning_rate: float = 1e-3,
    ) -> None:
        super().__init__(learning_rate=learning_rate)

        self.input_proj = nn.Linear(input_size, d_model)
        self.pos_encoding = PositionalEncoding(d_model, dropout=dropout)

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=nhead,
            dropout=dropout,
            batch_first=True,
        )
        self.transformer = nn.TransformerEncoder(
            encoder_layer, num_layers=num_layers
        )
        self.output_proj = nn.Linear(d_model, output_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Forward pass.

        Args:
            x: (batch, num_assets_or_seq_len, input_size)

        Returns:
            (batch, num_assets_or_seq_len, output_size)
        """
        x = self.input_proj(x)
        x = self.pos_encoding(x)
        x = self.transformer(x)
        return self.output_proj(x)
