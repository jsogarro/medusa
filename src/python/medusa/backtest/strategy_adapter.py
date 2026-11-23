"""Adapter bridging Medusa signal strategies to NautilusTrader format.

NautilusTrader uses class-based strategies with on_bar / on_trade handlers.
This adapter wraps Medusa's signal-based strategies so they can run in
the Nautilus event-driven engine.
"""

from __future__ import annotations

from collections import deque
from typing import Any

import pandas as pd
from loguru import logger

try:
    from nautilus_trader.model.data import Bar, BarType
    from nautilus_trader.model.enums import OrderSide, TimeInForce
    from nautilus_trader.model.identifiers import InstrumentId
    from nautilus_trader.trading.strategy import Strategy

    NAUTILUS_AVAILABLE = True
except ImportError:
    NAUTILUS_AVAILABLE = False
    Strategy = object  # type: ignore


class NautilusStrategyAdapter(Strategy):  # type: ignore
    """Wraps a Medusa BaseStrategy for NautilusTrader execution.

    Maintains a rolling window of bars, generates signals from Medusa strategy,
    and translates them into NautilusTrader orders.
    """

    def __init__(
        self,
        medusa_strategy: Any,
        instrument_id: InstrumentId,
        lookback_periods: int = 100,
        order_size: float = 1.0,
    ) -> None:
        """Initialize the strategy adapter.

        Args:
            medusa_strategy: A Medusa BaseStrategy instance.
            instrument_id: NautilusTrader instrument ID to trade.
            lookback_periods: Number of bars to maintain in buffer.
            order_size: Order size for each signal (in base currency).
        """
        if not NAUTILUS_AVAILABLE:
            raise ImportError(
                "nautilus_trader not installed. Install with: pip install nautilus_trader"
            )

        super().__init__()
        self.medusa_strategy = medusa_strategy
        self.instrument_id = instrument_id
        self.lookback_periods = lookback_periods
        self.order_size = order_size

        # Rolling window of OHLCV data
        self._bar_buffer: deque[dict[str, Any]] = deque(maxlen=lookback_periods)
        self._position_open = False

        logger.info(
            f"NautilusStrategyAdapter initialized: {type(medusa_strategy).__name__} "
            f"for {instrument_id}, lookback={lookback_periods}"
        )

    def on_start(self) -> None:
        """Called when strategy starts."""
        from nautilus_trader.model.data import BarSpecification
        from nautilus_trader.model.enums import BarAggregation, PriceType

        logger.info("Strategy starting")
        bar_spec = BarSpecification(
            step=1,
            aggregation=BarAggregation.MINUTE,
            price_type=PriceType.LAST,
        )
        bar_type = BarType(instrument_id=self.instrument_id, bar_spec=bar_spec)
        self.subscribe_bars(bar_type)

    def on_bar(self, bar: Bar) -> None:
        """Handle incoming bar data.

        Args:
            bar: NautilusTrader Bar object.
        """
        # Add bar to buffer
        self._bar_buffer.append(
            {
                "timestamp": pd.Timestamp(bar.ts_event, unit="ns"),
                "open": float(bar.open),
                "high": float(bar.high),
                "low": float(bar.low),
                "close": float(bar.close),
                "volume": float(bar.volume),
            }
        )

        # Wait until we have enough data
        if len(self._bar_buffer) < self.lookback_periods:
            return

        # Convert buffer to DataFrame
        df = pd.DataFrame(list(self._bar_buffer))
        df.set_index("timestamp", inplace=True)

        # Generate signal using Medusa strategy
        signal = self.medusa_strategy.generate_signal(df)

        if signal is None:
            return

        action = signal.get("action")
        if action == "buy" and not self._position_open:
            self._submit_market_order(OrderSide.BUY, self.order_size)
            self._position_open = True
            logger.info(f"BUY signal: {signal}")

        elif action == "sell" and self._position_open:
            self._submit_market_order(OrderSide.SELL, self.order_size)
            self._position_open = False
            logger.info(f"SELL signal: {signal}")

    def _submit_market_order(self, side: OrderSide, size: float) -> None:
        """Submit a market order.

        Args:
            side: BUY or SELL.
            size: Order size in base currency.
        """
        from nautilus_trader.model.objects import Quantity

        # Guard against None order_factory (during testing outside engine)
        if self.order_factory is None:
            logger.warning("order_factory is None — skipping order submission (testing mode?)")
            return

        order = self.order_factory.market(
            instrument_id=self.instrument_id,
            order_side=side,
            quantity=Quantity.from_str(f"{size:.8f}"),
            time_in_force=TimeInForce.GTC,
        )
        self.submit_order(order)

    def on_order_filled(self, event: Any) -> None:
        """Handle order fill events.

        Args:
            event: OrderFilled event.
        """
        logger.info(f"Order filled: {event}")

    def on_stop(self) -> None:
        """Called when strategy stops."""
        logger.info("Strategy stopped")
        # Close any open positions
        if self._position_open:
            self._submit_market_order(OrderSide.SELL, self.order_size)
