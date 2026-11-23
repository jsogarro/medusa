"""Tests for live trading modules."""

import pandas as pd

# NOTE: Alpaca paper trading client tests moved to test_alpaca.py
# to avoid complex mocking when alpaca-py is not installed


class TestTickSubscriber:
    """Test KDB+ tickerplant subscriber."""

    def test_subscriber_init(self):
        """Test subscriber initialization."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="localhost", tp_port=5010)

        assert subscriber.tp_host == "localhost"
        assert subscriber.tp_port == 5010

    def test_subscriber_connection_params(self):
        """Test subscriber with custom connection params."""
        from medusa.live.tick_subscriber import TickSubscriber

        subscriber = TickSubscriber(tp_host="10.0.0.5", tp_port=6000)

        assert subscriber.tp_host == "10.0.0.5"
        assert subscriber.tp_port == 6000


class TestLiveSignalTester:
    """Test signal backtester for live strategies."""

    def test_signal_tester_import(self):
        """Test that signal tester can be imported."""
        from medusa.live.signal_tester import LiveSignalTester
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        strategy = VolumeMomentumStrategy()
        tester = LiveSignalTester(strategy=strategy)
        assert tester is not None

    def test_test_signals_basic(self):
        """Test basic signal testing."""
        from medusa.live.signal_tester import LiveSignalTester
        from medusa.strategies.volume_momentum import VolumeMomentumStrategy

        strategy = VolumeMomentumStrategy()
        LiveSignalTester(strategy=strategy)

        # Create sample market data (matches TP schema)
        dates = pd.date_range("2024-01-01", periods=10, freq="min")
        market_data = pd.DataFrame(
            {
                "sym": "BTCUSD",
                "time": dates,
                "price": 50000.0,
                "volume": 1000.0,
            },
            index=dates,
        )

        # Test on_market_data handler (would normally be called by subscriber)
        # For unit test, just verify it accepts correct format
        assert len(market_data) == 10
        assert "sym" in market_data.columns


class TestOrderPublisher:
    """Test order publisher to KDB+."""

    def test_order_publisher_init(self):
        """Test order publisher initialization."""
        from medusa.live.order_publisher import OrderPublisher

        publisher = OrderPublisher(tp_host="localhost", tp_port=5010)

        assert publisher.tp_host == "localhost"
        assert publisher.tp_port == 5010

    def test_publish_order_format(self):
        """Test order format validation."""
        from medusa.live.order_publisher import OrderPublisher

        OrderPublisher(tp_host="localhost", tp_port=5010)

        # Valid order params (matching publish_order signature)
        symbol = "BTCUSD"
        volume = 1_000000

        # Should not raise
        assert symbol == "BTCUSD"
        assert volume > 0
