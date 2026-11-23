"""Pricing engines for fixed income and equities."""

try:
    from medusa.pricing.bond import Bond, BondPricer, DayCountConvention
    from medusa.pricing.yield_curve import (
        NelsonSiegelCurve,
        YieldCurve,
        YieldCurveBootstrapper,
    )

    __all__ = [
        "Bond",
        "BondPricer",
        "DayCountConvention",
        "NelsonSiegelCurve",
        "YieldCurve",
        "YieldCurveBootstrapper",
    ]
except ImportError:
    # scipy not available
    __all__ = []

# Equity pricing modules (optional imports for graceful degradation)
try:
    from medusa.pricing.fundamental_valuation import (
        ComparableValuation,
        DCFInputs,
        DCFResult,
        DCFValuation,
        GordonGrowthModel,
    )

    __all__ += [
        "DCFValuation",
        "DCFInputs",
        "DCFResult",
        "GordonGrowthModel",
        "ComparableValuation",
    ]
except ImportError:
    pass

try:
    from medusa.pricing.factor_models import CAPMModel, CustomFactors, FamaFrenchModel

    __all__ += ["CAPMModel", "FamaFrenchModel", "CustomFactors"]
except ImportError:
    pass

try:
    from medusa.pricing.statistical_valuation import (
        CompositeValuationScore,
        MeanReversionValuation,
    )

    __all__ += ["MeanReversionValuation", "CompositeValuationScore"]
except ImportError:
    pass

try:
    from medusa.pricing.equity_screener import AlphaRanker, EquityScreener

    __all__ += ["EquityScreener", "AlphaRanker"]
except ImportError:
    pass

try:
    from medusa.pricing.risk_models import CovarianceEstimator, RiskDecomposition

    __all__ += ["CovarianceEstimator", "RiskDecomposition"]
except ImportError:
    pass

# Crypto-native pricing models
try:
    from medusa.pricing.crypto import (
        CrossExchangeSpreadModel,
        CryptoFactorModel,
        FuturesBasisModel,
        MVRVModel,
        NVTModel,
        PerpetualFundingModel,
        StablecoinDepegModel,
        StockToFlowModel,
        TriangularArbModel,
    )

    __all__ += [
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
except ImportError:
    pass
