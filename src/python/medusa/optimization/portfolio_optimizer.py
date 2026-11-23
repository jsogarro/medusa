"""Portfolio optimization: mean-variance, risk parity, Black-Litterman, CVaR minimization."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import numpy as np
import pandas as pd
from loguru import logger
from scipy.optimize import minimize

if TYPE_CHECKING:
    from numpy.typing import NDArray


@dataclass
class OptimizationResult:
    """Result of a portfolio optimization.

    Attributes:
        weights: Optimal portfolio weights (asset → weight).
        expected_return: Annualized expected portfolio return.
        expected_risk: Annualized expected portfolio volatility.
        sharpe_ratio: Risk-adjusted return (excess return / volatility).
        method: Optimization method used.
        constraints_satisfied: Whether all constraints were satisfied.
        efficient_frontier: Efficient frontier points (optional).

    """

    weights: pd.Series
    expected_return: float
    expected_risk: float
    sharpe_ratio: float
    method: str
    constraints_satisfied: bool
    efficient_frontier: pd.DataFrame | None = None


class MeanVarianceOptimizer:
    """Markowitz mean-variance portfolio optimization.

    Maximize: w^T μ - (λ/2) w^T Σ w
    Subject to: Σ w_i = 1, w_i >= 0 (long-only) or unconstrained

    Uses scipy.optimize.minimize with SLSQP method.
    """

    def optimize(
        self,
        expected_returns: pd.Series,
        cov_matrix: pd.DataFrame,
        risk_aversion: float = 1.0,
        constraints: dict[str, float | bool] | None = None,
    ) -> OptimizationResult:
        """Find optimal portfolio weights.

        Args:
            expected_returns: Expected returns per asset.
            cov_matrix: Asset covariance matrix.
            risk_aversion: Risk aversion parameter (λ).
                Higher values → more risk-averse → lower risk portfolios.
            constraints: Portfolio constraints:
                - long_only: bool (default True) — w_i >= 0
                - max_weight: float — No single asset > max_weight
                - min_weight: float — Minimum position size
                - target_return: float — Target expected return
                - max_volatility: float — Maximum portfolio volatility
                - sector_limits: dict[str, float] — Max weight per sector

        Returns:
            OptimizationResult with optimal weights and metrics.

        Raises:
            ValueError: If optimization fails or inputs are invalid.

        """
        if expected_returns.empty or cov_matrix.empty:
            raise ValueError("Expected returns and covariance matrix cannot be empty")

        # Align expected returns and covariance matrix
        assets = expected_returns.index
        if not all(a in cov_matrix.index for a in assets):
            raise ValueError("All assets in expected_returns must be in covariance matrix")

        mu = expected_returns.loc[assets].values
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806
        n = len(assets)

        # Parse constraints
        constraints_dict = constraints or {}
        long_only = constraints_dict.get("long_only", True)
        max_weight = constraints_dict.get("max_weight", 1.0)
        min_weight = constraints_dict.get("min_weight", 0.0)
        target_return = constraints_dict.get("target_return")
        max_volatility = constraints_dict.get("max_volatility")

        # Objective function: minimize -utility = -(w^T μ - λ/2 w^T Σ w)
        def objective(w: NDArray[np.float64]) -> float:
            portfolio_return = float(w @ mu)
            portfolio_variance = float(w @ Sigma @ w)
            utility = portfolio_return - (risk_aversion / 2) * portfolio_variance
            return -utility  # Minimize negative utility

        # Constraints list for scipy
        constraints_list = []

        # Budget constraint: sum of weights = 1
        constraints_list.append({"type": "eq", "fun": lambda w: np.sum(w) - 1.0})

        # Target return constraint
        if target_return is not None:
            constraints_list.append({"type": "eq", "fun": lambda w: w @ mu - target_return})

        # Maximum volatility constraint
        if max_volatility is not None:

            def volatility_constraint(w: NDArray[np.float64]) -> float:
                portfolio_vol = float(np.sqrt(w @ Sigma @ w))
                return max_volatility - portfolio_vol

            constraints_list.append({"type": "ineq", "fun": volatility_constraint})

        # Bounds on individual weights
        if long_only:
            bounds = [(min_weight, max_weight) for _ in range(n)]
        else:
            bounds = [(-1.0, max_weight) for _ in range(n)]  # Allow short selling

        # Initial guess: equal weight
        w0 = np.ones(n) / n

        # Optimize
        result = minimize(
            objective,
            w0,
            method="SLSQP",
            bounds=bounds,
            constraints=constraints_list,
            options={"maxiter": 1000, "ftol": 1e-9},
        )

        if not result.success:
            logger.warning(f"Optimization did not converge: {result.message}")

        # Extract optimal weights
        optimal_weights = pd.Series(result.x, index=assets)

        # Calculate metrics
        portfolio_return = float(optimal_weights @ mu)
        portfolio_variance = float(optimal_weights.values @ Sigma @ optimal_weights.values)
        portfolio_vol = float(np.sqrt(portfolio_variance))

        # Sharpe ratio (assuming risk-free rate = 0 for simplicity)
        sharpe = portfolio_return / portfolio_vol if portfolio_vol > 0 else 0.0

        logger.info(
            f"Mean-variance optimization complete: "
            f"return={portfolio_return:.4f}, vol={portfolio_vol:.4f}, sharpe={sharpe:.4f}"
        )

        return OptimizationResult(
            weights=optimal_weights,
            expected_return=portfolio_return,
            expected_risk=portfolio_vol,
            sharpe_ratio=sharpe,
            method="mean_variance",
            constraints_satisfied=result.success,
        )

    def efficient_frontier(
        self,
        expected_returns: pd.Series,
        cov_matrix: pd.DataFrame,
        n_points: int = 50,
    ) -> pd.DataFrame:
        """Generate efficient frontier (risk vs return curve).

        For each target return level, find the minimum-variance portfolio.

        Args:
            expected_returns: Expected returns per asset.
            cov_matrix: Asset covariance matrix.
            n_points: Number of points on the frontier.

        Returns:
            DataFrame with columns: risk, return, sharpe, weights.

        """
        # Determine range of target returns
        # Min return = minimum variance portfolio
        # Max return = highest individual asset return
        min_var_result = self.min_variance(cov_matrix)
        min_return = min_var_result.expected_return
        max_return = expected_returns.max()

        # Generate target returns
        target_returns = np.linspace(min_return, max_return, n_points)

        frontier_points = []

        for target_ret in target_returns:
            try:
                result = self.optimize(
                    expected_returns,
                    cov_matrix,
                    risk_aversion=0.0,  # Ignore utility, just minimize variance
                    constraints={"target_return": target_ret, "long_only": True},
                )

                frontier_points.append(
                    {
                        "risk": result.expected_risk,
                        "return": result.expected_return,
                        "sharpe": result.sharpe_ratio,
                        "weights": result.weights.to_dict(),
                    }
                )
            except Exception as e:
                logger.debug(f"Failed to optimize for target return {target_ret:.4f}: {e}")
                continue

        frontier_df = pd.DataFrame(frontier_points)
        logger.info(f"Efficient frontier generated: {len(frontier_df)} points")
        return frontier_df

    def max_sharpe(
        self,
        expected_returns: pd.Series,
        cov_matrix: pd.DataFrame,
        risk_free_rate: float = 0.04,
    ) -> OptimizationResult:
        """Find the tangency portfolio (maximum Sharpe ratio).

        This is the portfolio with the highest risk-adjusted return.

        Args:
            expected_returns: Expected returns per asset.
            cov_matrix: Asset covariance matrix.
            risk_free_rate: Risk-free rate for Sharpe calculation.

        Returns:
            OptimizationResult for the max Sharpe portfolio.

        """
        assets = expected_returns.index
        mu = expected_returns.loc[assets].values
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806
        n = len(assets)

        # Objective: minimize negative Sharpe ratio
        def neg_sharpe(w: NDArray[np.float64]) -> float:
            portfolio_return = float(w @ mu)
            portfolio_vol = float(np.sqrt(w @ Sigma @ w))
            if portfolio_vol == 0:
                return 1e10  # Penalize zero volatility
            sharpe = (portfolio_return - risk_free_rate) / portfolio_vol
            return -sharpe

        # Constraints: sum of weights = 1
        constraints = [{"type": "eq", "fun": lambda w: np.sum(w) - 1.0}]

        # Bounds: long-only
        bounds = [(0.0, 1.0) for _ in range(n)]

        # Initial guess: equal weight
        w0 = np.ones(n) / n

        # Optimize
        result = minimize(
            neg_sharpe,
            w0,
            method="SLSQP",
            bounds=bounds,
            constraints=constraints,
            options={"maxiter": 1000, "ftol": 1e-9},
        )

        if not result.success:
            logger.warning(f"Max Sharpe optimization did not converge: {result.message}")

        # Extract optimal weights
        optimal_weights = pd.Series(result.x, index=assets)

        # Calculate metrics
        portfolio_return = float(optimal_weights @ mu)
        portfolio_vol = float(np.sqrt(optimal_weights.values @ Sigma @ optimal_weights.values))
        sharpe = (portfolio_return - risk_free_rate) / portfolio_vol if portfolio_vol > 0 else 0.0

        logger.info(
            f"Max Sharpe portfolio: "
            f"return={portfolio_return:.4f}, vol={portfolio_vol:.4f}, sharpe={sharpe:.4f}"
        )

        return OptimizationResult(
            weights=optimal_weights,
            expected_return=portfolio_return,
            expected_risk=portfolio_vol,
            sharpe_ratio=sharpe,
            method="max_sharpe",
            constraints_satisfied=result.success,
        )

    def min_variance(
        self,
        cov_matrix: pd.DataFrame,
    ) -> OptimizationResult:
        """Find the minimum variance portfolio (global minimum risk).

        This portfolio has the lowest possible risk regardless of return.

        Args:
            cov_matrix: Asset covariance matrix.

        Returns:
            OptimizationResult for the minimum variance portfolio.

        """
        assets = cov_matrix.index
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806
        n = len(assets)

        # Objective: minimize portfolio variance
        def portfolio_variance(w: NDArray[np.float64]) -> float:
            return float(w @ Sigma @ w)

        # Constraints: sum of weights = 1
        constraints = [{"type": "eq", "fun": lambda w: np.sum(w) - 1.0}]

        # Bounds: long-only
        bounds = [(0.0, 1.0) for _ in range(n)]

        # Initial guess: equal weight
        w0 = np.ones(n) / n

        # Optimize
        result = minimize(
            portfolio_variance,
            w0,
            method="SLSQP",
            bounds=bounds,
            constraints=constraints,
            options={"maxiter": 1000, "ftol": 1e-9},
        )

        if not result.success:
            logger.warning(f"Min variance optimization did not converge: {result.message}")

        # Extract optimal weights
        optimal_weights = pd.Series(result.x, index=assets)

        # Calculate metrics (no expected returns provided, so return = 0)
        portfolio_vol = float(np.sqrt(optimal_weights.values @ Sigma @ optimal_weights.values))

        logger.info(f"Min variance portfolio: vol={portfolio_vol:.4f}")

        return OptimizationResult(
            weights=optimal_weights,
            expected_return=0.0,  # Unknown without expected returns
            expected_risk=portfolio_vol,
            sharpe_ratio=0.0,  # Cannot compute without expected returns
            method="min_variance",
            constraints_satisfied=result.success,
        )


class RiskParityOptimizer:
    """Equal Risk Contribution (Risk Parity) portfolio.

    Find weights such that each asset contributes equally to portfolio risk:
    w_i * (Σw)_i / (w^T Σ w) = 1/N for all i

    Uses iterative optimization (scipy.optimize.minimize).
    """

    def optimize(
        self,
        cov_matrix: pd.DataFrame,
        risk_budgets: pd.Series | None = None,
    ) -> OptimizationResult:
        """Find risk parity weights.

        Args:
            cov_matrix: Asset covariance matrix.
            risk_budgets: Target risk contribution per asset (default: equal 1/N).

        Returns:
            OptimizationResult with risk parity weights.

        """
        assets = cov_matrix.index
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806
        n = len(assets)

        # Default risk budgets: equal contribution
        if risk_budgets is None:
            b = np.ones(n) / n
        else:
            b = risk_budgets.loc[assets].values

        # Objective: minimize sum of squared deviations from target risk contributions
        def objective(w: NDArray[np.float64]) -> float:
            # Portfolio variance
            portfolio_var = float(w @ Sigma @ w)

            if portfolio_var == 0:
                return 1e10  # Penalize zero variance

            # Marginal risk contributions: (Σw)_i
            mrc: NDArray[np.float64] = Sigma @ w

            # Risk contributions: w_i * (Σw)_i / portfolio_var
            risk_contrib = w * mrc / portfolio_var

            # Sum of squared deviations from target
            deviation = risk_contrib - b
            return float(np.sum(deviation**2))

        # Constraints: sum of weights = 1
        constraints = [{"type": "eq", "fun": lambda w: np.sum(w) - 1.0}]

        # Bounds: long-only
        bounds = [(0.0, 1.0) for _ in range(n)]

        # Initial guess: equal weight
        w0 = np.ones(n) / n

        # Optimize
        result = minimize(
            objective,
            w0,
            method="SLSQP",
            bounds=bounds,
            constraints=constraints,
            options={"maxiter": 1000, "ftol": 1e-9},
        )

        if not result.success:
            logger.warning(f"Risk parity optimization did not converge: {result.message}")

        # Extract optimal weights
        optimal_weights = pd.Series(result.x, index=assets)

        # Calculate metrics
        portfolio_vol = float(np.sqrt(optimal_weights.values @ Sigma @ optimal_weights.values))

        logger.info(f"Risk parity portfolio: vol={portfolio_vol:.4f}")

        return OptimizationResult(
            weights=optimal_weights,
            expected_return=0.0,  # Unknown without expected returns
            expected_risk=portfolio_vol,
            sharpe_ratio=0.0,  # Cannot compute without expected returns
            method="risk_parity",
            constraints_satisfied=result.success,
        )


class BlackLittermanOptimizer:
    """Black-Litterman model: combine market equilibrium with investor views.

    Posterior returns = (τΣ)^{-1} + P^T Ω^{-1} P)^{-1} ((τΣ)^{-1} π + P^T Ω^{-1} Q)

    where:
    - π = equilibrium returns (from market cap weights)
    - P = pick matrix (which assets the view is about)
    - Q = view returns
    - Ω = view uncertainty
    - τ = scaling factor (typically 0.025)
    """

    def optimize(
        self,
        cov_matrix: pd.DataFrame,
        market_caps: pd.Series,
        views: list[dict[str, list[str] | float]],
        risk_aversion: float = 2.5,
        risk_free_rate: float = 0.04,
        tau: float = 0.025,
    ) -> OptimizationResult:
        """Optimize using Black-Litterman posterior returns.

        Args:
            cov_matrix: Asset covariance matrix.
            market_caps: Market capitalizations (used to derive equilibrium weights).
            views: List of investor views, each dict with:
                - assets: list[str] — Assets in the view
                - return: float — Expected return for this view
                - confidence: float — Confidence level (0-1)
            risk_aversion: Risk aversion parameter (δ).
            risk_free_rate: Risk-free rate.
            tau: Scaling factor for uncertainty (typical: 0.025).

        Returns:
            OptimizationResult with Black-Litterman weights.

        Example:
            >>> views = [
            ...     {"assets": ["AAPL"], "return": 0.10, "confidence": 0.5},
            ...     {"assets": ["MSFT", "GOOGL"], "return": 0.08, "confidence": 0.3},
            ... ]

        """
        assets = cov_matrix.index
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806
        n = len(assets)

        # Step 1: Calculate market equilibrium weights (market cap weighted)
        mkt_caps_aligned = market_caps.loc[assets]
        w_mkt = mkt_caps_aligned / mkt_caps_aligned.sum()

        # Step 2: Implied equilibrium returns: π = δ Σ w_mkt
        pi = risk_aversion * Sigma @ w_mkt.values

        # Step 3: Construct P (pick matrix) and Q (view returns) from views
        k = len(views)  # Number of views
        P = np.zeros((k, n))  # noqa: N806
        Q = np.zeros(k)  # noqa: N806
        Omega = np.zeros((k, k))  # noqa: N806

        for i, view in enumerate(views):
            view_assets = view["assets"]
            view_return = view["return"]
            confidence = view["confidence"]

            # P matrix: 1 for assets in the view (equal weighted if multiple)
            for asset in view_assets:
                if asset in assets:
                    asset_idx = assets.get_loc(asset)
                    P[i, asset_idx] = 1.0 / len(view_assets)

            # Q vector: view return
            Q[i] = view_return

            # Omega matrix: view uncertainty (diagonal)
            # Higher confidence → lower uncertainty
            view_variance = tau * (P[i] @ Sigma @ P[i].T)
            Omega[i, i] = view_variance / confidence

        # Step 4: Calculate posterior returns
        # E[R] = [(τΣ)^{-1} + P^T Ω^{-1} P]^{-1} [(τΣ)^{-1} π + P^T Ω^{-1} Q]
        tau_sigma_inv = np.linalg.inv(tau * Sigma)  # noqa: N806
        omega_inv = np.linalg.inv(Omega)  # noqa: N806

        posterior_cov_inv = tau_sigma_inv + P.T @ omega_inv @ P
        posterior_cov = np.linalg.inv(posterior_cov_inv)

        posterior_returns = posterior_cov @ (tau_sigma_inv @ pi + P.T @ omega_inv @ Q)

        # Step 5: Optimize using posterior returns (mean-variance)
        posterior_returns_series = pd.Series(posterior_returns, index=assets)

        mv_optimizer = MeanVarianceOptimizer()
        result = mv_optimizer.max_sharpe(posterior_returns_series, cov_matrix, risk_free_rate)

        logger.info(
            f"Black-Litterman optimization: {k} views applied, sharpe={result.sharpe_ratio:.4f}"
        )

        # Update method
        return OptimizationResult(
            weights=result.weights,
            expected_return=result.expected_return,
            expected_risk=result.expected_risk,
            sharpe_ratio=result.sharpe_ratio,
            method="black_litterman",
            constraints_satisfied=result.constraints_satisfied,
        )

    def implied_returns(
        self,
        cov_matrix: pd.DataFrame,
        market_caps: pd.Series,
        risk_aversion: float = 2.5,
    ) -> pd.Series:
        """Calculate equilibrium (implied) returns from market cap weights.

        π = δ Σ w_mkt

        Args:
            cov_matrix: Asset covariance matrix.
            market_caps: Market capitalizations.
            risk_aversion: Risk aversion parameter (δ).

        Returns:
            Implied equilibrium returns.

        """
        assets = cov_matrix.index
        Sigma = cov_matrix.loc[assets, assets].values  # noqa: N806

        # Market cap weights
        mkt_caps_aligned = market_caps.loc[assets]
        w_mkt = mkt_caps_aligned / mkt_caps_aligned.sum()

        # Implied returns
        pi = risk_aversion * Sigma @ w_mkt.values

        result = pd.Series(pi, index=assets)
        logger.info(f"Implied equilibrium returns calculated for {len(result)} assets")
        return result


class RebalancingEngine:
    """Generate trade list to move from current to target allocation."""

    def generate_trades(
        self,
        current_weights: pd.Series,
        target_weights: pd.Series,
        portfolio_value: float,
        prices: pd.Series,
        min_trade_value: float = 100,
    ) -> pd.DataFrame:
        """Generate rebalancing trades.

        Args:
            current_weights: Current portfolio weights.
            target_weights: Target portfolio weights.
            portfolio_value: Total portfolio value ($).
            prices: Current prices per asset.
            min_trade_value: Minimum trade value ($) to execute.

        Returns:
            DataFrame with columns:
            - symbol: Asset symbol
            - current_weight: Current weight
            - target_weight: Target weight
            - trade_qty: Number of shares to buy/sell (+ = buy, - = sell)
            - trade_value: Dollar value of trade

        """
        # Align all series
        all_assets = current_weights.index.union(target_weights.index)

        current_aligned = current_weights.reindex(all_assets, fill_value=0.0)
        target_aligned = target_weights.reindex(all_assets, fill_value=0.0)

        # Calculate weight differences
        weight_diff = target_aligned - current_aligned

        # Calculate trade values
        trade_values = weight_diff * portfolio_value

        trades = []

        for asset in all_assets:
            trade_value = trade_values[asset]

            # Skip if trade is too small
            if abs(trade_value) < min_trade_value:
                continue

            # Calculate trade quantity
            price = prices.get(asset, np.nan)
            if pd.isna(price) or price <= 0:
                logger.warning(f"Invalid price for {asset}, skipping trade")
                continue

            trade_qty = trade_value / price

            trades.append(
                {
                    "symbol": asset,
                    "current_weight": current_aligned[asset],
                    "target_weight": target_aligned[asset],
                    "trade_qty": trade_qty,
                    "trade_value": trade_value,
                }
            )

        trades_df = pd.DataFrame(trades)

        if not trades_df.empty:
            logger.info(
                f"Rebalancing: {len(trades_df)} trades generated, "
                f"total value=${abs(trades_df['trade_value']).sum():,.2f}"
            )
        else:
            logger.info("Rebalancing: no trades needed (all below min_trade_value)")

        return trades_df
