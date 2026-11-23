"""ResilientKdbConnection retry policy and TickSubscriber idle behaviour (no live q or pykx)."""

from __future__ import annotations

import sys
import types
from unittest.mock import MagicMock

import pytest

from medusa.data import equity_kdb_loader, kdb_loader
from medusa.data.kdb_loader import ResilientKdbConnection
from medusa.live import tick_subscriber
from medusa.live.tick_subscriber import TickSubscriber


class QError(Exception):
    """Stand-in for a q evaluation error (e.g. 'type)."""


def _fake_pykx(monkeypatch, *connections):
    fake = types.ModuleType("pykx")
    fake.QConnection = MagicMock(side_effect=list(connections))
    fake.QError = QError
    monkeypatch.setitem(sys.modules, "pykx", fake)
    return fake


def test_missing_pykx_is_not_retried(monkeypatch):
    monkeypatch.setitem(sys.modules, "pykx", None)  # makes `import pykx` raise ImportError
    sleep = MagicMock()
    monkeypatch.setattr(kdb_loader.time, "sleep", sleep)
    with pytest.raises(ImportError):
        ResilientKdbConnection(max_retries=3).connect()
    sleep.assert_not_called()


def test_q_error_is_raised_not_rerun(monkeypatch):
    conn = MagicMock(side_effect=QError("type"))
    fake = _fake_pykx(monkeypatch, conn)
    rc = ResilientKdbConnection()
    with pytest.raises(QError):
        rc.query("1+`a")
    assert conn.call_count == 1  # evaluated once, never re-executed
    assert fake.QConnection.call_count == 1  # and no reconnect


def test_lost_connection_reconnects_and_reruns(monkeypatch):
    dead = MagicMock(side_effect=ConnectionResetError("reset"))
    live = MagicMock(return_value=42)
    fake = _fake_pykx(monkeypatch, dead, live)
    assert ResilientKdbConnection().query("x") == 42
    assert fake.QConnection.call_count == 2


def test_closed_ipc_connection_reconnects(monkeypatch):
    # pykx raises a bare RuntimeError (not OSError) when q has died
    dead = MagicMock(side_effect=RuntimeError("Attempted to use a closed IPC connection"))
    live = MagicMock(return_value=7)
    fake = _fake_pykx(monkeypatch, dead, live)
    rc = ResilientKdbConnection()
    assert rc.query("x") == 7
    assert fake.QConnection.call_count == 2
    assert rc._conn is live


def test_q_error_keeps_the_connection(monkeypatch):
    conn = MagicMock(side_effect=QError("type"))
    _fake_pykx(monkeypatch, conn)
    rc = ResilientKdbConnection()
    with pytest.raises(QError):
        rc.query("1+`a")
    assert rc._conn is conn


def test_equity_loader_shares_the_one_connection_class():
    assert equity_kdb_loader.ResilientKdbConnection is ResilientKdbConnection


def test_tick_listener_sleeps_when_idle(monkeypatch):
    sub = TickSubscriber(tp_host="h", tp_port=1)
    sub._conn = MagicMock()
    sub._conn.poll.side_effect = [None, None, KeyboardInterrupt]
    sleep = MagicMock()
    monkeypatch.setattr(tick_subscriber.time, "sleep", sleep)
    sub.start()
    assert sleep.call_count == 2
