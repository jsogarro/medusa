"""Tests for data loaders: CSV, KDB, Alpaca (with mocks)."""

from __future__ import annotations

import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

# Test 1-5: CsvDataLoader tests


class TestCsvDataLoader:
    """Test CSV data loader."""

    @pytest.fixture
    def sample_csv_file(self):
        """Create a temporary CSV file with OHLCV data."""
        csv_content = """timestamp,open,high,low,close,volume
2024-01-01,100.0,105.0,99.0,102.0,1000
2024-01-02,102.0,106.0,101.0,104.0,1200
2024-01-03,104.0,108.0,103.0,107.0,1100
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(csv_content)
            temp_path = Path(f.name)

        yield temp_path

        # Cleanup
        temp_path.unlink()

    def test_load_valid_csv(self, sample_csv_file):
        """Test loading valid CSV with OHLCV columns."""
        from medusa.data.csv_loader import CsvDataLoader

        df = CsvDataLoader.load_ohlcv(sample_csv_file)

        assert len(df) == 3
        assert "open" in df.columns
        assert "high" in df.columns
        assert "low" in df.columns
        assert "close" in df.columns
        assert "volume" in df.columns
        assert df.index.name == "timestamp"

    def test_validate_columns(self):
        """Test that CSV with missing columns raises ValueError."""
        from medusa.data.csv_loader import CsvDataLoader

        csv_content = """timestamp,open,high,low
2024-01-01,100.0,105.0,99.0
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
            f.write(csv_content)
            temp_path = Path(f.name)

        try:
            with pytest.raises(ValueError, match="CSV missing required columns"):
                CsvDataLoader.load_ohlcv(temp_path)
        finally:
            temp_path.unlink()

    def test_handle_missing_file(self):
        """Test that missing CSV file raises FileNotFoundError."""
        from medusa.data.csv_loader import CsvDataLoader

        nonexistent_path = Path("/tmp/nonexistent_file_12345.csv")

        with pytest.raises(FileNotFoundError, match="CSV file not found"):
            CsvDataLoader.load_ohlcv(nonexistent_path)

    def test_sorts_by_timestamp(self, sample_csv_file):
        """Test that data is sorted by timestamp index."""
        from medusa.data.csv_loader import CsvDataLoader

        df = CsvDataLoader.load_ohlcv(sample_csv_file)

        # Verify sorted
        assert df.index.is_monotonic_increasing

    def test_parses_timestamps(self, sample_csv_file):
        """Test that timestamps are parsed as datetime."""
        from medusa.data.csv_loader import CsvDataLoader

        df = CsvDataLoader.load_ohlcv(sample_csv_file)

        assert pd.api.types.is_datetime64_any_dtype(df.index)


# Test 6-11: KdbDataLoader tests


class TestKdbDataLoader:
    """Test KDB+ data loader with mocks."""

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_connect_to_hdb(self, mock_conn_class):
        """Test connection to HDB."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader = KdbDataLoader()
        loader.connect(port=5012)

        mock_conn_class.assert_called_once()
        mock_conn.connect.assert_called_once()

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_symbol_validation(self, mock_conn_class):
        """Test that invalid symbols are rejected."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader = KdbDataLoader()
        loader.connect()

        # Invalid symbol with special characters
        with pytest.raises(ValueError, match="Invalid symbol format"):
            loader.load_trades(
                symbol="BTC/USD",  # '/' is not allowed
                start_date=datetime(2024, 1, 1),
                end_date=datetime(2024, 1, 2),
            )

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_trades(self, mock_conn_class):
        """Test loading trade data."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        # Mock PyKX result
        mock_result = MagicMock()
        mock_result.pd.return_value = pd.DataFrame(
            {
                "time": pd.date_range("2024-01-01", periods=10, freq="S"),
                "price": [50000.0] * 10,
                "volume": [1.0] * 10,
                "side": ["buy"] * 10,
            }
        )
        mock_conn.query.return_value = mock_result

        loader = KdbDataLoader()
        loader._resilient_conn = mock_conn

        df = loader.load_trades(
            symbol="BTCUSD",
            start_date=datetime(2024, 1, 1),
            end_date=datetime(2024, 1, 2),
        )

        assert len(df) == 10
        assert "timestamp" in df.columns
        assert "price" in df.columns
        assert "size" in df.columns
        assert "side" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_quotes(self, mock_conn_class):
        """Test loading quote data."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        # Mock PyKX result
        mock_result = MagicMock()
        mock_result.pd.return_value = pd.DataFrame(
            {
                "time": pd.date_range("2024-01-01", periods=10, freq="S"),
                "bid": [49990.0] * 10,
                "bidSize": [0.5] * 10,
                "ask": [50010.0] * 10,
                "askSize": [0.6] * 10,
            }
        )
        mock_conn.query.return_value = mock_result

        loader = KdbDataLoader()
        loader._resilient_conn = mock_conn

        df = loader.load_quotes(
            symbol="BTCUSD",
            start_date=datetime(2024, 1, 1),
            end_date=datetime(2024, 1, 2),
        )

        assert len(df) == 10
        assert "timestamp" in df.columns
        assert "bid_price" in df.columns
        assert "bid_size" in df.columns
        assert "ask_price" in df.columns
        assert "ask_size" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_load_ohlcv(self, mock_conn_class):
        """Test loading OHLCV bars."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        # Mock PyKX result
        mock_result = MagicMock()
        mock_result.pd.return_value = pd.DataFrame(
            {
                "timestamp": pd.date_range("2024-01-01", periods=24, freq="h"),
                "open": [50000.0] * 24,
                "high": [50100.0] * 24,
                "low": [49900.0] * 24,
                "close": [50050.0] * 24,
                "volume": [10.0] * 24,
            }
        )
        mock_conn.query.return_value = mock_result

        loader = KdbDataLoader()
        loader._resilient_conn = mock_conn

        df = loader.load_ohlcv(
            symbol="BTCUSD",
            start_date=datetime(2024, 1, 1),
            end_date=datetime(2024, 1, 2),
            interval="1h",
        )

        assert len(df) == 24
        assert "timestamp" in df.columns
        assert "open" in df.columns
        assert "high" in df.columns
        assert "low" in df.columns
        assert "close" in df.columns
        assert "volume" in df.columns

    @patch("medusa.data.kdb_loader.ResilientKdbConnection")
    def test_unsupported_interval_raises_error(self, mock_conn_class):
        """Test that unsupported interval raises ValueError."""
        from medusa.data.kdb_loader import KdbDataLoader

        mock_conn = MagicMock()
        mock_conn_class.return_value = mock_conn

        loader = KdbDataLoader()
        loader._resilient_conn = mock_conn

        with pytest.raises(ValueError, match="Unsupported interval"):
            loader.load_ohlcv(
                symbol="BTCUSD",
                start_date=datetime(2024, 1, 1),
                end_date=datetime(2024, 1, 2),
                interval="10s",  # Not supported
            )


# Test 12-15: Alpaca Data Loader tests (mock API)


try:
    from alpaca.trading import TradingClient as _AlpacaCheck  # noqa: F401

    _ALPACA_AVAILABLE = True
except ImportError:
    _ALPACA_AVAILABLE = False


@pytest.mark.skipif(not _ALPACA_AVAILABLE, reason="alpaca-py not installed")
class TestAlpacaDataLoader:
    """Test Alpaca historical data loader (via AlpacaPaperClient)."""

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_get_portfolio_history(self, mock_trading_client):
        """Test get portfolio history."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock portfolio history
        mock_history = MagicMock()
        mock_history.timestamp = [1704067200, 1704153600, 1704240000]  # Unix timestamps
        mock_history.equity = [100000.0, 100500.0, 101000.0]
        mock_history.profit_loss = [0.0, 500.0, 1000.0]
        mock_history.profit_loss_pct = [0.0, 0.005, 0.01]

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_portfolio_history.return_value = mock_history

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        df = client.get_portfolio_history(period="1M", timeframe="1D")

        assert isinstance(df, pd.DataFrame)
        assert len(df) == 3
        assert "equity" in df.columns
        assert "profit_loss" in df.columns
        assert "profit_loss_pct" in df.columns
        assert pd.api.types.is_datetime64_any_dtype(df.index)

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_get_orders(self, mock_trading_client):
        """Test get orders with status filter."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock order
        mock_order = MagicMock()
        mock_order.id = "order123"
        mock_order.symbol = "AAPL"
        mock_order.qty = "100"
        mock_order.filled_qty = "100"
        mock_order.side = MagicMock(value="buy")
        mock_order.order_type = MagicMock(value="market")
        mock_order.status = MagicMock(value="filled")
        mock_order.created_at = datetime(2024, 1, 1, 10, 0, 0)
        mock_order.filled_at = datetime(2024, 1, 1, 10, 0, 1)

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_orders.return_value = [mock_order]

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        orders = client.get_orders(status="closed", limit=50)

        assert len(orders) == 1
        assert orders[0]["id"] == "order123"
        assert orders[0]["symbol"] == "AAPL"
        assert orders[0]["status"] == "filled"

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_parse_bars(self, mock_trading_client):
        """Test parsing bars from Alpaca API (if implemented)."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # This documents expected behavior for bar loading
        # (if we add get_bars() method to AlpacaPaperClient)
        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")

        # For now, just verify client exists
        assert client is not None

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_parse_trades(self, mock_trading_client):
        """Test parsing trades from Alpaca API (if implemented)."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # This documents expected behavior for trade loading
        # (if we add get_trades() method to AlpacaPaperClient)
        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")

        assert client is not None
