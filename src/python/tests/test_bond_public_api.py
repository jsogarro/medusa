"""Tests for public fixed-income exports."""

from medusa.data import TreasuryDataLoader
from medusa.pricing import Bond, BondPricer, DayCountConvention, YieldCurve, YieldCurveBootstrapper


def test_pricing_public_exports() -> None:
    """Fixed-income pricing objects should be exported from medusa.pricing."""
    assert Bond.__name__ == "Bond"
    assert BondPricer.__name__ == "BondPricer"
    assert DayCountConvention.__name__ == "DayCountConvention"
    assert YieldCurve.__name__ == "YieldCurve"
    assert YieldCurveBootstrapper.__name__ == "YieldCurveBootstrapper"


def test_data_public_exports() -> None:
    """Bond-related loaders should be exported from medusa.data."""
    assert TreasuryDataLoader.__name__ == "TreasuryDataLoader"
