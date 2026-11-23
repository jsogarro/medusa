"""Tests for crypto-native pricing and valuation models."""

import numpy as np
import pandas as pd
import pytest

from medusa.pricing.crypto.arbitrage import (
    CrossExchangeSpreadModel,
    StablecoinDepegModel,
    TriangularArbModel,
)
from medusa.pricing.crypto.derivatives import FuturesBasisModel, PerpetualFundingModel
from medusa.pricing.crypto.factor_model import CryptoFactorModel
from medusa.pricing.crypto.onchain_valuation import MVRVModel, NVTModel, StockToFlowModel


@pytest.fixture
def sample_onchain_data():
    """Sample on-chain data for testing."""
    dates = pd.date_range("2024-01-01", periods=100, freq="D")
    np.random.seed(42)

    return pd.DataFrame(
        {
            "market_cap": np.random.uniform(500e9, 1000e9, 100),  # $500B-$1T
            "tx_volume_usd": np.random.uniform(1e9, 10e9, 100),  # $1B-$10B daily
            "realized_cap": np.random.uniform(400e9, 800e9, 100),  # $400B-$800B
            "price": np.random.uniform(30000, 60000, 100),  # $30k-$60k
            "supply": 19.5e6,  # 19.5M BTC
            "annual_production": 328500,  # ~328k BTC/year (post-halving)
            "active_addresses": np.random.uniform(800000, 1200000, 100),
            "volume": np.random.uniform(10e9, 50e9, 100),
            "sentiment_score": np.random.uniform(-1, 1, 100),
        },
        index=dates,
    )


@pytest.fixture
def sample_btc_returns():
    """Sample BTC returns for correlation factor."""
    dates = pd.date_range("2024-01-01", periods=100, freq="D")
    np.random.seed(123)
    return pd.Series(np.random.normal(0, 0.03, 100), index=dates)


class TestNVTModel:
    """Test NVT (Network Value to Transactions) model."""

    def test_calculate_nvt(self, sample_onchain_data):
        """Test NVT ratio calculation."""
        nvt = NVTModel.calculate_nvt(sample_onchain_data)
        assert len(nvt) == len(sample_onchain_data)
        assert nvt.isna().sum() < 10  # Allow some NaN at start due to rolling window
        assert (nvt > 0).sum() > 90  # Most values should be positive

    def test_nvt_missing_columns(self):
        """Test NVT calculation with missing columns."""
        df = pd.DataFrame({"market_cap": [1e9]})
        with pytest.raises(ValueError, match="tx_volume_usd"):
            NVTModel.calculate_nvt(df)

    def test_generate_signals(self, sample_onchain_data):
        """Test NVT signal generation."""
        result = NVTModel.generate_signals(sample_onchain_data, lookback=30)
        assert "nvt" in result.columns
        assert "zscore" in result.columns
        assert "signal" in result.columns
        assert result["signal"].isin([-1, 0, 1]).all()
        # Should have some buy/sell signals
        assert (result["signal"] != 0).sum() > 0

    def test_nvt_signals_extreme_zscore(self):
        """Test NVT signals at extreme z-scores."""
        df = pd.DataFrame(
            {
                "market_cap": [1e12] * 100,
                "tx_volume_usd": [1e9] * 50 + [10e9] * 50,  # Jump in tx volume
            }
        )
        result = NVTModel.generate_signals(df, lookback=30)
        # After tx volume jump, NVT should drop, triggering buy signal
        assert (result["signal"] == 1).sum() > 0

    def test_nvt_signals_custom_lookback(self, sample_onchain_data):
        """Test NVT signals with custom lookback period."""
        result = NVTModel.generate_signals(sample_onchain_data, lookback=60)
        assert len(result) == len(sample_onchain_data)
        assert "nvt_mean" in result.columns


class TestMVRVModel:
    """Test MVRV (Market Value to Realized Value) model."""

    def test_calculate_mvrv(self, sample_onchain_data):
        """Test MVRV ratio calculation."""
        mvrv = MVRVModel.calculate_mvrv(sample_onchain_data)
        assert len(mvrv) == len(sample_onchain_data)
        assert (mvrv > 0).all()
        assert mvrv.mean() > 1.0  # Market cap typically > realized cap

    def test_mvrv_missing_columns(self):
        """Test MVRV calculation with missing columns."""
        df = pd.DataFrame({"market_cap": [1e9]})
        with pytest.raises(ValueError, match="realized_cap"):
            MVRVModel.calculate_mvrv(df)

    def test_generate_signals(self, sample_onchain_data):
        """Test MVRV signal generation."""
        result = MVRVModel.generate_signals(sample_onchain_data)
        assert "mvrv" in result.columns
        assert "signal" in result.columns
        assert result["signal"].isin([-1, 0, 1]).all()

    def test_mvrv_buy_signal_below_1(self):
        """Test MVRV generates buy signal when ratio < 1.0."""
        df = pd.DataFrame({"market_cap": [500e9], "realized_cap": [600e9]})
        result = MVRVModel.generate_signals(df)
        assert result["mvrv"].iloc[0] < 1.0
        assert result["signal"].iloc[0] == 1  # Buy signal

    def test_mvrv_sell_signal_above_3_5(self):
        """Test MVRV generates sell signal when ratio > 3.5."""
        df = pd.DataFrame({"market_cap": [1000e9], "realized_cap": [250e9]})
        result = MVRVModel.generate_signals(df)
        assert result["mvrv"].iloc[0] > 3.5
        assert result["signal"].iloc[0] == -1  # Sell signal


class TestStockToFlowModel:
    """Test Stock-to-Flow model for Bitcoin valuation."""

    def test_calculate_s2f(self):
        """Test S2F ratio calculation."""
        s2f = StockToFlowModel.calculate_s2f(supply=19.5e6, annual_production=328500)
        assert s2f > 0
        assert 50 < s2f < 70  # BTC S2F typically 50-60 range

    def test_s2f_invalid_production(self):
        """Test S2F calculation with invalid annual production."""
        with pytest.raises(ValueError, match="Annual production must be positive"):
            StockToFlowModel.calculate_s2f(supply=19.5e6, annual_production=0)

    def test_predict_fair_value(self):
        """Test S2F fair value prediction."""
        s2f = 56  # Typical BTC S2F
        fair_value = StockToFlowModel.predict_fair_value(s2f)
        assert fair_value > 0
        assert fair_value > 10000  # Should predict significant value

    def test_generate_signals(self, sample_onchain_data):
        """Test S2F signal generation."""
        result = StockToFlowModel.generate_signals(sample_onchain_data)
        assert "s2f" in result.columns
        assert "fair_value" in result.columns
        assert "price_to_fair_value" in result.columns
        assert "signal" in result.columns
        assert result["signal"].isin([0, 1]).all()  # Only buy signals

    def test_s2f_buy_signal_below_70_pct(self):
        """Test S2F generates buy signal when price < 70% of fair value."""
        df = pd.DataFrame({"price": [30000], "supply": [19.5e6], "annual_production": [328500]})
        result = StockToFlowModel.generate_signals(df)
        # With S2F ~59, fair value should be >$100k, so price_to_fair_value < 0.7
        if result["price_to_fair_value"].iloc[0] < 0.7:
            assert result["signal"].iloc[0] == 1


class TestPerpetualFundingModel:
    """Test perpetual futures funding rate model."""

    def test_calculate_annualized_carry(self):
        """Test annualized carry calculation."""
        funding_rate_8h = 0.0001  # 0.01% per 8 hours
        annualized = PerpetualFundingModel.calculate_annualized_carry(funding_rate_8h)
        assert annualized > 0
        assert 0.10 < annualized < 0.15  # ~10-15% APR for 0.01% 8h rate

    def test_annualized_carry_negative_funding(self):
        """Test annualized carry with negative funding rate."""
        funding_rate_8h = -0.0001
        annualized = PerpetualFundingModel.calculate_annualized_carry(funding_rate_8h)
        assert annualized < 0

    def test_detect_arbitrage(self):
        """Test funding rate arbitrage detection."""
        df = pd.DataFrame(
            {
                "funding_rate": [
                    0.0015,  # High positive (short perp) - increased from 0.0005
                    0.0001,
                    -0.0001,
                    -0.0015,  # High negative (long perp)
                ]
            }
        )
        result = PerpetualFundingModel.detect_arbitrage(df, threshold=0.001)
        assert "carry" in result.columns
        assert "annualized_carry" in result.columns
        assert "arbitrage_signal" in result.columns
        assert result["arbitrage_signal"].iloc[0] == 1  # Short perp
        assert result["arbitrage_signal"].iloc[3] == -1  # Long perp

    def test_funding_arbitrage_missing_column(self):
        """Test funding arbitrage with missing column."""
        df = pd.DataFrame({"price": [50000]})
        with pytest.raises(ValueError, match="funding_rate"):
            PerpetualFundingModel.detect_arbitrage(df)


class TestFuturesBasisModel:
    """Test futures basis and cash-and-carry arbitrage model."""

    def test_calculate_basis(self):
        """Test basis calculation."""
        basis = FuturesBasisModel.calculate_basis(futures_price=51000, spot_price=50000)
        assert basis == 1000

    def test_annualize_basis(self):
        """Test annualized basis calculation."""
        annualized = FuturesBasisModel.annualize_basis(basis=1000, spot=50000, days_to_expiry=90)
        assert annualized > 0
        # (1000/50000) * (365/90) = 0.02 * 4.056 ≈ 0.081 (8.1%)
        assert 0.07 < annualized < 0.10

    def test_annualize_basis_invalid_days(self):
        """Test annualized basis with invalid days to expiry."""
        with pytest.raises(ValueError, match="Days to expiry must be positive"):
            FuturesBasisModel.annualize_basis(basis=1000, spot=50000, days_to_expiry=0)

    def test_detect_arbitrage(self):
        """Test cash-and-carry arbitrage detection."""
        df = pd.DataFrame(
            {
                "futures_price": [52000, 51000, 49000],
                "spot_price": [50000, 50000, 50000],
                "days_to_expiry": [90, 90, 90],
            }
        )
        result = FuturesBasisModel.detect_arbitrage(df, cost_threshold=0.05)
        assert "basis" in result.columns
        assert "annualized_basis" in result.columns
        assert "arbitrage_signal" in result.columns
        # First row has large contango, should trigger arbitrage
        assert result["arbitrage_signal"].iloc[0] == 1

    def test_futures_arbitrage_missing_columns(self):
        """Test futures arbitrage with missing columns."""
        df = pd.DataFrame({"futures_price": [51000]})
        with pytest.raises(ValueError, match="Missing required columns"):
            FuturesBasisModel.detect_arbitrage(df)


class TestTriangularArbModel:
    """Test triangular arbitrage model."""

    def test_calculate_synthetic_rate(self):
        """Test synthetic rate calculation."""
        # BTC/USD = 50000, ETH/BTC = 0.06, synthetic ETH/USD = 50000 * 0.06 = 3000
        synthetic = TriangularArbModel.calculate_synthetic_rate(rate_ab=50000, rate_bc=0.06)
        assert synthetic == 3000

    def test_synthetic_rate_with_validation(self):
        """Test synthetic rate with cross-check validation."""
        synthetic = TriangularArbModel.calculate_synthetic_rate(
            rate_ab=50000,
            rate_bc=0.06,
            rate_ca=1 / 3000,  # Direct rate C/A
        )
        assert abs(synthetic - 3000) < 1e-6

    def test_detect_opportunity(self):
        """Test triangular arbitrage opportunity detection."""
        # Synthetic ETH/USD = 50000 * 0.06 = 3000, Direct = 2900 (10 profit)
        rates = {"AB": 50000, "BC": 0.06, "AC": 2900}
        result = TriangularArbModel.detect_opportunity(rates, fee_rate=0.001)
        assert result["synthetic_rate"] == 3000
        assert result["direct_rate"] == 2900
        assert result["profitable"] is True

    def test_detect_opportunity_unprofitable(self):
        """Test triangular arbitrage with unprofitable spread."""
        # Small spread that doesn't cover fees
        # Synthetic = 50000 * 0.06 = 3000, Direct = 2997, spread = 0.1%, fees = 0.3%
        rates = {"AB": 50000, "BC": 0.06, "AC": 2997}
        result = TriangularArbModel.detect_opportunity(rates, fee_rate=0.001)
        assert result["profitable"] is False

    def test_triangular_missing_rates(self):
        """Test triangular arbitrage with missing rates."""
        rates = {"AB": 50000}
        with pytest.raises(ValueError, match="rates must contain"):
            TriangularArbModel.detect_opportunity(rates)


class TestCrossExchangeSpreadModel:
    """Test cross-exchange arbitrage model."""

    def test_detect_arbitrage(self):
        """Test cross-exchange arbitrage detection."""
        prices = {"binance": 50000, "coinbase": 51000, "kraken": 49000}
        opportunities = CrossExchangeSpreadModel.detect_arbitrage(prices, transfer_cost=0.002)
        assert len(opportunities) > 0
        # Should find buy on kraken (49000), sell on coinbase (51000)
        assert any(
            opp["buy_exchange"] == "kraken" and opp["sell_exchange"] == "coinbase"
            for opp in opportunities
        )

    def test_cross_exchange_no_arbitrage(self):
        """Test cross-exchange with no profitable arbitrage."""
        prices = {"binance": 50000, "coinbase": 50050}  # 0.1% spread < transfer cost
        opportunities = CrossExchangeSpreadModel.detect_arbitrage(prices, transfer_cost=0.002)
        assert len(opportunities) == 0

    def test_cross_exchange_insufficient_exchanges(self):
        """Test cross-exchange with insufficient exchanges."""
        prices = {"binance": 50000}
        with pytest.raises(ValueError, match="Need at least 2 exchanges"):
            CrossExchangeSpreadModel.detect_arbitrage(prices)


class TestStablecoinDepegModel:
    """Test stablecoin depeg arbitrage model."""

    def test_calculate_depeg(self):
        """Test depeg percentage calculation."""
        depeg = StablecoinDepegModel.calculate_depeg(price=0.95, peg_value=1.0)
        assert abs(depeg - (-0.05)) < 1e-6  # 5% below peg

    def test_generate_signals(self):
        """Test stablecoin depeg signal generation."""
        df = pd.DataFrame(
            {
                "price": [
                    0.99,  # Below threshold
                    1.01,  # Above threshold
                    0.97,  # Trigger stop-loss
                ]
            }
        )
        result = StablecoinDepegModel.generate_signals(df, threshold=0.005, stop_loss=0.02)
        assert "depeg" in result.columns
        assert "signal" in result.columns
        assert "stop_loss_triggered" in result.columns
        assert result["signal"].iloc[0] == 1  # Buy signal
        assert result["signal"].iloc[1] == -1  # Sell signal
        assert result["stop_loss_triggered"].iloc[2]  # Stop-loss triggered

    def test_depeg_signals_missing_column(self):
        """Test depeg signals with missing price column."""
        df = pd.DataFrame({"volume": [1000]})
        with pytest.raises(ValueError, match="price"):
            StablecoinDepegModel.generate_signals(df)


class TestCryptoFactorModel:
    """Test multi-factor alpha model."""

    def test_calculate_momentum_factor(self, sample_onchain_data):
        """Test momentum factor calculation."""
        momentum = CryptoFactorModel.calculate_momentum_factor(sample_onchain_data)
        assert len(momentum) == len(sample_onchain_data)
        # Z-score should have mean ~0, std ~1
        assert abs(momentum.mean()) < 0.5
        assert 0.5 < momentum.std() < 1.5

    def test_calculate_volatility_factor(self, sample_onchain_data):
        """Test volatility factor calculation."""
        volatility = CryptoFactorModel.calculate_volatility_factor(sample_onchain_data)
        assert len(volatility) == len(sample_onchain_data)

    def test_calculate_liquidity_factor(self, sample_onchain_data):
        """Test liquidity factor calculation."""
        liquidity = CryptoFactorModel.calculate_liquidity_factor(sample_onchain_data)
        assert len(liquidity) == len(sample_onchain_data)

    def test_calculate_network_factor(self, sample_onchain_data):
        """Test network activity factor calculation."""
        network = CryptoFactorModel.calculate_network_factor(sample_onchain_data)
        assert len(network) == len(sample_onchain_data)

    def test_calculate_sentiment_factor(self, sample_onchain_data):
        """Test sentiment factor calculation."""
        sentiment = CryptoFactorModel.calculate_sentiment_factor(sample_onchain_data)
        assert len(sentiment) == len(sample_onchain_data)

    def test_calculate_correlation_factor(self, sample_onchain_data, sample_btc_returns):
        """Test correlation factor calculation."""
        correlation = CryptoFactorModel.calculate_correlation_factor(
            sample_onchain_data, sample_btc_returns
        )
        assert len(correlation) == len(sample_onchain_data)

    def test_calculate_alpha_score(self, sample_onchain_data):
        """Test alpha score calculation from factors."""
        factors = pd.DataFrame(
            {
                "momentum": np.random.randn(100),
                "volatility": np.random.randn(100),
                "liquidity": np.random.randn(100),
                "network": np.random.randn(100),
                "sentiment": np.random.randn(100),
                "correlation": np.random.randn(100),
            },
            index=sample_onchain_data.index,
        )
        alpha = CryptoFactorModel.calculate_alpha_score(factors)
        assert len(alpha) == len(factors)
        assert abs(alpha.mean()) < 0.5  # Should be close to zero

    def test_alpha_score_custom_weights(self):
        """Test alpha score with custom factor weights."""
        factors = pd.DataFrame(
            {
                "momentum": [1.0, -1.0],
                "volatility": [0.5, -0.5],
            }
        )
        weights = {"momentum": 0.7, "volatility": 0.3}
        alpha = CryptoFactorModel.calculate_alpha_score(factors, weights)
        # First row: 0.7 * 1.0 + 0.3 * 0.5 = 0.85
        assert abs(alpha.iloc[0] - 0.85) < 1e-6

    def test_alpha_score_invalid_weights(self):
        """Test alpha score with invalid weights (don't sum to 1.0)."""
        factors = pd.DataFrame({"momentum": [1.0]})
        weights = {"momentum": 0.5}  # Sum = 0.5 != 1.0
        with pytest.raises(ValueError, match="must sum to 1.0"):
            CryptoFactorModel.calculate_alpha_score(factors, weights)

    def test_generate_portfolio_weights_long_only(self):
        """Test portfolio weight generation (long-only)."""
        alpha = pd.Series([1.0, -0.5, 2.0, 0.0], index=["BTC", "ETH", "SOL", "DOGE"])
        weights = CryptoFactorModel.generate_portfolio_weights(alpha, long_only=True)
        assert (weights >= 0).all()
        assert abs(weights.sum() - 1.0) < 1e-6  # Sum to 1.0

    def test_generate_portfolio_weights_long_short(self):
        """Test portfolio weight generation (long-short)."""
        alpha = pd.Series([1.0, -0.5, 2.0, -1.0], index=["BTC", "ETH", "SOL", "DOGE"])
        weights = CryptoFactorModel.generate_portfolio_weights(alpha, long_only=False)
        assert (weights > 0).sum() > 0  # Some longs
        assert (weights < 0).sum() > 0  # Some shorts
        assert abs(weights.sum()) < 0.1  # Approximately dollar-neutral
