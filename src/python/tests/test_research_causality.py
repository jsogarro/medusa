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


def test_pipeline_rows_do_not_depend_on_later_bars():
    df = _random_walk(1500)
    k = 1450  # past the train/test boundary, so scaling is unaffected
    perturbed = df.copy()
    perturbed.iloc[k:, :] = perturbed.iloc[k:, :] * 3
    a = FeaturePipeline().run(df)
    b = FeaturePipeline().run(perturbed)
    np.testing.assert_array_equal(a["x_train"], b["x_train"])
    pd.testing.assert_series_equal(a["y_train"], b["y_train"])
    m = len(a["x_test"]) - 100  # rows well before k (feature windows + 1-bar target)
    np.testing.assert_array_equal(a["x_test"][:m], b["x_test"][:m])
    pd.testing.assert_series_equal(a["y_test"].iloc[:m], b["y_test"].iloc[:m])


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


# --- pairs trading: long/short separation and exits ---------------------------------------

_NAN = float("nan")


def _pairs_with_z(monkeypatch, z_values):
    """A pairs strategy whose hedge ratio is 1 and whose spread z-score is ``z_values``."""
    from medusa.strategies import pairs_trading

    idx = pd.date_range("2024-01-01", periods=len(z_values), freq="D")
    z = pd.Series(z_values, index=idx)
    ratio = pd.Series(np.where(z.isna(), np.nan, 1.0), index=idx)
    monkeypatch.setattr(PairsTradingStrategy, "_rolling_hedge_ratio", lambda s, p1, p2: ratio)
    monkeypatch.setattr(pairs_trading, "z_score_spread", lambda spread, window: z)
    data = pd.DataFrame({("A", "close"): 100.0, ("B", "close"): 50.0}, index=idx)
    return PairsTradingStrategy("A", "B"), data


# z -> (long entry, long exit, short entry, short exit); entry 2, exit 0, stop 3
_PAIRS_TABLE = [
    (_NAN, (False, True, False, True)),  # spread undefined: a position must be able to leave
    (-2.5, (True, False, False, True)),
    (-3.5, (False, True, False, True)),  # beyond the stop: no entry, stop out
    (-1.0, (False, False, False, True)),
    (0.0, (False, True, False, True)),
    (1.0, (False, True, False, False)),
    (2.5, (False, True, True, False)),
    (3.5, (False, True, False, True)),
]


def test_pairs_long_and_short_spread_signals_are_separate(monkeypatch):
    strat, data = _pairs_with_z(monkeypatch, [0.5] + [z for z, _ in _PAIRS_TABLE])
    le, lx = strat.generate_signals(data)
    se, sx = strat.generate_short_signals(data)
    got = list(zip(le, lx, se, sx))[1:]
    assert got == [expected for _, expected in _PAIRS_TABLE]


def test_pairs_position_can_exit_after_cointegration_breaks(monkeypatch):
    strat, data = _pairs_with_z(monkeypatch, [0.0, -2.5, -2.5] + [_NAN] * 5)
    le, lx = strat.generate_signals(data)
    assert le.iloc[1]
    assert lx.iloc[3:].all()  # no hedge ratio from bar 3 on: must flatten, never hold
    assert not le.iloc[3:].any()


def test_pairs_exits_when_real_cointegration_breaks():
    rng = np.random.default_rng(3)
    n, k = 500, 250
    common = np.cumsum(rng.normal(0, 0.5, n))
    a = 100 + common + rng.normal(0, 0.3, n)
    b = 50 + 0.5 * common + rng.normal(0, 0.15, n)
    b[k:] = 50 + np.cumsum(rng.normal(0, 3.0, n - k))  # B decouples from A
    data = pd.DataFrame(
        {("BTC", "close"): a, ("ETH", "close"): b},
        index=pd.date_range("2024-01-01", periods=n, freq="D"),
    )
    kw = dict(asset1="BTC", asset2="ETH", lookback=100, spread_window=30, retest_period=30)
    strat = PairsTradingStrategy(**kw)
    ratio = strat._rolling_hedge_ratio(data[("BTC", "close")], data[("ETH", "close")])
    assert ratio.iloc[100:k].notna().any() and ratio.iloc[-60:].isna().all()  # it does break
    le, lx = strat.generate_signals(data)
    se, sx = strat.generate_short_signals(data)
    assert lx[ratio.isna()].all() and sx[ratio.isna()].all()
    assert not le[ratio.isna()].any() and not se[ratio.isna()].any()


def test_pairs_short_spread_signal_opens_a_short_position(monkeypatch):
    from medusa.backtest.vectorbt_engine import VectorBTEngine

    strat, data = _pairs_with_z(monkeypatch, [0.5, 2.5, 1.0, 1.0, -0.5, 0.5])
    pf = VectorBTEngine(asset_class="crypto").run_strategy(data[("A", "close")], strat, data)
    assert pf.trades.records_readable["Direction"].tolist() == ["Short"]


def test_pairs_long_spread_signal_opens_a_long_position(monkeypatch):
    from medusa.backtest.vectorbt_engine import VectorBTEngine

    strat, data = _pairs_with_z(monkeypatch, [-0.5, -2.5, -1.0, -1.0, 0.5, -0.5])
    pf = VectorBTEngine(asset_class="crypto").run_strategy(data[("A", "close")], strat, data)
    assert pf.trades.records_readable["Direction"].tolist() == ["Long"]


def test_pairs_short_signals_do_not_depend_on_later_bars():
    data = _pair()
    k = 300
    perturbed = data.copy()
    perturbed.iloc[k:, 0] += np.linspace(0, 60, len(data) - k)
    kw = dict(asset1="BTC", asset2="ETH", lookback=100, spread_window=30, retest_period=30)
    a = PairsTradingStrategy(**kw).generate_short_signals(data)
    b = PairsTradingStrategy(**kw).generate_short_signals(perturbed)
    for s1, s2 in zip(a, b):
        pd.testing.assert_series_equal(s1.iloc[:k], s2.iloc[:k])
    assert a[0].iloc[:k].any() or a[1].iloc[:k].any()  # not vacuous


# --- meta-labeling: short wiring, exits, confidence filter, barriers ------------------------


class _ReturnSignModel:
    """Primary model that follows the sign of the latest 1-bar return (causal)."""

    def predict(self, features):
        return np.sign(features["return_1d"].to_numpy())


class _ConstProba:
    def __init__(self, p: float) -> None:
        self.p = p

    def predict_proba(self, features):
        p = np.full(len(features), self.p)
        return np.column_stack([1 - p, p])


def test_short_primary_signal_opens_a_short_position():
    from medusa.backtest.vectorbt_engine import VectorBTEngine

    data = _ohlcv()
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(-1))
    pf = VectorBTEngine(asset_class="crypto").run_strategy(data["close"], strat, data)
    assert set(pf.trades.records_readable["Direction"]) == {"Short"}


def test_long_primary_signal_opens_a_long_position():
    from medusa.backtest.vectorbt_engine import VectorBTEngine

    data = _ohlcv()
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(1))
    pf = VectorBTEngine(asset_class="crypto").run_strategy(data["close"], strat, data)
    assert set(pf.trades.records_readable["Direction"]) == {"Long"}


def test_meta_short_signals_follow_primary_and_exit_when_it_stops_saying_short():
    data = _ohlcv()
    strat = MLMetaLabelingStrategy(primary_model=_ReturnSignModel())
    short_entries, short_exits = strat.generate_short_signals(data)
    ret = data["close"].pct_change().iloc[25:]  # skip the feature warm-up
    short_entries, short_exits = short_entries.iloc[25:], short_exits.iloc[25:]
    assert short_entries[ret < 0].all() and not short_entries[ret >= 0].any()
    assert short_exits[ret > 0].all() and not short_exits[ret < 0].any()


def test_meta_long_exits_when_primary_turns_short_not_only_flat():
    data = _ohlcv()
    _, exits = MLMetaLabelingStrategy(primary_model=_ReturnSignModel()).generate_signals(data)
    ret = data["close"].pct_change().iloc[25:]  # skip the feature warm-up
    exits = exits.iloc[25:]
    assert exits[ret < 0].all()  # primary == -1 must close a long
    assert not exits[ret > 0].any()


def test_meta_confidence_filter_applies_to_short_entries():
    data = _ohlcv()
    low = MLMetaLabelingStrategy(primary_model=_ConstModel(-1), meta_model=_ConstProba(0.1))
    high = MLMetaLabelingStrategy(primary_model=_ConstModel(-1), meta_model=_ConstProba(0.9))
    assert not low.generate_short_entries(data).any()
    assert high.generate_short_entries(data).any()


def test_meta_short_signals_do_not_depend_on_later_bars():
    data = _ohlcv(200)
    k = 150
    perturbed = data.copy()
    perturbed.iloc[k:, perturbed.columns.get_loc("close")] *= 1.5
    strat = MLMetaLabelingStrategy(primary_model=_ReturnSignModel())
    a = strat.generate_short_signals(data)
    b = strat.generate_short_signals(perturbed)
    for s1, s2 in zip(a, b):
        pd.testing.assert_series_equal(s1.iloc[:k], s2.iloc[:k])
    assert a[0].iloc[:k].any()


def test_triple_barrier_simultaneous_barriers_resolve_to_stop():
    prices = pd.Series([100.0] * 6)  # return is exactly 0: both zero-width barriers are hit at once
    strat = MLMetaLabelingStrategy(
        primary_model=_ConstModel(1), take_profit_pct=0.0, stop_loss_pct=0.0, max_holding_bars=3
    )
    labels = strat._create_triple_barrier_labels(prices, pd.Series(1, index=prices.index))
    assert labels.iloc[0] == -1


def test_triple_barrier_time_out_is_labelled_by_sign_of_final_return():
    strat = MLMetaLabelingStrategy(primary_model=_ConstModel(1), max_holding_bars=3)
    side = pd.Series(1, index=range(6))
    up = pd.Series([100.0, 100.2, 100.4, 100.6, 100.6, 100.6])  # +0.6%: inside both barriers
    down = pd.Series([100.0, 99.8, 99.6, 99.4, 99.4, 99.4])  # -0.6%
    assert strat._create_triple_barrier_labels(up, side).iloc[0] == 1
    assert strat._create_triple_barrier_labels(down, side).iloc[0] == -1
