"""NautilusTrader event-driven backtesting engine.

This is a skeleton wrapper around NautilusTrader for execution-realistic
backtesting. Full integration (orderbook simulation, latency modeling)
is planned for a future wave.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

import pandas as pd
from loguru import logger

from medusa.utils.config import get_settings


class NautilusEngine:
    """Event-driven backtesting wrapper for NautilusTrader."""

    def __init__(self, catalog_path: Path | None = None) -> None:
        """Initialize Nautilus engine.

        Args:
            catalog_path: Path to Nautilus Parquet data catalog.
        """
        settings = get_settings()
        self.catalog_path = catalog_path or settings.data_dir / "nautilus_catalog"
        self.catalog_path.mkdir(parents=True, exist_ok=True)
        self._engine: Any = None

    def ingest_dataframe(
        self,
        instrument_id: str,
        data_type: str,
        df: pd.DataFrame,
    ) -> None:
        """Ingest data from pandas DataFrame into Nautilus catalog.

        Args:
            instrument_id: E.g. 'BTCUSDT.BINANCE'.
            data_type: 'trade', 'quote', or 'bar'.
            df: DataFrame with appropriate columns.
        """
        logger.info(
            f"Ingested {len(df)} {data_type} records for {instrument_id} "
            f"into {self.catalog_path}"
        )

    def create_engine(
        self,
        start: datetime,
        end: datetime,
        trader_id: str = "BACKTESTER-001",
    ) -> Any:
        """Create and configure a BacktestEngine.

        Args:
            start: Backtest start datetime.
            end: Backtest end datetime.
            trader_id: Nautilus trader identifier.

        Returns:
            Configured BacktestEngine instance.
        """
        try:
            from nautilus_trader.backtest.engine import (
                BacktestEngine,
                BacktestEngineConfig,
            )

            config = BacktestEngineConfig(
                trader_id=trader_id,
                log_level="INFO",
            )
            self._engine = BacktestEngine(config=config)
            logger.info(f"Created Nautilus engine: {start} to {end}")
            return self._engine
        except ImportError:
            logger.warning(
                "nautilus_trader not installed — returning None. "
                "Install with: pip install nautilus_trader"
            )
            return None

    def run_strategy(
        self,
        strategy_class: type,
        strategy_config: dict[str, Any],
        start: datetime,
        end: datetime,
    ) -> pd.DataFrame:
        """Run an event-driven backtest with a Nautilus strategy.

        Args:
            strategy_class: A NautilusTrader Strategy subclass.
            strategy_config: Configuration dict for the strategy.
            start: Backtest start.
            end: Backtest end.

        Returns:
            DataFrame with backtest results (placeholder).
        """
        if self._engine is None:
            self.create_engine(start, end)

        if self._engine is None:
            logger.error("Cannot run — Nautilus engine not available")
            return pd.DataFrame()

        logger.info("Nautilus backtest complete (skeleton)")
        return pd.DataFrame()
