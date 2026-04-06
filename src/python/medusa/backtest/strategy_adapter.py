"""Adapter bridging Medusa signal strategies to NautilusTrader format.

NautilusTrader uses class-based strategies with on_bar / on_trade handlers.
This adapter wraps Medusa's signal-based strategies so they can run in
the Nautilus event-driven engine.

Full implementation pending NautilusTrader deep integration.
"""

from __future__ import annotations

from typing import Any

from loguru import logger


class StrategyAdapter:
    """Bridge between Medusa BaseStrategy and NautilusTrader Strategy.

    Converts signal-based strategies (entries/exits boolean arrays) into
    NautilusTrader event-driven callbacks.
    """

    def __init__(self, medusa_strategy: Any) -> None:
        """Initialize adapter.

        Args:
            medusa_strategy: A Medusa BaseStrategy instance.
        """
        self.medusa_strategy = medusa_strategy
        logger.info(
            f"Adapter wrapping {type(medusa_strategy).__name__} for Nautilus"
        )

    def to_nautilus_strategy(self) -> Any:
        """Convert to a NautilusTrader Strategy instance.

        Returns:
            Nautilus Strategy (placeholder — returns None until full integration).
        """
        logger.warning(
            "NautilusTrader strategy adapter is a skeleton. "
            "Full conversion not yet implemented."
        )
        return None
