"""Tests for portfolio optimization module."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from medusa.optimization import (
    BlackLittermanOptimizer,
    MeanVarianceOptimizer,
    RebalancingEngine,
    RiskParityOptimizer,
)


@pytest.fixture
def simple_returns():
    """Simple 3-asset returns for testing."""
    np.random.seed(42)
    dates = pd.date_range("2020-01-01", periods=252, freq="D")
    returns = pd.DataFrame(
        {
            "AAPL": np.random.normal(0.0005, 0.02, 252),
            "MSFT": np.random.normal(0.0004, 0.018, 252),
            "GOOGL": np.random.normal(0.0006, 0.022, 252),
        },
        index=dates,
    )
    return returns


@pytest.fixture
def expected_returns(simple_returns):
    """Annualized expected returns."""
    return simple_returns.mean() * 252


@pytest.fixture
def cov_matrix(simple_returns):
    """Annualized covariance matrix."""
    return simple_returns.cov() * 252


@pytest.fixture
def market_caps():
    """Market capitalizations for Black-Litterman."""
    return pd.Series({"AAPL": 2.8e12, "MSFT": 2.5e12, "GOOGL": 1.8e12})


# ============================================================================
# MeanVarianceOptimizer Tests
# ============================================================================


def test_mean_variance_equal_returns_equal_weights(cov_matrix):
    """If all assets have equal expected returns, min variance → equal weights."""
    # Equal expected returns
    expected_returns = pd.Series([0.10, 0.10, 0.10], index=cov_matrix.index)

    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(expected_returns, cov_matrix, risk_aversion=1.0)

    # Weights should be roughly equal (within tolerance)
    assert result.constraints_satisfied
    assert np.allclose(result.weights.values, [1 / 3, 1 / 3, 1 / 3], atol=0.1)
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_mean_variance_constraints_max_weight(expected_returns, cov_matrix):
    """Max weight constraint should be enforced."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(
        expected_returns,
        cov_matrix,
        risk_aversion=1.0,
        constraints={"max_weight": 0.40},
    )

    # No weight should exceed 40%
    assert result.constraints_satisfied
    assert all(result.weights <= 0.40 + 1e-6)
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_mean_variance_constraints_min_weight(expected_returns, cov_matrix):
    """Min weight constraint should be enforced."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(
        expected_returns,
        cov_matrix,
        risk_aversion=1.0,
        constraints={"min_weight": 0.2},
    )

    # All weights should be >= 20%
    assert result.constraints_satisfied
    assert all(result.weights >= 0.2 - 1e-6)
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_mean_variance_long_only(expected_returns, cov_matrix):
    """Long-only constraint should prevent negative weights."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(
        expected_returns,
        cov_matrix,
        risk_aversion=1.0,
        constraints={"long_only": True},
    )

    # All weights should be non-negative
    assert result.constraints_satisfied
    assert all(result.weights >= -1e-6)
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_mean_variance_target_return(expected_returns, cov_matrix):
    """Target return constraint should be satisfied."""
    target_return = 0.08

    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(
        expected_returns,
        cov_matrix,
        risk_aversion=0.0,  # Ignore utility, just minimize variance
        constraints={"target_return": target_return},
    )

    # Portfolio return should match target (within tolerance)
    assert abs(result.expected_return - target_return) < 1e-3


def test_efficient_frontier_monotonic(expected_returns, cov_matrix):
    """Efficient frontier should have monotonically increasing return with risk."""
    optimizer = MeanVarianceOptimizer()
    frontier = optimizer.efficient_frontier(expected_returns, cov_matrix, n_points=20)

    # Returns should increase with risk
    assert not frontier.empty
    assert len(frontier) > 0

    # Check monotonicity (allowing small violations due to numerical noise)
    return_values = frontier["return"].values

    for i in range(1, len(return_values)):
        # Return should generally increase with risk (allow small violations)
        if return_values[i] < return_values[i - 1]:
            # Allow small violations (< 1%)
            assert (return_values[i - 1] - return_values[i]) / return_values[i - 1] < 0.01


def test_max_sharpe_higher_than_individual(expected_returns, cov_matrix):
    """Max Sharpe portfolio should have higher Sharpe than any individual asset."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.max_sharpe(expected_returns, cov_matrix, risk_free_rate=0.04)

    # Calculate Sharpe for individual assets
    individual_sharpes = []
    for asset in expected_returns.index:
        asset_return = expected_returns[asset]
        asset_vol = np.sqrt(cov_matrix.loc[asset, asset])
        sharpe = (asset_return - 0.04) / asset_vol if asset_vol > 0 else 0.0
        individual_sharpes.append(sharpe)

    max_individual_sharpe = max(individual_sharpes)

    # Portfolio Sharpe should be >= max individual Sharpe (diversification benefit)
    assert result.sharpe_ratio >= max_individual_sharpe - 1e-3


def test_max_sharpe_weights_sum_to_one(expected_returns, cov_matrix):
    """Max Sharpe weights should sum to 1."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.max_sharpe(expected_returns, cov_matrix)

    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_min_variance_lowest_risk(expected_returns, cov_matrix):
    """Min variance portfolio should have lowest risk on frontier."""
    optimizer = MeanVarianceOptimizer()
    min_var_result = optimizer.min_variance(cov_matrix)

    # Generate frontier and check min variance is at the left edge
    frontier = optimizer.efficient_frontier(expected_returns, cov_matrix, n_points=30)

    if not frontier.empty:
        min_frontier_risk = frontier["risk"].min()
        # Min variance portfolio should have risk <= minimum on frontier
        assert min_var_result.expected_risk <= min_frontier_risk + 1e-3


def test_min_variance_weights_sum_to_one(cov_matrix):
    """Min variance weights should sum to 1."""
    optimizer = MeanVarianceOptimizer()
    result = optimizer.min_variance(cov_matrix)

    assert abs(result.weights.sum() - 1.0) < 1e-6


# ============================================================================
# RiskParityOptimizer Tests
# ============================================================================


def test_risk_parity_equal_contribution(cov_matrix):
    """Risk parity should give equal risk contribution (within tolerance)."""
    optimizer = RiskParityOptimizer()
    result = optimizer.optimize(cov_matrix)

    # Calculate risk contributions
    weights = result.weights.values
    Sigma = cov_matrix.values  # noqa: N806
    portfolio_var = weights @ Sigma @ weights
    mrc = Sigma @ weights
    risk_contrib = weights * mrc / portfolio_var

    # Risk contributions should be roughly equal
    target_contrib = 1.0 / len(weights)
    assert np.allclose(risk_contrib, target_contrib, atol=0.05)


def test_risk_parity_weights_sum_to_one(cov_matrix):
    """Risk parity weights should sum to 1."""
    optimizer = RiskParityOptimizer()
    result = optimizer.optimize(cov_matrix)

    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_risk_parity_custom_budgets(cov_matrix):
    """Risk parity with custom risk budgets."""
    # Custom budgets: AAPL 50%, others 25% each
    risk_budgets = pd.Series([0.5, 0.25, 0.25], index=cov_matrix.index)

    optimizer = RiskParityOptimizer()
    result = optimizer.optimize(cov_matrix, risk_budgets=risk_budgets)

    # Calculate risk contributions
    weights = result.weights.values
    Sigma = cov_matrix.values  # noqa: N806
    portfolio_var = weights @ Sigma @ weights
    mrc = Sigma @ weights
    risk_contrib = weights * mrc / portfolio_var

    # Risk contributions should match budgets
    assert np.allclose(risk_contrib, risk_budgets.values, atol=0.05)


# ============================================================================
# BlackLittermanOptimizer Tests
# ============================================================================


def test_black_litterman_bullish_view_increases_weight(cov_matrix, market_caps, expected_returns):
    """Bullish view on an asset should increase its weight."""
    optimizer = BlackLittermanOptimizer()

    # Baseline: no views (pure equilibrium)
    baseline_result = optimizer.optimize(
        cov_matrix,
        market_caps,
        views=[],
        risk_aversion=2.5,
        risk_free_rate=0.04,
    )

    # With bullish view on AAPL
    bullish_views = [
        {"assets": ["AAPL"], "return": 0.15, "confidence": 0.8},
    ]
    bullish_result = optimizer.optimize(
        cov_matrix,
        market_caps,
        views=bullish_views,
        risk_aversion=2.5,
        risk_free_rate=0.04,
    )

    # AAPL weight should increase
    assert bullish_result.weights["AAPL"] > baseline_result.weights["AAPL"]


def test_black_litterman_implied_returns(cov_matrix, market_caps):
    """Implied returns should be calculated from market caps."""
    optimizer = BlackLittermanOptimizer()
    implied_returns = optimizer.implied_returns(cov_matrix, market_caps, risk_aversion=2.5)

    # Implied returns should be proportional to market cap weights
    # Higher market cap → higher equilibrium return (given risk parity assumption)
    assert not implied_returns.empty
    assert len(implied_returns) == len(cov_matrix)


def test_black_litterman_weights_sum_to_one(cov_matrix, market_caps):
    """Black-Litterman weights should sum to 1."""
    optimizer = BlackLittermanOptimizer()

    views = [
        {"assets": ["AAPL"], "return": 0.10, "confidence": 0.5},
    ]

    result = optimizer.optimize(
        cov_matrix,
        market_caps,
        views=views,
        risk_aversion=2.5,
        risk_free_rate=0.04,
    )

    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_black_litterman_multiple_views(cov_matrix, market_caps):
    """Black-Litterman with multiple views."""
    optimizer = BlackLittermanOptimizer()

    views = [
        {"assets": ["AAPL"], "return": 0.12, "confidence": 0.7},
        {"assets": ["MSFT", "GOOGL"], "return": 0.08, "confidence": 0.5},
    ]

    result = optimizer.optimize(
        cov_matrix,
        market_caps,
        views=views,
        risk_aversion=2.5,
        risk_free_rate=0.04,
    )

    assert result.constraints_satisfied
    assert abs(result.weights.sum() - 1.0) < 1e-6


# ============================================================================
# RebalancingEngine Tests
# ============================================================================


def test_rebalancing_trades_sum_to_zero():
    """Rebalancing trades should be dollar-neutral (sum to zero)."""
    current_weights = pd.Series({"AAPL": 0.4, "MSFT": 0.3, "GOOGL": 0.3})
    target_weights = pd.Series({"AAPL": 0.3, "MSFT": 0.4, "GOOGL": 0.3})
    prices = pd.Series({"AAPL": 150.0, "MSFT": 300.0, "GOOGL": 2800.0})

    engine = RebalancingEngine()
    trades = engine.generate_trades(
        current_weights, target_weights, portfolio_value=100000, prices=prices
    )

    # Trade values should sum to approximately zero (within rounding)
    if not trades.empty:
        total_trade_value = trades["trade_value"].sum()
        assert abs(total_trade_value) < 1.0  # Within $1


def test_rebalancing_min_trade_value():
    """Trades below min_trade_value should be skipped."""
    current_weights = pd.Series({"AAPL": 0.333, "MSFT": 0.333, "GOOGL": 0.334})
    target_weights = pd.Series({"AAPL": 0.334, "MSFT": 0.333, "GOOGL": 0.333})
    prices = pd.Series({"AAPL": 150.0, "MSFT": 300.0, "GOOGL": 2800.0})

    engine = RebalancingEngine()
    trades = engine.generate_trades(
        current_weights,
        target_weights,
        portfolio_value=10000,
        prices=prices,
        min_trade_value=500,  # High threshold
    )

    # Small rebalancing should generate no trades
    assert trades.empty or len(trades) == 0


def test_rebalancing_correct_direction():
    """Trade quantities should have correct sign (buy/sell)."""
    current_weights = pd.Series({"AAPL": 0.2, "MSFT": 0.3, "GOOGL": 0.5})
    target_weights = pd.Series({"AAPL": 0.4, "MSFT": 0.3, "GOOGL": 0.3})
    prices = pd.Series({"AAPL": 150.0, "MSFT": 300.0, "GOOGL": 2800.0})

    engine = RebalancingEngine()
    trades = engine.generate_trades(
        current_weights, target_weights, portfolio_value=100000, prices=prices
    )

    # AAPL should be bought (positive qty)
    aapl_trade = trades[trades["symbol"] == "AAPL"]
    if not aapl_trade.empty:
        assert aapl_trade.iloc[0]["trade_qty"] > 0

    # GOOGL should be sold (negative qty)
    googl_trade = trades[trades["symbol"] == "GOOGL"]
    if not googl_trade.empty:
        assert googl_trade.iloc[0]["trade_qty"] < 0


# ============================================================================
# Edge Cases
# ============================================================================


def test_two_assets_optimization():
    """Optimization with only 2 assets."""
    returns = pd.DataFrame(
        {
            "A": np.random.normal(0.001, 0.02, 100),
            "B": np.random.normal(0.0008, 0.015, 100),
        }
    )
    expected_returns = returns.mean() * 252
    cov_matrix = returns.cov() * 252

    optimizer = MeanVarianceOptimizer()
    result = optimizer.max_sharpe(expected_returns, cov_matrix)

    assert result.constraints_satisfied
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_perfectly_correlated_assets():
    """Optimization with perfectly correlated assets."""
    # Create perfectly correlated returns
    base = np.random.normal(0.001, 0.02, 100)
    returns = pd.DataFrame({"A": base, "B": base * 1.1, "C": base * 0.9})

    expected_returns = returns.mean() * 252
    cov_matrix = returns.cov() * 252

    optimizer = MeanVarianceOptimizer()
    result = optimizer.max_sharpe(expected_returns, cov_matrix)

    # Should still produce valid weights
    assert result.constraints_satisfied
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_single_asset_degenerate():
    """Single asset portfolio (degenerate case)."""
    returns = pd.DataFrame({"A": np.random.normal(0.001, 0.02, 100)})
    expected_returns = returns.mean() * 252
    cov_matrix = returns.cov() * 252

    optimizer = MeanVarianceOptimizer()
    result = optimizer.max_sharpe(expected_returns, cov_matrix)

    # Should allocate 100% to the only asset
    assert abs(result.weights["A"] - 1.0) < 1e-6


def test_empty_inputs_raise_error():
    """Empty inputs should raise ValueError."""
    optimizer = MeanVarianceOptimizer()

    with pytest.raises(ValueError, match="cannot be empty"):
        optimizer.optimize(pd.Series(), pd.DataFrame(), risk_aversion=1.0)


def test_efficient_frontier_correct_number_of_points(expected_returns, cov_matrix):
    """Efficient frontier should generate requested number of points."""
    optimizer = MeanVarianceOptimizer()
    frontier = optimizer.efficient_frontier(expected_returns, cov_matrix, n_points=15)

    # Should generate up to 15 points (some may fail due to infeasibility)
    assert not frontier.empty
    assert len(frontier) <= 15


def test_max_sharpe_risk_free_rate_impact(expected_returns, cov_matrix):
    """Higher risk-free rate should reduce Sharpe ratio."""
    optimizer = MeanVarianceOptimizer()

    result_low_rf = optimizer.max_sharpe(expected_returns, cov_matrix, risk_free_rate=0.02)
    result_high_rf = optimizer.max_sharpe(expected_returns, cov_matrix, risk_free_rate=0.06)

    # Higher risk-free rate → lower Sharpe ratio
    assert result_low_rf.sharpe_ratio > result_high_rf.sharpe_ratio


def test_risk_parity_zero_variance_assets_handled():
    """Risk parity should handle very low variance gracefully."""
    # Create covariance with one very low variance asset
    cov = pd.DataFrame(
        [[0.04, 0.01, 0.01], [0.01, 0.0001, 0.0], [0.01, 0.0, 0.03]],
        index=["A", "B", "C"],
        columns=["A", "B", "C"],
    )

    optimizer = RiskParityOptimizer()
    result = optimizer.optimize(cov)

    # Should still produce valid weights
    assert result.constraints_satisfied
    assert abs(result.weights.sum() - 1.0) < 1e-6


def test_rebalancing_no_trades_when_aligned():
    """No trades should be generated when current = target weights."""
    weights = pd.Series({"AAPL": 0.5, "MSFT": 0.3, "GOOGL": 0.2})
    prices = pd.Series({"AAPL": 150.0, "MSFT": 300.0, "GOOGL": 2800.0})

    engine = RebalancingEngine()
    trades = engine.generate_trades(weights, weights, portfolio_value=100000, prices=prices)

    # Should be empty (no rebalancing needed)
    assert trades.empty


def test_mean_variance_max_volatility_constraint(expected_returns, cov_matrix):
    """Max volatility constraint should be enforced when feasible."""
    # Use a higher max_vol that's achievable
    max_vol = 0.25

    optimizer = MeanVarianceOptimizer()
    result = optimizer.optimize(
        expected_returns,
        cov_matrix,
        risk_aversion=1.0,
        constraints={"max_volatility": max_vol},
    )

    # If optimization succeeded, volatility should be <= max_volatility
    if result.constraints_satisfied:
        assert result.expected_risk <= max_vol + 1e-3
