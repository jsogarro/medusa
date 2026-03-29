"""Structural tests for the medusa package.

These tests verify package structure, imports, type annotations, and API
contracts. As the package grows, these tests ensure backward compatibility
and API stability.
"""

from __future__ import annotations

import inspect
from typing import get_type_hints

import pandas as pd
import pytest


def test_package_version() -> None:
    """Verify package version is accessible and correctly formatted."""
    import medusa

    assert medusa.__version__ == "0.1.0"
    assert isinstance(medusa.__version__, str)
    assert len(medusa.__version__.split(".")) == 3  # Semantic versioning


def test_package_exports() -> None:
    """Verify top-level package exports __all__ and includes version."""
    import medusa

    assert hasattr(medusa, "__all__")
    assert "__version__" in medusa.__all__


def test_backtest_module_imports() -> None:
    """Verify backtest module can be imported and exports Backtester."""
    from medusa.backtest import Backtester

    assert Backtester is not None
    assert inspect.isclass(Backtester)


def test_data_module_imports() -> None:
    """Verify data module can be imported and exports DataLoader."""
    from medusa.data import DataLoader

    assert DataLoader is not None
    assert inspect.isclass(DataLoader)


def test_backtester_initialization() -> None:
    """Verify Backtester can be instantiated with default and custom capital."""
    from medusa.backtest import Backtester

    # Default capital
    bt_default = Backtester()
    assert bt_default.initial_capital == 100_000.0
    assert bt_default.current_capital == 100_000.0
    assert bt_default.positions == {}

    # Custom capital
    bt_custom = Backtester(initial_capital=50_000.0)
    assert bt_custom.initial_capital == 50_000.0
    assert bt_custom.current_capital == 50_000.0


def test_backtester_type_annotations() -> None:
    """Verify Backtester methods have proper type annotations."""
    from medusa.backtest import Backtester

    # Check __init__ annotations
    init_hints = get_type_hints(Backtester.__init__)
    assert "initial_capital" in init_hints
    assert init_hints["initial_capital"] is float
    assert init_hints["return"] is type(None)

    # Check run() annotations
    run_hints = get_type_hints(Backtester.run)
    assert "data" in run_hints
    assert "strategy" in run_hints
    assert run_hints["return"] is pd.DataFrame


def test_data_loader_initialization() -> None:
    """Verify DataLoader can be instantiated with default and custom params."""
    from medusa.data import DataLoader

    # Default connection params
    dl_default = DataLoader()
    assert dl_default.kdb_host == "localhost"
    assert dl_default.kdb_port == 5000

    # Custom connection params
    dl_custom = DataLoader(kdb_host="192.168.1.100", kdb_port=5001)
    assert dl_custom.kdb_host == "192.168.1.100"
    assert dl_custom.kdb_port == 5001


def test_data_loader_type_annotations() -> None:
    """Verify DataLoader methods have proper type annotations."""
    from medusa.data import DataLoader

    # Check __init__ annotations
    init_hints = get_type_hints(DataLoader.__init__)
    assert "kdb_host" in init_hints
    assert init_hints["kdb_host"] is str
    assert "kdb_port" in init_hints
    assert init_hints["kdb_port"] is int

    # Check load_ohlcv() annotations
    load_hints = get_type_hints(DataLoader.load_ohlcv)
    assert "symbol" in load_hints
    assert load_hints["symbol"] is str
    assert load_hints["return"] is pd.DataFrame


def test_backtester_not_implemented() -> None:
    """Verify Backtester.run() raises NotImplementedError (stub)."""
    from medusa.backtest import Backtester

    bt = Backtester()
    df = pd.DataFrame()

    class DummyStrategy:
        def generate_signals(self, data: pd.DataFrame) -> pd.DataFrame:
            return data

    with pytest.raises(NotImplementedError, match="not yet implemented"):
        bt.run(df, DummyStrategy())


def test_data_loader_not_implemented() -> None:
    """Verify DataLoader.load_ohlcv() raises NotImplementedError (stub)."""
    from datetime import datetime

    from medusa.data import DataLoader

    dl = DataLoader()

    with pytest.raises(NotImplementedError, match="not yet implemented"):
        dl.load_ohlcv("BTCUSD", datetime(2024, 1, 1), datetime(2024, 1, 31))


def test_strategy_protocol_exists() -> None:
    """Verify Strategy protocol is defined in engine module."""
    from medusa.backtest.engine import Strategy

    assert Strategy is not None
    # Protocol should have generate_signals as an attribute
    assert hasattr(Strategy, "generate_signals")
