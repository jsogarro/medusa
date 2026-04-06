"""Risk analytics for strategy evaluation."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from loguru import logger


class RiskAnalytics:
    """Calculate risk metrics for strategy returns."""

    @staticmethod
    def sharpe_ratio(
        returns: pd.Series,
        risk_free_rate: float = 0.0,
        periods: int = 252,
    ) -> float:
        """Annualized Sharpe ratio.

        Args:
            returns: Daily returns series.
            risk_free_rate: Annual risk-free rate.
            periods: Trading days per year.
        """
        excess = returns - risk_free_rate / periods
        std = excess.std()
        if std == 0 or np.isnan(std):
            return float("nan")
        return float(excess.mean() / std * np.sqrt(periods))

    @staticmethod
    def sortino_ratio(
        returns: pd.Series,
        risk_free_rate: float = 0.0,
        periods: int = 252,
    ) -> float:
        """Annualized Sortino ratio (downside deviation only)."""
        excess = returns - risk_free_rate / periods
        downside = excess[excess < 0]
        if len(downside) == 0:
            return float("nan")
        std = downside.std()
        if std == 0 or np.isnan(std):
            return float("nan")
        return float(excess.mean() / std * np.sqrt(periods))

    @staticmethod
    def max_drawdown(returns: pd.Series) -> float:
        """Maximum drawdown from peak to trough."""
        cumulative = (1 + returns).cumprod()
        peak = cumulative.cummax()
        drawdown = (cumulative - peak) / peak
        return float(drawdown.min())

    @staticmethod
    def calmar_ratio(returns: pd.Series, periods: int = 252) -> float:
        """Calmar ratio (CAGR / max drawdown)."""
        ann_return = float(returns.mean() * periods)
        mdd = RiskAnalytics.max_drawdown(returns)
        if mdd == 0 or np.isnan(mdd):
            return float("nan")
        return ann_return / abs(mdd)

    @staticmethod
    def var(
        returns: pd.Series,
        confidence: float = 0.95,
    ) -> float:
        """Value at Risk (historical simulation).

        Args:
            returns: Daily returns.
            confidence: Confidence level (e.g. 0.95 for 95% VaR).

        Returns:
            VaR as a negative number (loss).
        """
        return float(np.percentile(returns.dropna(), (1 - confidence) * 100))

    @staticmethod
    def cvar(
        returns: pd.Series,
        confidence: float = 0.95,
    ) -> float:
        """Conditional Value at Risk (Expected Shortfall).

        Average loss beyond VaR threshold.
        """
        var_val = RiskAnalytics.var(returns, confidence)
        tail = returns[returns <= var_val]
        if len(tail) == 0:
            return var_val
        return float(tail.mean())

    @staticmethod
    def full_report(
        returns: pd.Series,
        risk_free_rate: float = 0.0,
    ) -> dict[str, Any]:
        """Generate comprehensive risk report.

        Returns:
            Dictionary with all risk metrics.
        """
        report = {
            "sharpe_ratio": RiskAnalytics.sharpe_ratio(returns, risk_free_rate),
            "sortino_ratio": RiskAnalytics.sortino_ratio(returns, risk_free_rate),
            "max_drawdown": RiskAnalytics.max_drawdown(returns),
            "calmar_ratio": RiskAnalytics.calmar_ratio(returns),
            "var_95": RiskAnalytics.var(returns, 0.95),
            "var_99": RiskAnalytics.var(returns, 0.99),
            "cvar_95": RiskAnalytics.cvar(returns, 0.95),
            "cvar_99": RiskAnalytics.cvar(returns, 0.99),
            "annualized_return": float(returns.mean() * 252),
            "annualized_volatility": float(returns.std() * np.sqrt(252)),
            "skewness": float(returns.skew()),
            "kurtosis": float(returns.kurtosis()),
            "positive_days": int((returns > 0).sum()),
            "negative_days": int((returns < 0).sum()),
            "best_day": float(returns.max()),
            "worst_day": float(returns.min()),
        }

        logger.info(
            f"Risk report: Sharpe={report['sharpe_ratio']:.2f}, "
            f"MaxDD={report['max_drawdown']:.2%}, "
            f"VaR95={report['var_95']:.4f}"
        )
        return report
