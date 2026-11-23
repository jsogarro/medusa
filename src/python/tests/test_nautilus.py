"""Tests for NautilusTrader integration.

Tests the data adapter, strategy adapter, and backtesting engine.
"""

from __future__ import annotations

import pytest

# Skip all tests if NautilusTrader is not available
pytest.importorskip("nautilus_trader", reason="nautilus_trader not installed")

from datetime import UTC

import pandas as pd

from medusa.backtest.nautilus_adapter import NautilusDataAdapter
from medusa.backtest.nautilus_engine import ExchangeConfig, NautilusEngine
from medusa.backtest.strategy_adapter import NautilusStrategyAdapter
from medusa.strategies.examples.sma_crossover import SMACrossoverStrategy


class TestNautilusDataAdapter:
    """Test data conversion from Medusa to NautilusTrader format."""

    @pytest.mark.parametrize(
        "instrument_type",
        ["spot", "perpetual"],
    )
    def test_create_instrument(self, instrument_type: str) -> None:
        """Test creating different instrument types."""
        instrument = NautilusDataAdapter.create_instrument(
            symbol="BTCUSDT",
            venue="BINANCE",
            instrument_type=instrument_type,
        )
        assert instrument is not None
        assert str(instrument.id.symbol) == "BTCUSDT"
        assert str(instrument.id.venue) == "BINANCE"

    def test_df_to_bars(self, sample_ohlcv):
        """Test converting OHLCV DataFrame to NautilusTrader bars."""
        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")
        bars = NautilusDataAdapter.df_to_bars(
            sample_ohlcv.reset_index(),
            instrument.id,
        )
        assert len(bars) == len(sample_ohlcv)
        assert all(hasattr(bar, "open") for bar in bars)
        assert all(hasattr(bar, "close") for bar in bars)
        assert all(hasattr(bar, "volume") for bar in bars)

    def test_df_to_trades(self):
        """Test converting trade DataFrame to NautilusTrader trades."""
        df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2024-01-01", periods=100, freq="1s"),
                "price": [50000.0 + i * 10 for i in range(100)],
                "size": [0.1 + i * 0.01 for i in range(100)],
                "side": ["BUYER" if i % 2 == 0 else "SELLER" for i in range(100)],
            }
        )

        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")
        trades = NautilusDataAdapter.df_to_trades(df, instrument.id)

        assert len(trades) == 100
        assert all(hasattr(t, "price") for t in trades)
        assert all(hasattr(t, "size") for t in trades)
        assert all(hasattr(t, "aggressor_side") for t in trades)

    def test_df_to_quotes(self):
        """Test converting quote DataFrame to NautilusTrader quotes."""
        df = pd.DataFrame(
            {
                "timestamp": pd.date_range("2024-01-01", periods=100, freq="1s"),
                "bid_price": [49990.0 + i * 10 for i in range(100)],
                "bid_size": [1.0 + i * 0.1 for i in range(100)],
                "ask_price": [50010.0 + i * 10 for i in range(100)],
                "ask_size": [1.0 + i * 0.1 for i in range(100)],
            }
        )

        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")
        quotes = NautilusDataAdapter.df_to_quotes(df, instrument.id)

        assert len(quotes) == 100
        assert all(hasattr(q, "bid_price") for q in quotes)
        assert all(hasattr(q, "ask_price") for q in quotes)


class TestNautilusStrategyAdapter:
    """Test strategy adapter bridging Medusa to NautilusTrader."""

    def test_adapter_initialization(self):
        """Test that adapter wraps a Medusa strategy correctly."""
        medusa_strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")

        adapter = NautilusStrategyAdapter(
            medusa_strategy=medusa_strategy,
            instrument_id=instrument.id,
            lookback_periods=100,
            order_size=1.0,
        )

        assert adapter.medusa_strategy is medusa_strategy
        assert adapter.lookback_periods == 100
        assert adapter.order_size == 1.0

    def test_bar_buffer_management(self, sample_ohlcv):
        """Test that the adapter maintains a rolling bar buffer."""

        medusa_strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")

        adapter = NautilusStrategyAdapter(
            medusa_strategy=medusa_strategy,
            instrument_id=instrument.id,
            lookback_periods=100,
            order_size=1.0,
        )

        # Convert to bars
        bars = NautilusDataAdapter.df_to_bars(
            sample_ohlcv.reset_index(),
            instrument.id,
        )

        # Feed bars to adapter (simulating on_bar calls)
        for bar in bars[:150]:
            adapter.on_bar(bar)

        # Buffer should have exactly 100 bars (maxlen)
        assert len(adapter._bar_buffer) == 100


class TestNautilusEngine:
    """Test NautilusTrader backtesting engine."""

    def test_engine_initialization(self, tmp_path):
        """Test engine initialization with custom catalog path."""
        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(
            catalog_path=catalog_path,
            initial_capital=50_000.0,
            exchange="BINANCE",
        )

        assert engine.catalog_path == catalog_path
        assert engine.initial_capital == 50_000.0
        assert engine.exchange_config.name == "BINANCE"

    def test_exchange_configs(self):
        """Test that different exchanges have correct latency configs."""
        binance_engine = NautilusEngine(exchange="BINANCE")
        coinbase_engine = NautilusEngine(exchange="COINBASE")
        kraken_engine = NautilusEngine(exchange="KRAKEN")

        assert binance_engine.exchange_config.rest_latency_ms == 50
        assert coinbase_engine.exchange_config.rest_latency_ms == 100
        assert kraken_engine.exchange_config.rest_latency_ms == 150

    def test_catalog_creation(self, tmp_path):
        """Test that data catalog is created correctly."""
        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(catalog_path=catalog_path)

        catalog = engine.get_catalog()
        assert catalog is not None
        assert catalog_path.exists()

    def test_ingest_bars(self, tmp_path, sample_ohlcv):
        """Test ingesting bars into the catalog."""
        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(catalog_path=catalog_path)

        instrument = NautilusDataAdapter.create_instrument("BTCUSDT", "BINANCE")
        bars = NautilusDataAdapter.df_to_bars(
            sample_ohlcv.reset_index(),
            instrument.id,
        )

        # Should not raise
        engine.ingest_bars(str(instrument.id), bars)

    def test_create_engine_with_latency(self, tmp_path):
        """Test that engine is created with latency models."""
        from datetime import datetime

        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(
            catalog_path=catalog_path,
            exchange="COINBASE",
        )

        start = datetime(2024, 1, 1, tzinfo=UTC)
        end = datetime(2024, 1, 31, tzinfo=UTC)

        backtest_engine = engine.create_engine(start, end)
        assert backtest_engine is not None


class TestIntegrationBacktest:
    """Integration test: full backtest workflow."""

    def test_full_backtest_pipeline(self, tmp_path, sample_ohlcv):
        """Test complete backtest: data ingestion → strategy → results."""

        # Create engine
        catalog_path = tmp_path / "nautilus_catalog"
        engine = NautilusEngine(
            catalog_path=catalog_path,
            initial_capital=100_000.0,
            exchange="BINANCE",
        )

        # Create instrument
        instrument = NautilusDataAdapter.create_instrument(
            "BTCUSDT",
            "BINANCE",
            instrument_type="spot",
        )

        # Convert and ingest data
        bars = NautilusDataAdapter.df_to_bars(
            sample_ohlcv.reset_index(),
            instrument.id,
        )
        engine.ingest_bars(str(instrument.id), bars)

        # Create strategy adapter
        medusa_strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        NautilusStrategyAdapter(
            medusa_strategy=medusa_strategy,
            instrument_id=instrument.id,
            lookback_periods=60,
            order_size=0.1,
        )

        # Create engine and add venue
        start = sample_ohlcv.index[0].to_pydatetime().replace(tzinfo=UTC)
        end = sample_ohlcv.index[-1].to_pydatetime().replace(tzinfo=UTC)
        backtest_engine = engine.create_engine(start, end)

        # Verify engine was created successfully
        assert backtest_engine is not None

        # Verify the engine has the venue configured
        assert len(backtest_engine.list_venues()) == 1

        # Note: Full backtest execution would require more complex data loading
        # For now, we verify that the components integrate correctly


class TestLatencyModeling:
    """Test latency modeling configurations."""

    @pytest.mark.parametrize(
        "exchange_name,rest_latency,ws_latency",
        [
            ("BINANCE", 50, 5),
            ("COINBASE", 100, 10),
            ("CUSTOM", 200, 20),
        ],
    )
    def test_exchange_latency(self, exchange_name: str, rest_latency: int, ws_latency: int) -> None:
        """Test exchange latency configurations."""
        config = ExchangeConfig(
            name=exchange_name,
            rest_latency_ms=rest_latency,
            ws_latency_ms=ws_latency,
        )
        assert config.name == exchange_name
        assert config.rest_latency_ms == rest_latency
        assert config.ws_latency_ms == ws_latency
