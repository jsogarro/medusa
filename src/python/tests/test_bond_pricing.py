"""Tests for bond pricing engine."""

from datetime import date

import pytest

from medusa.pricing.bond import Bond, BondPricer, DayCountConvention


class TestDayCountConventions:
    """Test day count fraction calculations."""

    def test_30_360(self):
        """Test 30/360 day count convention."""
        start = date(2024, 1, 15)
        end = date(2024, 7, 15)
        fraction = BondPricer._day_count_fraction(start, end, DayCountConvention.THIRTY_360)
        # 6 months = 180 days / 360 = 0.5
        assert abs(fraction - 0.5) < 1e-6

    def test_act_act(self):
        """Test ACT/ACT day count convention."""
        start = date(2024, 1, 1)
        end = date(2024, 7, 1)
        fraction = BondPricer._day_count_fraction(start, end, DayCountConvention.ACT_ACT)
        # 182 actual days / 365.25 ≈ 0.498
        assert 0.49 < fraction < 0.51

    def test_act_360(self):
        """Test ACT/360 day count convention."""
        start = date(2024, 1, 1)
        end = date(2024, 4, 1)
        fraction = BondPricer._day_count_fraction(start, end, DayCountConvention.ACT_360)
        # 91 days / 360 ≈ 0.253
        assert abs(fraction - (91 / 360)) < 1e-6

    def test_act_365(self):
        """Test ACT/365 day count convention."""
        start = date(2024, 1, 1)
        end = date(2024, 12, 31)
        fraction = BondPricer._day_count_fraction(start, end, DayCountConvention.ACT_365)
        # 365 days / 365 = 1.0
        assert abs(fraction - 1.0) < 1e-6


class TestBondValidation:
    """Test Bond dataclass validation."""

    def test_valid_bond(self):
        """Test creating a valid bond."""
        bond = Bond(
            cusip="912828YK0",
            coupon_rate=0.05,
            maturity_date=date(2034, 2, 15),
            face_value=100.0,
            coupon_frequency=2,
            day_count=DayCountConvention.THIRTY_360,
            issue_date=date(2024, 2, 15),
        )
        assert bond.cusip == "912828YK0"
        assert bond.coupon_rate == 0.05

    def test_invalid_cusip(self):
        """Test that invalid CUSIP raises error."""
        with pytest.raises(ValueError, match="CUSIP must be 9 characters"):
            Bond(
                cusip="12345",  # Too short
                coupon_rate=0.05,
                maturity_date=date(2034, 2, 15),
            )

    def test_negative_coupon_rate(self):
        """Test that negative coupon rate raises error."""
        with pytest.raises(ValueError, match="Coupon rate must be non-negative"):
            Bond(
                cusip="912828YK0",
                coupon_rate=-0.01,
                maturity_date=date(2034, 2, 15),
            )

    def test_invalid_frequency(self):
        """Test that invalid frequency raises error."""
        with pytest.raises(ValueError, match="Coupon frequency must be"):
            Bond(
                cusip="912828YK0",
                coupon_rate=0.05,
                maturity_date=date(2034, 2, 15),
                coupon_frequency=3,  # Invalid
            )


class TestBondPricing:
    """Test bond present value calculations."""

    @pytest.fixture
    def sample_bond(self):
        """10-year 5% semi-annual bond."""
        return Bond(
            cusip="912828YK0",
            coupon_rate=0.05,
            maturity_date=date(2034, 2, 15),
            face_value=100.0,
            coupon_frequency=2,
            day_count=DayCountConvention.THIRTY_360,
            issue_date=date(2024, 2, 15),
        )

    def test_present_value_at_par(self, sample_bond):
        """Test PV when YTM equals coupon rate (should be 100)."""
        settlement = date(2024, 2, 15)
        ytm = 0.05  # Same as coupon
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        assert abs(pv - 100.0) < 0.1  # Should be close to par

    def test_present_value_premium(self, sample_bond):
        """Test PV when YTM < coupon rate (premium bond)."""
        settlement = date(2024, 2, 15)
        ytm = 0.03  # Lower than coupon
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        assert pv > 100.0  # Should trade at premium

    def test_present_value_discount(self, sample_bond):
        """Test PV when YTM > coupon rate (discount bond)."""
        settlement = date(2024, 2, 15)
        ytm = 0.07  # Higher than coupon
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        assert pv < 100.0  # Should trade at discount

    def test_zero_coupon_bond(self):
        """Test zero-coupon bond pricing."""
        bond = Bond(
            cusip="912828ZZ0",
            coupon_rate=0.0,
            maturity_date=date(2029, 2, 15),
            face_value=100.0,
            coupon_frequency=2,
        )
        settlement = date(2024, 2, 15)
        ytm = 0.04
        pv = BondPricer.present_value(bond, ytm, settlement)
        # PV = 100 / (1 + 0.04/2)^(5*2) = 100 / 1.02^10 ≈ 82.03
        expected = 100 / (1.02**10)
        assert abs(pv - expected) < 1.0


class TestYieldToMaturity:
    """Test YTM solver."""

    @pytest.fixture
    def sample_bond(self):
        """10-year 5% semi-annual bond."""
        return Bond(
            cusip="912828YK0",
            coupon_rate=0.05,
            maturity_date=date(2034, 2, 15),
            coupon_frequency=2,
        )

    def test_ytm_at_par(self, sample_bond):
        """Test YTM when price equals par."""
        settlement = date(2024, 2, 15)
        price = 100.0
        ytm = BondPricer.yield_to_maturity(sample_bond, price, settlement)
        # YTM should equal coupon rate
        assert abs(ytm - 0.05) < 1e-4

    def test_ytm_premium_bond(self, sample_bond):
        """Test YTM for premium bond."""
        settlement = date(2024, 2, 15)
        price = 110.0  # Premium
        ytm = BondPricer.yield_to_maturity(sample_bond, price, settlement)
        # YTM should be < coupon rate
        assert ytm < 0.05
        # Verify by recalculating PV
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        assert abs(pv - price) < 0.01

    def test_ytm_discount_bond(self, sample_bond):
        """Test YTM for discount bond."""
        settlement = date(2024, 2, 15)
        price = 90.0  # Discount
        ytm = BondPricer.yield_to_maturity(sample_bond, price, settlement)
        # YTM should be > coupon rate
        assert ytm > 0.05
        # Verify by recalculating PV
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        assert abs(pv - price) < 0.01


class TestDuration:
    """Test Macaulay and modified duration."""

    @pytest.fixture
    def sample_bond(self):
        """5-year 4% semi-annual bond."""
        return Bond(
            cusip="912828AB1",
            coupon_rate=0.04,
            maturity_date=date(2029, 2, 15),
            coupon_frequency=2,
        )

    def test_macaulay_duration(self, sample_bond):
        """Test Macaulay duration calculation."""
        settlement = date(2024, 2, 15)
        ytm = 0.04
        mac_dur = BondPricer.macaulay_duration(sample_bond, ytm, settlement)
        # For a 5-year bond at par, duration should be < 5 years
        assert 4.0 < mac_dur < 5.0

    def test_modified_duration(self, sample_bond):
        """Test modified duration calculation."""
        settlement = date(2024, 2, 15)
        ytm = 0.04
        mac_dur = BondPricer.macaulay_duration(sample_bond, ytm, settlement)
        mod_dur = BondPricer.modified_duration(sample_bond, ytm, settlement)
        # Modified duration = Macaulay / (1 + y/f)
        expected = mac_dur / (1 + ytm / sample_bond.coupon_frequency)
        assert abs(mod_dur - expected) < 1e-6

    def test_zero_coupon_duration(self):
        """Test duration of zero-coupon bond equals maturity."""
        bond = Bond(
            cusip="912828ZZ1",
            coupon_rate=0.0,
            maturity_date=date(2029, 2, 15),
            coupon_frequency=2,
        )
        settlement = date(2024, 2, 15)
        ytm = 0.04
        mac_dur = BondPricer.macaulay_duration(bond, ytm, settlement)
        # Duration of zero-coupon bond = time to maturity
        assert abs(mac_dur - 5.0) < 0.1


class TestConvexity:
    """Test convexity calculation."""

    @pytest.fixture
    def sample_bond(self):
        """5-year 4% semi-annual bond."""
        return Bond(
            cusip="912828AB2",
            coupon_rate=0.04,
            maturity_date=date(2029, 2, 15),
            coupon_frequency=2,
        )

    def test_convexity_positive(self, sample_bond):
        """Test that convexity is positive."""
        settlement = date(2024, 2, 15)
        ytm = 0.04
        conv = BondPricer.convexity(sample_bond, ytm, settlement)
        assert conv > 0

    def test_convexity_zero_coupon(self):
        """Test convexity of zero-coupon bond."""
        bond = Bond(
            cusip="912828ZZ2",
            coupon_rate=0.0,
            maturity_date=date(2029, 2, 15),
            coupon_frequency=2,
        )
        settlement = date(2024, 2, 15)
        ytm = 0.04
        conv = BondPricer.convexity(bond, ytm, settlement)
        # Zero-coupon bond has higher convexity than coupon bonds
        assert conv > 0


class TestDV01:
    """Test DV01 calculation."""

    @pytest.fixture
    def sample_bond(self):
        """5-year 4% semi-annual bond."""
        return Bond(
            cusip="912828AB3",
            coupon_rate=0.04,
            maturity_date=date(2029, 2, 15),
            coupon_frequency=2,
        )

    def test_dv01_positive(self, sample_bond):
        """Test that DV01 is positive."""
        settlement = date(2024, 2, 15)
        ytm = 0.04
        dv01 = BondPricer.dv01(sample_bond, ytm, settlement)
        assert dv01 > 0

    def test_dv01_relationship(self, sample_bond):
        """Test DV01 = modified_duration * PV * 0.0001."""
        settlement = date(2024, 2, 15)
        ytm = 0.04
        mod_dur = BondPricer.modified_duration(sample_bond, ytm, settlement)
        pv = BondPricer.present_value(sample_bond, ytm, settlement)
        expected_dv01 = mod_dur * pv * 0.0001
        dv01 = BondPricer.dv01(sample_bond, ytm, settlement)
        assert abs(dv01 - expected_dv01) < 1e-6


class TestAccruedInterest:
    """Test accrued interest calculation."""

    @pytest.fixture
    def sample_bond(self):
        """Bond with known coupon dates."""
        return Bond(
            cusip="912828AI0",
            coupon_rate=0.06,  # 6% annual
            maturity_date=date(2029, 8, 15),
            coupon_frequency=2,  # Semi-annual
            issue_date=date(2024, 2, 15),
        )

    def test_accrued_interest_mid_period(self, sample_bond):
        """Test accrued interest halfway through coupon period."""
        # Last coupon: Feb 15, Next coupon: Aug 15
        settlement = date(2024, 5, 15)  # 3 months after last coupon
        accrued = BondPricer.accrued_interest(sample_bond, settlement)
        # Half-period accrued ≈ (100 * 0.06 / 2) * 0.5 = 1.5
        assert 1.0 < accrued < 2.0

    def test_accrued_interest_at_coupon_date(self, sample_bond):
        """Test accrued interest at coupon payment date."""
        settlement = date(2024, 8, 15)  # Coupon date
        accrued = BondPricer.accrued_interest(sample_bond, settlement)
        # Should be near zero or small
        assert accrued < 0.5

    def test_accrued_interest_after_maturity(self, sample_bond):
        """Test accrued interest after maturity."""
        settlement = date(2030, 1, 1)  # After maturity
        accrued = BondPricer.accrued_interest(sample_bond, settlement)
        assert accrued == 0.0
