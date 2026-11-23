"""q-injection and strict-input regressions for live/ and data/ (no live q or pykx needed)."""

from __future__ import annotations

import sys
import types
from unittest.mock import MagicMock

import pytest

from medusa.live.order_publisher import OrderPublisher
from medusa.live.tick_subscriber import TickSubscriber


@pytest.fixture
def conn(monkeypatch):
    c = MagicMock()
    fake = types.ModuleType("pykx")
    fake.QConnection = MagicMock(return_value=c)
    monkeypatch.setitem(sys.modules, "pykx", fake)
    return c


ORDER = dict(
    order_id=1, exchange="coinbase", symbol="BTCUSD", side="buy",
    order_type="limit", price=5, volume=7, actor="strat",
)  # fmt: skip


@pytest.mark.parametrize(
    "field,bad",
    [
        ("exchange", 'x`; system "id"'),
        ("symbol", "BTC/USD"),
        ("symbol", "A\nB"),
        ("actor", "a b"),
        ("side", "BUY; drop"),
        ("side", "short"),
        ("order_type", "stop"),
        ("price", '1j; system "id"'),
        ("price", 1.5),
        ("volume", True),
        ("order_id", "1"),
    ],
)
def test_publish_order_rejects_bad_field(conn, field, bad):
    pub = OrderPublisher(tp_host="h", tp_port=1)
    with pytest.raises(ValueError):
        pub.publish_order(**{**ORDER, field: bad})
    conn.assert_not_called()


def test_publish_order_valid_sends_one_expression(conn):
    OrderPublisher(tp_host="h", tp_port=1).publish_order(**ORDER)
    assert conn.call_count == 1
    expr = conn.call_args.args[0]
    assert "`BTCUSD" in expr and "5j; 7j" in expr


@pytest.mark.parametrize("bad", ['marketData; system "id"', "t`x", ""])
def test_subscribe_rejects_bad_table(conn, bad):
    with pytest.raises(ValueError):
        TickSubscriber(tp_host="h", tp_port=1).subscribe(bad)
    conn.assert_not_called()


@pytest.mark.parametrize("bad", ["A`B", "A B", "A;B", "A\n"])
def test_subscribe_rejects_bad_symbol(conn, bad):
    with pytest.raises(ValueError):
        TickSubscriber(tp_host="h", tp_port=1).subscribe("marketData", symbols=["BTCUSD", bad])
    conn.assert_not_called()


def test_subscribe_builds_exact_symbol_list(conn):
    sub = TickSubscriber(tp_host="h", tp_port=1)
    sub.subscribe("marketData", symbols=["BTCUSD", "ETHUSD"])
    sub.subscribe("marketData")
    assert [c.args[0] for c in conn.call_args_list] == [
        ".u.sub[`marketData; `BTCUSD`ETHUSD]",
        ".u.sub[`marketData; `]",
    ]


def test_subscribe_single_symbol_is_enlisted(conn):
    TickSubscriber(tp_host="h", tp_port=1).subscribe("marketData", symbols=["BTCUSD"])
    assert conn.call_args.args[0] == ".u.sub[`marketData; enlist`BTCUSD]"


# --- equity loader (L4 + H19) -------------------------------------------------
from medusa.data.equity_kdb_loader import EquityKdbLoader, _validate_equity_symbol  # noqa: E402


@pytest.mark.parametrize("bad", ['1Min`; system "id"', "1Year", "", "1Day\n"])
def test_equity_load_bars_rejects_bad_timeframe(bad):
    loader = EquityKdbLoader()
    loader.query = MagicMock()
    with pytest.raises(ValueError):
        loader.load_bars("AAPL", "2024-01-01", "2024-01-31", timeframe=bad)
    loader.query.assert_not_called()


def test_equity_symbol_rejects_trailing_newline():
    with pytest.raises(ValueError):
        _validate_equity_symbol("AAPL\n")


def test_kdb_loader_symbol_rejects_trailing_newline():
    from medusa.data.kdb_loader import _SYMBOL_RE

    assert _SYMBOL_RE.fullmatch("BTCUSD\n") is None


# --- config (L4) --------------------------------------------------------------
def test_kdb_password_is_secret():
    from pydantic import SecretStr

    from medusa.utils.config import KdbConfig

    cfg = KdbConfig(password="hunter2")
    assert isinstance(cfg.password, SecretStr)
    assert "hunter2" not in repr(cfg) and "hunter2" not in str(cfg)


# --- alpaca (L4) ---------------------------------------------------------------
def test_alpaca_side_typo_is_rejected():
    from medusa.live.alpaca_paper import _normalize_side

    assert _normalize_side("BUY") == "buy"
    assert _normalize_side("sell") == "sell"
    with pytest.raises(ValueError):
        _normalize_side("byu")


def test_alpaca_period_1y_and_unknown():
    from medusa.live.alpaca_paper import _normalize_period

    assert _normalize_period("1Y") == "1Y"
    with pytest.raises(ValueError):
        _normalize_period("5Y")


def test_validate_symbol_rejects_trailing_newline():
    from medusa.data.validators import validate_symbol

    validate_symbol("AAPL")
    with pytest.raises(ValueError):
        validate_symbol("AAPL\n")


def test_order_types_match_the_q_definition():
    from medusa.data.q_safe import ORDER_TYPES

    assert ORDER_TYPES == {"market", "limit", "stop_loss", "take_profit"}


def test_q_long_accepts_numpy_ints_but_not_bool_or_float():
    import numpy as np

    from medusa.data.q_safe import q_long

    out = q_long(np.int64(5))
    assert out == 5 and type(out) is int
    assert q_long(np.int32(-3)) == -3
    for bad in (np.bool_(True), True, np.float64(1.0), 1.0, "1"):
        with pytest.raises(ValueError):
            q_long(bad)


# --- secrets, side and period normalisation -------------------------------------------------


@pytest.mark.parametrize(
    "module,cls", [("kdb_loader", "KdbDataLoader"), ("equity_kdb_loader", "EquityKdbLoader")]
)
def test_loader_passes_plain_password_to_pykx(monkeypatch, module, cls):
    import importlib

    from medusa.utils.config import KdbConfig

    fake = types.ModuleType("pykx")
    fake.QConnection = MagicMock()
    monkeypatch.setitem(sys.modules, "pykx", fake)
    loader = getattr(importlib.import_module(f"medusa.data.{module}"), cls)(
        KdbConfig(username="u", password="s3cret")
    )
    loader.connect()
    assert fake.QConnection.call_args.kwargs["password"] == "s3cret"
    assert type(fake.QConnection.call_args.kwargs["password"]) is str


def test_normalize_side():
    from medusa.live.alpaca_paper import _normalize_side

    assert _normalize_side("BUY") == "buy"
    assert _normalize_side("Sell") == "sell"
    for bad in ("buyy", "sel", "", "short"):
        with pytest.raises(ValueError):
            _normalize_side(bad)


@pytest.fixture
def paper_client():
    from unittest.mock import patch

    from medusa.live.alpaca_paper import AlpacaPaperClient

    with (
        patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True),
        patch("medusa.live.alpaca_paper.TradingClient") as tc,
    ):
        yield AlpacaPaperClient(api_key="k", secret_key="s"), tc.return_value


def test_submit_order_with_typo_side_is_rejected_not_sold(paper_client):
    client, api = paper_client
    with pytest.raises(ValueError):
        client.submit_order(symbol="AAPL", qty=1, side="buyy")
    api.submit_order.assert_not_called()


@pytest.mark.parametrize(
    "given,sent",
    [("1D", "1D"), ("1W", "1W"), ("1M", "1M"), ("3M", "3M"), ("1Y", "1A"), ("1A", "1A")],
)
def test_portfolio_history_period_is_sent_in_alpacas_tokens(paper_client, given, sent):
    client, api = paper_client
    api.get_portfolio_history.return_value = MagicMock(
        timestamp=[1704067200], equity=[1.0], profit_loss=[0.0], profit_loss_pct=[0.0]
    )
    client.get_portfolio_history(period=given, timeframe="1D")
    req = api.get_portfolio_history.call_args.kwargs["history_filter"]
    assert (req.period, req.timeframe) == (sent, "1D")


@pytest.mark.parametrize("bad", ["2Y", "1m", "", "all", "1M; drop"])
def test_portfolio_history_rejects_unknown_period(paper_client, bad):
    client, api = paper_client
    with pytest.raises(ValueError):
        client.get_portfolio_history(period=bad)
    api.get_portfolio_history.assert_not_called()
