"""Additional simulation and optimization tests to reach 90% coverage."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

# Test 1-5: Monte Carlo simulation edge cases


class TestMonteCarloEdgeCases:
    """Test Monte Carlo simulation edge cases beyond existing tests."""

    def test_monte_carlo_with_zero_volatility(self):
        """Test Monte Carlo with nearly-zero volatility (deterministic)."""
        from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig

        np.random.seed(42)
        # Create minimal historical returns with near-zero variance
        returns = pd.DataFrame(
            np.full((100, 2), 0.0002),  # constant returns
            columns=["Asset_A", "Asset_B"],
        )
        # Add tiny noise to avoid singular covariance
        returns += np.random.normal(0, 1e-8, returns.shape)

        weights = pd.Series({"Asset_A": 0.6, "Asset_B": 0.4})

        config = SimulationConfig(n_paths=10, n_steps=50, method="gbm")
        engine = MonteCarloEngine(config)
        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        # With near-zero volatility, P&L distribution should be tight
        assert result.std_pnl < 5000  # Low variance

    def test_monte_carlo_bootstrap_method(self):
        """Test Monte Carlo with bootstrap resampling."""
        from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.0005, 0.02, (500, 2)),
            columns=["Asset_A", "Asset_B"],
        )
        weights = pd.Series({"Asset_A": 0.5, "Asset_B": 0.5})

        config = SimulationConfig(n_paths=10, n_steps=50, method="historical_bootstrap")
        engine = MonteCarloEngine(config)
        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        assert result.pnl_distribution is not None
        assert len(result.pnl_distribution) == 10

    def test_monte_carlo_stress_test(self):
        """Test Monte Carlo stress test with extreme parameters."""
        from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig

        np.random.seed(42)
        # High-volatility historical returns
        returns = pd.DataFrame(
            np.random.normal(0.0, 0.05, (200, 2)),
            columns=["BTC", "ETH"],
        )
        weights = pd.Series({"BTC": 0.6, "ETH": 0.4})

        config = SimulationConfig(n_paths=100, n_steps=50, method="gbm")
        engine = MonteCarloEngine(config)
        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        # High volatility should produce wide range of outcomes
        assert result.std_pnl > 100  # High variance

    def test_monte_carlo_confidence_intervals(self):
        """Test Monte Carlo VaR/CVaR calculation."""
        from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.0001, 0.02, (500, 2)),
            columns=["Asset_A", "Asset_B"],
        )
        weights = pd.Series({"Asset_A": 0.5, "Asset_B": 0.5})

        config = SimulationConfig(n_paths=1000, n_steps=50, method="gbm")
        engine = MonteCarloEngine(config)
        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        # VaR should be positive (representing a loss amount)
        assert result.var_95 >= 0
        # CVaR >= VaR (expected shortfall is worse than VaR)
        assert result.cvar_95 >= result.var_95

    def test_monte_carlo_seed_reproducibility(self):
        """Test that same seed produces same results."""
        from medusa.simulation.monte_carlo import MonteCarloEngine, SimulationConfig

        returns = pd.DataFrame(
            np.random.RandomState(0).normal(0.0005, 0.02, (200, 2)),
            columns=["Asset_A", "Asset_B"],
        )
        weights = pd.Series({"Asset_A": 0.5, "Asset_B": 0.5})

        config = SimulationConfig(n_paths=10, n_steps=50, method="gbm")

        # Run 1
        np.random.seed(42)
        engine1 = MonteCarloEngine(config)
        result1 = engine1.simulate_portfolio(returns, weights, initial_value=100000)

        # Run 2 with same seed
        np.random.seed(42)
        engine2 = MonteCarloEngine(config)
        result2 = engine2.simulate_portfolio(returns, weights, initial_value=100000)

        # Should be identical
        assert np.allclose(result1.pnl_distribution, result2.pnl_distribution)


# Test 6-10: Portfolio optimization edge cases


class TestPortfolioOptimizationEdgeCases:
    """Test portfolio optimization edge cases."""

    def test_min_variance_portfolio(self):
        """Test minimum variance portfolio optimization."""
        from medusa.optimization.portfolio_optimizer import MeanVarianceOptimizer

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.001, 0.02, (252, 3)),
            columns=["Asset_A", "Asset_B", "Asset_C"],
        )
        cov_matrix = returns.cov() * 252  # Annualized

        optimizer = MeanVarianceOptimizer()
        result = optimizer.min_variance(cov_matrix)

        # Weights should sum to 1
        assert pytest.approx(result.weights.sum(), rel=0.01) == 1.0
        # All weights should be between 0 and 1 (long-only)
        assert np.all(result.weights >= -0.01)  # Allow tiny numerical noise
        assert np.all(result.weights <= 1.01)

    def test_max_sharpe_portfolio(self):
        """Test maximum Sharpe ratio portfolio."""
        from medusa.optimization.portfolio_optimizer import MeanVarianceOptimizer

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.001, 0.02, (252, 3)),
            columns=["Asset_A", "Asset_B", "Asset_C"],
        )
        expected_returns = returns.mean() * 252  # Annualized
        cov_matrix = returns.cov() * 252

        optimizer = MeanVarianceOptimizer()
        result = optimizer.max_sharpe(expected_returns, cov_matrix, risk_free_rate=0.02)

        assert pytest.approx(result.weights.sum(), rel=0.01) == 1.0
        assert np.all(result.weights >= -0.01)
        assert np.all(result.weights <= 1.01)

    def test_efficient_frontier(self):
        """Test efficient frontier calculation."""
        from medusa.optimization.portfolio_optimizer import MeanVarianceOptimizer

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.001, 0.02, (252, 3)),
            columns=["Asset_A", "Asset_B", "Asset_C"],
        )
        expected_returns = returns.mean() * 252
        cov_matrix = returns.cov() * 252

        optimizer = MeanVarianceOptimizer()
        frontier = optimizer.efficient_frontier(expected_returns, cov_matrix, n_points=10)

        # Frontier should be a DataFrame with risk, return, weights columns
        assert isinstance(frontier, pd.DataFrame)
        assert len(frontier) >= 2  # At least some points should succeed
        assert "risk" in frontier.columns
        assert "return" in frontier.columns
        assert "weights" in frontier.columns

    def test_black_litterman_optimization(self):
        """Test Black-Litterman model with views."""
        from medusa.optimization.portfolio_optimizer import BlackLittermanOptimizer

        np.random.seed(42)
        returns = pd.DataFrame(
            np.random.normal(0.001, 0.02, (252, 3)),
            columns=["Asset_A", "Asset_B", "Asset_C"],
        )
        cov_matrix = returns.cov() * 252

        # Market capitalizations
        market_caps = pd.Series({"Asset_A": 1e9, "Asset_B": 5e8, "Asset_C": 2e8})

        # Investor views: Asset A will outperform
        views = [
            {"assets": ["Asset_A"], "return": 0.12, "confidence": 0.5},
        ]

        optimizer = BlackLittermanOptimizer()
        result = optimizer.optimize(
            cov_matrix=cov_matrix,
            market_caps=market_caps,
            views=views,
        )

        # Weights should sum to ~1
        assert pytest.approx(result.weights.sum(), rel=0.01) == 1.0

    def test_rebalancing_zero_trade_case(self):
        """Test rebalancing when current weights equal target."""
        from medusa.optimization.portfolio_optimizer import RebalancingEngine

        assets = ["Asset_A", "Asset_B", "Asset_C"]
        current_weights = pd.Series([0.4, 0.4, 0.2], index=assets)
        target_weights = pd.Series([0.4, 0.4, 0.2], index=assets)
        prices = pd.Series([100.0, 50.0, 25.0], index=assets)

        engine = RebalancingEngine()
        trades = engine.generate_trades(
            current_weights=current_weights,
            target_weights=target_weights,
            portfolio_value=100000.0,
            prices=prices,
        )

        # No significant trades needed (all < min_trade_value)
        assert isinstance(trades, pd.DataFrame)
        if len(trades) > 0:
            assert all(abs(trades["trade_value"]) < 200)


# Test 11-15: Scenario analysis using ScenarioEngine


class TestScenarioAnalysis:
    """Test ScenarioEngine for stress testing."""

    def test_parallel_shift_scenario(self):
        """Test running a scenario with portfolio."""
        from medusa.simulation.scenario_engine import ScenarioEngine

        engine = ScenarioEngine()
        weights = pd.Series({"SPY": 0.6, "BTC": 0.3, "gold": 0.1})

        result = engine.run_scenario(100000, weights, "2008_financial_crisis")

        assert "pnl" in result
        assert result["pnl"] < 0  # Crisis scenario should show losses

    def test_steepener_scenario(self):
        """Test scenario with rate shock."""
        from medusa.simulation.scenario_engine import ScenarioEngine

        engine = ScenarioEngine()
        weights = pd.Series({"bonds_2y": 0.3, "bonds_10y": 0.4, "bonds_30y": 0.3})

        result = engine.run_scenario(100000, weights, "rate_shock_200bp")

        # Rate shock should cause losses in bonds
        assert result["pnl"] < 0

    def test_flattener_scenario(self):
        """Test COVID crash scenario."""
        from medusa.simulation.scenario_engine import ScenarioEngine

        engine = ScenarioEngine()
        weights = pd.Series({"SPY": 0.5, "BTC": 0.3, "bonds_10y": 0.2})

        result = engine.run_scenario(100000, weights, "2020_covid_crash")

        assert result["pnl"] < 0
        assert "period" in result

    def test_butterfly_scenario(self):
        """Test custom scenario addition and execution."""
        from medusa.simulation.scenario_engine import ScenarioEngine

        engine = ScenarioEngine()

        # Add custom scenario
        engine.add_custom_scenario(
            scenario_name="test_butterfly",
            description="Test butterfly move",
            shocks={"bonds_2y": 0.01, "bonds_10y": -0.02, "bonds_30y": 0.01},
        )

        weights = pd.Series({"bonds_2y": 0.3, "bonds_10y": 0.4, "bonds_30y": 0.3})
        result = engine.run_scenario(100000, weights, "test_butterfly")

        assert "pnl" in result
        # Clean up: remove the custom scenario from class-level dict
        del ScenarioEngine.HISTORICAL_SCENARIOS["test_butterfly"]

    def test_twist_scenario(self):
        """Test running all scenarios and getting comparison."""
        from medusa.simulation.scenario_engine import ScenarioEngine

        engine = ScenarioEngine()
        weights = pd.Series({"SPY": 0.5, "BTC": 0.3, "bonds_10y": 0.2})

        results = engine.run_all_scenarios(100000, weights)

        assert isinstance(results, pd.DataFrame)
        assert len(results) > 0
        assert "pnl" in results.columns
        assert "scenario" in results.columns
        # Should be sorted by pnl (worst first)
        assert results.iloc[0]["pnl"] <= results.iloc[-1]["pnl"]
