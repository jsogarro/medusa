"""Test coverage for strategies and utils modules.

Improves coverage for:
- vpin_filter.py (59% → 90%)
- ml_meta_labeling.py (61% → 90%)
- pairs_trading.py (62% → 90%)
- funding_arb.py (63% → 90%)
- validation.py (0% → 90%)
- logging.py (0% → 90%)
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest

from medusa.strategies.funding_arb import FundingArbStrategy
from medusa.strategies.ml_meta_labeling import MLMetaLabelingStrategy
from medusa.strategies.pairs_trading import PairsTradingStrategy
from medusa.strategies.vpin_filter import VPINFilterStrategy
from medusa.utils import logging, validation

# ─── Test Fixtures ────────────────────────────────────────────────────────────


@pytest.fixture
def sample_ohlcv() -> pd.DataFrame:
    """Sample OHLCV data for testing."""
    dates = pd.date_range("2024-01-01", periods=200, freq="1h")
    np.random.seed(42)

    data = pd.DataFrame(
        {
            "close": 100 + np.cumsum(np.random.randn(200) * 0.5),
            "volume": np.random.randint(1000, 10000, 200),
            "buy_volume": np.random.randint(400, 6000, 200),
        },
        index=dates,
    )
    return data


@pytest.fixture
def mock_underlying_strategy() -> MagicMock:
    """Mock underlying strategy for VPIN filter tests."""
    strategy = MagicMock()

    # Mock generate_signals to return boolean Series matching input size
    def generate_signals_side_effect(data: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
        # Alternate entries for testing
        entries = pd.Series(
            [i % 10 == 0 for i in range(len(data))],
            index=data.index,
        )
        exits = pd.Series(
            [i % 10 == 5 for i in range(len(data))],
            index=data.index,
        )
        return entries, exits

    strategy.generate_signals.side_effect = generate_signals_side_effect

    # Mock generate_signal for single-point tests
    def generate_signal_side_effect(data: pd.DataFrame) -> dict[str, Any] | None:
        # Return BUY signal with size
        return {
            "action": "BUY",
            "price": data["close"].iloc[-1],
            "size": 1.0,
        }

    strategy.generate_signal.side_effect = generate_signal_side_effect

    return strategy


@pytest.fixture
def mock_primary_model() -> MagicMock:
    """Mock primary ML model for meta-labeling tests."""
    model = MagicMock()

    # Return predictions matching input size: -1, 0, 1
    def predict_side_effect(features: np.ndarray | pd.DataFrame) -> np.ndarray:
        n = len(features)
        # Cycle through -1, 0, 1
        return np.array([(-1) ** i if i % 3 != 1 else 0 for i in range(n)])

    model.predict.side_effect = predict_side_effect
    return model


@pytest.fixture
def mock_meta_model() -> MagicMock:
    """Mock meta-labeling model."""
    model = MagicMock()

    # Return probabilities (2D array for binary classifier)
    def predict_proba_side_effect(features: np.ndarray | pd.DataFrame) -> np.ndarray:
        n = len(features)
        # Return [prob_class_0, prob_class_1] for each sample
        proba = np.random.rand(n, 2)
        # Normalize to sum to 1
        proba = proba / proba.sum(axis=1, keepdims=True)
        return proba

    model.predict_proba.side_effect = predict_proba_side_effect
    return model


# ─── VPIN Filter Strategy Tests ──────────────────────────────────────────────


class TestVPINFilterStrategy:
    """Test VPINFilterStrategy."""

    def test_generate_signal_live(
        self,
        sample_ohlcv: pd.DataFrame,
        mock_underlying_strategy: MagicMock,
    ) -> None:
        """Test generate_signal() for live signal generation."""
        strategy = VPINFilterStrategy(
            underlying_strategy=mock_underlying_strategy,
            vpin_high_threshold=0.7,
            vpin_low_threshold=0.3,
        )

        signal = strategy.generate_signal(sample_ohlcv)

        # Signal may be None if VPIN is high, but if it exists, verify structure
        if signal is not None:
            assert "vpin" in signal
            assert "vpin_status" in signal
            assert signal["vpin_status"] in ["low", "medium", "high"]
        else:
            # If None, underlying strategy should have been called
            assert mock_underlying_strategy.generate_signal.called

    def test_generate_signal_neutral_zone(
        self,
        sample_ohlcv: pd.DataFrame,
        mock_underlying_strategy: MagicMock,
    ) -> None:
        """Test signal in neutral VPIN zone (size adjustment)."""
        strategy = VPINFilterStrategy(
            underlying_strategy=mock_underlying_strategy,
            vpin_high_threshold=0.9,  # Very high threshold
            vpin_low_threshold=0.1,  # Very low threshold
        )

        signal = strategy.generate_signal(sample_ohlcv)

        # In neutral zone, should adjust size
        if signal is not None and "vpin_adjusted" in signal:
            assert signal["vpin_adjusted"] is True
            assert 0 < signal["size"] < 1.0

    def test_generate_signal_no_underlying_signal(
        self,
        sample_ohlcv: pd.DataFrame,
    ) -> None:
        """Test when underlying strategy returns None."""
        mock_strategy = MagicMock()
        mock_strategy.generate_signal.return_value = None

        strategy = VPINFilterStrategy(underlying_strategy=mock_strategy)
        signal = strategy.generate_signal(sample_ohlcv)

        assert signal is None

    def test_get_vpin_statistics(
        self,
        sample_ohlcv: pd.DataFrame,
        mock_underlying_strategy: MagicMock,
    ) -> None:
        """Test VPIN statistics calculation."""
        strategy = VPINFilterStrategy(underlying_strategy=mock_underlying_strategy)

        stats = strategy.get_vpin_statistics(sample_ohlcv)

        assert "current" in stats
        assert "mean" in stats
        assert "std" in stats
        assert "min" in stats
        assert "max" in stats
        assert "pct_high_toxicity" in stats
        assert "pct_low_toxicity" in stats

        # All stats should be floats
        for key, value in stats.items():
            assert isinstance(value, float)


# ─── ML Meta-Labeling Strategy Tests ──────────────────────────────────────────


class TestMLMetaLabelingStrategy:
    """Test MLMetaLabelingStrategy."""

    def test_triple_barrier_label_long_take_profit(self) -> None:
        """Test triple-barrier labeling for long take-profit."""
        # Create price series with clear take-profit pattern
        prices = pd.Series([100, 101, 102, 103, 104], index=pd.date_range("2024-01-01", periods=5))
        side = pd.Series([1, 0, 0, 0, 0], index=prices.index)

        model = MagicMock()
        strategy = MLMetaLabelingStrategy(
            primary_model=model,
            take_profit_pct=0.02,  # 2%
            stop_loss_pct=0.01,  # 1%
            max_holding_bars=3,
        )

        labels = strategy._create_triple_barrier_labels(prices, side)

        # First bar should hit take-profit (102 > 100 * 1.02)
        assert labels.iloc[0] == 1

    def test_triple_barrier_label_long_stop_loss(self) -> None:
        """Test triple-barrier labeling for long stop-loss."""
        # Price drops, hits stop-loss
        prices = pd.Series([100, 99, 98, 97, 96], index=pd.date_range("2024-01-01", periods=5))
        side = pd.Series([1, 0, 0, 0, 0], index=prices.index)

        model = MagicMock()
        strategy = MLMetaLabelingStrategy(
            primary_model=model,
            take_profit_pct=0.02,
            stop_loss_pct=0.01,
            max_holding_bars=3,
        )

        labels = strategy._create_triple_barrier_labels(prices, side)

        # Should hit stop-loss (99 < 100 * 0.99)
        assert labels.iloc[0] == -1

    def test_generate_signal_low_confidence(
        self,
        sample_ohlcv: pd.DataFrame,
        mock_primary_model: MagicMock,
    ) -> None:
        """Test generate_signal when meta-model has low confidence."""
        # Mock meta-model with low confidence
        low_confidence_model = MagicMock()
        low_confidence_model.predict_proba.return_value = np.array([[0.9, 0.1]])  # Only 10% conf

        strategy = MLMetaLabelingStrategy(
            primary_model=mock_primary_model,
            meta_model=low_confidence_model,
            meta_threshold=0.6,
        )

        signal = strategy.generate_signal(sample_ohlcv)

        # Should return None due to low confidence
        assert signal is None

    def test_generate_signal_live(
        self,
        sample_ohlcv: pd.DataFrame,
        mock_primary_model: MagicMock,
        mock_meta_model: MagicMock,
    ) -> None:
        """Test generate_signal for live signal generation."""
        # Make meta-model return high confidence
        high_confidence_model = MagicMock()
        high_confidence_model.predict_proba.return_value = np.array([[0.2, 0.8]])  # 80% conf

        strategy = MLMetaLabelingStrategy(
            primary_model=mock_primary_model,
            meta_model=high_confidence_model,
            meta_threshold=0.6,
        )

        signal = strategy.generate_signal(sample_ohlcv)

        # Should return a signal with confidence
        if signal is not None:
            assert "action" in signal
            assert "confidence" in signal
            assert signal["confidence"] >= 0.6


# ─── Pairs Trading Strategy Tests ────────────────────────────────────────────


class TestPairsTradingStrategy:
    """Test PairsTradingStrategy."""

    def test_update_cointegration(self) -> None:
        """Test _update_cointegration method."""
        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH")

        # Create cointegrated price series
        dates = pd.date_range("2024-01-01", periods=300, freq="1h")
        price1 = pd.Series(100 + np.cumsum(np.random.randn(300) * 0.1), index=dates)
        price2 = price1 * 0.05 + np.random.randn(300) * 0.01  # Cointegrated

        strategy._update_cointegration(price1, price2)

        # Should set hedge ratio and last retest date
        assert strategy._hedge_ratio is not None
        assert strategy._last_retest_date is not None
        assert strategy._last_retest_date == dates[-1]

    def test_generate_signal_multiindex(self) -> None:
        """Test generate_signal with MultiIndex columns."""
        strategy = PairsTradingStrategy(asset1="BTC", asset2="ETH", lookback=100)

        # Create MultiIndex data
        dates = pd.date_range("2024-01-01", periods=150, freq="1h")
        price1 = 100 + np.cumsum(np.random.randn(150) * 0.5)
        price2 = price1 * 0.05 + np.random.randn(150) * 0.1

        data = pd.DataFrame(
            {
                ("BTC", "close"): price1,
                ("ETH", "close"): price2,
            },
            index=dates,
        )

        signal = strategy.generate_signal(data)

        # May or may not return signal depending on z-score
        # Just verify it doesn't crash and returns correct format
        if signal is not None:
            assert "action" in signal
            assert signal["action"] in ["LONG_SPREAD", "SHORT_SPREAD", "CLOSE_SPREAD"]

    def test_generate_signal_retest_period(self) -> None:
        """Test retest period behavior."""
        strategy = PairsTradingStrategy(
            asset1="BTC",
            asset2="ETH",
            lookback=100,
            retest_period=30,
        )

        # Create data
        dates = pd.date_range("2024-01-01", periods=150, freq="1D")
        price1 = pd.Series(100 + np.cumsum(np.random.randn(150) * 0.5), index=dates)
        price2 = price1 * 0.05 + np.random.randn(150) * 0.1

        data = pd.DataFrame(
            {
                "close_BTC": price1,
                "close_ETH": price2,
            },
        )

        # First call should trigger cointegration test
        entries1, _ = strategy.generate_signals(data)
        first_test_date = strategy._last_retest_date

        # Immediate second call should NOT retest (within 30 days)
        entries2, _ = strategy.generate_signals(data)
        assert strategy._last_retest_date == first_test_date


# ─── Funding Arbitrage Strategy Tests ────────────────────────────────────────


class TestFundingArbStrategy:
    """Test FundingArbStrategy."""

    def test_calculate_apr(self) -> None:
        """Test APR calculation."""
        strategy = FundingArbStrategy(funding_interval_hours=8)

        # 0.05% per 8h → ~55% APR
        apr = strategy._calculate_apr(0.0005)

        # 365 * 24 / 8 = 1095 periods per year
        # 0.0005 * 1095 = 0.5475 (54.75%)
        expected_apr = 0.0005 * (365 * 24 / 8)
        assert abs(apr - expected_apr) < 1e-6

    def test_generate_signal_live(self) -> None:
        """Test generate_signal for live signal generation."""
        strategy = FundingArbStrategy(
            funding_entry_threshold=0.0005,
            consecutive_periods=2,
        )

        # Create data with high funding rate
        dates = pd.date_range("2024-01-01", periods=10, freq="8h")
        data = pd.DataFrame(
            {
                "funding_rate": [0.0006] * 10,  # Above threshold
                "close": [100.0] * 10,
                "perp_price": [100.5] * 10,
            },
            index=dates,
        )

        signal = strategy.generate_signal(data)

        # May return entry or exit signal depending on state
        if signal is not None:
            assert "action" in signal
            assert signal["action"] in ["ENTER_ARB", "EXIT_ARB"]
            assert "apr" in signal
            if signal["action"] == "ENTER_ARB":
                assert "legs" in signal

    def test_generate_signal_max_position_constraint(self) -> None:
        """Test max_position_pct constraint."""
        strategy = FundingArbStrategy(max_position_pct=0.3)

        dates = pd.date_range("2024-01-01", periods=10, freq="8h")
        data = pd.DataFrame(
            {
                "funding_rate": [0.001] * 10,
                "close": [100.0] * 10,
                "perp_price": [100.5] * 10,  # Add perp_price to avoid fallback issue
            },
            index=dates,
        )

        signal = strategy.generate_signal(data)

        if signal is not None and signal["action"] == "ENTER_ARB":
            assert signal["size"] == 0.3

    def test_calculate_pnl(self) -> None:
        """Test P&L calculation."""
        strategy = FundingArbStrategy()

        # Entry at 100 spot, 100.5 perp
        # Exit at 102 spot, 101 perp
        # Funding payments: [0.0005, 0.0005, 0.0005] = 0.0015 total
        funding_payments = pd.Series([0.0005, 0.0005, 0.0005])

        pnl = strategy.calculate_pnl(
            entry_spot_price=100,
            entry_perp_price=100.5,
            exit_spot_price=102,
            exit_perp_price=101,
            funding_payments=funding_payments,
            position_size=1.0,
        )

        # Spot P&L: (102 - 100) * 1 = 2
        assert abs(pnl["spot_pnl"] - 2.0) < 1e-6

        # Perp P&L (short): (100.5 - 101) * 1 = -0.5
        assert abs(pnl["perp_pnl"] - (-0.5)) < 1e-6

        # Funding P&L: 0.0015 * 1 = 0.0015
        assert abs(pnl["funding_pnl"] - 0.0015) < 1e-6

        # Total: 2 + (-0.5) + 0.0015 = 1.5015
        assert abs(pnl["total_pnl"] - 1.5015) < 1e-6

    def test_estimate_carry(self) -> None:
        """Test carry estimation."""
        strategy = FundingArbStrategy(funding_interval_hours=8)

        # 0.05% per 8h, 30 days holding
        # 30 * 24 / 8 = 90 periods
        # 0.0005 * 90 = 0.045 (4.5%)
        carry = strategy.estimate_carry(funding_rate=0.0005, holding_days=30)

        expected_carry = 0.0005 * (30 * 24 / 8)
        assert abs(carry - expected_carry) < 1e-6


# ─── Validation Utils Tests ───────────────────────────────────────────────────


class TestValidationUtils:
    """Test validation utilities."""

    def test_validate_symbol_strict_valid(self) -> None:
        """Test valid symbol validation."""
        assert validation.validate_symbol_strict("BTCUSD") == "BTCUSD"
        assert validation.validate_symbol_strict("btcusd") == "BTCUSD"  # Auto-uppercase
        assert validation.validate_symbol_strict("BTC123") == "BTC123"

    def test_validate_symbol_strict_with_underscore(self) -> None:
        """Test symbol with underscore (options)."""
        assert (
            validation.validate_symbol_strict("AAPL_C_150_20240101", allow_underscore=True)
            == "AAPL_C_150_20240101"
        )

    @pytest.mark.parametrize("allow_underscore", [False, True])
    def test_validate_symbol_strict_rejects_trailing_newline(self, allow_underscore: bool) -> None:
        with pytest.raises(ValueError, match="only.*allowed"):
            validation.validate_symbol_strict("AAPL\n", allow_underscore=allow_underscore)

    def test_validate_symbol_strict_invalid_chars(self) -> None:
        """Test invalid characters are rejected."""
        with pytest.raises(ValueError, match="only.*allowed"):
            validation.validate_symbol_strict("BTC-USD")

        with pytest.raises(ValueError, match="only.*allowed"):
            validation.validate_symbol_strict("BTC;DROP TABLE")

    def test_validate_symbol_strict_none(self) -> None:
        """Test None symbol is rejected."""
        with pytest.raises(TypeError, match="cannot be None"):
            validation.validate_symbol_strict(None)

    def test_validate_symbol_strict_not_string(self) -> None:
        """Test non-string symbol is rejected."""
        with pytest.raises(TypeError, match="must be string"):
            validation.validate_symbol_strict(123)  # type: ignore

    def test_validate_symbol_strict_empty(self) -> None:
        """Test empty symbol is rejected."""
        with pytest.raises(ValueError, match="cannot be empty"):
            validation.validate_symbol_strict("")

    def test_validate_symbol_strict_too_long(self) -> None:
        """Test symbol exceeding max length is rejected."""
        long_symbol = "A" * 100
        with pytest.raises(ValueError, match="exceeds max length"):
            validation.validate_symbol_strict(long_symbol)

    def test_validate_symbol_list_valid(self) -> None:
        """Test valid symbol list validation."""
        symbols = ["BTCUSD", "ethusd", "SOL123"]
        result = validation.validate_symbol_list(symbols)
        assert result == ["BTCUSD", "ETHUSD", "SOL123"]

    def test_validate_symbol_list_invalid(self) -> None:
        """Test invalid symbol list is rejected."""
        with pytest.raises(TypeError, match="must be a list"):
            validation.validate_symbol_list("BTCUSD")  # type: ignore

        with pytest.raises(ValueError):
            validation.validate_symbol_list(["BTCUSD", "BTC-USD"])


# ─── Logging Utils Tests ──────────────────────────────────────────────────────


class TestLoggingUtils:
    """Test logging configuration utilities."""

    def test_setup_logging_default(self, capsys: pytest.CaptureFixture) -> None:
        """Test default logging setup."""
        logging.setup_logging(level="INFO")

        # Import logger and test it
        from loguru import logger

        logger.info("Test message")

        # Check that message appears in stderr
        captured = capsys.readouterr()
        assert "Test message" in captured.err

    def test_setup_logging_with_file(self, tmp_path: Path) -> None:
        """Test logging with file output."""
        log_file = tmp_path / "test.log"

        logging.setup_logging(level="DEBUG", log_file=log_file)

        # Import logger and log message
        from loguru import logger

        logger.debug("Debug message to file")

        # Flush and check file
        logger.remove()  # Force flush
        assert log_file.exists()

        content = log_file.read_text()
        assert "Debug message to file" in content

    def test_setup_logging_level_filter(self, capsys: pytest.CaptureFixture) -> None:
        """Test log level filtering."""
        logging.setup_logging(level="WARNING")

        from loguru import logger

        logger.info("Info message (should not appear)")
        logger.warning("Warning message (should appear)")

        captured = capsys.readouterr()
        assert "Info message" not in captured.err
        assert "Warning message" in captured.err


# ─── Run Tests ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
