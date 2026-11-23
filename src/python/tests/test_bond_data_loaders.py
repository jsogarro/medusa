"""Tests for bond data loaders (Treasury and FRED)."""

from unittest.mock import MagicMock, patch

import pytest

try:
    from medusa.data.fred_loader import FREDDataLoader
    from medusa.data.treasury_loader import TreasuryDataLoader

    LOADERS_AVAILABLE = True
except ImportError:
    LOADERS_AVAILABLE = False


@pytest.mark.skipif(not LOADERS_AVAILABLE, reason="Data loaders not available")
class TestTreasuryDataLoader:
    """Test Treasury Fiscal Data API loader."""

    @pytest.fixture
    def mock_yield_curve_response(self):
        """Mock API response for yield curve."""
        return {
            "data": [
                {
                    "record_date": "2024-02-15",
                    "security_desc": "Treasury 1-Month",
                    "avg_interest_rate_amt": "5.25",
                },
                {
                    "record_date": "2024-02-15",
                    "security_desc": "Treasury 10-Year",
                    "avg_interest_rate_amt": "4.15",
                },
                {
                    "record_date": "2024-02-15",
                    "security_desc": "Treasury 30-Year",
                    "avg_interest_rate_amt": "4.45",
                },
            ]
        }

    @patch("medusa.data.treasury_loader.requests.get")
    def test_fetch_yield_curve(self, mock_get, mock_yield_curve_response):
        """Test fetching yield curve with mocked API."""
        mock_response = MagicMock()
        mock_response.json.return_value = mock_yield_curve_response
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        df = TreasuryDataLoader.fetch_yield_curve("2024-02-15")

        assert not df.empty
        assert "tenor" in df.columns
        assert "rate" in df.columns
        assert len(df) == 3

        # Check rate values
        assert df[df["tenor"] == 1]["rate"].iloc[0] == 5.25
        assert df[df["tenor"] == 120]["rate"].iloc[0] == 4.15
        assert df[df["tenor"] == 360]["rate"].iloc[0] == 4.45

    @patch("medusa.data.treasury_loader.requests.get")
    def test_fetch_yield_curve_empty_response(self, mock_get):
        """Test handling empty API response."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"data": []}
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        with pytest.raises(ValueError, match="No yield curve data available"):
            TreasuryDataLoader.fetch_yield_curve("2024-02-15")

    @patch("medusa.data.treasury_loader.requests.get")
    def test_fetch_auction_results(self, mock_get):
        """Test fetching auction results."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "data": [
                {
                    "auction_date": "2024-02-15",
                    "security_type": "Bill",
                    "cusip": "912797KE5",
                    "high_yield": "5.25",
                }
            ]
        }
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        df = TreasuryDataLoader.fetch_auction_results("Bill")

        assert not df.empty
        assert "auction_date" in df.columns
        assert "cusip" in df.columns

    @patch("medusa.data.treasury_loader.requests.get")
    def test_fetch_historical_rates(self, mock_get):
        """Test fetching historical rates."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "data": [
                {"record_date": "2024-01-15", "avg_interest_rate_amt": "4.10"},
                {"record_date": "2024-02-15", "avg_interest_rate_amt": "4.15"},
            ]
        }
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        df = TreasuryDataLoader.fetch_historical_rates("10-YEAR", "2024-01-01", "2024-02-28")

        assert len(df) == 2
        assert "rate" in df.columns
        assert df.index.name == "date"

    @patch("medusa.data.treasury_loader.requests.get")
    def test_request_error_handling(self, mock_get):
        """Test handling of request errors."""
        import requests

        mock_get.side_effect = requests.RequestException("Network error")

        with pytest.raises(RuntimeError, match="Treasury API request failed"):
            TreasuryDataLoader.fetch_yield_curve("2024-02-15")


@pytest.mark.skipif(not LOADERS_AVAILABLE, reason="Data loaders not available")
class TestFREDDataLoader:
    """Test FRED API loader."""

    @pytest.fixture
    def mock_api_key(self, monkeypatch):
        """Mock FRED API key."""
        # Non-secret placeholder used only to validate env-var propagation.
        monkeypatch.setenv("FRED_API_KEY", "dummy")
        return "dummy"

    def test_init_with_api_key(self, mock_api_key):
        """Test initialization with API key."""
        loader = FREDDataLoader()
        assert loader.api_key == "dummy"

    def test_init_without_api_key(self, monkeypatch):
        """Test that missing API key raises error."""
        monkeypatch.delenv("FRED_API_KEY", raising=False)
        with pytest.raises(ValueError, match="FRED API key required"):
            FREDDataLoader()

    @patch("medusa.data.fred_loader.requests.get")
    def test_fetch_series(self, mock_get, mock_api_key):
        """Test fetching a single time series."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "observations": [
                {"date": "2024-01-15", "value": "4.10"},
                {"date": "2024-02-15", "value": "4.15"},
                {"date": "2024-03-15", "value": "."},  # Missing data
            ]
        }
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        loader = FREDDataLoader(api_key=mock_api_key)
        series = loader.fetch_series("DGS10", "2024-01-01", "2024-03-31")

        assert len(series) == 2  # Missing value excluded
        assert series.iloc[0] == 4.10
        assert series.iloc[1] == 4.15

    @patch("medusa.data.fred_loader.requests.get")
    def test_fetch_yield_curve(self, mock_get, mock_api_key):
        """Test fetching yield curve snapshot."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "observations": [{"date": "2024-02-15", "value": "4.15"}]
        }
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        loader = FREDDataLoader(api_key=mock_api_key)
        df = loader.fetch_yield_curve("2024-02-15")

        assert not df.empty
        assert "tenor" in df.columns
        assert "months" in df.columns
        assert "rate" in df.columns

    @patch("medusa.data.fred_loader.requests.get")
    def test_fetch_credit_spreads(self, mock_get, mock_api_key):
        """Test fetching credit spreads."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "observations": [
                {"date": "2024-01-15", "value": "0.65"},
                {"date": "2024-02-15", "value": "0.70"},
            ]
        }
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        loader = FREDDataLoader(api_key=mock_api_key)
        df = loader.fetch_credit_spreads("2024-01-01", "2024-02-28", ["AAA"])

        assert "AAA" in df.columns
        assert len(df) == 2

    @patch("medusa.data.fred_loader.requests.get")
    def test_request_error_handling(self, mock_get, mock_api_key):
        """Test handling of request errors."""
        import requests

        mock_get.side_effect = requests.RequestException("API error")

        loader = FREDDataLoader(api_key=mock_api_key)
        with pytest.raises(RuntimeError, match="FRED API request failed"):
            loader.fetch_series("DGS10", "2024-01-01", "2024-02-28")

    @patch("medusa.data.fred_loader.requests.get")
    def test_fetch_series_no_observations(self, mock_get, mock_api_key):
        """Test handling of empty observations."""
        mock_response = MagicMock()
        mock_response.json.return_value = {}  # No observations key
        mock_response.raise_for_status = MagicMock()
        mock_get.return_value = mock_response

        loader = FREDDataLoader(api_key=mock_api_key)
        with pytest.raises(RuntimeError, match="No observations returned"):
            loader.fetch_series("DGS10", "2024-01-01", "2024-02-28")
