"""Causality / look-ahead regression tests for research code."""

from __future__ import annotations

import numpy as np
import pandas as pd

from medusa.features.order_flow_features import vpin
from medusa.features.pipeline import FeaturePipeline
from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy
from medusa.strategies.pairs_trading import PairsTradingStrategy


class _ConstModel:
    def __init__(self, value: int) -> None:
        self.value = value

    def predict(self, features):
        return np.full(len(features), self.value)


def _ohlcv(n: int = 120, seed: int = 0) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    close = 100 * np.exp(np.cumsum(rng.normal(0, 0.01, n)))
    return pd.DataFrame(
        {
            "open": close,
            "high": close * 1.001,
            "low": close * 0.999,
            "close": close,
            "volume": rng.uniform(100, 1000, n),
        },
        index=pd.date_range("2024-01-01", periods=n, freq="D"),
    )


def test_short_primary_signal_is_not_a_long_entry():
    data = _ohlcv()
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(-1))
    entries, _ = strat.generate_signals(data)
    assert not entries.any()
    assert strat.generate_short_entries(data).any()


def test_long_primary_signal_is_a_long_entry():
    data = _ohlcv()
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(1))
    entries, _ = strat.generate_signals(data)
    assert entries.any()
    assert not strat.generate_short_entries(data).any()


def test_triple_barrier_take_profit_on_non_datetime_index():
    prices = pd.Series([100.0, 103.0] + [103.0] * 5)  # RangeIndex, TP hit, no SL
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(1), max_holding_bars=3)
    labels = strat._create_triple_barrier_labels(prices, pd.Series(1, index=prices.index))
    assert labels.iloc[0] == 1


def test_triple_barrier_stop_before_take_profit_on_tz_index():
    idx = pd.date_range("2024-01-01", periods=8, freq="h", tz="UTC")
    prices = pd.Series([100.0, 98.0, 103.0, 103.0, 103.0, 103.0, 103.0, 103.0], index=idx)
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(1), max_holding_bars=3)
    labels = strat._create_triple_barrier_labels(prices, pd.Series(1, index=idx))
    assert labels.iloc[0] == -1


def test_triple_barrier_short_take_profit():
    prices = pd.Series([100.0, 97.0, 97.0, 97.0, 97.0, 97.0])
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(-1), max_holding_bars=3)
    labels = strat._create_triple_barrier_labels(prices, pd.Series(-1, index=prices.index))
    assert labels.iloc[0] == 1


def _random_walk(n: int = 600, seed: int = 1) -> pd.DataFrame:
    return _ohlcv(n, seed)


def test_pipeline_target_is_next_bar_return():
    df = _random_walk()
    out = FeaturePipeline().run(df)
    r = np.log(df["close"] / df["close"].shift(1))
    idx = out["y_train"].index[10]
    nxt = df.index[df.index.get_loc(idx) + 1]
    assert out["y_train"].loc[idx] == r.loc[nxt]


def test_pipeline_random_walk_out_of_sample_r2_near_zero():
    out = FeaturePipeline().run(_random_walk(1500))
    xtr, ytr = out["x_train"].to_numpy(), out["y_train"].to_numpy()
    xte, yte = out["x_test"].to_numpy(), out["y_test"].to_numpy()
    xtr1 = np.c_[np.ones(len(xtr)), xtr]
    beta, *_ = np.linalg.lstsq(xtr1, ytr, rcond=None)
    pred = np.c_[np.ones(len(xte)), xte] @ beta
    r2 = 1 - ((yte - pred) ** 2).sum() / ((yte - yte.mean()) ** 2).sum()
    assert r2 < 0.05


def _pair(n: int = 400, seed: int = 3) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    common = np.cumsum(rng.normal(0, 0.5, n))
    a = 100 + common + rng.normal(0, 0.3, n)
    b = 50 + 0.5 * common + rng.normal(0, 0.15, n)
    return pd.DataFrame(
        {("BTC", "close"): a, ("ETH", "close"): b},
        index=pd.date_range("2024-01-01", periods=n, freq="D"),
    )


def test_pairs_signals_do_not_depend_on_later_bars():
    data = _pair()
    k = 300
    perturbed = data.copy()
    perturbed.iloc[k:, 0] += np.linspace(0, 60, len(data) - k)
    kw = dict(asset1="BTC", asset2="ETH", lookback=100, spread_window=30, retest_period=30)
    e1, x1 = PairsTradingStrategy(**kw).generate_signals(data)
    e2, x2 = PairsTradingStrategy(**kw).generate_signals(perturbed)
    pd.testing.assert_series_equal(e1.iloc[:k], e2.iloc[:k])
    pd.testing.assert_series_equal(x1.iloc[:k], x2.iloc[:k])
    assert e1.iloc[:k].any()  # the test must not pass vacuously


def test_pairs_exit_fires_when_zscore_crosses_zero():
    kw = dict(asset1="BTC", asset2="ETH", lookback=100, spread_window=30, retest_period=30)
    entries, exits = PairsTradingStrategy(**kw).generate_signals(_pair())
    assert entries.any()
    assert exits.any()


def _trades(n: int = 400, seed: int = 5, with_buy: bool = False) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    df = pd.DataFrame(
        {
            "close": 100 + np.cumsum(rng.normal(0, 0.5, n)),
            "volume": rng.uniform(5, 15, n),
        },
        index=pd.date_range("2024-01-01", periods=n, freq="min"),
    )
    if with_buy:
        df["buy_volume"] = df["volume"] * rng.uniform(0.2, 0.8, n)
    return df


def test_vpin_does_not_depend_on_later_bars():
    for with_buy in (False, True):
        df = _trades(with_buy=with_buy)
        k = 300
        perturbed = df.copy()
        perturbed.iloc[k:, perturbed.columns.get_loc("volume")] *= 7
        perturbed.iloc[k:, perturbed.columns.get_loc("close")] += 25
        if with_buy:
            perturbed.iloc[k:, perturbed.columns.get_loc("buy_volume")] *= 7
        a = vpin(df, volume_bucket_size=50, window=5)
        b = vpin(perturbed, volume_bucket_size=50, window=5)
        pd.testing.assert_series_equal(a.iloc[:k], b.iloc[:k])
        assert a.iloc[:k].notna().any()
