"""NautilusTrader data adapter for Medusa data formats.

Converts Medusa data (OHLCV DataFrames, trades, quotes) into NautilusTrader
format for realistic event-driven backtesting.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

import pandas as pd
from loguru import logger

try:
    from nautilus_trader.core.datetime import dt_to_unix_nanos
    from nautilus_trader.model.currencies import Currency
    from nautilus_trader.model.data import Bar, BarSpecification, BarType, QuoteTick, TradeTick
    from nautilus_trader.model.enums import (
        AggressorSide,
        BarAggregation,
        PriceType,
    )
    from nautilus_trader.model.identifiers import InstrumentId, Symbol, TradeId, Venue
    from nautilus_trader.model.instruments import CryptoPerpetual, CurrencyPair
    from nautilus_trader.model.objects import Money, Price, Quantity

    NAUTILUS_AVAILABLE = True
except ImportError:
    NAUTILUS_AVAILABLE = False


class NautilusDataAdapter:
    """Converts Medusa data formats to NautilusTrader objects."""

    def __init__(self) -> None:
        """Initialize the data adapter."""
        if not NAUTILUS_AVAILABLE:
            logger.warning(
                "nautilus_trader not available — adapter will not function. "
                "Install with: pip install nautilus_trader"
            )

    @staticmethod
    def create_instrument(
        symbol: str,
        venue: str = "BINANCE",
        instrument_type: str = "spot",
    ) -> Any:
        """Create a NautilusTrader instrument from symbol.

        Args:
            symbol: Trading pair symbol (e.g., 'BTCUSDT', 'ETHUSDT').
            venue: Exchange venue name.
            instrument_type: 'spot', 'perpetual', or 'future'.

        Returns:
            CurrencyPair, CryptoPerpetual, or CryptoFuture instrument.
        """
        if not NAUTILUS_AVAILABLE:
            return None

        # Parse symbol (e.g., BTCUSDT -> BTC/USDT)
        base = symbol[:-4] if len(symbol) > 4 else symbol[:3]
        quote = symbol[-4:] if len(symbol) > 4 else symbol[3:]

        instrument_id = InstrumentId(
            symbol=Symbol(symbol),
            venue=Venue(venue),
        )

        if instrument_type == "spot":
            return CurrencyPair(
                instrument_id=instrument_id,
                raw_symbol=Symbol(symbol),
                base_currency=Currency.from_str(base),
                quote_currency=Currency.from_str(quote),
                price_precision=2,
                size_precision=8,
                price_increment=Price.from_str("0.01"),
                size_increment=Quantity.from_str("0.00000001"),
                max_quantity=Quantity.from_str("9000.00000000"),
                min_quantity=Quantity.from_str("0.00000001"),
                max_price=Price.from_str("1000000.00"),
                min_price=Price.from_str("0.01"),
                margin_init=Decimal("0"),
                margin_maint=Decimal("0"),
                maker_fee=Decimal("0.001"),
                taker_fee=Decimal("0.001"),
                ts_event=0,
                ts_init=0,
            )
        elif instrument_type == "perpetual":
            return CryptoPerpetual(
                instrument_id=instrument_id,
                raw_symbol=Symbol(symbol),
                base_currency=Currency.from_str(base),
                quote_currency=Currency.from_str(quote),
                settlement_currency=Currency.from_str(quote),
                is_inverse=False,
                price_precision=2,
                size_precision=8,
                price_increment=Price.from_str("0.01"),
                size_increment=Quantity.from_str("0.00000001"),
                max_quantity=Quantity.from_str("9000.00000000"),
                min_quantity=Quantity.from_str("0.00000001"),
                max_notional=None,
                min_notional=Money.from_str("10.00 USDT"),
                max_price=Price.from_str("1000000.00"),
                min_price=Price.from_str("0.01"),
                margin_init=Decimal("0.05"),
                margin_maint=Decimal("0.025"),
                maker_fee=Decimal("0.0002"),
                taker_fee=Decimal("0.0004"),
                ts_event=0,
                ts_init=0,
            )
        else:
            raise ValueError(f"Unsupported instrument_type: {instrument_type!r}")

    @staticmethod
    def df_to_bars(
        df: pd.DataFrame,
        instrument_id: InstrumentId,
        bar_type: BarType | None = None,
    ) -> list[Bar]:
        """Convert OHLCV DataFrame to NautilusTrader Bars.

        Args:
            df: DataFrame with columns: timestamp, open, high, low, close, volume.
            instrument_id: NautilusTrader instrument identifier.
            bar_type: BarType (if None, creates a 1-MINUTE BAR).

        Returns:
            List of Bar objects.
        """
        if not NAUTILUS_AVAILABLE:
            return []

        if df.empty:
            logger.warning(f"Empty DataFrame passed to df_to_bars for {instrument_id}")
            return []

        if bar_type is None:
            bar_spec = BarSpecification(
                step=1,
                aggregation=BarAggregation.MINUTE,
                price_type=PriceType.LAST,
            )
            bar_type = BarType(
                instrument_id=instrument_id,
                bar_spec=bar_spec,
            )

        bars: list[Bar] = []
        # Row-by-row iteration required: NautilusTrader Bar objects
        # must be constructed individually (no vectorized constructor available)
        for _, row in df.iterrows():
            ts = row.get("timestamp", row.name)
            if isinstance(ts, pd.Timestamp):
                ts_ns = int(ts.value)
            elif isinstance(ts, datetime):
                ts_ns = dt_to_unix_nanos(ts)
            else:
                # Assume epoch seconds
                ts_ns = int(ts * 1_000_000_000)

            # Ensure OHLC is valid: high >= max(open, close), low <= min(open, close)
            open_val = float(row["open"])
            high_val = float(row["high"])
            low_val = float(row["low"])
            close_val = float(row["close"])

            # Fix invalid OHLC data
            high_val = max(high_val, open_val, close_val)
            low_val = min(low_val, open_val, close_val)

            bar = Bar(
                bar_type=bar_type,
                open=Price.from_str(f"{open_val:.8f}"),
                high=Price.from_str(f"{high_val:.8f}"),
                low=Price.from_str(f"{low_val:.8f}"),
                close=Price.from_str(f"{close_val:.8f}"),
                volume=Quantity.from_str(f"{row['volume']:.8f}"),
                ts_event=ts_ns,
                ts_init=ts_ns,
            )
            bars.append(bar)

        logger.info(f"Converted {len(bars)} bars for {instrument_id}")
        return bars

    @staticmethod
    def df_to_trades(
        df: pd.DataFrame,
        instrument_id: InstrumentId,
    ) -> list[TradeTick]:
        """Convert trade DataFrame to NautilusTrader TradeTicks.

        Args:
            df: DataFrame with columns: timestamp, price, size, side (optional).
            instrument_id: NautilusTrader instrument identifier.

        Returns:
            List of TradeTick objects.
        """
        if not NAUTILUS_AVAILABLE:
            return []

        if df.empty:
            logger.warning(f"Empty DataFrame passed to df_to_trades for {instrument_id}")
            return []

        trades: list[TradeTick] = []
        # Row-by-row iteration required: NautilusTrader TradeTick objects
        # must be constructed individually (no vectorized constructor available)
        for idx, row in df.iterrows():
            ts = row.get("timestamp", row.name)
            if isinstance(ts, pd.Timestamp):
                ts_ns = int(ts.value)
            elif isinstance(ts, datetime):
                ts_ns = dt_to_unix_nanos(ts)
            else:
                ts_ns = int(ts * 1_000_000_000)

            side_str = row.get("side", "BUYER")
            aggressor_side = AggressorSide.BUYER if side_str == "BUYER" else AggressorSide.SELLER

            trade = TradeTick(
                instrument_id=instrument_id,
                price=Price.from_str(f"{row['price']:.8f}"),
                size=Quantity.from_str(f"{row['size']:.8f}"),
                aggressor_side=aggressor_side,
                trade_id=TradeId(f"{idx}"),
                ts_event=ts_ns,
                ts_init=ts_ns,
            )
            trades.append(trade)

        logger.info(f"Converted {len(trades)} trades for {instrument_id}")
        return trades

    @staticmethod
    def df_to_quotes(
        df: pd.DataFrame,
        instrument_id: InstrumentId,
    ) -> list[QuoteTick]:
        """Convert quote DataFrame to NautilusTrader QuoteTicks.

        Args:
            df: DataFrame with columns: timestamp, bid_price, bid_size, ask_price, ask_size.
            instrument_id: NautilusTrader instrument identifier.

        Returns:
            List of QuoteTick objects.
        """
        if not NAUTILUS_AVAILABLE:
            return []

        if df.empty:
            logger.warning(f"Empty DataFrame passed to df_to_quotes for {instrument_id}")
            return []

        quotes: list[QuoteTick] = []
        # Row-by-row iteration required: NautilusTrader QuoteTick objects
        # must be constructed individually (no vectorized constructor available)
        for _, row in df.iterrows():
            ts = row.get("timestamp", row.name)
            if isinstance(ts, pd.Timestamp):
                ts_ns = int(ts.value)
            elif isinstance(ts, datetime):
                ts_ns = dt_to_unix_nanos(ts)
            else:
                ts_ns = int(ts * 1_000_000_000)

            quote = QuoteTick(
                instrument_id=instrument_id,
                bid_price=Price.from_str(f"{row['bid_price']:.8f}"),
                ask_price=Price.from_str(f"{row['ask_price']:.8f}"),
                bid_size=Quantity.from_str(f"{row['bid_size']:.8f}"),
                ask_size=Quantity.from_str(f"{row['ask_size']:.8f}"),
                ts_event=ts_ns,
                ts_init=ts_ns,
            )
            quotes.append(quote)

        logger.info(f"Converted {len(quotes)} quotes for {instrument_id}")
        return quotes
