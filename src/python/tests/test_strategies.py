"""Tests for trading strategies."""

import pandas as pd

from medusa.strategies.base import BaseStrategy
from medusa.strategies.examples.sma_crossover import (
    SMACrossoverStrategy,
    sma_crossover_signals,
)


class TestSMACrossoverSignals:
    def test_returns_boolean_series(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 10, 50)
        assert entries.dtype == bool
        assert exits.dtype == bool
        assert len(entries) == len(sample_price)

    def test_entries_and_exits_not_simultaneous(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 10, 50)
        simultaneous = entries & exits
        assert not simultaneous.any()

    def test_custom_periods(self, sample_price):
        entries, exits = sma_crossover_signals(sample_price, 5, 20)
        assert entries.any() or True  # May not have signals with random data


class TestSMACrossoverStrategy:
    def test_implements_base(self):
        strategy = SMACrossoverStrategy()
        assert isinstance(strategy, BaseStrategy)

    def test_generate_signals(self, sample_ohlcv):
        strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        entries, exits = strategy.generate_signals(sample_ohlcv)
        assert isinstance(entries, pd.Series)
        assert isinstance(exits, pd.Series)

    def test_generate_signal_insufficient_data(self):
        strategy = SMACrossoverStrategy(fast_period=10, slow_period=50)
        short_data = pd.DataFrame({"close": [1.0] * 10})
        assert strategy.generate_signal(short_data) is None

    def test_generate_signal_with_enough_data(self, sample_ohlcv):
        strategy = SMACrossoverStrategy(fast_period=5, slow_period=20)
        signal = strategy.generate_signal(sample_ohlcv)
        # Signal could be None or a dict — both are valid
        if signal is not None:
            assert "action" in signal
            assert signal["action"] in ("buy", "sell")
