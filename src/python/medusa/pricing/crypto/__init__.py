"""Crypto-native pricing and valuation models.

This package provides cryptocurrency-specific pricing models including:
- On-chain valuation metrics (NVT, MVRV, Stock-to-Flow)
- Derivatives pricing (perpetual funding, futures basis)
- Arbitrage detection (triangular, cross-exchange, stablecoin depeg)
- Multi-factor alpha models for crypto portfolios
"""

from __future__ import annotations

from medusa.pricing.crypto.arbitrage import (
    CrossExchangeSpreadModel,
    StablecoinDepegModel,
    TriangularArbModel,
)
from medusa.pricing.crypto.derivatives import FuturesBasisModel, PerpetualFundingModel
from medusa.pricing.crypto.factor_model import CryptoFactorModel
from medusa.pricing.crypto.onchain_valuation import MVRVModel, NVTModel, StockToFlowModel

__all__ = [
    "NVTModel",
    "MVRVModel",
    "StockToFlowModel",
    "PerpetualFundingModel",
    "FuturesBasisModel",
    "TriangularArbModel",
    "CrossExchangeSpreadModel",
    "StablecoinDepegModel",
    "CryptoFactorModel",
]
