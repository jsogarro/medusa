"""Monte Carlo simulation engine for portfolio risk analysis.

Generates thousands of correlated price paths using Geometric Brownian Motion
or historical bootstrap, then calculates VaR, CVaR, and other risk metrics.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import numpy as np
import pandas as pd
from loguru import logger

if TYPE_CHECKING:
    from numpy.typing import NDArray

try:
    from sklearn.covariance import LedoitWolf

    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    logger.warning("sklearn not installed - Ledoit-Wolf covariance unavailable")


@dataclass
class SimulationConfig:
    """Configuration for Monte Carlo simulation."""

    n_paths: int = 10000  # Number of simulation paths
    n_steps: int = 252  # Steps per path (1 year daily)
    dt: float = 1 / 252  # Time step (1 trading day)
    method: str = "gbm"  # "gbm" or "historical_bootstrap"
    confidence_levels: list[float] = field(default_factory=lambda: [0.95, 0.99])


@dataclass
class SimulationResult:
    """Results from Monte Carlo simulation."""

    pnl_distribution: NDArray[np.float64]  # Final P&L for each path
    paths: NDArray[np.float64]  # Full price paths (n_paths × n_steps × n_assets)
    var_95: float  # 95% Value at Risk
    var_99: float  # 99% Value at Risk
    cvar_95: float  # 95% Conditional VaR (Expected Shortfall)
    cvar_99: float  # 99% CVaR
    expected_pnl: float  # Mean P&L
    std_pnl: float  # Std dev of P&L
    prob_profit: float  # Probability of profit
    max_drawdown_dist: NDArray[np.float64]  # Max drawdown per path
    sharpe_distribution: NDArray[np.float64]  # Sharpe ratio per path


class MonteCarloEngine:
    """Multi-asset Monte Carlo simulation with correlated returns."""

    def __init__(self, config: SimulationConfig | None = None) -> None:
        """Initialize Monte Carlo engine.

        Args:
            config: Simulation configuration. Defaults to SimulationConfig().

        """
        self.config = config or SimulationConfig()

    def simulate_portfolio(
        self,
        returns: pd.DataFrame,  # Historical returns (dates × assets)
        weights: pd.Series,  # Portfolio weights
        initial_value: float = 100000,  # Starting portfolio value
    ) -> SimulationResult:
        """Run Monte Carlo simulation on a portfolio.

        Algorithm:
        1. Estimate covariance matrix from historical returns (Ledoit-Wolf)
        2. Cholesky decomposition for correlated draws
        3. Generate n_paths of correlated returns
        4. Calculate portfolio value paths
        5. Compute VaR, CVaR, and other metrics

        Args:
            returns: Historical returns DataFrame (rows=dates, columns=assets).
            weights: Portfolio weights Series (index=assets, sum should be 1.0).
            initial_value: Starting portfolio value in dollars.

        Returns:
            SimulationResult with P&L distribution and risk metrics.

        Raises:
            ValueError: If returns is empty, weights don't match returns columns,
                or method is invalid.

        """
        if returns.empty:
            raise ValueError("Returns DataFrame is empty")

        # Align weights with returns columns
        assets = returns.columns
        if not all(asset in weights.index for asset in assets):
            raise ValueError("All assets in returns must have weights")

        weights = weights.loc[assets]

        # Estimate expected returns (annualized mean)
        mu = returns.mean().values * 252  # Annualized

        # Estimate covariance matrix (annualized)
        if SKLEARN_AVAILABLE:
            lw = LedoitWolf()
            cov = lw.fit(returns.values).covariance_ * 252
            logger.info(f"Ledoit-Wolf covariance: shrinkage={lw.shrinkage_:.4f}")
        else:
            cov = returns.cov().values * 252
            logger.warning("Using sample covariance (sklearn not available)")

        n_assets = len(assets)

        # Generate paths based on method
        if self.config.method == "gbm":
            paths = self._generate_gbm_paths(mu, cov, n_assets)
        elif self.config.method == "historical_bootstrap":
            paths = self._generate_bootstrap_paths(returns)
        else:
            raise ValueError(
                f"Invalid method '{self.config.method}'. Use 'gbm' or 'historical_bootstrap'."
            )

        # Calculate portfolio value paths
        portfolio_paths = self._calculate_portfolio_paths(paths, weights.values, initial_value)

        # Calculate P&L distribution (final value - initial value)
        pnl_distribution = portfolio_paths[:, -1] - initial_value

        # Calculate risk metrics
        var_95 = self.calculate_var(pnl_distribution, 0.95)
        var_99 = self.calculate_var(pnl_distribution, 0.99)
        cvar_95 = self.calculate_cvar(pnl_distribution, 0.95)
        cvar_99 = self.calculate_cvar(pnl_distribution, 0.99)

        expected_pnl = float(np.mean(pnl_distribution))
        std_pnl = float(np.std(pnl_distribution))
        prob_profit = float(np.mean(pnl_distribution > 0))

        # Calculate max drawdown per path
        max_drawdown_dist = self._calculate_max_drawdown_distribution(portfolio_paths)

        # Calculate Sharpe ratio per path (assuming 0 risk-free rate)
        sharpe_dist = self._calculate_sharpe_distribution(portfolio_paths, initial_value)

        logger.info(
            f"Monte Carlo simulation complete: {self.config.n_paths} paths, "
            f"{self.config.n_steps} steps, method={self.config.method}"
        )
        logger.info(
            f"Expected P&L: ${expected_pnl:,.2f}, Std: ${std_pnl:,.2f}, "
            f"Prob(profit): {prob_profit:.1%}"
        )
        logger.info(
            f"VaR(95%): ${var_95:,.2f}, VaR(99%): ${var_99:,.2f}, "
            f"CVaR(95%): ${cvar_95:,.2f}, CVaR(99%): ${cvar_99:,.2f}"
        )

        return SimulationResult(
            pnl_distribution=pnl_distribution,
            paths=paths,
            var_95=var_95,
            var_99=var_99,
            cvar_95=cvar_95,
            cvar_99=cvar_99,
            expected_pnl=expected_pnl,
            std_pnl=std_pnl,
            prob_profit=prob_profit,
            max_drawdown_dist=max_drawdown_dist,
            sharpe_distribution=sharpe_dist,
        )

    def _generate_gbm_paths(
        self,
        mu: NDArray[np.float64],  # Expected returns per asset
        cov: NDArray[np.float64],  # Covariance matrix
        n_assets: int,
    ) -> NDArray[np.float64]:
        """Generate Geometric Brownian Motion paths.

        For each path i, step t:
        dS/S = μ dt + σ dW
        S_{t+1} = S_t * exp((μ - σ²/2)dt + σ√dt * Z)

        where Z ~ N(0, Σ) (correlated via Cholesky)

        Args:
            mu: Expected returns per asset (n_assets,).
            cov: Covariance matrix (n_assets × n_assets).
            n_assets: Number of assets.

        Returns:
            Price paths (n_paths × n_steps × n_assets).

        """
        # Cholesky decomposition for correlated random draws
        try:
            L = np.linalg.cholesky(cov)  # noqa: N806 (mathematical notation)
        except np.linalg.LinAlgError:
            logger.warning("Covariance matrix not positive definite, using diagonal")
            L = np.diag(np.sqrt(np.diag(cov)))  # noqa: N806

        # Initialize paths (start at 1.0 for relative returns)
        paths = np.ones((self.config.n_paths, self.config.n_steps, n_assets))

        # Drift term: (μ - σ²/2) * dt
        volatilities = np.sqrt(np.diag(cov))
        drift = (mu - 0.5 * volatilities**2) * self.config.dt

        # Generate all random draws at once for efficiency
        # Shape: (n_paths, n_steps-1, n_assets)
        Z = np.random.standard_normal(  # noqa: N806 (standard notation for random variable)
            (self.config.n_paths, self.config.n_steps - 1, n_assets)
        )

        # Apply Cholesky correlation - vectorized across all paths and steps
        # Reshape to (n_paths * (n_steps-1), n_assets) for batch matmul
        z_flat = Z.reshape(-1, n_assets)
        correlated_z_flat = z_flat @ L.T  # Batch multiply with Cholesky matrix
        correlated_z = correlated_z_flat.reshape(
            self.config.n_paths, self.config.n_steps - 1, n_assets
        )

        # GBM evolution - fully vectorized using cumulative sum of log returns
        # S_{t+1} = S_t * exp(drift + vol * sqrt(dt) * Z)
        # log(S_{t+1}/S_0) = sum_{i=0}^{t} (drift + vol * sqrt(dt) * Z_i)
        log_returns = drift[None, None, :] + np.sqrt(self.config.dt) * correlated_z

        # Cumulative sum of log returns, then exponentiate
        cumulative_log_returns = np.cumsum(log_returns, axis=1)
        paths[:, 1:, :] = np.exp(cumulative_log_returns)  # S_0 = 1.0, so just exp(log(S_t/S_0))

        logger.debug(
            f"Generated GBM paths: {self.config.n_paths} paths, "
            f"{self.config.n_steps} steps, {n_assets} assets"
        )

        return paths

    def _generate_bootstrap_paths(
        self,
        returns: pd.DataFrame,
    ) -> NDArray[np.float64]:
        """Generate paths by randomly sampling historical returns with replacement.

        Args:
            returns: Historical returns DataFrame (rows=dates, columns=assets).

        Returns:
            Price paths (n_paths × n_steps × n_assets).

        """
        n_assets = len(returns.columns)
        n_historical = len(returns)

        # Initialize paths (start at 1.0 for relative returns)
        paths = np.ones((self.config.n_paths, self.config.n_steps, n_assets))

        # Convert returns to numpy for efficiency
        returns_array = returns.values

        for i in range(self.config.n_paths):
            # Randomly sample historical returns with replacement
            sampled_indices = np.random.randint(0, n_historical, self.config.n_steps - 1)
            sampled_returns = returns_array[sampled_indices, :]

            # Accumulate returns to get price paths
            for t in range(self.config.n_steps - 1):
                paths[i, t + 1, :] = paths[i, t, :] * (1 + sampled_returns[t, :])

        logger.debug(
            f"Generated bootstrap paths: {self.config.n_paths} paths, "
            f"{self.config.n_steps} steps, {n_assets} assets"
        )

        return paths

    def _calculate_portfolio_paths(
        self,
        asset_paths: NDArray[np.float64],  # (n_paths × n_steps × n_assets)
        weights: NDArray[np.float64],  # (n_assets,)
        initial_value: float,
    ) -> NDArray[np.float64]:
        """Calculate portfolio value paths from asset paths and weights.

        Args:
            asset_paths: Asset price paths (relative to starting price 1.0).
            weights: Portfolio weights (sum should be 1.0).
            initial_value: Initial portfolio value.

        Returns:
            Portfolio value paths (n_paths × n_steps).

        """
        # Portfolio value at each step is weighted sum of asset values
        # asset_paths[i, t, j] is the relative price of asset j at time t in path i
        portfolio_paths = np.sum(asset_paths * weights[None, None, :], axis=2)

        # Scale by initial value
        portfolio_paths = portfolio_paths * initial_value

        return portfolio_paths

    def _calculate_max_drawdown_distribution(
        self,
        portfolio_paths: NDArray[np.float64],  # (n_paths × n_steps)
    ) -> NDArray[np.float64]:
        """Calculate maximum drawdown for each path.

        Args:
            portfolio_paths: Portfolio value paths (n_paths × n_steps).

        Returns:
            Max drawdown per path (n_paths,). Negative values (e.g., -0.15 = 15% DD).

        """
        n_paths = portfolio_paths.shape[0]
        max_drawdowns = np.zeros(n_paths)

        for i in range(n_paths):
            path = portfolio_paths[i, :]
            running_max = np.maximum.accumulate(path)
            drawdowns = (path - running_max) / running_max
            max_drawdowns[i] = np.min(drawdowns)

        return max_drawdowns

    def _calculate_sharpe_distribution(
        self,
        portfolio_paths: NDArray[np.float64],  # (n_paths × n_steps)
        initial_value: float,
    ) -> NDArray[np.float64]:
        """Calculate Sharpe ratio for each path.

        Args:
            portfolio_paths: Portfolio value paths (n_paths × n_steps).
            initial_value: Initial portfolio value.

        Returns:
            Sharpe ratio per path (n_paths,). Assuming risk-free rate = 0.

        """
        # Calculate returns for each path
        returns = np.diff(portfolio_paths, axis=1) / portfolio_paths[:, :-1]

        # Sharpe = mean(returns) / std(returns) * sqrt(252) for annualization
        mean_returns = np.mean(returns, axis=1)
        std_returns = np.std(returns, axis=1)

        # Avoid division by zero with np.errstate
        with np.errstate(divide="ignore", invalid="ignore"):
            sharpe = np.where(std_returns > 0, mean_returns / std_returns * np.sqrt(252), 0.0)

        return sharpe

    def calculate_var(
        self,
        pnl: NDArray[np.float64],
        confidence: float = 0.95,
    ) -> float:
        """Value at Risk: worst loss at given confidence level.

        VaR_α = -percentile(PnL, 1-α)

        Args:
            pnl: P&L distribution (n_paths,).
            confidence: Confidence level (e.g., 0.95 for 95% VaR).

        Returns:
            VaR in dollars (positive number representing maximum loss).

        Raises:
            ValueError: If confidence not in (0, 1).

        """
        if not 0 < confidence < 1:
            raise ValueError(f"Confidence must be in (0, 1), got {confidence}")

        var = -float(np.percentile(pnl, (1 - confidence) * 100))

        logger.debug(f"VaR({confidence:.0%}) = ${var:,.2f}")

        return var

    def calculate_cvar(
        self,
        pnl: NDArray[np.float64],
        confidence: float = 0.95,
    ) -> float:
        """Conditional VaR (Expected Shortfall): average loss beyond VaR.

        CVaR_α = -E[PnL | PnL ≤ -VaR_α]

        Args:
            pnl: P&L distribution (n_paths,).
            confidence: Confidence level (e.g., 0.95 for 95% CVaR).

        Returns:
            CVaR in dollars (positive number representing expected tail loss).

        Raises:
            ValueError: If confidence not in (0, 1).

        """
        if not 0 < confidence < 1:
            raise ValueError(f"Confidence must be in (0, 1), got {confidence}")

        var = self.calculate_var(pnl, confidence)
        tail_losses = pnl[pnl <= -var]

        if len(tail_losses) == 0:
            cvar = var
        else:
            cvar = -float(np.mean(tail_losses))

        logger.debug(f"CVaR({confidence:.0%}) = ${cvar:,.2f}")

        return cvar

    def stress_test(
        self,
        portfolio_value: float,
        weights: pd.Series,
        scenarios: dict[str, dict[str, float]],
    ) -> pd.DataFrame:
        """Run historical stress test scenarios.

        Args:
            portfolio_value: Current portfolio value in dollars.
            weights: Portfolio weights Series (index=assets).
            scenarios: Dict of scenario_name -> {asset: shock_return}.

        Returns:
            DataFrame with scenario results (columns: scenario, pnl, pnl_pct).

        Example:
            scenarios = {
                "2008_crisis": {"BTC": -0.40, "ETH": -0.55, "SPY": -0.38},
                "2020_covid": {"BTC": -0.50, "ETH": -0.60, "SPY": -0.34},
                "rate_hike": {"BTC": -0.20, "bonds_10y": -0.08},
            }

        """
        results = []

        for scenario_name, shocks in scenarios.items():
            # Calculate P&L for this scenario
            pnl = 0.0

            for asset, shock in shocks.items():
                if asset in weights.index:
                    asset_value = portfolio_value * weights[asset]
                    asset_pnl = asset_value * shock
                    pnl += asset_pnl

            pnl_pct = (pnl / portfolio_value) * 100 if portfolio_value > 0 else 0.0

            results.append({"scenario": scenario_name, "pnl": pnl, "pnl_pct": pnl_pct})

            logger.info(f"Stress test '{scenario_name}': P&L=${pnl:,.2f} ({pnl_pct:+.2f}%)")

        return pd.DataFrame(results)
