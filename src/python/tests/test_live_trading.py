"""Tests for live trading modules: AlpacaPaperClient, OrderPublisher, TickSubscriber."""

from __future__ import annotations

from datetime import datetime
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

# Test 1-5: AlpacaPaperClient tests


try:
    from alpaca.trading import TradingClient as _AlpacaCheck  # noqa: F401

    ALPACA_AVAILABLE = True
except ImportError:
    ALPACA_AVAILABLE = False


@pytest.mark.skipif(not ALPACA_AVAILABLE, reason="alpaca-py not installed")
class TestAlpacaPaperClient:
    """Test Alpaca paper trading client."""

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_submit_market_order(self, mock_trading_client):
        """Test submit market order with mock API."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock order response
        mock_order = MagicMock()
        mock_order.id = "order123"
        mock_order.client_order_id = "client456"
        mock_order.symbol = "AAPL"
        mock_order.qty = "100"
        mock_order.filled_qty = "0"
        mock_order.side = MagicMock(value="buy")
        mock_order.order_type = MagicMock(value="market")
        mock_order.status = MagicMock(value="pending_new")
        mock_order.created_at = datetime(2024, 1, 1, 12, 0, 0)
        mock_order.filled_at = None
        mock_order.filled_avg_price = None

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.submit_order.return_value = mock_order

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        result = client.submit_order(symbol="AAPL", qty=100, side="buy")

        assert result["id"] == "order123"
        assert result["symbol"] == "AAPL"
        assert result["qty"] == 100.0
        assert result["side"] == "buy"
        assert result["status"] == "pending_new"

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_cancel_order(self, mock_trading_client):
        """Test cancel order."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.cancel_order_by_id.return_value = None

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        success = client.cancel_order("order123")

        assert success is True
        mock_client_instance.cancel_order_by_id.assert_called_once_with("order123")

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_get_positions(self, mock_trading_client):
        """Test get all positions."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock position
        mock_pos = MagicMock()
        mock_pos.symbol = "AAPL"
        mock_pos.qty = "100"
        mock_pos.avg_entry_price = "150.5"
        mock_pos.market_value = "15200"
        mock_pos.cost_basis = "15050"
        mock_pos.unrealized_pl = "150"
        mock_pos.unrealized_plpc = "0.01"
        mock_pos.current_price = "152.0"

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_all_positions.return_value = [mock_pos]

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        positions = client.get_positions()

        assert len(positions) == 1
        assert positions[0]["symbol"] == "AAPL"
        assert positions[0]["qty"] == 100.0
        assert positions[0]["side"] == "long"
        assert positions[0]["unrealized_pl"] == 150.0

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True)
    @patch("medusa.live.alpaca_paper.TradingClient")
    def test_get_account(self, mock_trading_client):
        """Test get account information."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock account
        mock_account = MagicMock()
        mock_account.id = "acc123"
        mock_account.status = MagicMock(value="ACTIVE")
        mock_account.currency = "USD"
        mock_account.cash = "50000"
        mock_account.portfolio_value = "75000"
        mock_account.equity = "75000"
        mock_account.last_equity = "74500"
        mock_account.buying_power = "100000"
        mock_account.initial_margin = "25000"
        mock_account.maintenance_margin = "15000"
        mock_account.daytrade_count = 0
        mock_account.daytrading_buying_power = "200000"

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_account.return_value = mock_account

        client = AlpacaPaperClient(api_key="test_key", secret_key="test_secret")
        account = client.get_account()

        assert account["id"] == "acc123"
        assert account["status"] == "ACTIVE"
        assert account["cash"] == 50000.0
        assert account["equity"] == 75000.0
        assert account["buying_power"] == 100000.0

    @patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", False)
    def test_alpaca_not_installed(self):
        """Test error when alpaca-py not installed."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        with pytest.raises(ImportError, match="alpaca-py trading module not installed"):
            AlpacaPaperClient(api_key="test", secret_key="test")


# Test 6-13: OrderPublisher tests


class TestOrderPublisher:
    """Test OrderPublisher for publishing to kdb+ TP."""

    def test_init(self):
        """Test OrderPublisher initialization."""
        from medusa.live.order_publisher import OrderPublisher

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)
        assert publisher.tp_host == "localhost"
        assert publisher.tp_port == 5010

    def test_init_default_config(self):
        """Test OrderPublisher with default config."""
        from medusa.live.order_publisher import OrderPublisher

        publisher = OrderPublisher()
        # Uses get_settings().kdb defaults
        assert publisher._conn is None

    @patch("pykx.QConnection")
    def test_connect(self, mock_qconnection):
        """Test connection to TP."""
        from medusa.live.order_publisher import OrderPublisher

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)
        publisher.connect()

        mock_qconnection.assert_called_once_with(host="localhost", port=5010)
        assert publisher._conn == mock_conn

    @patch("pykx.QConnection")
    def test_disconnect(self, mock_qconnection):
        """Test disconnect from TP."""
        from medusa.live.order_publisher import OrderPublisher

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)
        publisher.connect()
        publisher.disconnect()

        mock_conn.close.assert_called_once()
        assert publisher._conn is None

    @patch("pykx.QConnection")
    def test_publish_order_valid_format(self, mock_qconnection):
        """Test publish order with valid format."""
        from medusa.live.order_publisher import OrderPublisher

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)
        publisher.connect()

        publisher.publish_order(
            order_id=1,
            exchange="coinbase",
            symbol="BTCUSD",
            side="buy",
            order_type="limit",
            price=50000_000000,  # 50000.0 in fixed-precision
            volume=1_000000,  # 1.0 BTC
            actor="momentum_strategy",
        )

        # Verify that a q expression was executed
        assert mock_conn.call_count == 1

    @patch("pykx.QConnection")
    def test_publish_order_invalid_symbol_rejected(self, mock_qconnection):
        """Test that invalid symbols should be validated (if implemented)."""
        from medusa.live.order_publisher import OrderPublisher

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)
        publisher.connect()

        # Currently no validation in OrderPublisher — this documents expected behavior
        # If validation is added, this test should expect a ValueError
        symbol = "BTC/USD"  # Invalid: contains '/'
        # For now, this will not raise (just documents the gap)
        publisher.publish_order(
            order_id=1,
            exchange="coinbase",
            symbol=symbol,
            side="buy",
            order_type="market",
            price=50000_000000,
            volume=1_000000,
            actor="test",
        )

    @patch("pykx.QConnection")
    def test_context_manager(self, mock_qconnection):
        """Test OrderPublisher as context manager."""
        from medusa.live.order_publisher import OrderPublisher

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        with OrderPublisher(tp_host="localhost", tp_port=5010) as publisher:
            assert publisher._conn == mock_conn

        mock_conn.close.assert_called_once()


# Test 14-23: TickSubscriber tests


class TestTickSubscriber:
    """Test TickSubscriber for real-time market data."""

    def test_init(self):
        """Test TickSubscriber initialization."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)
        assert subscriber.tp_host == "localhost"
        assert subscriber.tp_port == 5010
        assert subscriber._conn is None

    @patch("pykx.QConnection")
    def test_connect(self, mock_qconnection):
        """Test connection to TP."""
        from medusa.live.tick_subscriber import TickSubscriber

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)
        subscriber.connect()

        mock_qconnection.assert_called_once_with(host="localhost", port=5010)
        assert subscriber._conn == mock_conn

    @patch("pykx.QConnection")
    def test_disconnect(self, mock_qconnection):
        """Test disconnect from TP."""
        from medusa.live.tick_subscriber import TickSubscriber

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)
        subscriber.connect()
        subscriber.disconnect()

        mock_conn.close.assert_called_once()
        assert subscriber._conn is None

    @patch("pykx.QConnection")
    def test_subscribe_all_symbols(self, mock_qconnection):
        """Test subscribe to all symbols."""
        from medusa.live.tick_subscriber import TickSubscriber

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)
        subscriber.connect()
        subscriber.subscribe("marketData", symbols=None)

        # Should execute .u.sub with backtick for all symbols
        mock_conn.assert_called()

    @patch("pykx.QConnection")
    def test_subscribe_specific_symbols(self, mock_qconnection):
        """Test subscribe to specific symbols."""
        from medusa.live.tick_subscriber import TickSubscriber

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)
        subscriber.connect()
        subscriber.subscribe("marketData", symbols=["BTCUSD", "ETHUSD"])

        mock_conn.assert_called()

    def test_register_handler(self):
        """Test register callback handler."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)

        def handler(df: pd.DataFrame) -> None:
            pass

        subscriber.register_handler("marketData", handler)

        assert "marketData" in subscriber._handlers
        assert subscriber._handlers["marketData"] == handler

    def test_on_update_with_handler(self):
        """Test on_update calls registered handler."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)

        # Mock handler
        mock_handler = MagicMock()
        subscriber.register_handler("marketData", mock_handler)

        # Mock PyKX Table
        mock_kx_table = MagicMock()
        test_df = pd.DataFrame(
            {
                "sym": ["BTCUSD"],
                "price": [50000.0],
                "volume": [1.0],
            }
        )
        mock_kx_table.pd.return_value = test_df

        subscriber.on_update("marketData", mock_kx_table)

        # Verify handler was called with DataFrame
        mock_handler.assert_called_once()
        assert isinstance(mock_handler.call_args[0][0], pd.DataFrame)

    def test_on_update_no_handler(self):
        """Test on_update when no handler registered."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)

        # No handler registered for tradeEvent
        mock_kx_table = MagicMock()
        test_df = pd.DataFrame({"sym": ["BTCUSD"]})
        mock_kx_table.pd.return_value = test_df

        # Should not raise
        subscriber.on_update("tradeEvent", mock_kx_table)

    @patch("pykx.QConnection")
    def test_subscribe_reconnect_on_failure(self, mock_qconnection):
        """Test auto-reconnect if connection is None."""
        from medusa.live.tick_subscriber import TickSubscriber

        mock_conn = MagicMock()
        mock_qconnection.return_value = mock_conn

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)

        # Don't connect manually — subscribe should connect
        subscriber.subscribe("marketData")

        # Verify connection was established
        assert subscriber._conn == mock_conn
