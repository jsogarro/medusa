"""Risk models for portfolio construction and risk decomposition."""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger

try:
    from sklearn.covariance import OAS, LedoitWolf, ShrunkCovariance

    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    logger.warning("sklearn not installed - advanced covariance estimators unavailable")


class CovarianceEstimator:
    """Covariance matrix estimation with shrinkage."""

    @staticmethod
    def estimate(
        returns: pd.DataFrame,
        method: str = "sample",
    ) -> pd.DataFrame:
        """Estimate covariance matrix from returns.

        Args:
            returns: DataFrame of asset returns (columns = assets, rows = dates).
            method: Estimation method:
                - 'sample': Sample covariance (no shrinkage).
                - 'ledoit_wolf': Ledoit-Wolf shrinkage.
                - 'oas': Oracle Approximating Shrinkage.
                - 'shrunk': Shrunk covariance with optimal shrinkage.

        Returns:
            Covariance matrix as DataFrame (index and columns = asset names).

        Raises:
            ValueError: If method is not supported or sklearn is required but not installed.
        """
        if returns.empty:
            raise ValueError("Returns DataFrame is empty")

        if method == "sample":
            cov = returns.cov()
            logger.info(f"Sample covariance computed: {cov.shape[0]} assets")
            return cov

        # Advanced methods require sklearn
        if not SKLEARN_AVAILABLE:
            raise ValueError(
                f"Method '{method}' requires sklearn. Install with: pip install scikit-learn"
            )

        returns_array = returns.values

        if method == "ledoit_wolf":
            lw = LedoitWolf()
            cov_array = lw.fit(returns_array).covariance_
            logger.info(
                f"Ledoit-Wolf covariance computed: "
                f"{cov_array.shape[0]} assets, shrinkage={lw.shrinkage_:.4f}"
            )
        elif method == "oas":
            oas = OAS()
            cov_array = oas.fit(returns_array).covariance_
            logger.info(
                f"OAS covariance computed: "
                f"{cov_array.shape[0]} assets, shrinkage={oas.shrinkage_:.4f}"
            )
        elif method == "shrunk":
            shrunk = ShrunkCovariance()
            cov_array = shrunk.fit(returns_array).covariance_
            logger.info(
                f"Shrunk covariance computed: "
                f"{cov_array.shape[0]} assets, shrinkage={shrunk.shrinkage:.4f}"
            )
        else:
            raise ValueError(
                f"Unsupported method: {method}. Supported: sample, ledoit_wolf, oas, shrunk"
            )

        # Convert back to DataFrame with asset names
        cov = pd.DataFrame(cov_array, index=returns.columns, columns=returns.columns)
        return cov

    @staticmethod
    def correlation_from_covariance(cov: pd.DataFrame) -> pd.DataFrame:
        """Convert covariance matrix to correlation matrix.

        Args:
            cov: Covariance matrix.

        Returns:
            Correlation matrix.
        """
        std = np.sqrt(np.diag(cov))
        std_matrix = np.outer(std, std)
        corr = cov / std_matrix
        logger.debug(f"Correlation matrix computed from covariance: {corr.shape[0]} assets")
        return pd.DataFrame(corr, index=cov.index, columns=cov.columns)


class RiskDecomposition:
    """Risk decomposition for factor models."""

    @staticmethod
    def decompose_variance(
        weights: pd.Series,
        betas: pd.DataFrame,
        factor_cov: pd.DataFrame,
        specific_risk: pd.Series,
    ) -> dict[str, float]:
        r"""Decompose portfolio variance into factor and specific risk.

        .. math::

            \sigma_p^2 = w' B \Sigma_f B' w + w' \Sigma_{\epsilon} w

        where:
        - :math:`w` = portfolio weights
        - :math:`B` = factor loadings (betas)
        - :math:`\Sigma_f` = factor covariance matrix
        - :math:`\Sigma_{\epsilon}` = specific risk (diagonal)

        Args:
            weights: Portfolio weights (index = assets).
            betas: Factor loadings (rows = assets, columns = factors).
            factor_cov: Factor covariance matrix.
            specific_risk: Specific risk (idiosyncratic volatility) per asset.

        Returns:
            Dictionary with keys: 'total_variance', 'factor_variance',
            'specific_variance', 'factor_contribution_pct', 'specific_contribution_pct'.
        """
        # Align all inputs
        assets = weights.index
        if not all(a in betas.index for a in assets):
            raise ValueError("All assets in weights must be in betas")
        if not all(a in specific_risk.index for a in assets):
            raise ValueError("All assets in weights must be in specific_risk")

        # Subset to portfolio assets
        w = weights.values
        B = betas.loc[assets].values  # noqa: N806
        sigma_eps = specific_risk.loc[assets].values

        # Factor variance: w' B Sigma_f B' w
        factor_variance = w @ B @ factor_cov.values @ B.T @ w

        # Specific variance: w' Sigma_eps w (diagonal specific risk)
        specific_variance = w @ np.diag(sigma_eps**2) @ w

        # Total variance
        total_variance = factor_variance + specific_variance

        # Contributions
        factor_pct = factor_variance / total_variance * 100 if total_variance > 0 else 0.0
        specific_pct = specific_variance / total_variance * 100 if total_variance > 0 else 0.0

        logger.info(
            f"Risk decomposition: total_var={total_variance:.6f}, "
            f"factor={factor_pct:.1f}%, specific={specific_pct:.1f}%"
        )

        return {
            "total_variance": total_variance,
            "factor_variance": factor_variance,
            "specific_variance": specific_variance,
            "factor_contribution_pct": factor_pct,
            "specific_contribution_pct": specific_pct,
        }

    @staticmethod
    def marginal_risk_contribution(
        weights: pd.Series,
        cov: pd.DataFrame,
    ) -> pd.Series:
        r"""Calculate marginal risk contribution (MRC) for each asset.

        .. math::

            MRC_i = \frac{\partial \sigma_p}{\partial w_i} = \frac{(\Sigma w)_i}{\sigma_p}

        Args:
            weights: Portfolio weights (index = assets).
            cov: Asset covariance matrix.

        Returns:
            Marginal risk contribution per asset.
        """
        # Align weights and covariance
        assets = weights.index
        if not all(a in cov.index for a in assets):
            raise ValueError("All assets in weights must be in covariance matrix")

        w = weights.loc[assets].values
        Sigma = cov.loc[assets, assets].values  # noqa: N806

        # Portfolio variance
        portfolio_variance = w @ Sigma @ w
        portfolio_vol = np.sqrt(portfolio_variance)

        if portfolio_vol == 0:
            logger.warning("Portfolio volatility is zero, returning zero MRC")
            return pd.Series(0.0, index=assets)

        # MRC = (Sigma * w) / portfolio_vol
        mrc = (Sigma @ w) / portfolio_vol

        result = pd.Series(mrc, index=assets)

        logger.debug(f"Marginal risk contribution computed for {len(result)} assets")

        return result

    @staticmethod
    def risk_parity_weights(
        cov: pd.DataFrame,
        tol: float = 1e-6,
        max_iter: int = 1000,
    ) -> pd.Series:
        """Calculate risk parity portfolio weights (equal risk contribution).

        Iterative algorithm to find weights such that each asset contributes
        equally to portfolio risk.

        Args:
            cov: Asset covariance matrix.
            tol: Convergence tolerance.
            max_iter: Maximum iterations.

        Returns:
            Risk parity weights (sum = 1).

        Raises:
            ValueError: If algorithm fails to converge.
        """
        n = len(cov)
        assets = cov.index

        # Initialize with equal weights
        w = np.ones(n) / n

        for iteration in range(max_iter):
            # Calculate marginal risk contributions
            portfolio_vol = np.sqrt(w @ cov.values @ w)
            mrc = (cov.values @ w) / portfolio_vol

            # Update weights: w_i = 1 / MRC_i
            w_new = 1 / mrc
            w_new = w_new / np.sum(w_new)  # Normalize to sum to 1

            # Check convergence
            diff = np.max(np.abs(w_new - w))
            if diff < tol:
                logger.info(
                    f"Risk parity converged in {iteration + 1} iterations: max_diff={diff:.2e}"
                )
                return pd.Series(w_new, index=assets)

            w = w_new

        raise ValueError(f"Risk parity failed to converge after {max_iter} iterations")
