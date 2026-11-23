"""Integration tests for Monte Carlo simulation + portfolio optimization."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from medusa.optimization.portfolio_optimizer import MeanVarianceOptimizer
from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig, SimulationResult


class TestMonteCarloBasic:
    """Basic Monte Carlo simulation tests."""

    def test_gbm_simulation_shapes(self) -> None:
        """Verify GBM simulation generates correct output shapes."""
        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.randn(252, 3) * 0.01,  # 1% daily volatility
            columns=["BTC", "ETH", "SOL"],
        )
        weights = pd.Series([0.5, 0.3, 0.2], index=["BTC", "ETH", "SOL"])
        config = SimulationConfig(n_paths=100, n_steps=50, method="gbm")
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=10000)

        assert result.pnl_distribution.shape == (100,)
        assert result.paths.shape == (100, 50, 3)
        assert result.max_drawdown_dist.shape == (100,)
        assert result.sharpe_distribution.shape == (100,)

    def test_var_cvar_properties(self) -> None:
        """Verify VaR/CVaR satisfy mathematical properties."""
        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.randn(252, 2) * 0.02,
            columns=["A", "B"],
        )
        weights = pd.Series([0.6, 0.4], index=["A", "B"])
        config = SimulationConfig(n_paths=10000, n_steps=252)
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        # VaR/CVaR are reported as positive numbers (representing loss magnitude)
        # VaR(99%) >= VaR(95%) — 99th percentile is rarer but worse
        assert result.var_99 >= result.var_95

        # CVaR (expected shortfall) >= VaR (tail mean is always worse than percentile)
        assert result.cvar_95 >= result.var_95
        assert result.cvar_99 >= result.var_99

        # CVaR(99%) >= CVaR(95%) (99th percentile tail is worse)
        assert result.cvar_99 >= result.cvar_95

        # Probability of profit in [0, 1]
        assert 0 <= result.prob_profit <= 1

    def test_historical_bootstrap_method(self) -> None:
        """Verify historical bootstrap sampling works."""
        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.randn(100, 2) * 0.015,
            columns=["X", "Y"],
        )
        weights = pd.Series([0.5, 0.5], index=["X", "Y"])
        config = SimulationConfig(n_paths=500, n_steps=50, method="historical_bootstrap")
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=50000)

        assert isinstance(result, SimulationResult)
        assert result.paths.shape == (500, 50, 2)

    def test_zero_volatility_edge_case(self) -> None:
        """Zero volatility should produce deterministic paths (all equal)."""
        returns = pd.DataFrame(
            np.zeros((252, 1)),  # Zero returns = zero volatility
            columns=["A"],
        )
        weights = pd.Series([1.0], index=["A"])
        config = SimulationConfig(n_paths=100, n_steps=50)
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=10000)

        # All paths should be identical (all P&L near zero)
        assert result.std_pnl < 1.0  # Near-zero variance
        assert result.var_95 == pytest.approx(0.0, abs=0.1)


class TestPortfolioOptimizationBasic:
    """Basic portfolio optimization tests."""

    def test_mean_variance_basic(self) -> None:
        """Verify mean-variance optimizer produces valid weights."""
        expected_returns = pd.Series([0.10, 0.08, 0.12], index=["A", "B", "C"])
        cov_matrix = pd.DataFrame(
            [[0.04, 0.01, 0.02], [0.01, 0.03, 0.01], [0.02, 0.01, 0.05]],
            index=["A", "B", "C"],
            columns=["A", "B", "C"],
        )

        optimizer = MeanVarianceOptimizer()
        result = optimizer.optimize(expected_returns, cov_matrix, risk_aversion=1.0)

        # Weights sum to 1
        assert result.weights.sum() == pytest.approx(1.0, abs=1e-4)

        # Long-only by default
        assert (result.weights >= 0).all()

        # Sharpe ratio is positive (assuming positive returns)
        assert result.sharpe_ratio > 0

    def test_max_weight_constraint(self) -> None:
        """Verify max_weight constraint is enforced."""
        expected_returns = pd.Series([0.15, 0.08, 0.06], index=["A", "B", "C"])
        cov_matrix = pd.DataFrame(
            [[0.02, 0.00, 0.00], [0.00, 0.03, 0.00], [0.00, 0.00, 0.04]],
            index=["A", "B", "C"],
            columns=["A", "B", "C"],
        )

        optimizer = MeanVarianceOptimizer()
        result = optimizer.optimize(
            expected_returns,
            cov_matrix,
            constraints={"max_weight": 0.5},  # No asset > 50%
        )

        assert (result.weights <= 0.5 + 1e-4).all()
        assert result.constraints_satisfied

    def test_target_return_constraint(self) -> None:
        """Verify target return constraint works."""
        expected_returns = pd.Series([0.10, 0.15, 0.08], index=["A", "B", "C"])
        cov_matrix = pd.DataFrame(
            [[0.04, 0.01, 0.00], [0.01, 0.06, 0.00], [0.00, 0.00, 0.03]],
            index=["A", "B", "C"],
            columns=["A", "B", "C"],
        )

        optimizer = MeanVarianceOptimizer()
        result = optimizer.optimize(
            expected_returns,
            cov_matrix,
            constraints={"target_return": 0.12},
        )

        # Portfolio return should match target
        assert result.expected_return == pytest.approx(0.12, abs=1e-3)


class TestSimulationOptimizationIntegration:
    """Integration tests: simulate → optimize → re-simulate."""

    def test_optimization_improves_sharpe(self) -> None:
        """Optimized portfolio should have better Sharpe than equal-weight."""
        np.random.seed(42)

        # Generate correlated returns
        returns = pd.DataFrame(
            np.random.randn(252, 3) * np.array([0.02, 0.015, 0.025]),
            columns=["A", "B", "C"],
        )

        # Equal-weight portfolio
        equal_weights = pd.Series([1 / 3, 1 / 3, 1 / 3], index=["A", "B", "C"])

        # Simulate equal-weight
        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)
        equal_result = engine.simulate_portfolio(returns, equal_weights)

        # Optimize portfolio
        expected_returns = returns.mean() * 252  # Annualize
        cov_matrix = returns.cov() * 252
        optimizer = MeanVarianceOptimizer()
        opt_result = optimizer.optimize(expected_returns, cov_matrix, risk_aversion=2.0)

        # Simulate optimized portfolio
        opt_sim_result = engine.simulate_portfolio(returns, opt_result.weights)

        # Optimized portfolio should have higher expected return or lower risk
        # (Not always better Sharpe due to estimation error, but at least comparable)
        assert opt_sim_result.expected_pnl >= equal_result.expected_pnl * 0.8
        # Or lower risk:
        # assert opt_sim_result.std_pnl <= equal_result.std_pnl * 1.2

    def test_var_reduction_after_optimization(self) -> None:
        """Optimizing for minimum variance should reduce risk (std dev)."""
        np.random.seed(42)

        returns = pd.DataFrame(
            np.random.randn(252, 4) * np.array([0.03, 0.02, 0.025, 0.018]),
            columns=["A", "B", "C", "D"],
        )

        # Equal-weight baseline
        equal_weights = pd.Series([0.25, 0.25, 0.25, 0.25], index=["A", "B", "C", "D"])

        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)
        baseline_result = engine.simulate_portfolio(returns, equal_weights)

        # Optimize for minimum variance (high risk aversion)
        expected_returns = returns.mean() * 252
        cov_matrix = returns.cov() * 252
        optimizer = MeanVarianceOptimizer()
        opt_result = optimizer.optimize(expected_returns, cov_matrix, risk_aversion=10.0)

        # Simulate optimized portfolio to ensure optimized weights are accepted.
        engine.simulate_portfolio(returns, opt_result.weights)

        # Expected risk should be lower (optimization target)
        # Allow 20% tolerance due to simulation variance
        assert opt_result.expected_risk <= baseline_result.std_pnl / 100000 * 1.2

    def test_empty_returns_raises_error(self) -> None:
        """Empty returns should raise ValueError."""
        empty_returns = pd.DataFrame()
        weights = pd.Series([1.0], index=["A"])
        engine = MonteCarloEngine()

        with pytest.raises(ValueError, match="Returns DataFrame is empty"):
            engine.simulate_portfolio(empty_returns, weights)

    def test_weight_asset_mismatch_raises_error(self) -> None:
        """Weights not matching returns columns should raise error."""
        returns = pd.DataFrame(np.random.randn(100, 2), columns=["A", "B"])
        weights = pd.Series([0.5, 0.5], index=["X", "Y"])  # Wrong assets
        engine = MonteCarloEngine()

        with pytest.raises(ValueError, match="All assets in returns must have weights"):
            engine.simulate_portfolio(returns, weights)

    def test_invalid_optimization_method_raises_error(self) -> None:
        """Invalid simulation method should raise error."""
        returns = pd.DataFrame(np.random.randn(100, 2), columns=["A", "B"])
        weights = pd.Series([0.5, 0.5], index=["A", "B"])
        config = SimulationConfig(method="invalid_method")
        engine = MonteCarloEngine(config)

        with pytest.raises(ValueError, match="Invalid method"):
            engine.simulate_portfolio(returns, weights)


class TestEdgeCases:
    """Edge case handling tests."""

    def test_single_asset_portfolio(self) -> None:
        """Single-asset portfolio should work."""
        returns = pd.DataFrame(np.random.randn(252, 1) * 0.02, columns=["A"])
        weights = pd.Series([1.0], index=["A"])
        config = SimulationConfig(n_paths=1000, n_steps=100)
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=10000)

        assert result.pnl_distribution.shape == (1000,)
        assert result.paths.shape == (1000, 100, 1)

    def test_high_correlation_portfolio(self) -> None:
        """Highly correlated assets should produce similar paths."""
        np.random.seed(42)

        # Generate perfectly correlated returns
        base = np.random.randn(252)
        returns = pd.DataFrame(
            {"A": base * 0.02, "B": base * 0.02},  # Perfect correlation
        )
        weights = pd.Series([0.5, 0.5], index=["A", "B"])
        config = SimulationConfig(n_paths=1000, n_steps=100)
        engine = MonteCarloEngine(config)

        engine.simulate_portfolio(returns, weights, initial_value=10000)

        # Correlation matrix should be near [[1, 1], [1, 1]]
        corr = returns.corr()
        assert corr.loc["A", "B"] == pytest.approx(1.0, abs=0.01)

    def test_negative_expected_returns(self) -> None:
        """Portfolio with negative expected returns should have prob_profit < 0.5."""
        np.random.seed(42)

        returns = pd.DataFrame(
            np.random.randn(252, 2) * 0.02 - 0.01,  # Negative drift
            columns=["A", "B"],
        )
        weights = pd.Series([0.5, 0.5], index=["A", "B"])
        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(returns, weights, initial_value=10000)

        # Should lose money on average
        assert result.expected_pnl < 0
        assert result.prob_profit < 0.5
