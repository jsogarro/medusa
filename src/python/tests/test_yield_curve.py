"""Tests for yield curve construction and interpolation."""

import numpy as np
import pandas as pd
import pytest

from medusa.pricing.yield_curve import (
    NelsonSiegelCurve,
    YieldCurve,
    YieldCurveBootstrapper,
)


class TestYieldCurve:
    """Test yield curve basic functionality."""

    @pytest.fixture
    def sample_curve(self):
        """Create a sample upward-sloping yield curve."""
        tenors = np.array([0.25, 0.5, 1, 2, 5, 10, 30])
        rates = np.array([0.02, 0.025, 0.03, 0.035, 0.04, 0.042, 0.045])
        return YieldCurve(tenors, rates)

    def test_curve_creation(self, sample_curve):
        """Test yield curve initialization."""
        assert len(sample_curve.tenors) == 7
        assert len(sample_curve.rates) == 7

    def test_curve_validation_length_mismatch(self):
        """Test that mismatched lengths raise error."""
        with pytest.raises(ValueError, match="same length"):
            YieldCurve(
                tenors=np.array([1, 2, 3]),
                rates=np.array([0.02, 0.03]),  # Wrong length
            )

    def test_curve_validation_unsorted(self):
        """Test that unsorted tenors raise error."""
        with pytest.raises(ValueError, match="sorted"):
            YieldCurve(
                tenors=np.array([1, 3, 2]),  # Out of order
                rates=np.array([0.02, 0.03, 0.04]),
            )

    def test_linear_interpolation(self, sample_curve):
        """Test linear interpolation between points."""
        # Interpolate at 0.75 years (between 0.5 and 1)
        rate = sample_curve.interpolate(0.75, method="linear")
        # Should be midway between 0.025 and 0.03
        expected = 0.025 + 0.5 * (0.03 - 0.025)
        assert abs(rate - expected) < 1e-6

    def test_cubic_interpolation(self, sample_curve):
        """Test cubic spline interpolation."""
        rate = sample_curve.interpolate(0.75, method="cubic")
        # Should be smooth and between 0.025 and 0.03
        assert 0.025 <= rate <= 0.03

    def test_extrapolation_flat(self, sample_curve):
        """Test flat extrapolation beyond curve bounds."""
        # Below minimum tenor
        rate_low = sample_curve.interpolate(0.1)
        assert abs(rate_low - 0.02) < 1e-6  # Should equal first rate

        # Above maximum tenor
        rate_high = sample_curve.interpolate(50)
        assert abs(rate_high - 0.045) < 1e-6  # Should equal last rate

    def test_discount_factor(self, sample_curve):
        """Test discount factor calculation."""
        # DF(t) = exp(-r * t)
        tenor = 1.0
        rate = sample_curve.interpolate(tenor)
        df = sample_curve.discount_factor(tenor)
        expected = np.exp(-rate * tenor)
        assert abs(df - expected) < 1e-6

    def test_forward_rate(self, sample_curve):
        """Test forward rate calculation."""
        # Forward rate from 1y to 2y
        t1, t2 = 1.0, 2.0
        fwd = sample_curve.forward_rate(t1, t2)
        # Forward rate should be > 1y rate for upward-sloping curve
        r1 = sample_curve.interpolate(t1)
        assert fwd > r1

    def test_forward_rate_invalid(self, sample_curve):
        """Test that t2 <= t1 raises error."""
        with pytest.raises(ValueError, match="must be greater"):
            sample_curve.forward_rate(2.0, 1.0)


class TestNelsonSiegel:
    """Test Nelson-Siegel curve fitting."""

    def test_nelson_siegel_rate(self):
        """Test Nelson-Siegel rate calculation."""
        curve = NelsonSiegelCurve(beta0=0.04, beta1=-0.01, beta2=0.02, tau=1.0)
        rate_1y = curve.rate(1.0)
        assert 0.03 < rate_1y < 0.05  # Reasonable range

    def test_nelson_siegel_fit(self):
        """Test fitting Nelson-Siegel to observed curve."""
        # Create synthetic data
        tenors = np.array([0.25, 0.5, 1, 2, 5, 10, 30])
        rates = np.array([0.02, 0.025, 0.03, 0.035, 0.04, 0.042, 0.045])
        observed = YieldCurve(tenors, rates)

        # Fit Nelson-Siegel
        fitted = NelsonSiegelCurve.fit(observed)

        # Check that fitted curve approximates observed
        for tenor, rate in zip(tenors, rates):
            fitted_rate = fitted.rate(tenor)
            assert abs(fitted_rate - rate) < 0.01  # Within 100 bp

    def test_nelson_siegel_components(self):
        """Test Nelson-Siegel interpretable components."""
        # Level-only curve (flat)
        flat = NelsonSiegelCurve(beta0=0.05, beta1=0, beta2=0, tau=1.0)
        assert abs(flat.rate(1) - 0.05) < 1e-6
        assert abs(flat.rate(10) - 0.05) < 1e-6

    def test_nelson_siegel_at_zero(self):
        """Test Nelson-Siegel rate at t=0."""
        curve = NelsonSiegelCurve(beta0=0.04, beta1=-0.01, beta2=0.02, tau=1.0)
        rate_0 = curve.rate(0)
        # At t=0: y(0) = beta0 + beta1
        expected = curve.beta0 + curve.beta1
        assert abs(rate_0 - expected) < 1e-6


class TestBootstrapping:
    """Test yield curve bootstrapping."""

    def test_bootstrap_basic(self):
        """Test bootstrapping from par bonds."""
        par_bonds = pd.DataFrame(
            {
                "tenor": [1, 2, 5],
                "rate": [0.03, 0.035, 0.04],
                "frequency": [2, 2, 2],
            }
        )

        curve = YieldCurveBootstrapper.bootstrap(par_bonds)

        assert len(curve.tenors) == 3
        assert len(curve.rates) == 3
        # First zero rate should be close to first par rate (within 0.5%)
        assert abs(curve.rates[0] - 0.03) < 0.005

    def test_bootstrap_empty(self):
        """Test that empty DataFrame raises error."""
        par_bonds = pd.DataFrame(columns=["tenor", "rate", "frequency"])
        with pytest.raises(ValueError, match="cannot be empty"):
            YieldCurveBootstrapper.bootstrap(par_bonds)

    def test_bootstrap_missing_columns(self):
        """Test that missing columns raise error."""
        par_bonds = pd.DataFrame({"tenor": [1, 2], "rate": [0.03, 0.04]})
        with pytest.raises(ValueError, match="must have columns"):
            YieldCurveBootstrapper.bootstrap(par_bonds)

    def test_bootstrap_upward_sloping(self):
        """Test that upward-sloping par curve yields upward-sloping zero curve."""
        par_bonds = pd.DataFrame(
            {
                "tenor": [1, 2, 3, 5, 10],
                "rate": [0.02, 0.025, 0.03, 0.035, 0.04],
                "frequency": [2, 2, 2, 2, 2],
            }
        )

        curve = YieldCurveBootstrapper.bootstrap(par_bonds)

        # Check monotonicity (rates should increase with tenor)
        for i in range(len(curve.rates) - 1):
            assert curve.rates[i] <= curve.rates[i + 1]

    def test_bootstrap_single_bond(self):
        """Test bootstrapping with single bond."""
        par_bonds = pd.DataFrame(
            {
                "tenor": [2],
                "rate": [0.04],
                "frequency": [2],
            }
        )

        curve = YieldCurveBootstrapper.bootstrap(par_bonds)
        assert len(curve.tenors) == 1
        # Zero rate should be close to par rate for single bond (within 1%)
        assert abs(curve.rates[0] - 0.04) < 0.01
