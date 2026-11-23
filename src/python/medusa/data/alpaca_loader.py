"""Alpaca Markets historical data loader for US equities."""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any

import pandas as pd
from loguru import logger

try:
    from alpaca.data import StocksHistoricalDataClient
    from alpaca.data.requests import (
        StockBarsRequest,
        StockQuotesRequest,
        StockSnapshotRequest,
        StockTradesRequest,
    )
    from alpaca.data.timeframe import TimeFrame

    ALPACA_AVAILABLE = True
except ImportError:
    ALPACA_AVAILABLE = False
    logger.warning("alpaca-py not installed - AlpacaHistoricalLoader unavailable")


class AlpacaHistoricalLoader:
    """Load historical equity data from Alpaca Markets API."""

    def __init__(self, api_key: str | None = None, secret_key: str | None = None) -> None:
        """Initialize Alpaca data client.

        Args:
            api_key: Alpaca API key (defaults to ALPACA_API_KEY env var)
            secret_key: Alpaca secret key (defaults to ALPACA_SECRET_KEY env var)

        Raises:
            ImportError: If alpaca-py is not installed
            ValueError: If API keys are not provided and not in environment
        """
        if not ALPACA_AVAILABLE:
            raise ImportError("alpaca-py is not installed. Install with: pip install alpaca-py")

        self.api_key = api_key or os.getenv("ALPACA_API_KEY")
        self.secret_key = secret_key or os.getenv("ALPACA_SECRET_KEY")

        if not self.api_key or not self.secret_key:
            raise ValueError(
                "Alpaca API keys not found. Set ALPACA_API_KEY and ALPACA_SECRET_KEY "
                "environment variables or pass them to constructor."
            )

        self.client = StocksHistoricalDataClient(
            api_key=self.api_key,
            secret_key=self.secret_key,
        )
        logger.info("Alpaca historical data client initialized")

    def load_bars(
        self,
        symbol: str,
        start: str,
        end: str,
        timeframe: str = "1Day",
    ) -> pd.DataFrame:
        """Load OHLCV bars for a symbol.

        Args:
            symbol: Stock symbol (e.g., "AAPL")
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)
            timeframe: Timeframe (e.g., "1Min", "5Min", "1Hour", "1Day")

        Returns:
            DataFrame with columns: timestamp, open, high, low, close, volume, vwap, trade_count
        """
        # Map timeframe string to Alpaca TimeFrame
        tf_map = {
            "1Min": TimeFrame.Minute,
            "5Min": TimeFrame(5, "Min"),
            "15Min": TimeFrame(15, "Min"),
            "1Hour": TimeFrame.Hour,
            "1Day": TimeFrame.Day,
        }

        if timeframe not in tf_map:
            raise ValueError(
                f"Unsupported timeframe: {timeframe}. Supported: {list(tf_map.keys())}"
            )

        request = StockBarsRequest(
            symbol_or_symbols=symbol,
            timeframe=tf_map[timeframe],
            start=datetime.fromisoformat(start),
            end=datetime.fromisoformat(end),
        )

        bars = self.client.get_stock_bars(request)

        # Convert to DataFrame
        df = bars.df

        if df.empty:
            logger.warning(f"No bar data returned for {symbol} ({start} to {end})")
            return pd.DataFrame()

        # Reset index to get symbol and timestamp as columns
        df = df.reset_index()

        # Rename columns to match Medusa schema
        df = df.rename(
            columns={
                "timestamp": "timestamp",
                "open": "open",
                "high": "high",
                "low": "low",
                "close": "close",
                "volume": "volume",
                "vwap": "vwap",
                "trade_count": "trade_count",
            }
        )

        logger.info(f"Loaded {len(df)} bars for {symbol} ({timeframe})")
        return df[["timestamp", "open", "high", "low", "close", "volume", "vwap", "trade_count"]]

    def load_trades(
        self,
        symbol: str,
        start: str,
        end: str,
    ) -> pd.DataFrame:
        """Load trade ticks for a symbol.

        Args:
            symbol: Stock symbol
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)

        Returns:
            DataFrame with columns: timestamp, price, size, exchange, conditions
        """
        request = StockTradesRequest(
            symbol_or_symbols=symbol,
            start=datetime.fromisoformat(start),
            end=datetime.fromisoformat(end),
        )

        trades = self.client.get_stock_trades(request)
        df = trades.df

        if df.empty:
            logger.warning(f"No trade data returned for {symbol} ({start} to {end})")
            return pd.DataFrame()

        df = df.reset_index()

        # Rename columns
        df = df.rename(
            columns={
                "timestamp": "timestamp",
                "price": "price",
                "size": "size",
                "exchange": "exchange",
                "conditions": "conditions",
            }
        )

        logger.info(f"Loaded {len(df)} trades for {symbol}")
        return df[["timestamp", "price", "size", "exchange", "conditions"]]

    def load_quotes(
        self,
        symbol: str,
        start: str,
        end: str,
    ) -> pd.DataFrame:
        """Load quote data (bid/ask) for a symbol.

        Args:
            symbol: Stock symbol
            start: Start date (YYYY-MM-DD format)
            end: End date (YYYY-MM-DD format)

        Returns:
            DataFrame with columns: timestamp, bid_price, bid_size, ask_price, ask_size
        """
        request = StockQuotesRequest(
            symbol_or_symbols=symbol,
            start=datetime.fromisoformat(start),
            end=datetime.fromisoformat(end),
        )

        quotes = self.client.get_stock_quotes(request)
        df = quotes.df

        if df.empty:
            logger.warning(f"No quote data returned for {symbol} ({start} to {end})")
            return pd.DataFrame()

        df = df.reset_index()

        # Rename columns
        df = df.rename(
            columns={
                "timestamp": "timestamp",
                "bid_price": "bid_price",
                "bid_size": "bid_size",
                "ask_price": "ask_price",
                "ask_size": "ask_size",
            }
        )

        logger.info(f"Loaded {len(df)} quotes for {symbol}")
        return df[["timestamp", "bid_price", "bid_size", "ask_price", "ask_size"]]

    def get_snapshot(self, symbols: list[str]) -> pd.DataFrame:
        """Get current market snapshot for multiple symbols.

        Args:
            symbols: List of stock symbols

        Returns:
            DataFrame with latest quote, trade, and bar data for each symbol
        """
        request = StockSnapshotRequest(symbol_or_symbols=symbols)
        snapshots = self.client.get_stock_snapshot(request)

        rows = []
        for symbol, snapshot in snapshots.items():
            row = {
                "symbol": symbol,
                "timestamp": snapshot.latest_trade.timestamp if snapshot.latest_trade else None,
                "price": snapshot.latest_trade.price if snapshot.latest_trade else None,
                "bid_price": (snapshot.latest_quote.bid_price if snapshot.latest_quote else None),
                "ask_price": (snapshot.latest_quote.ask_price if snapshot.latest_quote else None),
                "bid_size": (snapshot.latest_quote.bid_size if snapshot.latest_quote else None),
                "ask_size": (snapshot.latest_quote.ask_size if snapshot.latest_quote else None),
                "daily_open": snapshot.daily_bar.open if snapshot.daily_bar else None,
                "daily_high": snapshot.daily_bar.high if snapshot.daily_bar else None,
                "daily_low": snapshot.daily_bar.low if snapshot.daily_bar else None,
                "daily_close": snapshot.daily_bar.close if snapshot.daily_bar else None,
                "daily_volume": snapshot.daily_bar.volume if snapshot.daily_bar else None,
            }
            rows.append(row)

        df = pd.DataFrame(rows)
        logger.info(f"Loaded snapshots for {len(df)} symbols")
        return df

    def get_asset_info(self, symbol: str) -> dict[str, Any]:
        """Get asset metadata (placeholder - requires Alpaca Trading API).

        Note: This requires the Alpaca Trading API client, not just data API.
        Returns stub data for now.

        Args:
            symbol: Stock symbol

        Returns:
            Dictionary with asset metadata
        """
        logger.warning(f"get_asset_info({symbol}) is not implemented - requires Alpaca Trading API")
        return {
            "symbol": symbol,
            "name": f"{symbol} Inc.",
            "asset_class": "us_equity",
            "exchange": "NASDAQ",
            "status": "active",
        }
