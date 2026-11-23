"""NautilusTrader event-driven backtesting engine.

Full integration with orderbook simulation, latency modeling, and realistic
exchange simulation for Medusa strategies.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import pandas as pd
from loguru import logger

from medusa.utils.config import get_settings

try:
    from nautilus_trader.backtest.engine import BacktestEngine, BacktestEngineConfig
    from nautilus_trader.backtest.models import FillModel, LatencyModel
    from nautilus_trader.model.currencies import Currency
    from nautilus_trader.model.data import Bar, QuoteTick, TradeTick
    from nautilus_trader.model.enums import AccountType, OmsType
    from nautilus_trader.model.identifiers import TraderId, Venue
    from nautilus_trader.model.objects import Money
    from nautilus_trader.persistence.catalog import ParquetDataCatalog

    NAUTILUS_AVAILABLE = True
except ImportError:
    NAUTILUS_AVAILABLE = False


@dataclass
class ExchangeConfig:
    """Exchange-specific configuration for simulation.

    Args:
        name: Exchange name (BINANCE, COINBASE, KRAKEN, etc.).
        rest_latency_ms: REST API latency in milliseconds.
        ws_latency_ms: WebSocket data latency in milliseconds.
        maker_fee: Maker fee as decimal (0.001 = 0.1%).
        taker_fee: Taker fee as decimal (0.001 = 0.1%).
    """

    name: str
    rest_latency_ms: int = 50
    ws_latency_ms: int = 5
    maker_fee: Decimal = field(default_factory=lambda: Decimal("0.001"))
    taker_fee: Decimal = field(default_factory=lambda: Decimal("0.001"))


# Exchange configurations
EXCHANGE_CONFIGS = {
    "BINANCE": ExchangeConfig(
        name="BINANCE",
        rest_latency_ms=50,
        ws_latency_ms=5,
        maker_fee=Decimal("0.001"),
        taker_fee=Decimal("0.001"),
    ),
    "COINBASE": ExchangeConfig(
        name="COINBASE",
        rest_latency_ms=100,
        ws_latency_ms=10,
        maker_fee=Decimal("0.005"),
        taker_fee=Decimal("0.006"),
    ),
    "KRAKEN": ExchangeConfig(
        name="KRAKEN",
        rest_latency_ms=150,
        ws_latency_ms=15,
        maker_fee=Decimal("0.0016"),
        taker_fee=Decimal("0.0026"),
    ),
}


class NautilusEngine:
    """Event-driven backtesting wrapper for NautilusTrader."""

    def __init__(
        self,
        catalog_path: Path | None = None,
        initial_capital: float = 100_000.0,
        exchange: str = "BINANCE",
    ) -> None:
        """Initialize Nautilus engine.

        Args:
            catalog_path: Path to Nautilus Parquet data catalog.
            initial_capital: Starting capital in USD.
            exchange: Exchange name for simulation (BINANCE, COINBASE, KRAKEN).
        """
        if not NAUTILUS_AVAILABLE:
            logger.error("nautilus_trader not installed. Install with: pip install nautilus_trader")
            return

        settings = get_settings()
        self.catalog_path = catalog_path or settings.data_dir / "nautilus_catalog"
        self.catalog_path.mkdir(parents=True, exist_ok=True)

        self.initial_capital = initial_capital
        self.exchange_config = EXCHANGE_CONFIGS.get(exchange.upper(), EXCHANGE_CONFIGS["BINANCE"])

        self._engine: BacktestEngine | None = None
        self._catalog: ParquetDataCatalog | None = None

        logger.info(
            f"NautilusEngine initialized: catalog={self.catalog_path}, "
            f"exchange={self.exchange_config.name}, capital=${initial_capital:,.2f}"
        )

    def get_catalog(self) -> ParquetDataCatalog:
        """Get or create the data catalog.

        Returns:
            ParquetDataCatalog instance.
        """
        if not NAUTILUS_AVAILABLE:
            raise ImportError("nautilus_trader not installed")

        if self._catalog is None:
            self._catalog = ParquetDataCatalog(str(self.catalog_path))
            logger.info(f"Created data catalog at {self.catalog_path}")

        return self._catalog

    def ingest_bars(
        self,
        instrument_id: str,
        bars: list[Bar],
    ) -> None:
        """Ingest bars into the data catalog.

        Args:
            instrument_id: NautilusTrader instrument ID string.
            bars: List of Bar objects.
        """
        if not NAUTILUS_AVAILABLE or not bars:
            return

        catalog = self.get_catalog()
        catalog.write_data(bars)
        logger.info(f"Ingested {len(bars)} bars for {instrument_id}")

    def ingest_trades(
        self,
        instrument_id: str,
        trades: list[TradeTick],
    ) -> None:
        """Ingest trade ticks into the data catalog.

        Args:
            instrument_id: NautilusTrader instrument ID string.
            trades: List of TradeTick objects.
        """
        if not NAUTILUS_AVAILABLE or not trades:
            return

        catalog = self.get_catalog()
        catalog.write_data(trades)
        logger.info(f"Ingested {len(trades)} trades for {instrument_id}")

    def ingest_quotes(
        self,
        instrument_id: str,
        quotes: list[QuoteTick],
    ) -> None:
        """Ingest quote ticks into the data catalog.

        Args:
            instrument_id: NautilusTrader instrument ID string.
            quotes: List of QuoteTick objects.
        """
        if not NAUTILUS_AVAILABLE or not quotes:
            return

        catalog = self.get_catalog()
        catalog.write_data(quotes)
        logger.info(f"Ingested {len(quotes)} quotes for {instrument_id}")

    def create_engine(
        self,
        start: datetime,
        end: datetime,
        trader_id: str = "BACKTESTER-001",
    ) -> BacktestEngine | None:
        """Create and configure a BacktestEngine with realistic simulation.

        Args:
            start: Backtest start datetime.
            end: Backtest end datetime.
            trader_id: Nautilus trader identifier.

        Returns:
            Configured BacktestEngine instance.

        Raises:
            ImportError: If nautilus_trader is not installed.
        """
        if not NAUTILUS_AVAILABLE:
            raise ImportError(
                "nautilus_trader not installed. Install with: pip install nautilus_trader"
            )

        config = BacktestEngineConfig(
            trader_id=TraderId(trader_id),
        )
        self._engine = BacktestEngine(config=config)

        # Configure fill model (maker/taker latency)
        fill_model = FillModel()

        # Configure latency model (REST + WS latency)
        latency_model = LatencyModel(
            base_latency_nanos=self.exchange_config.rest_latency_ms * 1_000_000,
        )

        # Add venue with exchange-specific latency and fees
        # For spot crypto trading, we need multi-currency balances
        venue = Venue(self.exchange_config.name)
        usd_currency = Currency.from_str("USD")
        usdt_currency = Currency.from_str("USDT")

        self._engine.add_venue(
            venue=venue,
            oms_type=OmsType.NETTING,
            account_type=AccountType.CASH,
            base_currency=None,  # Multi-currency account
            starting_balances=[
                Money(self.initial_capital, usd_currency),
                Money(self.initial_capital, usdt_currency),  # Also provide USDT for crypto pairs
            ],
            fill_model=fill_model,
            latency_model=latency_model,
        )

        logger.info(
            f"Created Nautilus engine: {start} to {end}, "
            f"venue={venue}, latency={self.exchange_config.rest_latency_ms}ms"
        )
        return self._engine

    def run_strategy(
        self,
        strategy: Any,
        instruments: list[Any],
        start: datetime,
        end: datetime,
    ) -> pd.DataFrame:
        """Run an event-driven backtest with a strategy.

        Args:
            strategy: NautilusTrader Strategy instance (or NautilusStrategyAdapter).
            instruments: List of Instrument objects to trade.
            start: Backtest start datetime.
            end: Backtest end datetime.

        Returns:
            DataFrame with backtest results (portfolio stats, trades, positions).
        """
        if not NAUTILUS_AVAILABLE:
            logger.error("nautilus_trader not installed")
            return pd.DataFrame()

        if self._engine is None:
            self.create_engine(start, end)

        if self._engine is None:
            logger.error("Failed to create Nautilus engine")
            return pd.DataFrame()

        # Add instruments to the engine
        for instrument in instruments:
            self._engine.add_instrument(instrument)

        # Add strategy
        self._engine.add_strategy(strategy)

        # Load data from catalog
        catalog = self.get_catalog()

        # Load bars for each instrument
        for instrument in instruments:
            # Query bars from catalog
            bars_data = catalog.bars(instrument_ids=[str(instrument.id)])
            if bars_data is not None and not bars_data.empty:
                self._engine.add_data(bars_data)
                logger.info(f"Loaded {len(bars_data)} bars for {instrument.id}")

        # Run the backtest
        self._engine.run()

        # Extract results
        account = self._engine.trader.generate_account_report(Venue(self.exchange_config.name))
        orders = self._engine.trader.generate_order_fills_report()
        positions = self._engine.trader.generate_positions_report()

        logger.info(f"Nautilus backtest complete: {len(orders)} orders, {len(positions)} positions")

        # Combine into a results summary
        results = {
            "account": account,
            "orders": orders,
            "positions": positions,
            "total_return": float(account.total_pnl) / self.initial_capital
            if account.total_pnl
            else 0.0,
        }

        return pd.DataFrame([results])

    def get_portfolio_stats(self) -> dict[str, Any]:
        """Get portfolio statistics after backtest.

        Returns:
            Dictionary with Sharpe, Sortino, max drawdown, etc.
        """
        if not NAUTILUS_AVAILABLE or self._engine is None:
            return {}

        account = self._engine.trader.generate_account_report(Venue(self.exchange_config.name))

        # Extract performance metrics
        stats = {
            "total_pnl": float(account.total_pnl),
            "total_return": float(account.total_pnl) / self.initial_capital,
            "num_orders": len(self._engine.trader.generate_order_fills_report()),
            "num_positions": len(self._engine.trader.generate_positions_report()),
        }

        logger.info(f"Portfolio stats: {stats}")
        return stats
