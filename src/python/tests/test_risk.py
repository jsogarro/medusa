"""Tests for risk analytics."""

import numpy as np
import pandas as pd

from medusa.analytics.risk import RiskAnalytics


class TestRiskAnalytics:
    def test_sharpe_ratio(self, sample_returns):
        sharpe = RiskAnalytics.sharpe_ratio(sample_returns)
        assert isinstance(sharpe, float)
        assert not np.isnan(sharpe)

    def test_sortino_ratio(self, sample_returns):
        sortino = RiskAnalytics.sortino_ratio(sample_returns)
        assert isinstance(sortino, float)

    def test_max_drawdown(self, sample_returns):
        mdd = RiskAnalytics.max_drawdown(sample_returns)
        assert mdd <= 0  # Drawdown is negative

    def test_calmar_ratio(self, sample_returns):
        calmar = RiskAnalytics.calmar_ratio(sample_returns)
        assert isinstance(calmar, float)

    def test_var(self, sample_returns):
        var95 = RiskAnalytics.var(sample_returns, 0.95)
        var99 = RiskAnalytics.var(sample_returns, 0.99)
        assert var99 <= var95  # 99% VaR is worse (more negative)

    def test_cvar(self, sample_returns):
        cvar = RiskAnalytics.cvar(sample_returns, 0.95)
        var = RiskAnalytics.var(sample_returns, 0.95)
        assert cvar <= var  # CVaR is worse than VaR

    def test_full_report(self, sample_returns):
        report = RiskAnalytics.full_report(sample_returns)
        assert "sharpe_ratio" in report
        assert "max_drawdown" in report
        assert "var_95" in report
        assert "cvar_95" in report
        assert report["positive_days"] + report["negative_days"] <= len(sample_returns)

    def test_sharpe_zero_std(self):
        constant_returns = pd.Series([0.0] * 100)
        result = RiskAnalytics.sharpe_ratio(constant_returns)
        assert np.isnan(result)
