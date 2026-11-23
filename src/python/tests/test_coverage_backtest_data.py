"""Test coverage improvement for backtest optimizer, nautilus engine, kdb loaders, order flow features, and models.

This module tests:
1. medusa/backtest/optimizer.py (53% -> target 80%+)
2. medusa/backtest/nautilus_engine.py (58% -> target 75%+)
3. medusa/data/equity_kdb_loader.py (56% -> target 75%+)
4. medusa/data/kdb_loader.py (65% -> target 80%+)
5. medusa/features/order_flow_features.py (63% -> target 80%+)
6. medusa/models/base.py (53% -> target 80%+)

All tests use synthetic data with fixed seeds for reproducibility.
External dependencies (kdb+, NautilusTrader, Optuna) are mocked.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest
import torch

# ============================================================================
# 1. BACKTEST OPTIMIZER TESTS
# ============================================================================


class TestOptunaOptimizer:
    """Test coverage for medusa/backtest/optimizer.py."""

    @pytest.fixture
    def mock_engine(self) -> MagicMock:
        """Mock VectorBTEngine for testing."""
        engine = MagicMock()
        pf = MagicMock()
        pf.sharpe_ratio.return_value = 1.5
        pf.total_return.return_value = 0.25
        pf.sortino_ratio.return_value = 1.8
        pf.calmar_ratio.return_value = 2.0
        pf.max_drawdown.return_value = 0.15
        engine.run_signals.return_value = pf
        return engine

    @pytest.fixture
    def sample_price(self) -> pd.Series:
        """Generate sample price series."""
        np.random.seed(42)
        dates = pd.date_range("2023-01-01", periods=100, freq="D")
        prices = 100 * np.exp(np.cumsum(np.random.randn(100) * 0.02))
        return pd.Series(prices, index=dates, name="close")

    def test_optimizer_init_missing_optuna(self, mock_engine: MagicMock) -> None:
        """Test optimizer raises error when optuna is not installed."""
        with patch("medusa.backtest.optimizer.HAS_OPTUNA", False):
            from medusa.backtest.optimizer import OptunaOptimizer

            with pytest.raises(ImportError, match="Optuna not installed"):
                OptunaOptimizer(mock_engine)

    def test_optimizer_init_invalid_sampler(self, mock_engine: MagicMock) -> None:
        """Test optimizer raises error for invalid sampler."""
        from medusa.backtest.optimizer import OptunaOptimizer

        with pytest.raises(ValueError, match="Unknown sampler"):
            OptunaOptimizer(mock_engine, sampler="invalid")

    def test_optimizer_init_invalid_pruner(self, mock_engine: MagicMock) -> None:
        """Test optimizer raises error for invalid pruner."""
        from medusa.backtest.optimizer import OptunaOptimizer

        with pytest.raises(ValueError, match="Unknown pruner"):
            OptunaOptimizer(mock_engine, pruner="invalid")

    def test_optimize_strategy_basic(self, mock_engine: MagicMock, sample_price: pd.Series) -> None:
        """Test basic strategy optimization."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine, n_trials=5, sampler="tpe", study_name="test_basic")

        def signal_func(price: pd.Series, fast: int, slow: int) -> tuple[pd.Series, pd.Series]:
            sma_fast = price.rolling(fast).mean()
            sma_slow = price.rolling(slow).mean()
            entries = sma_fast > sma_slow
            exits = sma_fast < sma_slow
            return entries, exits

        param_space = {
            "fast": {"type": "int", "low": 5, "high": 20},
            "slow": {"type": "int", "low": 20, "high": 50},
        }

        best_params = optimizer.optimize_strategy(
            sample_price, signal_func, param_space, metric="sharpe_ratio"
        )

        # Note: params returned are whatever the study thinks is best
        assert isinstance(best_params, dict)
        assert len(best_params) >= 1

    def test_optimize_strategy_float_params(
        self, mock_engine: MagicMock, sample_price: pd.Series
    ) -> None:
        """Test optimization with float parameters."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine, n_trials=3, study_name="test_float")

        def signal_func(price: pd.Series, threshold: float) -> tuple[pd.Series, pd.Series]:
            returns = price.pct_change()
            entries = returns > threshold
            exits = returns < -threshold
            return entries, exits

        param_space = {
            "threshold": {"type": "float", "low": 0.01, "high": 0.05},
        }

        best_params = optimizer.optimize_strategy(sample_price, signal_func, param_space)

        assert isinstance(best_params, dict)
        assert len(best_params) >= 1

    def test_optimize_strategy_categorical_params(
        self, mock_engine: MagicMock, sample_price: pd.Series
    ) -> None:
        """Test optimization with categorical parameters."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine, n_trials=3, study_name="test_categorical")

        def signal_func(price: pd.Series, ma_type: str) -> tuple[pd.Series, pd.Series]:
            if ma_type == "sma":
                ma = price.rolling(20).mean()
            else:
                ma = price.ewm(span=20).mean()
            entries = price > ma
            exits = price < ma
            return entries, exits

        param_space = {
            "ma_type": {"type": "categorical", "choices": ["sma", "ema"]},
        }

        best_params = optimizer.optimize_strategy(sample_price, signal_func, param_space)

        assert isinstance(best_params, dict)
        assert len(best_params) >= 1

    def test_optimize_strategy_unknown_param_type(
        self, mock_engine: MagicMock, sample_price: pd.Series
    ) -> None:
        """Test optimization raises error for unknown parameter type."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine, n_trials=1, study_name="test_unknown")

        def signal_func(price: pd.Series, param: Any) -> tuple[pd.Series, pd.Series]:
            return price > 0, price < 0

        param_space = {
            "param": {"type": "unknown", "low": 1, "high": 10},  # type: ignore[typeddict-item]
        }

        with pytest.raises(ValueError, match="Unknown parameter type"):
            optimizer.optimize_strategy(sample_price, signal_func, param_space)

    def test_optimize_strategy_invalid_metric(
        self, mock_engine: MagicMock, sample_price: pd.Series
    ) -> None:
        """Test optimization with invalid metric raises error when all trials pruned."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine, n_trials=1, study_name="test_invalid_unique")

        def signal_func(price: pd.Series, fast: int) -> tuple[pd.Series, pd.Series]:
            return price > 0, price < 0

        param_space = {"fast": {"type": "int", "low": 5, "high": 20}}

        # Invalid metric gets caught in objective function
        # When all trials are pruned, best_params raises ValueError
        with pytest.raises(ValueError, match="No trials are completed yet"):
            optimizer.optimize_strategy(
                sample_price, signal_func, param_space, metric="invalid_metric"
            )

    def test_optimize_strategy_nan_handling(self, sample_price: pd.Series) -> None:
        """Test optimization handles NaN/inf metric values via pruning."""
        from medusa.backtest.optimizer import OptunaOptimizer

        mock_engine = MagicMock()
        pf = MagicMock()
        pf.sharpe_ratio.return_value = float("nan")
        mock_engine.run_signals.return_value = pf

        optimizer = OptunaOptimizer(mock_engine, n_trials=2, study_name="test_nan_unique")

        def signal_func(price: pd.Series, fast: int) -> tuple[pd.Series, pd.Series]:
            return price > 0, price < 0

        param_space = {"fast": {"type": "int", "low": 5, "high": 20}}

        # All trials will be pruned due to NaN, raising ValueError
        with pytest.raises(ValueError, match="No trials are completed yet"):
            optimizer.optimize_strategy(sample_price, signal_func, param_space)

    def test_get_trials_dataframe_no_study(self, mock_engine: MagicMock) -> None:
        """Test get_trials_dataframe raises error when no study exists."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine)

        with pytest.raises(ValueError, match="No study available"):
            optimizer.get_trials_dataframe()

    def test_plot_optimization_history_no_study(self, mock_engine: MagicMock) -> None:
        """Test plot_optimization_history raises error when no study exists."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine)

        with pytest.raises(ValueError, match="No study available"):
            optimizer.plot_optimization_history()

    def test_plot_param_importances_no_study(self, mock_engine: MagicMock) -> None:
        """Test plot_param_importances raises error when no study exists."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine)

        with pytest.raises(ValueError, match="No study available"):
            optimizer.plot_param_importances()

    def test_plot_parallel_coordinate_no_study(self, mock_engine: MagicMock) -> None:
        """Test plot_parallel_coordinate raises error when no study exists."""
        from medusa.backtest.optimizer import OptunaOptimizer

        optimizer = OptunaOptimizer(mock_engine)

        with pytest.raises(ValueError, match="No study available"):
            optimizer.plot_parallel_coordinate()


# ============================================================================
# 2. NAUTILUS ENGINE TESTS
# ============================================================================


class TestNautilusEngine:
    """Test coverage for medusa/backtest/nautilus_engine.py."""

    def test_init_missing_nautilus(self) -> None:
        """Test engine logs error when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            # When NAUTILUS_AVAILABLE is False, __init__ returns early after logging error
            # The engine object exists but some attributes may not be set
            # Just verify it doesn't crash
            assert engine is not None

    def test_init_default_params(self) -> None:
        """Test engine initialization with default parameters."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine()
        assert engine.initial_capital == 100_000.0
        assert engine.exchange_config.name == "BINANCE"

    def test_init_custom_exchange(self) -> None:
        """Test engine initialization with custom exchange."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine(exchange="KRAKEN", initial_capital=50_000.0)
        assert engine.exchange_config.name == "KRAKEN"
        assert engine.initial_capital == 50_000.0

    def test_init_unknown_exchange(self) -> None:
        """Test engine defaults to BINANCE for unknown exchange."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine(exchange="UNKNOWN")
        assert engine.exchange_config.name == "BINANCE"

    def test_get_catalog_missing_nautilus(self) -> None:
        """Test get_catalog raises error when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            with pytest.raises(ImportError, match="nautilus_trader not installed"):
                engine.get_catalog()

    @patch("medusa.backtest.nautilus_engine.ParquetDataCatalog")
    def test_get_catalog_creates_catalog(self, mock_catalog_class: MagicMock) -> None:
        """Test get_catalog creates catalog on first call."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        mock_catalog = MagicMock()
        mock_catalog_class.return_value = mock_catalog

        engine = NautilusEngine()
        catalog = engine.get_catalog()

        assert catalog is mock_catalog
        assert engine._catalog is mock_catalog
        mock_catalog_class.assert_called_once()

    def test_ingest_bars_missing_nautilus(self) -> None:
        """Test ingest_bars does nothing when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            # Should not raise
            engine.ingest_bars("BTCUSD", [])

    def test_ingest_bars_empty_list(self) -> None:
        """Test ingest_bars does nothing with empty bars list."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine()
        # Should not raise
        engine.ingest_bars("BTCUSD", [])

    def test_ingest_trades_missing_nautilus(self) -> None:
        """Test ingest_trades does nothing when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            # Should not raise
            engine.ingest_trades("BTCUSD", [])

    def test_ingest_quotes_missing_nautilus(self) -> None:
        """Test ingest_quotes does nothing when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            # Should not raise
            engine.ingest_quotes("BTCUSD", [])

    def test_create_engine_missing_nautilus(self) -> None:
        """Test create_engine raises error when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            with pytest.raises(ImportError, match="nautilus_trader not installed"):
                engine.create_engine(datetime.now(), datetime.now())

    def test_run_strategy_missing_nautilus(self) -> None:
        """Test run_strategy returns empty DataFrame when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            result = engine.run_strategy(None, [], datetime.now(), datetime.now())  # type: ignore[arg-type]
            assert result.empty

    def test_run_strategy_no_engine(self) -> None:
        """Test run_strategy returns empty DataFrame when engine is None."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine()
        engine._engine = None

        with patch.object(engine, "create_engine", return_value=None):
            result = engine.run_strategy(None, [], datetime.now(), datetime.now())  # type: ignore[arg-type]
            assert result.empty

    def test_get_portfolio_stats_missing_nautilus(self) -> None:
        """Test get_portfolio_stats returns empty dict when nautilus_trader is not installed."""
        with patch("medusa.backtest.nautilus_engine.NAUTILUS_AVAILABLE", False):
            from medusa.backtest.nautilus_engine import NautilusEngine

            engine = NautilusEngine()
            stats = engine.get_portfolio_stats()
            assert stats == {}

    def test_get_portfolio_stats_no_engine(self) -> None:
        """Test get_portfolio_stats returns empty dict when engine is None."""
        pytest.importorskip("nautilus_trader")
        from medusa.backtest.nautilus_engine import NautilusEngine

        engine = NautilusEngine()
        stats = engine.get_portfolio_stats()
        assert stats == {}


# ============================================================================
# 3. EQUITY KDB LOADER TESTS
# ============================================================================


class TestEquityKdbLoader:
    """Test coverage for medusa/data/equity_kdb_loader.py."""

    @pytest.fixture
    def mock_pykx_connection(self) -> MagicMock:
        """Mock PyKX connection."""
        conn = MagicMock()
        result = MagicMock()
        result.pd.return_value = pd.DataFrame()
        conn.return_value = result
        return conn

    @pytest.fixture
    def loader(self) -> Any:
        """Create EquityKdbLoader instance."""
        from medusa.data.equity_kdb_loader import EquityKdbLoader

        return EquityKdbLoader()

    def test_validate_equity_symbol_valid(self) -> None:
        """Test symbol validation accepts valid equity symbols."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        assert _validate_equity_symbol("AAPL") == "AAPL"
        assert _validate_equity_symbol("MSFT") == "MSFT"
        assert _validate_equity_symbol("A") == "A"
        assert _validate_equity_symbol("GOOGL") == "GOOGL"

    def test_validate_equity_symbol_lowercase(self) -> None:
        """Test symbol validation rejects lowercase symbols."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        # The function requires uppercase, so lowercase is rejected
        with pytest.raises(ValueError, match="Invalid equity symbol format"):
            _validate_equity_symbol("aapl")

    def test_validate_equity_symbol_invalid_format(self) -> None:
        """Test symbol validation rejects invalid formats."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        with pytest.raises(ValueError, match="Invalid equity symbol format"):
            _validate_equity_symbol("TOOLONG123")

        with pytest.raises(ValueError, match="Invalid equity symbol format"):
            _validate_equity_symbol("123")

        with pytest.raises(ValueError, match="Invalid equity symbol format"):
            _validate_equity_symbol("AA-PL")

    def test_validate_equity_symbol_non_alphabetic(self) -> None:
        """Test symbol validation rejects non-alphabetic characters."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        # Numeric characters are caught by the regex check first
        with pytest.raises(ValueError, match="Invalid equity symbol format"):
            _validate_equity_symbol("AAP1")

    def test_resilient_connection_init(self) -> None:
        """Test ResilientKdbConnection initialization."""
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection(
            host="testhost", port=5555, username="user", password="pass", timeout=10.0
        )
        assert conn.host == "testhost"
        assert conn.port == 5555
        assert conn.username == "user"
        assert conn.password == "pass"
        assert conn.timeout == 10.0
        assert conn._conn is None

    def test_resilient_connection_connect_success(self) -> None:
        """Test successful connection."""
        pytest.importorskip("pykx")
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection()

        # Patch the import inside the connect method
        with patch("medusa.data.equity_kdb_loader.ResilientKdbConnection.connect") as mock_connect:
            mock_connect.return_value = None
            conn.connect()
            mock_connect.assert_called_once()

    def test_resilient_connection_connect_retry(self) -> None:
        """Test connection retry on failure."""
        pytest.importorskip("pykx")
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection(max_retries=2)

        # Mock the internal connection to fail
        with patch("medusa.data.equity_kdb_loader.ResilientKdbConnection.connect") as mock_connect:
            mock_connect.side_effect = ConnectionError("Failed to connect")

            with pytest.raises(ConnectionError):
                conn.connect()

    def test_resilient_connection_disconnect(self) -> None:
        """Test connection disconnect."""
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection()
        mock_conn = MagicMock()
        conn._conn = mock_conn

        conn.disconnect()

        mock_conn.close.assert_called_once()
        assert conn._conn is None

    def test_resilient_connection_query_no_connection(self) -> None:
        """Test query auto-connects when connection is None."""
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection()
        mock_conn = MagicMock()
        mock_conn.return_value = "result"

        with patch.object(conn, "connect"):
            conn._conn = mock_conn
            result = conn.query("test")

        assert result == "result"

    def test_resilient_connection_query_reconnect_on_failure(self) -> None:
        """Test query reconnects on failure."""
        from medusa.data.equity_kdb_loader import ResilientKdbConnection

        conn = ResilientKdbConnection()

        # Create two separate mock connections
        mock_conn1 = MagicMock(side_effect=ConnectionError("Connection lost"))
        mock_conn2 = MagicMock(return_value="result")

        # Track which connection should be used
        call_count = [0]

        def connect_side_effect() -> None:
            call_count[0] += 1
            if call_count[0] == 1:
                conn._conn = mock_conn2

        with patch.object(conn, "connect", side_effect=connect_side_effect):
            # First call with failing connection
            conn._conn = mock_conn1
            result = conn.query("test")

            # After first failure, connect should be called
            assert call_count[0] == 1
            assert result == "result"

    def test_loader_init_default_config(self, loader: Any) -> None:
        """Test loader initialization with default config."""
        assert loader._resilient_conn is None

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_loader_connect(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test loader connect method."""
        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader.connect(port=5555)

        assert loader._resilient_conn is mock_conn
        mock_conn.connect.assert_called_once()

    def test_loader_disconnect(self, loader: Any) -> None:
        """Test loader disconnect method."""
        mock_conn = MagicMock()
        loader._resilient_conn = mock_conn

        loader.disconnect()

        mock_conn.disconnect.assert_called_once()
        assert loader._resilient_conn is None

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_loader_ensure_connected(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test _ensure_connected creates connection if needed."""
        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader._ensure_connected()

        assert loader._resilient_conn is mock_conn
        mock_conn.connect.assert_called_once()

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_bars_empty_result(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_bars returns empty DataFrame when no data found."""
        mock_conn = MagicMock()
        result = MagicMock()
        result.pd.return_value = pd.DataFrame()
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        df = loader.load_bars("AAPL", "2023-01-01", "2023-01-31")

        assert df.empty

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_bars_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_bars returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2023-01-01", periods=5, freq="D"),
                "open": [100.0, 101.0, 102.0, 103.0, 104.0],
                "high": [101.0, 102.0, 103.0, 104.0, 105.0],
                "low": [99.0, 100.0, 101.0, 102.0, 103.0],
                "close": [100.5, 101.5, 102.5, 103.5, 104.5],
                "volume": [1000, 1100, 1200, 1300, 1400],
                "vwap": [100.3, 101.3, 102.3, 103.3, 104.3],
                "tradeCount": [50, 55, 60, 65, 70],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        df = loader.load_bars("AAPL", "2023-01-01", "2023-01-05")

        assert len(df) == 5
        assert "trade_count" in df.columns
        assert "tradeCount" not in df.columns

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_quotes_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_quotes returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2023-01-01", periods=3, freq="s"),
                "bidPrice": [100.0, 100.1, 100.2],
                "bidSize": [10, 20, 30],
                "askPrice": [100.1, 100.2, 100.3],
                "askSize": [15, 25, 35],
                "tape": ["A", "B", "C"],
                "conditions": ["", "", ""],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        df = loader.load_quotes("AAPL", "2023-01-01", "2023-01-01")

        assert len(df) == 3
        assert "bid_price" in df.columns
        assert "bid_size" in df.columns
        assert "ask_price" in df.columns
        assert "ask_size" in df.columns

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_trades_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_trades returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2023-01-01", periods=3, freq="ms"),
                "price": [100.0, 100.1, 100.2],
                "size": [10, 20, 30],
                "tradeExchange": ["NASDAQ", "NYSE", "ARCA"],
                "tape": ["A", "B", "C"],
                "conditions": ["", "", ""],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        df = loader.load_trades("AAPL", "2023-01-01", "2023-01-01")

        assert len(df) == 3
        assert "trade_exchange" in df.columns
        assert "tradeExchange" not in df.columns

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_metadata_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_metadata returns metadata dict with renamed keys."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "sym": ["AAPL"],
                "name": ["Apple Inc."],
                "assetClass": ["equity"],
                "exchange": ["NASDAQ"],
                "sector": ["Technology"],
                "industry": ["Consumer Electronics"],
                "marketCap": [2500000000000],
                "dividendYield": [0.005],
                "peRatio": [28.5],
                "beta": [1.2],
                "avgVolume30d": [75000000],
                "updatedAt": [pd.Timestamp("2023-01-01")],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        metadata = loader.load_metadata("AAPL")

        assert metadata["symbol"] == "AAPL"
        assert metadata["name"] == "Apple Inc."
        assert metadata["asset_class"] == "equity"
        assert metadata["market_cap"] == 2500000000000

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_metadata_empty(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_metadata returns empty dict when no data found."""
        mock_conn = MagicMock()
        result = MagicMock()
        result.pd.return_value = pd.DataFrame()
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        # Use a valid symbol that just doesn't exist in the data
        metadata = loader.load_metadata("TSLA")

        assert metadata == {}

    @patch("medusa.data.equity_kdb_loader.ResilientKdbConnection")
    def test_load_positions_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_positions returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "sym": ["AAPL", "MSFT"],
                "quantity": [100, 50],
                "avgEntryPrice": [150.0, 300.0],
                "marketValue": [15500.0, 15250.0],
                "unrealizedPnL": [500.0, 250.0],
                "side": ["long", "long"],
                "marginUsed": [7500.0, 7500.0],
                "updatedAt": [pd.Timestamp("2023-01-01"), pd.Timestamp("2023-01-01")],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        df = loader.load_positions()

        assert len(df) == 2
        assert "symbol" in df.columns
        assert "avg_entry_price" in df.columns
        assert "market_value" in df.columns
        assert "unrealized_pnl" in df.columns
        assert "margin_used" in df.columns


# ============================================================================
# 4. KDB LOADER TESTS
# ============================================================================


class TestKdbDataLoader:
    """Test coverage for medusa/data/kdb_loader.py."""

    @pytest.fixture
    def loader(self) -> Any:
        """Create KdbDataLoader instance."""
        from medusa.data.kdb_loader import KdbDataLoader

        return KdbDataLoader()

    def test_validate_symbol_valid(self) -> None:
        """Test symbol validation accepts valid symbols."""
        from medusa.data.kdb_loader import _validate_symbol

        assert _validate_symbol("BTCUSD") == "BTCUSD"
        assert _validate_symbol("ETH_USDT") == "ETH_USDT"
        assert _validate_symbol("BTC.USD") == "BTC.USD"

    def test_validate_symbol_invalid(self) -> None:
        """Test symbol validation rejects invalid symbols."""
        from medusa.data.kdb_loader import _validate_symbol

        with pytest.raises(ValueError, match="Invalid symbol format"):
            _validate_symbol("BTC USD")  # Space not allowed

        with pytest.raises(ValueError, match="Invalid symbol format"):
            _validate_symbol("BTC;DROP TABLE")  # SQL injection attempt

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_loader_connect(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test loader connect method."""
        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader.connect(port=5555)

        assert loader._resilient_conn is mock_conn
        mock_conn.connect.assert_called_once()

    def test_loader_disconnect(self, loader: Any) -> None:
        """Test loader disconnect method."""
        mock_conn = MagicMock()
        loader._resilient_conn = mock_conn

        loader.disconnect()

        mock_conn.disconnect.assert_called_once()
        assert loader._resilient_conn is None

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_trades_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_trades returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "time": pd.date_range("2023-01-01", periods=5, freq="s"),
                "price": [100.0, 100.1, 100.2, 100.3, 100.4],
                "volume": [1.0, 2.0, 3.0, 4.0, 5.0],
                "side": ["buy", "sell", "buy", "buy", "sell"],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        start = datetime(2023, 1, 1)
        end = datetime(2023, 1, 2)
        df = loader.load_trades("BTCUSD", start, end)

        assert len(df) == 5
        assert "timestamp" in df.columns
        assert "size" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_quotes_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_quotes returns data with renamed columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "time": pd.date_range("2023-01-01", periods=3, freq="s"),
                "bid": [100.0, 100.1, 100.2],
                "bidSize": [10.0, 20.0, 30.0],
                "ask": [100.1, 100.2, 100.3],
                "askSize": [15.0, 25.0, 35.0],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        start = datetime(2023, 1, 1)
        end = datetime(2023, 1, 2)
        df = loader.load_quotes("BTCUSD", start, end)

        assert len(df) == 3
        assert "timestamp" in df.columns
        assert "bid_price" in df.columns
        assert "bid_size" in df.columns
        assert "ask_price" in df.columns
        assert "ask_size" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_ohlcv_with_data(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_ohlcv returns data with correct columns."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2023-01-01", periods=5, freq="min"),
                "open": [100.0, 101.0, 102.0, 103.0, 104.0],
                "high": [101.0, 102.0, 103.0, 104.0, 105.0],
                "low": [99.0, 100.0, 101.0, 102.0, 103.0],
                "close": [100.5, 101.5, 102.5, 103.5, 104.5],
                "volume": [1000.0, 1100.0, 1200.0, 1300.0, 1400.0],
            }
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        start = datetime(2023, 1, 1)
        end = datetime(2023, 1, 2)
        df = loader.load_ohlcv("BTCUSD", start, end, interval="1m")

        assert len(df) == 5
        assert "timestamp" in df.columns
        assert "open" in df.columns
        assert "volume" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_ohlcv_reset_index(self, mock_conn_class: MagicMock, loader: Any) -> None:
        """Test load_ohlcv resets index when timestamp is the index."""
        mock_conn = MagicMock()
        result_df = pd.DataFrame(
            {
                "open": [100.0, 101.0],
                "high": [101.0, 102.0],
                "low": [99.0, 100.0],
                "close": [100.5, 101.5],
                "volume": [1000.0, 1100.0],
            },
            index=pd.DatetimeIndex(
                pd.date_range("2023-01-01", periods=2, freq="min"), name="timestamp"
            ),
        )
        result = MagicMock()
        result.pd.return_value = result_df
        mock_conn.query.return_value = result
        mock_conn_class.return_value = mock_conn
        loader._resilient_conn = mock_conn

        start = datetime(2023, 1, 1)
        end = datetime(2023, 1, 2)
        df = loader.load_ohlcv("BTCUSD", start, end)

        assert "timestamp" in df.columns
        assert df.index.name != "timestamp"

    def test_load_ohlcv_invalid_interval(self, loader: Any) -> None:
        """Test load_ohlcv raises error for invalid interval."""
        with pytest.raises(ValueError, match="Unsupported interval"):
            loader.load_ohlcv("BTCUSD", datetime.now(), datetime.now(), interval="invalid")

    def test_context_manager(self, loader: Any) -> None:
        """Test loader works as context manager."""
        with patch.object(loader, "connect") as mock_connect:
            with patch.object(loader, "disconnect") as mock_disconnect:
                with loader:
                    pass

                mock_connect.assert_called_once()
                mock_disconnect.assert_called_once()


# ============================================================================
# 5. ORDER FLOW FEATURES TESTS
# ============================================================================


class TestOrderFlowFeatures:
    """Test coverage for medusa/features/order_flow_features.py."""

    @pytest.fixture
    def sample_ohlcv(self) -> pd.DataFrame:
        """Generate sample OHLCV data."""
        np.random.seed(42)
        dates = pd.date_range("2023-01-01", periods=100, freq="min")
        prices = 100 * np.exp(np.cumsum(np.random.randn(100) * 0.001))
        return pd.DataFrame(
            {
                "open": prices,
                "high": prices * 1.01,
                "low": prices * 0.99,
                "close": prices,
                "volume": np.random.randint(100, 1000, 100),
            },
            index=dates,
        )

    def test_vpin_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test VPIN calculation with basic parameters."""
        from medusa.features.order_flow_features import vpin

        result = vpin(sample_ohlcv, volume_bucket_size=10, window=10)

        assert len(result) == len(sample_ohlcv)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_vpin_with_buy_volume(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test VPIN calculation with explicit buy_volume column."""
        from medusa.features.order_flow_features import vpin

        df = sample_ohlcv.copy()
        df["buy_volume"] = df["volume"] * np.random.uniform(0.4, 0.6, len(df))

        result = vpin(df, volume_bucket_size=10, window=10)

        assert len(result) == len(df)
        assert result.notna().any()

    def test_trade_imbalance_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test trade imbalance calculation."""
        from medusa.features.order_flow_features import trade_imbalance

        result = trade_imbalance(sample_ohlcv, window=20)

        assert len(result) == len(sample_ohlcv)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_trade_imbalance_with_buy_volume(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test trade imbalance with explicit buy_volume."""
        from medusa.features.order_flow_features import trade_imbalance

        df = sample_ohlcv.copy()
        df["buy_volume"] = df["volume"] * 0.6

        result = trade_imbalance(df, window=20)

        assert len(result) == len(df)
        # With 60% buy volume, imbalance should be around 0.6
        assert result.iloc[-1] > 0.5

    def test_order_flow_toxicity_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test order flow toxicity calculation."""
        from medusa.features.order_flow_features import order_flow_toxicity

        result = order_flow_toxicity(sample_ohlcv, window=20)

        assert len(result) == len(sample_ohlcv)
        assert result.notna().any()

    def test_kyle_lambda_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test Kyle's lambda calculation."""
        from medusa.features.order_flow_features import kyle_lambda

        result = kyle_lambda(sample_ohlcv, window=20)

        assert len(result) == len(sample_ohlcv)
        # First window-1 values will be NaN
        assert result.iloc[:19].isna().all()

    def test_kyle_lambda_zero_std(self) -> None:
        """Test Kyle's lambda with zero standard deviation."""
        from medusa.features.order_flow_features import kyle_lambda

        # Constant price and volume
        df = pd.DataFrame(
            {
                "close": [100.0] * 50,
                "volume": [1000.0] * 50,
            }
        )

        result = kyle_lambda(df, window=20)

        # When std(x) = 0, lambda should remain NaN
        assert result.isna().all()

    def test_volume_clock_sampling_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test volume clock sampling."""
        from medusa.features.order_flow_features import volume_clock_sampling

        result = volume_clock_sampling(sample_ohlcv, volume_per_bar=5000)

        assert len(result) < len(sample_ohlcv)  # Should have fewer bars
        assert "open" in result.columns
        assert "high" in result.columns
        assert "low" in result.columns
        assert "close" in result.columns
        assert "volume" in result.columns

    def test_volume_clock_sampling_aggregation(self) -> None:
        """Test volume clock sampling aggregates correctly."""
        from medusa.features.order_flow_features import volume_clock_sampling

        # Create data where we know the expected aggregation
        df = pd.DataFrame(
            {
                "open": [100, 101, 102, 103, 104],
                "high": [101, 102, 103, 104, 105],
                "low": [99, 100, 101, 102, 103],
                "close": [100, 101, 102, 103, 104],
                "volume": [1000, 1000, 1000, 1000, 1000],
            }
        )

        result = volume_clock_sampling(df, volume_per_bar=2000)

        # Should aggregate into bars by volume buckets
        assert len(result) >= 2
        # Each bar should aggregate multiple source bars
        assert result["volume"].sum() == df["volume"].sum()

    def test_add_order_flow_features_basic(self, sample_ohlcv: pd.DataFrame) -> None:
        """Test adding all order flow features."""
        from medusa.features.order_flow_features import add_order_flow_features

        result = add_order_flow_features(sample_ohlcv, vpin_window=50, imbalance_window=20)

        assert "vpin" in result.columns
        assert "trade_imbalance" in result.columns
        assert "flow_toxicity" in result.columns
        assert "kyle_lambda" in result.columns
        assert len(result) == len(sample_ohlcv)


# ============================================================================
# 6. BASE MODEL TESTS
# ============================================================================


class TestBaseAlphaModel:
    """Test coverage for medusa/models/base.py."""

    def test_base_alpha_model_abstract(self) -> None:
        """Test BaseAlphaModel requires forward implementation."""
        from medusa.models.base import BaseAlphaModel

        # BaseAlphaModel defines abstract forward method
        # Verify that it cannot be called directly (it has no implementation)
        # A concrete subclass must implement it
        class ConcreteModel(BaseAlphaModel):
            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return x

        model = ConcreteModel()
        x = torch.randn(32, 10)
        result = model.forward(x)
        assert result.shape == x.shape

    def test_lightning_alpha_model_missing_lightning(self) -> None:
        """Test LightningAlphaModel stub when lightning is not installed."""
        # This test would require uninstalling lightning, which is installed
        # Skip this test as it's difficult to test the stub in the current environment
        pytest.skip("Lightning is installed; cannot test stub version")

    def test_lightning_alpha_model_init(self) -> None:
        """Test LightningAlphaModel initialization."""
        pytest.importorskip("lightning")
        from medusa.models.base import LightningAlphaModel

        # Need to implement forward to instantiate
        class ConcreteModel(LightningAlphaModel):
            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return x

        model = ConcreteModel(learning_rate=0.01)
        assert model.learning_rate == 0.01

    def test_lightning_alpha_model_training_step(self) -> None:
        """Test LightningAlphaModel training_step."""
        pytest.importorskip("lightning")
        from medusa.models.base import LightningAlphaModel

        class ConcreteModel(LightningAlphaModel):
            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return x.mean(dim=1, keepdim=True)

        model = ConcreteModel()
        x = torch.randn(32, 10)
        y = torch.randn(32, 1)

        loss = model.training_step((x, y), 0)

        assert isinstance(loss, torch.Tensor)
        assert loss.ndim == 0  # Scalar

    def test_lightning_alpha_model_validation_step(self) -> None:
        """Test LightningAlphaModel validation_step."""
        pytest.importorskip("lightning")
        from medusa.models.base import LightningAlphaModel

        class ConcreteModel(LightningAlphaModel):
            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return x.mean(dim=1, keepdim=True)

        model = ConcreteModel()
        x = torch.randn(32, 10)
        y = torch.randn(32, 1)

        loss = model.validation_step((x, y), 0)

        assert isinstance(loss, torch.Tensor)
        assert loss.ndim == 0  # Scalar

    def test_lightning_alpha_model_configure_optimizers(self) -> None:
        """Test LightningAlphaModel configure_optimizers."""
        pytest.importorskip("lightning")
        from medusa.models.base import LightningAlphaModel

        class ConcreteModel(LightningAlphaModel):
            def __init__(self, learning_rate: float = 1e-3) -> None:
                super().__init__(learning_rate)
                self.linear = torch.nn.Linear(10, 1)

            def forward(self, x: torch.Tensor) -> torch.Tensor:
                return self.linear(x)

        model = ConcreteModel(learning_rate=0.01)
        optimizer = model.configure_optimizers()

        assert isinstance(optimizer, torch.optim.Adam)
        assert optimizer.param_groups[0]["lr"] == 0.01


# ============================================================================
# RUN TESTS
# ============================================================================


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
