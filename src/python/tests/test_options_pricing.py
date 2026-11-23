"""Tests for Black-Scholes options pricing."""

import numpy as np
import pytest

from medusa.models.options_pricing import BlackScholesEngine, OptionParams, OptionType


class TestOptionParams:
    """Test option parameters validation."""

    def test_valid_params(self):
        """Test creating valid option parameters."""
        params = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )
        assert params.spot == 100
        assert params.option_type == OptionType.CALL

    def test_invalid_spot(self):
        """Test that non-positive spot raises error."""
        with pytest.raises(ValueError, match="Spot must be positive"):
            OptionParams(
                spot=0,
                strike=100,
                time_to_expiry=1.0,
                risk_free_rate=0.05,
                volatility=0.2,
            )

    def test_invalid_strike(self):
        """Test that non-positive strike raises error."""
        with pytest.raises(ValueError, match="Strike must be positive"):
            OptionParams(
                spot=100,
                strike=-100,
                time_to_expiry=1.0,
                risk_free_rate=0.05,
                volatility=0.2,
            )

    def test_invalid_time(self):
        """Test that negative time raises error."""
        with pytest.raises(ValueError, match="Time to expiry must be non-negative"):
            OptionParams(
                spot=100,
                strike=100,
                time_to_expiry=-1.0,
                risk_free_rate=0.05,
                volatility=0.2,
            )

    def test_invalid_volatility(self):
        """Test that negative volatility raises error."""
        with pytest.raises(ValueError, match="Volatility must be non-negative"):
            OptionParams(
                spot=100,
                strike=100,
                time_to_expiry=1.0,
                risk_free_rate=0.05,
                volatility=-0.2,
            )


class TestBlackScholesPricing:
    """Test Black-Scholes option pricing."""

    @pytest.fixture
    def atm_call(self):
        """At-the-money call option."""
        return OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )

    @pytest.fixture
    def atm_put(self):
        """At-the-money put option."""
        return OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )

    def test_call_price_positive(self, atm_call):
        """Test that call price is positive."""
        price = BlackScholesEngine.price(atm_call)
        assert price > 0

    def test_put_price_positive(self, atm_put):
        """Test that put price is positive."""
        price = BlackScholesEngine.price(atm_put)
        assert price > 0

    def test_put_call_parity(self, atm_call, atm_put):
        """Test put-call parity: C - P = S - K*exp(-rT)."""
        call_price = BlackScholesEngine.price(atm_call)
        put_price = BlackScholesEngine.price(atm_put)

        lhs = call_price - put_price
        rhs = atm_call.spot - atm_call.strike * np.exp(
            -atm_call.risk_free_rate * atm_call.time_to_expiry
        )

        assert abs(lhs - rhs) < 1e-6

    def test_itm_call(self):
        """Test in-the-money call has higher value."""
        itm_call = OptionParams(
            spot=110,  # Spot > Strike
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )
        atm_call = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )

        itm_price = BlackScholesEngine.price(itm_call)
        atm_price = BlackScholesEngine.price(atm_call)

        assert itm_price > atm_price

    def test_otm_put(self):
        """Test out-of-the-money put has lower value."""
        otm_put = OptionParams(
            spot=110,  # Spot > Strike
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )
        atm_put = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )

        otm_price = BlackScholesEngine.price(otm_put)
        atm_price = BlackScholesEngine.price(atm_put)

        assert otm_price < atm_price

    def test_zero_time_call(self):
        """Test call at expiration equals intrinsic value."""
        params = OptionParams(
            spot=110,
            strike=100,
            time_to_expiry=0.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )
        price = BlackScholesEngine.price(params)
        # Intrinsic value = max(S - K, 0) = 10
        assert abs(price - 10) < 1e-6

    def test_zero_time_put(self):
        """Test put at expiration equals intrinsic value."""
        params = OptionParams(
            spot=90,
            strike=100,
            time_to_expiry=0.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )
        price = BlackScholesEngine.price(params)
        # Intrinsic value = max(K - S, 0) = 10
        assert abs(price - 10) < 1e-6


class TestGreeks:
    """Test option Greeks calculations."""

    @pytest.fixture
    def sample_call(self):
        """Sample call option."""
        return OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )

    @pytest.fixture
    def sample_put(self):
        """Sample put option."""
        return OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )

    def test_call_delta_range(self, sample_call):
        """Test that call delta is between 0 and 1."""
        greeks = BlackScholesEngine.greeks(sample_call)
        assert 0 <= greeks["delta"] <= 1

    def test_put_delta_range(self, sample_put):
        """Test that put delta is between -1 and 0."""
        greeks = BlackScholesEngine.greeks(sample_put)
        assert -1 <= greeks["delta"] <= 0

    def test_gamma_positive(self, sample_call):
        """Test that gamma is positive."""
        greeks = BlackScholesEngine.greeks(sample_call)
        assert greeks["gamma"] > 0

    def test_vega_positive(self, sample_call):
        """Test that vega is positive."""
        greeks = BlackScholesEngine.greeks(sample_call)
        assert greeks["vega"] > 0

    def test_call_theta_negative(self, sample_call):
        """Test that call theta is typically negative (time decay)."""
        greeks = BlackScholesEngine.greeks(sample_call)
        # ATM calls usually have negative theta
        assert greeks["theta"] < 0

    def test_call_rho_positive(self, sample_call):
        """Test that call rho is positive."""
        greeks = BlackScholesEngine.greeks(sample_call)
        assert greeks["rho"] > 0

    def test_put_rho_negative(self, sample_put):
        """Test that put rho is negative."""
        greeks = BlackScholesEngine.greeks(sample_put)
        assert greeks["rho"] < 0

    def test_gamma_symmetry(self, sample_call, sample_put):
        """Test that gamma is same for call and put."""
        call_greeks = BlackScholesEngine.greeks(sample_call)
        put_greeks = BlackScholesEngine.greeks(sample_put)
        assert abs(call_greeks["gamma"] - put_greeks["gamma"]) < 1e-6

    def test_vega_symmetry(self, sample_call, sample_put):
        """Test that vega is same for call and put."""
        call_greeks = BlackScholesEngine.greeks(sample_call)
        put_greeks = BlackScholesEngine.greeks(sample_put)
        assert abs(call_greeks["vega"] - put_greeks["vega"]) < 1e-6


class TestImpliedVolatility:
    """Test implied volatility solver."""

    def test_iv_recovery(self):
        """Test that IV solver recovers known volatility."""
        true_vol = 0.25
        params = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=true_vol,
            option_type=OptionType.CALL,
        )

        # Calculate price with known volatility
        price = BlackScholesEngine.price(params)

        # Solve for IV with different initial guess
        params_guess = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.15,  # Different from true
            option_type=OptionType.CALL,
        )

        recovered_vol = BlackScholesEngine.implied_volatility(price, params_guess)

        assert abs(recovered_vol - true_vol) < 1e-4

    def test_iv_itm_call(self):
        """Test IV solver on ITM call."""
        params = OptionParams(
            spot=110,
            strike=100,
            time_to_expiry=0.5,
            risk_free_rate=0.05,
            volatility=0.3,
            option_type=OptionType.CALL,
        )
        price = BlackScholesEngine.price(params)

        params_guess = OptionParams(
            spot=110,
            strike=100,
            time_to_expiry=0.5,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )

        iv = BlackScholesEngine.implied_volatility(price, params_guess)
        assert abs(iv - 0.3) < 1e-4

    def test_iv_otm_put(self):
        """Test IV solver on OTM put."""
        params = OptionParams(
            spot=110,
            strike=100,
            time_to_expiry=0.5,
            risk_free_rate=0.05,
            volatility=0.35,
            option_type=OptionType.PUT,
        )
        price = BlackScholesEngine.price(params)

        params_guess = OptionParams(
            spot=110,
            strike=100,
            time_to_expiry=0.5,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.PUT,
        )

        iv = BlackScholesEngine.implied_volatility(price, params_guess)
        assert abs(iv - 0.35) < 1e-4

    def test_iv_convergence_failure(self):
        """Test that invalid price causes convergence failure."""
        params = OptionParams(
            spot=100,
            strike=100,
            time_to_expiry=1.0,
            risk_free_rate=0.05,
            volatility=0.2,
            option_type=OptionType.CALL,
        )

        # Price too high to be achievable
        with pytest.raises(ValueError, match="did not converge"):
            BlackScholesEngine.implied_volatility(
                price=1000,  # Unrealistic
                params=params,
                max_iter=10,
            )
