"""Factor models for equity pricing and risk estimation.

Implements CAPM, Fama-French, and custom factor models.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from loguru import logger
from scipy import stats


class CAPMModel:
    """Capital Asset Pricing Model."""

    @staticmethod
    def estimate_beta(
        returns: pd.Series,
        market_returns: pd.Series,
    ) -> float:
        r"""Estimate beta using linear regression.

        .. math::

            r_i = \alpha + \beta r_m + \epsilon

        where:
        - :math:`r_i` = asset return
        - :math:`r_m` = market return
        - :math:`\beta` = systematic risk (slope)

        Args:
            returns: Asset returns (aligned with market_returns).
            market_returns: Market portfolio returns.

        Returns:
            Beta (slope coefficient from OLS regression).

        Raises:
            ValueError: If returns and market_returns have different lengths.
        """
        if len(returns) != len(market_returns):
            raise ValueError(
                f"Returns length ({len(returns)}) != market returns length ({len(market_returns)})"
            )

        # Drop NaN values
        df = pd.DataFrame({"asset": returns, "market": market_returns}).dropna()

        if len(df) < 2:
            raise ValueError("Insufficient data after dropping NaN values")

        # OLS regression: returns = alpha + beta * market_returns
        slope, intercept, r_value, p_value, std_err = stats.linregress(df["market"], df["asset"])

        logger.debug(
            f"CAPM beta={slope:.4f}, alpha={intercept:.6f}, R²={r_value**2:.4f}, p={p_value:.4f}"
        )

        return slope

    @staticmethod
    def expected_return(
        beta: float,
        risk_free_rate: float,
        market_return: float,
    ) -> float:
        r"""Calculate expected return using CAPM.

        .. math::

            E[r_i] = r_f + \beta (E[r_m] - r_f)

        where:
        - :math:`r_f` = risk-free rate
        - :math:`E[r_m]` = expected market return
        - :math:`\beta` = systematic risk

        Args:
            beta: Asset beta.
            risk_free_rate: Risk-free rate (decimal).
            market_return: Expected market return (decimal).

        Returns:
            Expected return (decimal).
        """
        expected = risk_free_rate + beta * (market_return - risk_free_rate)

        logger.debug(
            f"CAPM expected return: β={beta:.4f}, rf={risk_free_rate:.4%}, "
            f"rm={market_return:.4%}, E[r]={expected:.4%}"
        )

        return expected


class FamaFrenchModel:
    """Fama-French 3-factor model."""

    @staticmethod
    def estimate_betas(
        returns: pd.Series,
        market_returns: pd.Series,
        smb_returns: pd.Series | None = None,
        hml_returns: pd.Series | None = None,
        window: int = 252,
    ) -> dict[str, float | pd.Series]:
        r"""Estimate Fama-French factor loadings (betas).

        Three-factor model:

        .. math::

            r_i - r_f = \alpha + \beta_{mkt}(r_m - r_f) + \beta_{SMB} SMB + \beta_{HML} HML + \epsilon

        where:
        - :math:`r_m - r_f` = market excess return
        - :math:`SMB` = Small Minus Big (size factor)
        - :math:`HML` = High Minus Low (value factor)

        Args:
            returns: Asset returns.
            market_returns: Market excess returns.
            smb_returns: Small Minus Big factor returns (optional).
            hml_returns: High Minus Low factor returns (optional).
            window: Rolling window for beta estimation (days).

        Returns:
            Dictionary with keys: 'beta_market', 'beta_smb', 'beta_hml', 'alpha',
            'r_squared'. If window < len(returns), also includes rolling betas.
        """
        # Align all series
        df = pd.DataFrame(
            {
                "asset": returns,
                "market": market_returns,
                "smb": smb_returns if smb_returns is not None else 0.0,
                "hml": hml_returns if hml_returns is not None else 0.0,
            }
        ).dropna()

        if len(df) < window:
            raise ValueError(f"Insufficient data: need {window} observations, got {len(df)}")

        # Full-period OLS regression
        X = df[["market", "smb", "hml"]].values  # noqa: N806
        y = df["asset"].values

        # Add constant for alpha
        X_with_const = np.column_stack([np.ones(len(X)), X])  # noqa: N806

        # OLS: (X'X)^-1 X'y
        coeffs = np.linalg.lstsq(X_with_const, y, rcond=None)[0]
        alpha, beta_market, beta_smb, beta_hml = coeffs

        # R-squared
        y_pred = X_with_const @ coeffs
        ss_res = np.sum((y - y_pred) ** 2)
        ss_tot = np.sum((y - np.mean(y)) ** 2)
        r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0

        result = {
            "beta_market": beta_market,
            "beta_smb": beta_smb,
            "beta_hml": beta_hml,
            "alpha": alpha,
            "r_squared": r_squared,
        }

        # Rolling beta estimation
        if len(df) >= window:
            rolling_betas = []
            for i in range(window, len(df) + 1):
                X_window = df[["market", "smb", "hml"]].iloc[i - window : i].values  # noqa: N806
                y_window = df["asset"].iloc[i - window : i].values
                X_window_const = np.column_stack([np.ones(len(X_window)), X_window])  # noqa: N806

                try:
                    coeffs_window = np.linalg.lstsq(X_window_const, y_window, rcond=None)[0]
                    rolling_betas.append(coeffs_window[1])  # beta_market
                except np.linalg.LinAlgError:
                    rolling_betas.append(np.nan)

            result["rolling_beta_market"] = pd.Series(rolling_betas, index=df.index[window - 1 :])

        logger.info(
            f"Fama-French: β_mkt={beta_market:.4f}, β_smb={beta_smb:.4f}, "
            f"β_hml={beta_hml:.4f}, α={alpha:.6f}, R²={r_squared:.4f}"
        )

        return result

    @staticmethod
    def expected_return(
        betas: dict[str, float],
        risk_free_rate: float,
        market_premium: float,
        smb_premium: float = 0.0,
        hml_premium: float = 0.0,
    ) -> float:
        r"""Calculate expected return using Fama-French model.

        .. math::

            E[r_i] = r_f + \beta_{mkt} \cdot RP_m + \beta_{SMB} \cdot RP_{SMB} + \beta_{HML} \cdot RP_{HML}

        where:
        - :math:`RP_m` = market risk premium
        - :math:`RP_{SMB}` = size premium
        - :math:`RP_{HML}` = value premium

        Args:
            betas: Dictionary with 'beta_market', 'beta_smb', 'beta_hml'.
            risk_free_rate: Risk-free rate (decimal).
            market_premium: Market risk premium (decimal).
            smb_premium: Size premium (decimal).
            hml_premium: Value premium (decimal).

        Returns:
            Expected return (decimal).
        """
        expected = (
            risk_free_rate
            + betas["beta_market"] * market_premium
            + betas.get("beta_smb", 0.0) * smb_premium
            + betas.get("beta_hml", 0.0) * hml_premium
        )

        logger.debug(
            f"Fama-French expected return: rf={risk_free_rate:.4%}, "
            f"mkt_prem={market_premium:.4%}, smb_prem={smb_premium:.4%}, "
            f"hml_prem={hml_premium:.4%}, E[r]={expected:.4%}"
        )

        return expected


class CustomFactors:
    """Custom factor calculations for alpha generation."""

    @staticmethod
    def quality_factor(fundamentals: pd.DataFrame) -> pd.Series:
        """Calculate quality factor score.

        Quality = high ROE + low leverage + stable earnings

        Args:
            fundamentals: DataFrame with columns: 'roe', 'debt_to_equity', 'earnings_volatility'.

        Returns:
            Quality factor score (z-score normalized, higher = better quality).
        """
        if not all(
            col in fundamentals.columns for col in ["roe", "debt_to_equity", "earnings_volatility"]
        ):
            raise ValueError("fundamentals must contain: roe, debt_to_equity, earnings_volatility")

        # Normalize each component to z-scores
        roe_z = (fundamentals["roe"] - fundamentals["roe"].mean()) / fundamentals["roe"].std()

        # Lower debt is better (invert sign)
        debt_z = (
            -(fundamentals["debt_to_equity"] - fundamentals["debt_to_equity"].mean())
            / fundamentals["debt_to_equity"].std()
        )

        # Lower volatility is better (invert sign)
        vol_z = (
            -(fundamentals["earnings_volatility"] - fundamentals["earnings_volatility"].mean())
            / fundamentals["earnings_volatility"].std()
        )

        # Composite quality score (equal weight)
        quality = (roe_z + debt_z + vol_z) / 3

        logger.info(f"Quality factor computed for {len(quality)} companies")
        return quality

    @staticmethod
    def low_volatility_factor(returns: pd.DataFrame) -> pd.Series:
        """Calculate low volatility factor.

        Low volatility anomaly: low-vol stocks tend to outperform high-vol stocks.

        Args:
            returns: DataFrame of asset returns (columns = assets, rows = dates).

        Returns:
            Low volatility score (z-score normalized, higher = lower volatility).
        """
        # Calculate realized volatility for each asset
        volatility = returns.std()

        # Invert and normalize (lower vol = higher score)
        low_vol_score = -((volatility - volatility.mean()) / volatility.std())

        logger.info(f"Low volatility factor computed for {len(low_vol_score)} assets")
        return low_vol_score

    @staticmethod
    def earnings_momentum_factor(fundamentals: pd.DataFrame) -> pd.Series:
        """Calculate earnings momentum factor.

        Earnings momentum = recent earnings surprise + earnings revision trend

        Args:
            fundamentals: DataFrame with columns: 'earnings_surprise', 'earnings_revision'.

        Returns:
            Earnings momentum score (z-score normalized).
        """
        if not all(
            col in fundamentals.columns for col in ["earnings_surprise", "earnings_revision"]
        ):
            raise ValueError("fundamentals must contain: earnings_surprise, earnings_revision")

        # Normalize each component
        surprise_z = (
            fundamentals["earnings_surprise"] - fundamentals["earnings_surprise"].mean()
        ) / fundamentals["earnings_surprise"].std()

        revision_z = (
            fundamentals["earnings_revision"] - fundamentals["earnings_revision"].mean()
        ) / fundamentals["earnings_revision"].std()

        # Composite momentum (equal weight)
        momentum = (surprise_z + revision_z) / 2

        logger.info(f"Earnings momentum factor computed for {len(momentum)} companies")
        return momentum
