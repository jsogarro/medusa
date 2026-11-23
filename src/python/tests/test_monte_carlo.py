"""Tests for Monte Carlo simulation engine."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from medusa.simulation import MonteCarloEngine, ScenarioEngine, SimulationConfig


class TestSimulationConfig:
    """Test SimulationConfig dataclass."""

    def test_default_config(self) -> None:
        """Test default configuration values."""
        config = SimulationConfig()

        assert config.n_paths == 10000
        assert config.n_steps == 252
        assert config.dt == pytest.approx(1 / 252)
        assert config.method == "gbm"
        assert config.confidence_levels == [0.95, 0.99]

    def test_custom_config(self) -> None:
        """Test custom configuration values."""
        config = SimulationConfig(
            n_paths=5000,
            n_steps=126,
            dt=1 / 126,
            method="historical_bootstrap",
            confidence_levels=[0.90, 0.95, 0.99],
        )

        assert config.n_paths == 5000
        assert config.n_steps == 126
        assert config.dt == pytest.approx(1 / 126)
        assert config.method == "historical_bootstrap"
        assert config.confidence_levels == [0.90, 0.95, 0.99]


class TestMonteCarloEngine:
    """Test MonteCarloEngine class."""

    @pytest.fixture
    def sample_returns(self) -> pd.DataFrame:
        """Create sample returns data for testing."""
        np.random.seed(42)
        n_days = 252
        returns = pd.DataFrame(
            {
                "BTC": np.random.normal(0.001, 0.03, n_days),
                "ETH": np.random.normal(0.0008, 0.035, n_days),
                "SPY": np.random.normal(0.0004, 0.01, n_days),
            }
        )
        return returns

    @pytest.fixture
    def sample_weights(self) -> pd.Series:
        """Create sample portfolio weights."""
        return pd.Series({"BTC": 0.4, "ETH": 0.3, "SPY": 0.3})

    @pytest.fixture
    def engine(self) -> MonteCarloEngine:
        """Create MonteCarloEngine with small config for fast tests."""
        config = SimulationConfig(n_paths=100, n_steps=50)
        return MonteCarloEngine(config)

    def test_default_initialization(self) -> None:
        """Test engine initialization with default config."""
        engine = MonteCarloEngine()

        assert engine.config.n_paths == 10000
        assert engine.config.n_steps == 252

    def test_custom_initialization(self) -> None:
        """Test engine initialization with custom config."""
        config = SimulationConfig(n_paths=5000, n_steps=126)
        engine = MonteCarloEngine(config)

        assert engine.config.n_paths == 5000
        assert engine.config.n_steps == 126

    def test_simulate_portfolio_gbm(
        self,
        engine: MonteCarloEngine,
        sample_returns: pd.DataFrame,
        sample_weights: pd.Series,
    ) -> None:
        """Test portfolio simulation with GBM method."""
        result = engine.simulate_portfolio(sample_returns, sample_weights, initial_value=100000)

        # Check result structure
        assert len(result.pnl_distribution) == 100  # n_paths
        assert result.paths.shape == (100, 50, 3)  # n_paths × n_steps × n_assets

        # Check risk metrics are calculated
        assert result.var_95 > 0
        assert result.var_99 > 0
        assert result.cvar_95 > 0
        assert result.cvar_99 > 0

        # CVaR should be >= VaR (tail is worse than cutoff)
        assert result.cvar_95 >= result.var_95
        assert result.cvar_99 >= result.var_99

        # 99% VaR should be >= 95% VaR (more extreme tail)
        assert result.var_99 >= result.var_95

        # Check distributions
        assert len(result.max_drawdown_dist) == 100
        assert len(result.sharpe_distribution) == 100

    def test_simulate_portfolio_bootstrap(
        self,
        sample_returns: pd.DataFrame,
        sample_weights: pd.Series,
    ) -> None:
        """Test portfolio simulation with historical bootstrap method."""
        config = SimulationConfig(n_paths=100, n_steps=50, method="historical_bootstrap")
        engine = MonteCarloEngine(config)

        result = engine.simulate_portfolio(sample_returns, sample_weights, initial_value=100000)

        # Check result structure
        assert len(result.pnl_distribution) == 100
        assert result.paths.shape == (100, 50, 3)

        # Check risk metrics
        assert result.var_95 > 0
        assert result.cvar_95 >= result.var_95

    def test_simulate_portfolio_invalid_method(
        self,
        sample_returns: pd.DataFrame,
        sample_weights: pd.Series,
    ) -> None:
        """Test that invalid method raises ValueError."""
        config = SimulationConfig(method="invalid_method")
        engine = MonteCarloEngine(config)

        with pytest.raises(ValueError, match="Invalid method"):
            engine.simulate_portfolio(sample_returns, sample_weights)

    def test_simulate_portfolio_empty_returns(
        self,
        sample_weights: pd.Series,
    ) -> None:
        """Test that empty returns raises ValueError."""
        engine = MonteCarloEngine()
        empty_returns = pd.DataFrame()

        with pytest.raises(ValueError, match="empty"):
            engine.simulate_portfolio(empty_returns, sample_weights)

    def test_simulate_portfolio_missing_weights(
        self,
        sample_returns: pd.DataFrame,
    ) -> None:
        """Test that missing weights raises ValueError."""
        engine = MonteCarloEngine()
        incomplete_weights = pd.Series({"BTC": 0.5, "ETH": 0.5})  # Missing SPY

        with pytest.raises(ValueError, match="must have weights"):
            engine.simulate_portfolio(sample_returns, incomplete_weights)

    def test_gbm_paths_shape(
        self,
        engine: MonteCarloEngine,
    ) -> None:
        """Test GBM path generation shape."""
        mu = np.array([0.1, 0.08, 0.06])
        cov = np.eye(3) * 0.04  # Diagonal covariance

        paths = engine._generate_gbm_paths(mu, cov, n_assets=3)

        assert paths.shape == (100, 50, 3)  # n_paths × n_steps × n_assets
        assert np.all(paths[:, 0, :] == 1.0)  # All paths start at 1.0

    def test_gbm_paths_mean_return(self) -> None:
        """Test that GBM paths have approximately correct mean return."""
        # Use large sample for statistical test
        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)

        mu = np.array([0.10])  # 10% expected return
        cov = np.array([[0.04]])  # 20% volatility (0.2^2 = 0.04)

        paths = engine._generate_gbm_paths(mu, cov, n_assets=1)

        # Calculate empirical mean return
        final_returns = paths[:, -1, 0] - 1.0  # paths start at 1.0
        mean_return = np.mean(final_returns)

        # Should be close to 10% (within 2% with large sample)
        assert mean_return == pytest.approx(0.10, abs=0.02)

    def test_gbm_paths_volatility(self) -> None:
        """Test that GBM paths have approximately correct volatility."""
        # Use large sample for statistical test
        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)

        mu = np.array([0.10])
        cov = np.array([[0.04]])  # 20% volatility

        paths = engine._generate_gbm_paths(mu, cov, n_assets=1)

        # Calculate empirical volatility
        returns = np.diff(paths[:, :, 0], axis=1) / paths[:, :-1, 0]
        empirical_vol = np.std(returns) * np.sqrt(252)

        # Should be close to 20% (within 2%)
        assert empirical_vol == pytest.approx(0.20, abs=0.02)

    def test_cholesky_correlation_preserved(self) -> None:
        """Test that Cholesky decomposition preserves correlation structure."""
        config = SimulationConfig(n_paths=5000, n_steps=252)
        engine = MonteCarloEngine(config)

        # Create correlated assets (BTC and ETH with 0.7 correlation)
        mu = np.array([0.10, 0.08])
        cov = np.array([[0.04, 0.028], [0.028, 0.0625]])  # corr = 0.7

        paths = engine._generate_gbm_paths(mu, cov, n_assets=2)

        # Calculate empirical correlation from step-to-step returns
        # (more stable than final returns which have compounding effects)
        returns_btc = np.diff(paths[:, :, 0], axis=1) / paths[:, :-1, 0]
        returns_eth = np.diff(paths[:, :, 1], axis=1) / paths[:, :-1, 1]

        # Flatten to get all returns
        all_returns_btc = returns_btc.flatten()
        all_returns_eth = returns_eth.flatten()

        empirical_corr = np.corrcoef(all_returns_btc, all_returns_eth)[0, 1]

        # Should preserve correlation structure (within 0.15 due to Monte Carlo variance)
        assert empirical_corr == pytest.approx(0.7, abs=0.15)

    def test_bootstrap_paths_shape(
        self,
        engine: MonteCarloEngine,
        sample_returns: pd.DataFrame,
    ) -> None:
        """Test bootstrap path generation shape."""
        paths = engine._generate_bootstrap_paths(sample_returns)

        assert paths.shape == (100, 50, 3)  # n_paths × n_steps × n_assets
        assert np.all(paths[:, 0, :] == 1.0)  # All paths start at 1.0

    def test_bootstrap_paths_use_historical_data(
        self,
        sample_returns: pd.DataFrame,
    ) -> None:
        """Test that bootstrap paths sample from historical distribution."""
        config = SimulationConfig(n_paths=1000, n_steps=100, method="historical_bootstrap")
        engine = MonteCarloEngine(config)

        paths = engine._generate_bootstrap_paths(sample_returns)

        # Calculate empirical mean and std from paths
        final_returns = paths[:, -1, 0] - 1.0  # BTC returns
        empirical_mean = np.mean(final_returns)

        # Historical mean (annualized from daily)
        historical_mean = sample_returns["BTC"].mean() * 100  # ~100 steps

        # Bootstrap should approximate historical distribution
        # (within 50% tolerance due to randomness)
        assert empirical_mean == pytest.approx(historical_mean, rel=0.5)

    def test_calculate_portfolio_paths(
        self,
        engine: MonteCarloEngine,
    ) -> None:
        """Test portfolio path calculation from asset paths."""
        # Create simple asset paths (2 assets, 3 time steps, 2 paths)
        asset_paths = np.array(
            [
                [[1.0, 1.0], [1.1, 1.05], [1.2, 1.1]],  # Path 1
                [[1.0, 1.0], [0.9, 0.95], [0.8, 0.9]],  # Path 2
            ]
        )

        weights = np.array([0.6, 0.4])
        initial_value = 100000

        portfolio_paths = engine._calculate_portfolio_paths(asset_paths, weights, initial_value)

        # Check shape
        assert portfolio_paths.shape == (2, 3)  # 2 paths, 3 time steps

        # Check initial value
        assert portfolio_paths[0, 0] == pytest.approx(100000)
        assert portfolio_paths[1, 0] == pytest.approx(100000)

        # Check path 1 calculation
        # Step 1: 0.6*1.1 + 0.4*1.05 = 1.08, scaled by 100000 = 108000
        assert portfolio_paths[0, 1] == pytest.approx(108000)

        # Check path 2 calculation
        # Step 1: 0.6*0.9 + 0.4*0.95 = 0.92, scaled by 100000 = 92000
        assert portfolio_paths[1, 1] == pytest.approx(92000)

    def test_calculate_max_drawdown_distribution(
        self,
        engine: MonteCarloEngine,
    ) -> None:
        """Test max drawdown calculation."""
        # Create portfolio paths with known drawdowns
        portfolio_paths = np.array(
            [
                [100, 110, 105, 115, 90],  # Max DD: (90-115)/115 = -21.7%
                [100, 95, 100, 105, 100],  # Max DD: (95-100)/100 = -5%
            ]
        )

        max_dd = engine._calculate_max_drawdown_distribution(portfolio_paths)

        assert len(max_dd) == 2
        assert max_dd[0] == pytest.approx(-21.7 / 100, abs=0.01)
        assert max_dd[1] == pytest.approx(-5.0 / 100, abs=0.01)

    def test_calculate_sharpe_distribution(
        self,
        engine: MonteCarloEngine,
    ) -> None:
        """Test Sharpe ratio calculation."""
        # Create portfolio paths (2 paths, 5 steps)
        portfolio_paths = np.array(
            [
                [100, 102, 104, 106, 108],  # Steady growth
                [100, 100, 100, 100, 100],  # Flat
            ]
        )

        sharpe = engine._calculate_sharpe_distribution(portfolio_paths, 100)

        assert len(sharpe) == 2
        assert sharpe[0] > 0  # Positive returns should have positive Sharpe
        assert sharpe[1] == 0  # Flat returns should have 0 Sharpe

    def test_calculate_var_basic(self, engine: MonteCarloEngine) -> None:
        """Test VaR calculation with simple distribution."""
        # Create symmetric distribution around 0
        pnl = np.array([-100, -50, 0, 50, 100])

        var_95 = engine.calculate_var(pnl, confidence=0.95)

        # 95% VaR = -percentile(pnl, 5%)
        # For this distribution, 5th percentile is between -100 and -50
        # np.percentile interpolates: 5th percentile = -90
        # So VaR = -(-90) = 90
        assert var_95 == pytest.approx(90, abs=1)

    def test_calculate_var_normal_distribution(self) -> None:
        """Test VaR with normal distribution (should be ~1.645σ for 95%)."""
        engine = MonteCarloEngine()

        np.random.seed(42)
        pnl = np.random.normal(0, 1000, size=10000)  # Mean=0, Std=1000

        var_95 = engine.calculate_var(pnl, confidence=0.95)

        # For normal distribution, 95% VaR = 1.645 * σ
        expected_var = 1.645 * 1000

        assert var_95 == pytest.approx(expected_var, rel=0.1)

    def test_calculate_var_invalid_confidence(self, engine: MonteCarloEngine) -> None:
        """Test that invalid confidence raises ValueError."""
        pnl = np.array([1, 2, 3])

        with pytest.raises(ValueError, match="Confidence must be in"):
            engine.calculate_var(pnl, confidence=0.0)

        with pytest.raises(ValueError, match="Confidence must be in"):
            engine.calculate_var(pnl, confidence=1.0)

        with pytest.raises(ValueError, match="Confidence must be in"):
            engine.calculate_var(pnl, confidence=1.5)

    def test_calculate_cvar_basic(self, engine: MonteCarloEngine) -> None:
        """Test CVaR calculation with simple distribution."""
        # Create distribution with known tail
        pnl = np.array([-200, -150, -100, -50, 0, 50, 100, 150, 200])

        cvar_95 = engine.calculate_cvar(pnl, confidence=0.95)

        # CVaR should be average of worst 5% (roughly -200 in this case)
        assert cvar_95 >= 150  # At least as bad as VaR

    def test_calculate_cvar_greater_than_var(self) -> None:
        """Test that CVaR >= VaR (Expected Shortfall is worse than cutoff)."""
        engine = MonteCarloEngine()

        np.random.seed(42)
        pnl = np.random.normal(0, 1000, size=10000)

        var_95 = engine.calculate_var(pnl, confidence=0.95)
        cvar_95 = engine.calculate_cvar(pnl, confidence=0.95)

        assert cvar_95 >= var_95

    def test_calculate_cvar_invalid_confidence(self, engine: MonteCarloEngine) -> None:
        """Test that invalid confidence raises ValueError."""
        pnl = np.array([1, 2, 3])

        with pytest.raises(ValueError, match="Confidence must be in"):
            engine.calculate_cvar(pnl, confidence=-0.1)

        with pytest.raises(ValueError, match="Confidence must be in"):
            engine.calculate_cvar(pnl, confidence=1.5)

    def test_stress_test_basic(self, engine: MonteCarloEngine) -> None:
        """Test stress test with simple scenario."""
        portfolio_value = 100000
        weights = pd.Series({"BTC": 0.5, "ETH": 0.3, "SPY": 0.2})

        scenarios = {
            "crash": {"BTC": -0.20, "ETH": -0.25, "SPY": -0.10},
        }

        results = engine.stress_test(portfolio_value, weights, scenarios)

        assert len(results) == 1
        assert results.loc[0, "scenario"] == "crash"

        # Calculate expected P&L
        expected_pnl = 100000 * 0.5 * (-0.20) + 100000 * 0.3 * (-0.25) + 100000 * 0.2 * (-0.10)

        assert results.loc[0, "pnl"] == pytest.approx(expected_pnl)
        assert results.loc[0, "pnl_pct"] == pytest.approx((expected_pnl / 100000) * 100)

    def test_stress_test_multiple_scenarios(self, engine: MonteCarloEngine) -> None:
        """Test stress test with multiple scenarios."""
        portfolio_value = 100000
        weights = pd.Series({"BTC": 0.6, "ETH": 0.4})

        scenarios = {
            "bull": {"BTC": 0.50, "ETH": 0.60},
            "bear": {"BTC": -0.40, "ETH": -0.50},
            "mixed": {"BTC": 0.20, "ETH": -0.10},
        }

        results = engine.stress_test(portfolio_value, weights, scenarios)

        assert len(results) == 3
        assert set(results["scenario"]) == {"bull", "bear", "mixed"}

    def test_stress_test_missing_asset(self, engine: MonteCarloEngine) -> None:
        """Test stress test with asset not in portfolio (should ignore)."""
        portfolio_value = 100000
        weights = pd.Series({"BTC": 1.0})

        scenarios = {
            "test": {"BTC": -0.20, "ETH": -0.30},  # ETH not in portfolio
        }

        results = engine.stress_test(portfolio_value, weights, scenarios)

        # Should only apply BTC shock
        expected_pnl = 100000 * 1.0 * (-0.20)
        assert results.loc[0, "pnl"] == pytest.approx(expected_pnl)

    def test_zero_volatility(self) -> None:
        """Test edge case with zero volatility."""
        config = SimulationConfig(n_paths=100, n_steps=10)
        engine = MonteCarloEngine(config)

        # Zero volatility, positive drift
        mu = np.array([0.10])
        cov = np.array([[0.0]])  # Zero variance

        paths = engine._generate_gbm_paths(mu, cov, n_assets=1)

        # All paths should be identical (deterministic drift only)
        assert np.allclose(paths[0, :, :], paths[1, :, :])

    def test_single_asset_portfolio(
        self,
        engine: MonteCarloEngine,
    ) -> None:
        """Test simulation with single asset."""
        returns = pd.DataFrame({"BTC": np.random.normal(0.001, 0.02, 252)})
        weights = pd.Series({"BTC": 1.0})

        result = engine.simulate_portfolio(returns, weights, initial_value=100000)

        assert result.paths.shape == (100, 50, 1)
        assert result.var_95 > 0

    def test_perfect_correlation(self) -> None:
        """Test edge case with perfectly correlated assets."""
        config = SimulationConfig(n_paths=1000, n_steps=50)
        engine = MonteCarloEngine(config)

        # Perfect correlation (note: must be positive semi-definite)
        # Use a valid correlation matrix structure
        mu = np.array([0.10, 0.10])
        vol1, vol2 = 0.20, 0.25  # Different volatilities
        corr = 0.95  # Very high correlation (not exactly 1.0 for numerical stability)
        cov = np.array([[vol1**2, corr * vol1 * vol2], [corr * vol1 * vol2, vol2**2]])

        paths = engine._generate_gbm_paths(mu, cov, n_assets=2)

        # Calculate correlation from step-to-step returns
        returns_1 = np.diff(paths[:, :, 0], axis=1) / paths[:, :-1, 0]
        returns_2 = np.diff(paths[:, :, 1], axis=1) / paths[:, :-1, 1]

        # Flatten to get all returns
        all_returns_1 = returns_1.flatten()
        all_returns_2 = returns_2.flatten()

        correlation = np.corrcoef(all_returns_1, all_returns_2)[0, 1]

        # Should have very high correlation (relaxed to 0.85 to account for MC variance)
        assert correlation > 0.85


class TestScenarioEngine:
    """Test ScenarioEngine class."""

    @pytest.fixture
    def engine(self) -> ScenarioEngine:
        """Create ScenarioEngine."""
        return ScenarioEngine()

    @pytest.fixture
    def sample_weights(self) -> pd.Series:
        """Create sample portfolio weights."""
        return pd.Series({"BTC": 0.4, "ETH": 0.3, "SPY": 0.3})

    def test_list_scenarios(self, engine: ScenarioEngine) -> None:
        """Test listing all available scenarios."""
        scenarios = engine.list_scenarios()

        assert isinstance(scenarios, list)
        assert len(scenarios) > 0
        assert "2008_financial_crisis" in scenarios
        assert "2020_covid_crash" in scenarios

    def test_get_scenario_details(self, engine: ScenarioEngine) -> None:
        """Test getting details of a specific scenario."""
        details = engine.get_scenario_details("2008_financial_crisis")

        assert "description" in details
        assert "shocks" in details
        assert isinstance(details["shocks"], dict)

    def test_get_scenario_details_not_found(self, engine: ScenarioEngine) -> None:
        """Test that unknown scenario raises ValueError."""
        with pytest.raises(ValueError, match="not found"):
            engine.get_scenario_details("unknown_scenario")

    def test_run_scenario_basic(
        self,
        engine: ScenarioEngine,
        sample_weights: pd.Series,
    ) -> None:
        """Test running a single scenario."""
        result = engine.run_scenario(100000, sample_weights, "2020_covid_crash")

        assert result["scenario"] == "2020_covid_crash"
        assert "description" in result
        assert "pnl" in result
        assert "pnl_pct" in result
        assert result["pnl"] < 0  # COVID crash should be negative

    def test_run_scenario_not_found(
        self,
        engine: ScenarioEngine,
        sample_weights: pd.Series,
    ) -> None:
        """Test that unknown scenario raises ValueError."""
        with pytest.raises(ValueError, match="not found"):
            engine.run_scenario(100000, sample_weights, "unknown_scenario")

    def test_run_all_scenarios(
        self,
        engine: ScenarioEngine,
        sample_weights: pd.Series,
    ) -> None:
        """Test running all scenarios."""
        results = engine.run_all_scenarios(100000, sample_weights)

        assert isinstance(results, pd.DataFrame)
        assert len(results) > 0
        assert "scenario" in results.columns
        assert "pnl" in results.columns
        assert "pnl_pct" in results.columns

        # Should be sorted by pnl (worst to best)
        assert results["pnl"].is_monotonic_increasing

    def test_add_custom_scenario(self, engine: ScenarioEngine) -> None:
        """Test adding a custom scenario."""
        initial_count = len(engine.list_scenarios())

        engine.add_custom_scenario(
            scenario_name="my_custom_crash",
            description="Custom hypothetical crash",
            shocks={"BTC": -0.30, "ETH": -0.40},
        )

        assert len(engine.list_scenarios()) == initial_count + 1
        assert "my_custom_crash" in engine.list_scenarios()

        details = engine.get_scenario_details("my_custom_crash")
        assert details["description"] == "Custom hypothetical crash"

    def test_add_custom_scenario_with_period(self, engine: ScenarioEngine) -> None:
        """Test adding a custom scenario with period."""
        engine.add_custom_scenario(
            scenario_name="my_crash_with_period",
            description="Test",
            shocks={"BTC": -0.20},
            period=("2024-01-01", "2024-01-31"),
        )

        details = engine.get_scenario_details("my_crash_with_period")
        assert "period" in details
        assert details["period"] == ("2024-01-01", "2024-01-31")

    def test_add_custom_scenario_duplicate(self, engine: ScenarioEngine) -> None:
        """Test that adding duplicate scenario raises ValueError."""
        with pytest.raises(ValueError, match="already exists"):
            engine.add_custom_scenario(
                scenario_name="2008_financial_crisis",
                description="Duplicate",
                shocks={},
            )

    def test_scenario_with_missing_asset(
        self,
        engine: ScenarioEngine,
    ) -> None:
        """Test scenario where portfolio doesn't have all shocked assets."""
        weights = pd.Series({"BTC": 1.0})  # Only BTC, no SPY

        result = engine.run_scenario(100000, weights, "2008_financial_crisis")

        # Should only apply shocks for assets in portfolio
        # 2008 scenario has SPY shock, but portfolio has only BTC
        # BTC is not in the scenario, so P&L should be 0
        assert result["pnl"] == pytest.approx(0.0)

    def test_scenario_calculation_accuracy(
        self,
        engine: ScenarioEngine,
    ) -> None:
        """Test scenario P&L calculation accuracy."""
        portfolio_value = 100000
        weights = pd.Series({"BTC": 0.5, "ETH": 0.5})

        # Run btc_flash_crash scenario: BTC -20%, ETH -25%
        result = engine.run_scenario(portfolio_value, weights, "btc_flash_crash")

        # Expected P&L: 100000 * (0.5 * -0.20 + 0.5 * -0.25) = -22500
        expected_pnl = 100000 * (0.5 * (-0.20) + 0.5 * (-0.25))

        assert result["pnl"] == pytest.approx(expected_pnl)
        assert result["pnl_pct"] == pytest.approx(-22.5)

    def test_all_historical_scenarios_have_required_fields(
        self,
        engine: ScenarioEngine,
    ) -> None:
        """Test that all historical scenarios have required fields."""
        for scenario_name in engine.list_scenarios():
            details = engine.get_scenario_details(scenario_name)

            assert "description" in details
            assert "shocks" in details
            assert isinstance(details["description"], str)
            assert isinstance(details["shocks"], dict)
