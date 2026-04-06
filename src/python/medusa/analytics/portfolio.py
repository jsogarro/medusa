"""Portfolio optimization using Riskfolio-Lib."""

from __future__ import annotations

import pandas as pd
from loguru import logger


class PortfolioOptimizer:
    """Portfolio optimization with mean-variance, risk parity, and HRP."""

    @staticmethod
    def mean_variance(
        returns: pd.DataFrame,
        method: str = "MV",
        risk_measure: str = "MV",
        risk_free_rate: float = 0.0,
    ) -> pd.Series:
        """Mean-variance optimization.

        Args:
            returns: Asset returns (columns = assets).
            method: 'MV' (max Sharpe), 'MinRisk', 'MaxRet', etc.
            risk_measure: 'MV', 'CVaR', 'EVaR', etc.
            risk_free_rate: Annual risk-free rate.

        Returns:
            Optimal weights as Series.
        """
        import riskfolio as rp

        port = rp.Portfolio(returns=returns)
        port.assets_stats(method_mu="hist", method_cov="hist")

        weights = port.optimization(
            model=method, rm=risk_measure, rf=risk_free_rate, hist=True
        )

        result = weights.squeeze()
        logger.info(f"Mean-variance ({method}, {risk_measure}): {len(result)} assets")
        return result

    @staticmethod
    def risk_parity(
        returns: pd.DataFrame,
        risk_measure: str = "MV",
    ) -> pd.Series:
        """Risk parity / equal risk contribution.

        Args:
            returns: Asset returns.
            risk_measure: Risk measure for parity.

        Returns:
            Risk parity weights.
        """
        import riskfolio as rp

        port = rp.Portfolio(returns=returns)
        port.assets_stats(method_mu="hist", method_cov="hist")

        weights = port.rp_optimization(
            model="Classic", rm=risk_measure, rf=0.0, hist=True
        )

        result = weights.squeeze()
        logger.info(f"Risk parity ({risk_measure}): {len(result)} assets")
        return result

    @staticmethod
    def hierarchical_risk_parity(returns: pd.DataFrame) -> pd.Series:
        """Hierarchical Risk Parity (HRP).

        Tree-based clustering approach to portfolio construction.
        More robust to estimation error than mean-variance.

        Args:
            returns: Asset returns.

        Returns:
            HRP weights.
        """
        import riskfolio as rp

        port = rp.HCPortfolio(returns=returns)
        weights = port.optimization(
            model="HRP",
            codependence="pearson",
            rm="MV",
            leaf_order=True,
        )

        result = weights.squeeze()
        logger.info(f"HRP: {len(result)} assets")
        return result

    @staticmethod
    def black_litterman(
        returns: pd.DataFrame,
        market_caps: pd.Series | None = None,
        views: dict[str, float] | None = None,
    ) -> pd.Series:
        """Black-Litterman optimization (placeholder).

        Full implementation requires:
        - Market equilibrium returns (from market caps)
        - Investor views (relative or absolute)
        - View confidence levels

        Args:
            returns: Historical returns.
            market_caps: Market capitalizations.
            views: Investor return views per asset.

        Returns:
            Posterior weights (placeholder — returns equal weight).
        """
        logger.warning("Black-Litterman is a placeholder — returning equal weight")
        n_assets = returns.shape[1]
        return pd.Series(
            [1.0 / n_assets] * n_assets,
            index=returns.columns,
            name="weight",
        )
