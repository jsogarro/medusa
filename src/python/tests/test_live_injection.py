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
