"""Tests for Alpaca integration modules."""

from __future__ import annotations

from datetime import datetime
from unittest.mock import MagicMock, Mock, patch

import pandas as pd
import pytest
from pydantic import SecretStr


class TestAlpacaHistoricalLoader:
    """Tests for AlpacaHistoricalLoader."""

    @pytest.fixture
    def mock_alpaca_client(self):
        """Mock Alpaca StocksHistoricalDataClient."""
        with patch("medusa.data.alpaca_loader.ALPACA_AVAILABLE", True):
            with patch(
                "medusa.data.alpaca_loader.StocksHistoricalDataClient", create=True
            ) as mock_client:
                with patch("medusa.data.alpaca_loader.TimeFrame", create=True) as mock_tf:
                    # Mock TimeFrame attributes
                    mock_tf.Minute = "1Min"
                    mock_tf.Hour = "1Hour"
                    mock_tf.Day = "1Day"
                    mock_tf.return_value = "TimeFrame"
                    with patch("medusa.data.alpaca_loader.StockBarsRequest", create=True):
                        with patch("medusa.data.alpaca_loader.StockSnapshotRequest", create=True):
                            yield mock_client

    def test_init_with_api_keys(self, mock_alpaca_client):
        """Test initialization with provided API keys."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        loader = AlpacaHistoricalLoader(api_key="test_key", secret_key="test_secret")
        assert loader.api_key == "test_key"
        assert loader.secret_key == "test_secret"
        mock_alpaca_client.assert_called_once()

    def test_init_with_env_vars(self, mock_alpaca_client, monkeypatch):
        """Test initialization with environment variables."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        monkeypatch.setenv("ALPACA_API_KEY", "env_key")
        monkeypatch.setenv("ALPACA_SECRET_KEY", "env_secret")

        loader = AlpacaHistoricalLoader()
        assert loader.api_key == "env_key"
        assert loader.secret_key == "env_secret"

    def test_init_missing_keys(self, mock_alpaca_client):
        """Test initialization fails without API keys."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        with pytest.raises(ValueError, match="Alpaca API keys not found"):
            AlpacaHistoricalLoader()

    def test_load_bars(self, mock_alpaca_client):
        """Test loading OHLCV bars."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        # Mock bars response
        mock_bars = MagicMock()
        mock_df = pd.DataFrame(
            {
                "symbol": ["AAPL"] * 3,
                "timestamp": pd.date_range("2026-01-01", periods=3, freq="D"),
                "open": [150.0, 151.0, 152.0],
                "high": [152.0, 153.0, 154.0],
                "low": [149.0, 150.0, 151.0],
                "close": [151.0, 152.0, 153.0],
                "volume": [1000000, 1100000, 1200000],
                "vwap": [150.5, 151.5, 152.5],
                "trade_count": [100, 110, 120],
            }
        )
        mock_bars.df = mock_df
        mock_client_instance = mock_alpaca_client.return_value
        mock_client_instance.get_stock_bars.return_value = mock_bars

        loader = AlpacaHistoricalLoader(api_key="test", secret_key="test")
        result = loader.load_bars("AAPL", "2026-01-01", "2026-01-03", "1Day")

        assert len(result) == 3
        assert "timestamp" in result.columns
        assert "open" in result.columns
        assert result["open"].iloc[0] == 150.0

    def test_load_bars_empty(self, mock_alpaca_client):
        """Test loading bars returns empty DataFrame when no data."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        mock_bars = MagicMock()
        mock_bars.df = pd.DataFrame()
        mock_client_instance = mock_alpaca_client.return_value
        mock_client_instance.get_stock_bars.return_value = mock_bars

        loader = AlpacaHistoricalLoader(api_key="test", secret_key="test")
        result = loader.load_bars("INVALID", "2026-01-01", "2026-01-03")

        assert result.empty

    def test_get_snapshot(self, mock_alpaca_client):
        """Test getting market snapshots."""
        from medusa.data.alpaca_loader import AlpacaHistoricalLoader

        # Mock snapshot response
        mock_snapshot = Mock()
        mock_snapshot.latest_trade.timestamp = datetime(2026, 1, 1, 10, 0)
        mock_snapshot.latest_trade.price = 150.0
        mock_snapshot.latest_quote.bid_price = 149.9
        mock_snapshot.latest_quote.ask_price = 150.1
        mock_snapshot.latest_quote.bid_size = 100
        mock_snapshot.latest_quote.ask_size = 200
        mock_snapshot.daily_bar.open = 148.0
        mock_snapshot.daily_bar.high = 151.0
        mock_snapshot.daily_bar.low = 147.0
        mock_snapshot.daily_bar.close = 150.0
        mock_snapshot.daily_bar.volume = 1000000

        mock_client_instance = mock_alpaca_client.return_value
        mock_client_instance.get_stock_snapshot.return_value = {"AAPL": mock_snapshot}

        loader = AlpacaHistoricalLoader(api_key="test", secret_key="test")
        result = loader.get_snapshot(["AAPL"])

        assert len(result) == 1
        assert result["symbol"].iloc[0] == "AAPL"
        assert result["price"].iloc[0] == 150.0
        assert result["bid_price"].iloc[0] == 149.9


class TestEquityKdbLoader:
    """Tests for EquityKdbLoader."""

    @pytest.fixture
    def mock_pykx(self):
        """Mock PyKX connection."""
        with patch("medusa.data.equity_kdb_loader.get_settings") as mock_settings:
            mock_config = Mock()
            mock_config.kdb.host = "localhost"
            mock_config.kdb.hdb_port = 5012
            mock_config.kdb.username = None
            mock_config.kdb.password = SecretStr("")
            mock_config.kdb.timeout = 10000
            mock_settings.return_value = mock_config

            # Mock pykx module imported inside connect()
            with patch("pykx.QConnection") as mock_qconnection:
                yield mock_qconnection, mock_config

    def test_init(self, mock_pykx):
        """Test EquityKdbLoader initialization."""
        from medusa.data.equity_kdb_loader import EquityKdbLoader

        mock_qconnection, _ = mock_pykx
        loader = EquityKdbLoader()
        assert loader._resilient_conn is None

    def test_validate_equity_symbol_valid(self):
        """Test equity symbol validation with valid symbols."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        assert _validate_equity_symbol("AAPL") == "AAPL"
        assert _validate_equity_symbol("MSFT") == "MSFT"
        assert _validate_equity_symbol("SPY") == "SPY"
        assert _validate_equity_symbol("QQQ") == "QQQ"
        assert _validate_equity_symbol("A") == "A"

    def test_validate_equity_symbol_invalid(self):
        """Test equity symbol validation with invalid symbols."""
        from medusa.data.equity_kdb_loader import _validate_equity_symbol

        with pytest.raises(ValueError, match="Invalid equity symbol"):
            _validate_equity_symbol("BTCUSD")  # Too long

        with pytest.raises(ValueError, match="Invalid equity symbol"):
            _validate_equity_symbol("aapl")  # Lowercase

        with pytest.raises(ValueError, match="Invalid equity symbol"):
            _validate_equity_symbol("AA123")  # Contains digits

    def test_load_bars(self, mock_pykx):
        """Test loading equity bars from kdb+."""
        from medusa.data.equity_kdb_loader import EquityKdbLoader

        mock_qconnection, _ = mock_pykx

        # Mock query result
        mock_result = Mock()
        mock_df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2026-01-01", periods=3, freq="D"),
                "open": [150.0, 151.0, 152.0],
                "high": [152.0, 153.0, 154.0],
                "low": [149.0, 150.0, 151.0],
                "close": [151.0, 152.0, 153.0],
                "volume": [1000000, 1100000, 1200000],
                "vwap": [150.5, 151.5, 152.5],
                "tradeCount": [100, 110, 120],
            }
        )
        mock_result.pd.return_value = mock_df

        mock_conn = Mock()
        mock_conn.return_value = mock_result
        mock_qconnection.return_value = mock_conn

        loader = EquityKdbLoader()
        loader.connect()
        result = loader.load_bars("AAPL", "2026-01-01", "2026-01-03", "1Day")

        assert len(result) == 3
        assert "trade_count" in result.columns  # Renamed from tradeCount

    def test_load_metadata(self, mock_pykx):
        """Test loading equity metadata from kdb+."""
        from medusa.data.equity_kdb_loader import EquityKdbLoader

        mock_qconnection, _ = mock_pykx

        # Mock query result
        mock_result = Mock()
        mock_df = pd.DataFrame(
            {
                "sym": ["AAPL"],
                "name": ["Apple Inc."],
                "assetClass": ["stock"],
                "exchange": ["NASDAQ"],
                "sector": ["Technology"],
                "industry": ["Consumer Electronics"],
                "marketCap": [3000000000000],
                "dividendYield": [0.5],
                "peRatio": [28.5],
                "beta": [1.2],
                "avgVolume30d": [50000000],
                "updatedAt": [pd.Timestamp("2026-01-01")],
            }
        )
        mock_result.pd.return_value = mock_df

        mock_conn = Mock()
        mock_conn.return_value = mock_result
        mock_qconnection.return_value = mock_conn

        loader = EquityKdbLoader()
        loader.connect()
        result = loader.load_metadata("AAPL")

        assert result["symbol"] == "AAPL"
        assert result["name"] == "Apple Inc."
        assert result["asset_class"] == "stock"
        assert result["pe_ratio"] == 28.5


class TestVectorBTEngineEquity:
    """Tests for VectorBT engine with equity support."""

    def test_init_equity(self):
        """Test VectorBT engine initialization with equity asset class."""
        from medusa.backtest.vectorbt_engine import VectorBTEngine

        with patch("medusa.backtest.vectorbt_engine.get_settings") as mock_settings:
            mock_config = Mock()
            mock_config.backtest.initial_capital = 100000.0
            mock_config.backtest.commission = 0.001
            mock_config.backtest.slippage = 0.0005
            mock_settings.return_value = mock_config

            engine = VectorBTEngine(asset_class="equity")
            assert engine.asset_class == "equity"
            assert engine.commission == 0.0  # Alpaca is commission-free
            assert engine.slippage == 0.0002  # Equity slippage

    def test_init_crypto(self):
        """Test VectorBT engine initialization with crypto asset class."""
        from medusa.backtest.vectorbt_engine import VectorBTEngine

        with patch("medusa.backtest.vectorbt_engine.get_settings") as mock_settings:
            mock_config = Mock()
            mock_config.backtest.initial_capital = 100000.0
            mock_config.backtest.commission = 0.001
            mock_config.backtest.slippage = 0.0005
            mock_settings.return_value = mock_config

            engine = VectorBTEngine(asset_class="crypto")
            assert engine.asset_class == "crypto"
            assert engine.commission == 0.001  # Uses config default
            assert engine.slippage == 0.0005

    def test_market_hours_filter(self):
        """Test market hours filtering for equity signals."""
        from medusa.backtest.vectorbt_engine import VectorBTEngine

        with patch("medusa.backtest.vectorbt_engine.get_settings") as mock_settings:
            mock_config = Mock()
            mock_config.backtest.initial_capital = 100000.0
            mock_config.backtest.commission = 0.001
            mock_config.backtest.slippage = 0.0005
            mock_settings.return_value = mock_config

            engine = VectorBTEngine(asset_class="equity")

            # Create signals at different times
            timestamps = pd.DatetimeIndex(
                [
                    "2026-01-02 08:00:00",  # Pre-market
                    "2026-01-02 10:00:00",  # Regular hours
                    "2026-01-02 14:00:00",  # Regular hours
                    "2026-01-02 17:00:00",  # After hours
                ],
                tz="US/Eastern",
            )

            signals = pd.Series([True, True, True, True], index=timestamps)

            # Filter regular hours only
            filtered = engine._filter_market_hours(signals, extended_hours=False)

            # Only 10:00 and 14:00 should pass
            assert not filtered.iloc[0]  # Pre-market blocked
            assert filtered.iloc[1]  # Regular hours allowed
            assert filtered.iloc[2]  # Regular hours allowed
            assert not filtered.iloc[3]  # After hours blocked

    def test_market_hours_filter_extended(self):
        """Test extended hours filtering."""
        from medusa.backtest.vectorbt_engine import VectorBTEngine

        with patch("medusa.backtest.vectorbt_engine.get_settings") as mock_settings:
            mock_config = Mock()
            mock_config.backtest.initial_capital = 100000.0
            mock_config.backtest.commission = 0.001
            mock_config.backtest.slippage = 0.0005
            mock_settings.return_value = mock_config

            engine = VectorBTEngine(asset_class="equity")

            timestamps = pd.DatetimeIndex(
                [
                    "2026-01-02 05:00:00",  # Pre-market (allowed in extended)
                    "2026-01-02 10:00:00",  # Regular hours
                    "2026-01-02 17:00:00",  # After hours (allowed in extended)
                    "2026-01-02 21:00:00",  # Outside extended hours
                ],
                tz="US/Eastern",
            )

            signals = pd.Series([True, True, True, True], index=timestamps)

            # Filter with extended hours
            filtered = engine._filter_market_hours(signals, extended_hours=True)

            assert filtered.iloc[0]  # Pre-market allowed
            assert filtered.iloc[1]  # Regular hours allowed
            assert filtered.iloc[2]  # After hours allowed
            assert not filtered.iloc[3]  # Outside extended hours blocked


class TestAlpacaPaperClient:
    """Tests for AlpacaPaperClient."""

    @pytest.fixture
    def mock_trading_client(self):
        """Mock Alpaca TradingClient."""
        with patch("medusa.live.alpaca_paper.ALPACA_TRADING_AVAILABLE", True):
            with patch("medusa.live.alpaca_paper.TradingClient", create=True) as mock_client:
                with patch("medusa.live.alpaca_paper.OrderSide", create=True) as mock_side:
                    mock_side.BUY = "BUY"
                    mock_side.SELL = "SELL"
                    with patch("medusa.live.alpaca_paper.TimeInForce", create=True) as mock_tif:
                        mock_tif.DAY = "DAY"
                        mock_tif.GTC = "GTC"
                        mock_tif.IOC = "IOC"
                        mock_tif.FOK = "FOK"
                        with patch("medusa.live.alpaca_paper.MarketOrderRequest", create=True):
                            with patch("medusa.live.alpaca_paper.GetOrdersRequest", create=True):
                                yield mock_client

    def test_init(self, mock_trading_client):
        """Test AlpacaPaperClient initialization."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        client = AlpacaPaperClient(api_key="test", secret_key="test")
        assert client.api_key == "test"
        assert client.secret_key == "test"
        mock_trading_client.assert_called_once_with(
            api_key="test",
            secret_key="test",
            paper=True,
        )

    def test_submit_order(self, mock_trading_client):
        """Test submitting a market order."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock order response
        mock_order = Mock()
        mock_order.id = "order_123"
        mock_order.client_order_id = "client_123"
        mock_order.symbol = "AAPL"
        mock_order.qty = 10
        mock_order.filled_qty = 0
        mock_order.side = Mock()
        mock_order.side.value = "buy"
        mock_order.order_type = Mock()
        mock_order.order_type.value = "market"
        mock_order.status = Mock()
        mock_order.status.value = "new"
        mock_order.created_at = datetime(2026, 1, 1, 10, 0)
        mock_order.filled_at = None
        mock_order.filled_avg_price = None

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.submit_order.return_value = mock_order

        client = AlpacaPaperClient(api_key="test", secret_key="test")
        result = client.submit_order("AAPL", 10, "buy", "market")

        assert result["id"] == "order_123"
        assert result["symbol"] == "AAPL"
        assert result["qty"] == 10.0
        assert result["side"] == "buy"
        assert result["status"] == "new"

    def test_get_positions(self, mock_trading_client):
        """Test getting positions."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock positions
        mock_pos = Mock()
        mock_pos.symbol = "AAPL"
        mock_pos.qty = 10
        mock_pos.avg_entry_price = 150.0
        mock_pos.market_value = 1520.0
        mock_pos.cost_basis = 1500.0
        mock_pos.unrealized_pl = 20.0
        mock_pos.unrealized_plpc = 0.0133
        mock_pos.current_price = 152.0

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_all_positions.return_value = [mock_pos]

        client = AlpacaPaperClient(api_key="test", secret_key="test")
        result = client.get_positions()

        assert len(result) == 1
        assert result[0]["symbol"] == "AAPL"
        assert result[0]["qty"] == 10.0
        assert result[0]["unrealized_pl"] == 20.0

    def test_get_account(self, mock_trading_client):
        """Test getting account info."""
        from medusa.live.alpaca_paper import AlpacaPaperClient

        # Mock account
        mock_account = Mock()
        mock_account.id = "account_123"
        mock_account.status = Mock()
        mock_account.status.value = "ACTIVE"
        mock_account.currency = "USD"
        mock_account.cash = 50000.0
        mock_account.portfolio_value = 100000.0
        mock_account.equity = 100000.0
        mock_account.last_equity = 99000.0
        mock_account.buying_power = 100000.0
        mock_account.initial_margin = 0.0
        mock_account.maintenance_margin = 0.0
        mock_account.daytrade_count = 0
        mock_account.daytrading_buying_power = 100000.0

        mock_client_instance = mock_trading_client.return_value
        mock_client_instance.get_account.return_value = mock_account

        client = AlpacaPaperClient(api_key="test", secret_key="test")
        result = client.get_account()

        assert result["id"] == "account_123"
        assert result["cash"] == 50000.0
        assert result["equity"] == 100000.0
        assert result["status"] == "ACTIVE"
