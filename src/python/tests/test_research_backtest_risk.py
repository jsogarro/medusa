"""Regression tests: backtest fill timing, optimizer direction, risk metrics."""

from __future__ import annotations

import sys
import types

import numpy as np
import pandas as pd
import pytest

from medusa.analytics.risk import RiskAnalytics
from medusa.backtest.vectorbt_engine import VectorBTEngine


def test_run_signals_fills_on_bar_after_signal(monkeypatch):
    captured = {}

    class _Portfolio:
        @staticmethod
        def from_signals(**kw):
            captured.update(kw)
            return types.SimpleNamespace(total_return=lambda: 0.0)

    monkeypatch.setitem(sys.modules, "vectorbt", types.SimpleNamespace(Portfolio=_Portfolio))
    idx = pd.date_range("2024-01-01", periods=5, freq="D")
    price = pd.Series(np.arange(5.0) + 100, index=idx)
    entries = pd.Series([False, True, False, False, False], index=idx)
    exits = pd.Series([False, False, False, True, False], index=idx)

    VectorBTEngine(asset_class="crypto").run_signals(price, entries, exits)

    assert captured["entries"].tolist() == [False, False, True, False, False]
    assert captured["exits"].tolist() == [False, False, False, False, True]


def test_run_signals_also_delays_short_signals(monkeypatch):
    captured = {}

    class _Portfolio:
        @staticmethod
        def from_signals(**kw):
            captured.update(kw)
            return types.SimpleNamespace(total_return=lambda: 0.0)

    monkeypatch.setitem(sys.modules, "vectorbt", types.SimpleNamespace(Portfolio=_Portfolio))
    idx = pd.date_range("2024-01-01", periods=5, freq="D")
    price = pd.Series(np.arange(5.0) + 100, index=idx)
    none = pd.Series(False, index=idx)
    short_in = pd.Series([False, True, False, False, False], index=idx)
    short_out = pd.Series([False, False, False, True, False], index=idx)

    VectorBTEngine(asset_class="crypto").run_signals(
        price, none, none, short_entries=short_in, short_exits=short_out
    )

    assert captured["short_entries"].tolist() == [False, False, True, False, False]
    assert captured["short_exits"].tolist() == [False, False, False, False, True]


def test_equity_engine_honours_explicit_commission():
    assert VectorBTEngine(asset_class="equity", commission=0.001).commission == 0.001
    assert VectorBTEngine(asset_class="equity").commission == 0.0


@pytest.mark.parametrize("dd", [-0.3, 0.3])
def test_max_drawdown_metric_is_higher_is_better(dd):
    from medusa.backtest.optimizer import _strategy_metric

    small = types.SimpleNamespace(max_drawdown=lambda: dd / 3)
    large = types.SimpleNamespace(max_drawdown=lambda: dd)
    assert _strategy_metric(small, "max_drawdown") > _strategy_metric(large, "max_drawdown")


def test_optimizer_default_storage_is_in_memory():
    pytest.importorskip("optuna")
    from medusa.backtest.optimizer import OptunaOptimizer

    assert OptunaOptimizer(types.SimpleNamespace()).storage is None


def test_sortino_uses_downside_deviation_over_all_observations():
    r = pd.Series([0.02, -0.01, 0.03, -0.03, 0.01, 0.0])
    dd = np.sqrt(np.mean(np.minimum(r, 0.0) ** 2))
    expected = r.mean() / dd * np.sqrt(252)
    assert RiskAnalytics.sortino_ratio(r) == pytest.approx(expected)


def test_sortino_single_loss_is_finite():
    r = pd.Series([0.01, 0.02, -0.01, 0.015])
    assert np.isfinite(RiskAnalytics.sortino_ratio(r))


def test_calmar_uses_cagr():
    r = pd.Series([0.10, -0.05, 0.10, 0.10])
    cagr = (1 + r).prod() ** (252 / len(r)) - 1
    assert RiskAnalytics.calmar_ratio(r) == pytest.approx(cagr / abs(RiskAnalytics.max_drawdown(r)))


def test_full_report_threads_periods():
    r = pd.Series(np.random.default_rng(0).normal(0.001, 0.02, 200))
    d365 = RiskAnalytics.full_report(r, periods=365)
    d252 = RiskAnalytics.full_report(r)
    assert d365["annualized_volatility"] == pytest.approx(r.std() * np.sqrt(365))
    assert d365["sharpe_ratio"] == pytest.approx(d252["sharpe_ratio"] * np.sqrt(365 / 252))
    assert d365["sortino_ratio"] == pytest.approx(RiskAnalytics.sortino_ratio(r, periods=365))
    assert d365["calmar_ratio"] == pytest.approx(RiskAnalytics.calmar_ratio(r, periods=365))
