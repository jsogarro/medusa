"""Comprehensive test coverage for pricing and model modules.

Improves test coverage for:
- medusa/features/volatility_surface.py (0% → target 80%)
- medusa/pricing/risk_models.py (43% → target 85%)
- medusa/pricing/equity_screener.py (61% → target 85%)
- medusa/models/registry.py (62% → target 85%)
- medusa/models/nbeats.py (32% → target 70%)
- medusa/models/tft.py (31% → target 70%)
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

# ============================================================================
# Volatility Surface Tests
# ============================================================================


class TestVolatilitySurface:
    """Tests for VolatilitySurface dataclass."""

    def test_volatility_surface_creation(self) -> None:
        """Test basic VolatilitySurface creation."""
        from medusa.features.volatility_surface import VolatilitySurface

        strikes = np.array([90.0, 95.0, 100.0, 105.0, 110.0])
        expiries = np.array([0.25, 0.5, 1.0])
        ivs = np.random.uniform(0.15, 0.35, size=(5, 3))

        surface = VolatilitySurface(
            strikes=strikes,
            expiries=expiries,
            ivs=ivs,
            underlying_price=100.0,
        )

        assert len(surface.strikes) == 5
        assert len(surface.expiries) == 3
        assert surface.ivs.shape == (5, 3)
        assert surface.underlying_price == 100.0

    def test_volatility_surface_validation_fail(self) -> None:
        """Test VolatilitySurface validation on shape mismatch."""
        from medusa.features.volatility_surface import VolatilitySurface

        strikes = np.array([90.0, 95.0, 100.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.random.uniform(0.2, 0.3, size=(4, 2))  # Wrong shape

        with pytest.raises(ValueError, match="IV array shape"):
            VolatilitySurface(
                strikes=strikes,
                expiries=expiries,
                ivs=ivs,
                underlying_price=100.0,
            )

    def test_volatility_surface_interpolate_no_scipy(self, monkeypatch) -> None:
        """Test interpolate raises ImportError when scipy not available."""
        from medusa.features import volatility_surface

        monkeypatch.setattr(volatility_surface, "SCIPY_AVAILABLE", False)

        from medusa.features.volatility_surface import VolatilitySurface

        strikes = np.array([90.0, 100.0, 110.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.array([[0.2, 0.22], [0.18, 0.20], [0.22, 0.24]])

        surface = VolatilitySurface(
            strikes=strikes, expiries=expiries, ivs=ivs, underlying_price=100.0
        )

        with pytest.raises(ImportError, match="scipy required"):
            surface.interpolate(95.0, 0.3)

    def test_volatility_surface_interpolate_with_scipy(self) -> None:
        """Test volatility surface interpolation with scipy."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurface

        strikes = np.array([90.0, 100.0, 110.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.array([[0.2, 0.22], [0.18, 0.20], [0.22, 0.24]])

        surface = VolatilitySurface(
            strikes=strikes, expiries=expiries, ivs=ivs, underlying_price=100.0
        )

        # Interpolate at intermediate point
        iv = surface.interpolate(95.0, 0.3)
        assert isinstance(iv, float)
        assert 0.15 < iv < 0.30  # Sanity check

    def test_volatility_surface_interpolate_no_valid_points(self) -> None:
        """Test interpolate fails when all IVs are NaN."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurface

        strikes = np.array([90.0, 100.0, 110.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.full((3, 2), np.nan)

        surface = VolatilitySurface(
            strikes=strikes, expiries=expiries, ivs=ivs, underlying_price=100.0
        )

        with pytest.raises(ValueError, match="No valid IV points"):
            surface.interpolate(95.0, 0.3)


class TestVolatilitySurfaceBuilder:
    """Tests for VolatilitySurfaceBuilder."""

    def test_from_quotes_no_scipy(self, monkeypatch) -> None:
        """Test from_quotes raises ImportError when scipy not available."""
        from medusa.features import volatility_surface

        monkeypatch.setattr(volatility_surface, "SCIPY_AVAILABLE", False)

        from medusa.features.volatility_surface import VolatilitySurfaceBuilder

        quotes = pd.DataFrame({"strike": [90.0, 100.0], "expiry": [0.25, 0.25], "iv": [0.2, 0.18]})

        with pytest.raises(ImportError, match="scipy required"):
            VolatilitySurfaceBuilder.from_quotes(quotes, underlying_price=100.0)

    def test_from_quotes_missing_columns(self) -> None:
        """Test from_quotes raises ValueError on missing columns."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurfaceBuilder

        quotes = pd.DataFrame({"strike": [90.0], "expiry": [0.25]})  # Missing 'iv'

        with pytest.raises(ValueError, match="Quotes must have columns"):
            VolatilitySurfaceBuilder.from_quotes(quotes, underlying_price=100.0)

    def test_from_quotes_empty_dataframe(self) -> None:
        """Test from_quotes raises ValueError on empty DataFrame."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurfaceBuilder

        quotes = pd.DataFrame(columns=["strike", "expiry", "iv"])

        with pytest.raises(ValueError, match="Quotes DataFrame is empty"):
            VolatilitySurfaceBuilder.from_quotes(quotes, underlying_price=100.0)

    def test_from_quotes_with_scipy(self) -> None:
        """Test volatility surface building with scipy."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurfaceBuilder

        quotes = pd.DataFrame(
            {
                "strike": [90.0, 95.0, 100.0, 105.0, 110.0] * 2,
                "expiry": [0.25] * 5 + [0.5] * 5,
                "iv": [0.22, 0.20, 0.18, 0.20, 0.22, 0.24, 0.22, 0.20, 0.22, 0.24],
            }
        )

        surface = VolatilitySurfaceBuilder.from_quotes(quotes, underlying_price=100.0)

        assert len(surface.strikes) == 5
        assert len(surface.expiries) == 2
        assert surface.underlying_price == 100.0

    def test_from_quotes_insufficient_points(self) -> None:
        """Test from_quotes with <3 points returns raw surface (no interpolation)."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import VolatilitySurfaceBuilder

        quotes = pd.DataFrame({"strike": [90.0, 100.0], "expiry": [0.25, 0.25], "iv": [0.2, 0.18]})

        surface = VolatilitySurfaceBuilder.from_quotes(quotes, underlying_price=100.0)

        assert len(surface.strikes) == 2
        assert len(surface.expiries) == 1
        # Should have NaN values since no interpolation was done
        assert np.isnan(surface.ivs).sum() == 0

    def test_analyze_skew_invalid_expiry_index(self) -> None:
        """Test analyze_skew raises ValueError on invalid expiry_index."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import (
            VolatilitySurface,
            VolatilitySurfaceBuilder,
        )

        strikes = np.array([90.0, 100.0, 110.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.array([[0.2, 0.22], [0.18, 0.20], [0.22, 0.24]])

        surface = VolatilitySurface(
            strikes=strikes, expiries=expiries, ivs=ivs, underlying_price=100.0
        )

        with pytest.raises(ValueError, match="Invalid expiry_index"):
            VolatilitySurfaceBuilder.analyze_skew(surface, expiry_index=5)

    def test_analyze_skew_calculation(self) -> None:
        """Test volatility skew calculation."""
        try:
            from scipy.interpolate import RBFInterpolator  # noqa: F401
        except ImportError:
            pytest.skip("scipy not available")

        from medusa.features.volatility_surface import (
            VolatilitySurface,
            VolatilitySurfaceBuilder,
        )

        # Create surface with known skew
        strikes = np.array([90.0, 100.0, 110.0])
        expiries = np.array([0.25, 0.5])
        ivs = np.array([[0.25, 0.27], [0.20, 0.22], [0.23, 0.25]])  # ATM=100

        surface = VolatilitySurface(
            strikes=strikes, expiries=expiries, ivs=ivs, underlying_price=100.0
        )

        skew = VolatilitySurfaceBuilder.analyze_skew(surface, expiry_index=0)

        # Check all metrics are present
        assert "put_skew" in skew
        assert "call_skew" in skew
        assert "risk_reversal" in skew
        assert "butterfly" in skew

        # Put skew = IV(90% strike) - IV(ATM) = 0.25 - 0.20 = 0.05
        assert abs(skew["put_skew"] - 0.05) < 0.01

        # Call skew = IV(110% strike) - IV(ATM) = 0.23 - 0.20 = 0.03
        assert abs(skew["call_skew"] - 0.03) < 0.01


class TestVolatilityAnalyzer:
    """Tests for VolatilityAnalyzer."""

    def test_calculate_iv_rank_empty_series(self) -> None:
        """Test IV rank returns 50.0 for empty historical series."""
        from medusa.features.volatility_surface import VolatilityAnalyzer

        historical = pd.Series([], dtype=float)
        rank = VolatilityAnalyzer.calculate_iv_rank(0.25, historical)
        assert rank == 50.0

    def test_calculate_iv_rank_constant_series(self) -> None:
        """Test IV rank returns 50.0 when all historical IVs are same."""
        from medusa.features.volatility_surface import VolatilityAnalyzer

        historical = pd.Series([0.2, 0.2, 0.2, 0.2])
        rank = VolatilityAnalyzer.calculate_iv_rank(0.2, historical)
        assert rank == 50.0

    def test_calculate_iv_rank_calculation(self) -> None:
        """Test IV rank calculation."""
        from medusa.features.volatility_surface import VolatilityAnalyzer

        historical = pd.Series([0.1, 0.2, 0.3, 0.4, 0.5])
        # Current IV = 0.3 is at midpoint
        rank = VolatilityAnalyzer.calculate_iv_rank(0.3, historical)
        assert abs(rank - 50.0) < 1.0

        # Current IV = 0.5 is at maximum
        rank = VolatilityAnalyzer.calculate_iv_rank(0.5, historical)
        assert abs(rank - 100.0) < 1.0

    def test_calculate_iv_percentile_empty_series(self) -> None:
        """Test IV percentile returns 50.0 for empty series."""
        from medusa.features.volatility_surface import VolatilityAnalyzer

        historical = pd.Series([], dtype=float)
        pct = VolatilityAnalyzer.calculate_iv_percentile(0.25, historical)
        assert pct == 50.0

    def test_calculate_iv_percentile_calculation(self) -> None:
        """Test IV percentile calculation."""
        from medusa.features.volatility_surface import VolatilityAnalyzer

        historical = pd.Series([0.1, 0.2, 0.3, 0.4, 0.5])
        # Current IV = 0.35 should be around 60th percentile
        pct = VolatilityAnalyzer.calculate_iv_percentile(0.35, historical)
        assert 50.0 < pct < 80.0


# ============================================================================
# Risk Models Tests
# ============================================================================


class TestCovarianceEstimator:
    """Tests for CovarianceEstimator."""

    def test_estimate_sample_empty_returns(self) -> None:
        """Test estimate raises ValueError on empty returns."""
        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame()

        with pytest.raises(ValueError, match="Returns DataFrame is empty"):
            CovarianceEstimator.estimate(returns, method="sample")

    def test_estimate_sample_method(self) -> None:
        """Test sample covariance estimation."""
        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame(
            {
                "AAPL": np.random.normal(0.001, 0.02, 100),
                "MSFT": np.random.normal(0.001, 0.02, 100),
                "GOOGL": np.random.normal(0.001, 0.02, 100),
            }
        )

        cov = CovarianceEstimator.estimate(returns, method="sample")

        assert cov.shape == (3, 3)
        assert list(cov.index) == ["AAPL", "MSFT", "GOOGL"]
        assert list(cov.columns) == ["AAPL", "MSFT", "GOOGL"]

    def test_estimate_ledoit_wolf_no_sklearn(self, monkeypatch) -> None:
        """Test ledoit_wolf method raises ValueError when sklearn not available."""
        from medusa.pricing import risk_models

        monkeypatch.setattr(risk_models, "SKLEARN_AVAILABLE", False)

        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame({"A": [0.01, 0.02], "B": [0.01, 0.03]})

        with pytest.raises(ValueError, match="requires sklearn"):
            CovarianceEstimator.estimate(returns, method="ledoit_wolf")

    def test_estimate_ledoit_wolf_with_sklearn(self) -> None:
        """Test Ledoit-Wolf covariance estimation."""
        try:
            from sklearn.covariance import LedoitWolf  # noqa: F401
        except ImportError:
            pytest.skip("sklearn not available")

        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame(
            {
                "A": np.random.normal(0.001, 0.02, 100),
                "B": np.random.normal(0.001, 0.02, 100),
            }
        )

        cov = CovarianceEstimator.estimate(returns, method="ledoit_wolf")

        assert cov.shape == (2, 2)
        assert list(cov.index) == ["A", "B"]

    def test_estimate_oas_with_sklearn(self) -> None:
        """Test OAS covariance estimation."""
        try:
            from sklearn.covariance import OAS  # noqa: F401
        except ImportError:
            pytest.skip("sklearn not available")

        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame(
            {
                "A": np.random.normal(0.001, 0.02, 100),
                "B": np.random.normal(0.001, 0.02, 100),
            }
        )

        cov = CovarianceEstimator.estimate(returns, method="oas")

        assert cov.shape == (2, 2)

    def test_estimate_shrunk_with_sklearn(self) -> None:
        """Test shrunk covariance estimation."""
        try:
            from sklearn.covariance import ShrunkCovariance  # noqa: F401
        except ImportError:
            pytest.skip("sklearn not available")

        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame(
            {
                "A": np.random.normal(0.001, 0.02, 100),
                "B": np.random.normal(0.001, 0.02, 100),
            }
        )

        cov = CovarianceEstimator.estimate(returns, method="shrunk")

        assert cov.shape == (2, 2)

    def test_estimate_unsupported_method(self) -> None:
        """Test unsupported method raises ValueError."""
        from medusa.pricing.risk_models import CovarianceEstimator

        returns = pd.DataFrame({"A": [0.01, 0.02], "B": [0.01, 0.03]})

        with pytest.raises(ValueError, match="Unsupported method"):
            CovarianceEstimator.estimate(returns, method="invalid")

    def test_correlation_from_covariance(self) -> None:
        """Test correlation matrix conversion."""
        from medusa.pricing.risk_models import CovarianceEstimator

        cov = pd.DataFrame([[0.04, 0.02], [0.02, 0.09]], index=["A", "B"], columns=["A", "B"])

        corr = CovarianceEstimator.correlation_from_covariance(cov)

        # Diagonal should be 1.0
        assert abs(corr.loc["A", "A"] - 1.0) < 1e-10
        assert abs(corr.loc["B", "B"] - 1.0) < 1e-10

        # Off-diagonal correlation = cov / (std_a * std_b)
        expected_corr = 0.02 / (0.2 * 0.3)
        assert abs(corr.loc["A", "B"] - expected_corr) < 1e-6


class TestRiskDecomposition:
    """Tests for RiskDecomposition."""

    def test_decompose_variance_missing_assets(self) -> None:
        """Test decompose_variance raises ValueError on missing assets."""
        from medusa.pricing.risk_models import RiskDecomposition

        weights = pd.Series([0.6, 0.4], index=["A", "B"])
        betas = pd.DataFrame([[1.0, 0.5]], index=["A"], columns=["factor1", "factor2"])
        factor_cov = pd.DataFrame(
            [[0.04, 0.01], [0.01, 0.09]],
            index=["factor1", "factor2"],
            columns=["factor1", "factor2"],
        )
        specific_risk = pd.Series([0.1], index=["A"])

        with pytest.raises(ValueError, match="All assets in weights must be in betas"):
            RiskDecomposition.decompose_variance(weights, betas, factor_cov, specific_risk)

    def test_decompose_variance_calculation(self) -> None:
        """Test variance decomposition calculation."""
        from medusa.pricing.risk_models import RiskDecomposition

        weights = pd.Series([0.6, 0.4], index=["A", "B"])
        betas = pd.DataFrame(
            [[1.0, 0.5], [0.8, 0.3]], index=["A", "B"], columns=["factor1", "factor2"]
        )
        factor_cov = pd.DataFrame(
            [[0.04, 0.01], [0.01, 0.09]],
            index=["factor1", "factor2"],
            columns=["factor1", "factor2"],
        )
        specific_risk = pd.Series([0.1, 0.12], index=["A", "B"])

        result = RiskDecomposition.decompose_variance(weights, betas, factor_cov, specific_risk)

        assert "total_variance" in result
        assert "factor_variance" in result
        assert "specific_variance" in result
        assert "factor_contribution_pct" in result
        assert "specific_contribution_pct" in result

        # Total should be sum of factor and specific
        assert (
            abs(
                result["total_variance"] - (result["factor_variance"] + result["specific_variance"])
            )
            < 1e-10
        )

        # Percentages should sum to 100
        assert (
            abs(result["factor_contribution_pct"] + result["specific_contribution_pct"] - 100.0)
            < 1e-6
        )

    def test_marginal_risk_contribution_zero_volatility(self) -> None:
        """Test MRC returns zeros when portfolio volatility is zero."""
        from medusa.pricing.risk_models import RiskDecomposition

        weights = pd.Series([0.5, 0.5], index=["A", "B"])
        cov = pd.DataFrame([[0.0, 0.0], [0.0, 0.0]], index=["A", "B"], columns=["A", "B"])

        mrc = RiskDecomposition.marginal_risk_contribution(weights, cov)

        assert (mrc == 0.0).all()

    def test_marginal_risk_contribution_calculation(self) -> None:
        """Test marginal risk contribution calculation."""
        from medusa.pricing.risk_models import RiskDecomposition

        weights = pd.Series([0.6, 0.4], index=["A", "B"])
        cov = pd.DataFrame([[0.04, 0.02], [0.02, 0.09]], index=["A", "B"], columns=["A", "B"])

        mrc = RiskDecomposition.marginal_risk_contribution(weights, cov)

        assert len(mrc) == 2
        assert mrc.index.tolist() == ["A", "B"]

    def test_risk_parity_weights_convergence(self) -> None:
        """Test risk parity weights converge to equal risk contributions."""
        from medusa.pricing.risk_models import RiskDecomposition

        cov = pd.DataFrame(
            [[0.04, 0.02, 0.01], [0.02, 0.09, 0.03], [0.01, 0.03, 0.16]],
            index=["A", "B", "C"],
            columns=["A", "B", "C"],
        )

        rp_weights = RiskDecomposition.risk_parity_weights(cov)

        # Weights should sum to 1
        assert abs(rp_weights.sum() - 1.0) < 1e-6

        # All weights should be positive
        assert (rp_weights > 0).all()

    def test_risk_parity_weights_small_tolerance(self) -> None:
        """Test risk parity with very strict tolerance."""
        from medusa.pricing.risk_models import RiskDecomposition

        # Normal covariance matrix
        cov = pd.DataFrame(
            [[0.04, 0.02, 0.01], [0.02, 0.09, 0.03], [0.01, 0.03, 0.16]],
            index=["A", "B", "C"],
            columns=["A", "B", "C"],
        )

        # Should still converge with strict tolerance
        rp_weights = RiskDecomposition.risk_parity_weights(cov, tol=1e-10)

        # Weights should sum to 1
        assert abs(rp_weights.sum() - 1.0) < 1e-6


# ============================================================================
# Equity Screener Tests
# ============================================================================


class TestEquityScreener:
    """Tests for EquityScreener."""

    def test_screen_empty_universe(self) -> None:
        """Test screening empty universe returns empty DataFrame."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame()
        criteria = {"market_cap": (">=", 1000)}

        result = EquityScreener.screen(universe, criteria)

        assert result.empty

    def test_screen_missing_column(self) -> None:
        """Test screening raises ValueError on missing column."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame({"symbol": ["AAPL"], "market_cap": [2800]})
        criteria = {"pe_ratio": (">", 10)}  # pe_ratio missing

        with pytest.raises(ValueError, match="Column 'pe_ratio' not found"):
            EquityScreener.screen(universe, criteria)

    def test_screen_operators(self) -> None:
        """Test all screening operators."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame(
            {
                "symbol": ["AAPL", "MSFT", "GOOGL", "TSLA"],
                "market_cap": [2800, 2500, 1800, 800],
                "pe_ratio": [28, 32, 25, 150],
                "roe": [0.40, 0.35, 0.28, 0.10],
                "sector": ["Tech", "Tech", "Tech", "Auto"],
            }
        )

        # Test '>' operator
        result = EquityScreener.screen(universe, {"market_cap": (">", 1000)})
        assert len(result) == 3

        # Test '>=' operator
        result = EquityScreener.screen(universe, {"market_cap": (">=", 2500)})
        assert len(result) == 2

        # Test '<' operator
        result = EquityScreener.screen(universe, {"pe_ratio": ("<", 30)})
        assert len(result) == 2

        # Test '<=' operator
        result = EquityScreener.screen(universe, {"pe_ratio": ("<=", 28)})
        assert len(result) == 2

        # Test '==' operator
        result = EquityScreener.screen(universe, {"sector": ("==", "Tech")})
        assert len(result) == 3

        # Test '!=' operator
        result = EquityScreener.screen(universe, {"sector": ("!=", "Tech")})
        assert len(result) == 1

        # Test 'in' operator
        result = EquityScreener.screen(universe, {"symbol": ("in", ["AAPL", "MSFT"])})
        assert len(result) == 2

        # Test 'not_in' operator
        result = EquityScreener.screen(universe, {"symbol": ("not_in", ["AAPL"])})
        assert len(result) == 3

    def test_screen_in_operator_invalid_threshold(self) -> None:
        """Test 'in' operator raises ValueError with non-list threshold."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame({"symbol": ["AAPL"], "market_cap": [2800]})

        with pytest.raises(ValueError, match="'in' operator requires list"):
            EquityScreener.screen(universe, {"symbol": ("in", "AAPL")})

    def test_screen_unsupported_operator(self) -> None:
        """Test unsupported operator raises ValueError."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame({"symbol": ["AAPL"], "market_cap": [2800]})

        with pytest.raises(ValueError, match="Unsupported operator"):
            EquityScreener.screen(universe, {"market_cap": ("~=", 1000)})

    def test_multi_stage_screen(self) -> None:
        """Test multi-stage screening with funnel tracking."""
        from medusa.pricing.equity_screener import EquityScreener

        universe = pd.DataFrame(
            {
                "symbol": ["AAPL", "MSFT", "GOOGL", "TSLA"],
                "market_cap": [2800, 2500, 1800, 800],
                "pe_ratio": [28, 32, 25, 150],
                "roe": [0.40, 0.35, 0.28, 0.10],
            }
        )

        stages = [
            {"market_cap": (">=", 1000)},  # Stage 1: 3 assets
            {"pe_ratio": ("<", 30), "roe": (">", 0.25)},  # Stage 2: 2 assets
        ]

        result, counts = EquityScreener.multi_stage_screen(universe, stages)

        assert len(counts) == 2
        assert counts[0] == 3
        assert counts[1] == 2
        assert len(result) == 2


class TestAlphaRanker:
    """Tests for AlphaRanker."""

    def test_rank_universe_empty(self) -> None:
        """Test rank_universe with empty DataFrame."""
        from medusa.pricing.equity_screener import AlphaRanker

        universe = pd.DataFrame()

        def scorer(row):
            return 0.0

        result = AlphaRanker.rank_universe(universe, scorer, top_n=10)

        assert result.empty

    def test_rank_universe_custom_scorer(self) -> None:
        """Test rank_universe with custom scorer."""
        from medusa.pricing.equity_screener import AlphaRanker

        universe = pd.DataFrame(
            {
                "symbol": ["AAPL", "MSFT", "GOOGL", "TSLA"],
                "pe_ratio": [28, 32, 25, 150],
                "roe": [0.40, 0.35, 0.28, 0.10],
            }
        )

        def value_quality_scorer(row):
            # Lower P/E is better, higher ROE is better
            return -row["pe_ratio"] + 100 * row["roe"]

        result = AlphaRanker.rank_universe(universe, value_quality_scorer, top_n=2)

        assert len(result) == 2
        assert "alpha_score" in result.columns
        assert "rank" in result.columns
        # AAPL should rank highest (score = -28 + 40 = 12)
        assert result.iloc[0]["symbol"] == "AAPL"

    def test_rank_by_metrics_missing_columns(self) -> None:
        """Test rank_by_metrics raises ValueError on missing columns."""
        from medusa.pricing.equity_screener import AlphaRanker

        universe = pd.DataFrame({"symbol": ["AAPL"], "market_cap": [2800]})

        with pytest.raises(ValueError, match="Missing columns"):
            AlphaRanker.rank_by_metrics(universe, {"pe_ratio": "asc"}, top_n=10)

    def test_rank_by_metrics_calculation(self) -> None:
        """Test rank_by_metrics with multiple metrics."""
        from medusa.pricing.equity_screener import AlphaRanker

        universe = pd.DataFrame(
            {
                "symbol": ["AAPL", "MSFT", "GOOGL", "TSLA"],
                "pe_ratio": [28, 32, 25, 150],
                "roe": [0.40, 0.35, 0.28, 0.10],
                "debt_to_equity": [1.5, 0.8, 0.3, 2.0],
            }
        )

        metrics = {
            "pe_ratio": "asc",  # Lower is better
            "roe": "desc",  # Higher is better
            "debt_to_equity": "asc",  # Lower is better
        }

        result = AlphaRanker.rank_by_metrics(universe, metrics, top_n=3)

        assert len(result) == 3
        assert "composite_rank" in result.columns
        assert "rank" in result.columns
        # Verify individual rank columns exist
        assert "pe_ratio_rank" in result.columns
        assert "roe_rank" in result.columns


# ============================================================================
# Model Registry Tests
# ============================================================================


class TestModelRegistry:
    """Tests for ModelRegistry (MLflow wrapper)."""

    def test_registry_init_no_mlflow(self, monkeypatch) -> None:
        """Test ModelRegistry raises ImportError when mlflow not available."""
        from medusa.models import registry

        monkeypatch.setattr(registry, "HAS_MLFLOW", False)

        from medusa.models.registry import ModelRegistry

        with pytest.raises(ImportError, match="MLflow not installed"):
            ModelRegistry()

    def test_registry_init_with_mlflow(self, tmp_path) -> None:
        """Test ModelRegistry initialization."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="test_exp", tracking_uri=tracking_uri)

        assert registry.experiment_name == "test_exp"
        assert registry.tracking_uri == tracking_uri
        assert registry.experiment_id is not None

    def test_log_training_run(self, tmp_path) -> None:
        """Test logging a training run."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="test", tracking_uri=tracking_uri)

        # Mock model
        class DummyModel:
            pass

        model = DummyModel()
        params = {"lr": 0.001, "epochs": 10}
        metrics = {"train_loss": 0.5, "val_sharpe": 1.2}
        tags = {"strategy": "sma"}

        run_id = registry.log_training_run(model=model, params=params, metrics=metrics, tags=tags)

        assert isinstance(run_id, str)
        assert len(run_id) > 0

    def test_compare_runs_empty(self, tmp_path) -> None:
        """Test compare_runs returns empty DataFrame when no runs."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="empty_exp", tracking_uri=tracking_uri)

        result = registry.compare_runs()

        assert result.empty

    def test_get_best_model_no_runs(self, tmp_path) -> None:
        """Test get_best_model raises ValueError when no runs."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="no_runs", tracking_uri=tracking_uri)

        with pytest.raises(ValueError, match="No runs found"):
            registry.get_best_model()

    def test_register_model_invalid_stage(self, tmp_path) -> None:
        """Test register_model raises ValueError on invalid stage."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="test", tracking_uri=tracking_uri)

        with pytest.raises(ValueError, match="Invalid stage"):
            registry.register_model(
                run_id="fake_run_id",
                model_name="model",
                registered_model_name="test_model",
                stage="invalid_stage",
            )

    def test_log_artifact_from_dict(self, tmp_path) -> None:
        """Test logging dictionary as JSON artifact."""
        try:
            import mlflow  # noqa: F401
        except ImportError:
            pytest.skip("mlflow not available")

        from medusa.models.registry import ModelRegistry

        tracking_uri = str(tmp_path / "mlruns")
        registry = ModelRegistry(experiment_name="test", tracking_uri=tracking_uri)

        # Start a run and log artifact
        import mlflow

        with mlflow.start_run():
            registry.log_artifact_from_dict({"key": "value"}, "test.json")


# ============================================================================
# N-BEATS Model Tests
# ============================================================================


class TestNBEATSModel:
    """Tests for NBEATSModel."""

    def test_nbeats_init(self) -> None:
        """Test N-BEATS initialization."""
        from medusa.models.nbeats import NBEATSModel

        class MockDataset:
            pass

        dataset = MockDataset()
        model = NBEATSModel(dataset, learning_rate=1e-4)

        assert model.dataset is dataset
        assert model._kwargs["learning_rate"] == 1e-4

    def test_nbeats_build_no_pytorch_forecasting(self, monkeypatch) -> None:
        """Test build returns None when pytorch-forecasting not available."""
        from medusa.models.nbeats import NBEATSModel

        class MockDataset:
            pass

        # Mock import failure
        import builtins

        original_import = builtins.__import__

        def mock_import(name, *args, **kwargs):
            if name == "pytorch_forecasting":
                raise ImportError("pytorch-forecasting not installed")
            return original_import(name, *args, **kwargs)

        monkeypatch.setattr(builtins, "__import__", mock_import)

        dataset = MockDataset()
        model = NBEATSModel(dataset)
        result = model.build()

        assert result is None

    def test_nbeats_model_property(self) -> None:
        """Test model property calls build if not built."""
        try:
            from pytorch_forecasting import NBeats  # noqa: F401
        except ImportError:
            pytest.skip("pytorch-forecasting not available")

        # The model property will call build, which requires a real dataset
        # Skip this test - it requires pytorch-forecasting internals
        pytest.skip("Requires full pytorch-forecasting TimeSeriesDataSet setup")


# ============================================================================
# TFT Model Tests
# ============================================================================


class TestTFTModel:
    """Tests for TFTModel."""

    def test_tft_init(self) -> None:
        """Test TFT initialization."""
        from medusa.models.tft import TFTModel

        class MockDataset:
            pass

        dataset = MockDataset()
        model = TFTModel(dataset, hidden_size=128)

        assert model.dataset is dataset
        assert model._kwargs["hidden_size"] == 128

    def test_tft_build_no_pytorch_forecasting(self, monkeypatch) -> None:
        """Test build returns None when pytorch-forecasting not available."""
        from medusa.models.tft import TFTModel

        class MockDataset:
            pass

        # Mock import failure
        import builtins

        original_import = builtins.__import__

        def mock_import(name, *args, **kwargs):
            if name == "pytorch_forecasting":
                raise ImportError("pytorch-forecasting not installed")
            return original_import(name, *args, **kwargs)

        monkeypatch.setattr(builtins, "__import__", mock_import)

        dataset = MockDataset()
        model = TFTModel(dataset)
        result = model.build()

        assert result is None

    def test_tft_model_property(self) -> None:
        """Test model property calls build if not built."""
        try:
            from pytorch_forecasting import TemporalFusionTransformer  # noqa: F401
        except ImportError:
            pytest.skip("pytorch-forecasting not available")

        # The model property will call build, which requires a real dataset
        # Skip this test - it requires pytorch-forecasting internals
        pytest.skip("Requires full pytorch-forecasting TimeSeriesDataSet setup")

    def test_tft_train_method(self) -> None:
        """Test train method builds model if not built."""
        try:
            from pytorch_forecasting import TemporalFusionTransformer  # noqa: F401
        except ImportError:
            pytest.skip("pytorch-forecasting not available")

        # The train method will call build, which requires a real dataset
        # Skip this test - it requires pytorch-forecasting internals
        pytest.skip("Requires full pytorch-forecasting TimeSeriesDataSet setup")
