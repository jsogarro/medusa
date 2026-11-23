"""FRED (Federal Reserve Economic Data) loader.

Loads economic time series data from the St. Louis Federal Reserve FRED API.
Includes yield curves, credit spreads, and macroeconomic indicators.

API Documentation: https://fred.stlouisfed.org/docs/api/fred/
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from datetime import date
from typing import Any, cast

import pandas as pd
from loguru import logger

try:
    import requests  # type: ignore[import-untyped]

    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    logger.warning("requests not available - FRED data loader disabled")


class FREDDataLoader:
    """Load economic data from FRED API."""

    BASE_URL = "https://api.stlouisfed.org/fred/"

    # Common yield curve series
    YIELD_CURVE_SERIES = {
        "1M": "DGS1MO",
        "3M": "DGS3MO",
        "6M": "DGS6MO",
        "1Y": "DGS1",
        "2Y": "DGS2",
        "3Y": "DGS3",
        "5Y": "DGS5",
        "7Y": "DGS7",
        "10Y": "DGS10",
        "20Y": "DGS20",
        "30Y": "DGS30",
    }

    # Credit spread series (ICE BofA indices)
    CREDIT_SPREADS = {
        "AAA": "BAMLC0A1CAAAEY",
        "AA": "BAMLC0A2CAAEY",
        "A": "BAMLC0A3CAEY",
        "BBB": "BAMLC0A4CBBBEY",
        "BB": "BAMLH0A1HYBBEY",
        "B": "BAMLH0A2HYBEY",
        "CCC": "BAMLH0A3HYCEY",
    }

    def __init__(self, api_key: str | None = None) -> None:
        """Initialize FRED data loader.

        Args:
            api_key: FRED API key (or set FRED_API_KEY env var).

        Raises:
            ValueError: If API key not provided.
        """
        self.api_key = api_key or os.getenv("FRED_API_KEY")
        if not self.api_key:
            raise ValueError(
                "FRED API key required. Set FRED_API_KEY environment variable "
                "or pass api_key parameter. Get key at: "
                "https://fred.stlouisfed.org/docs/api/api_key.html"
            )

    def _make_request(
        self,
        endpoint: str,
        params: Mapping[str, str | int] | None = None,
    ) -> dict[str, Any]:
        """Make API request to FRED.

        Args:
            endpoint: API endpoint (e.g., 'series/observations').
            params: Query parameters.

        Returns:
            JSON response as dictionary.

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if not REQUESTS_AVAILABLE:
            raise ImportError("requests library required for FRED data loader")

        url = f"{self.BASE_URL}{endpoint}"
        api_key = self.api_key
        if api_key is None:
            raise RuntimeError("FRED API key missing after initialization")

        all_params: dict[str, str | int] = {"api_key": api_key, "file_type": "json"}
        if params:
            all_params.update(params)

        logger.debug(f"FRED API request: {url}")

        try:
            response = requests.get(url, params=all_params, timeout=30)
            response.raise_for_status()
            return cast(dict[str, Any], response.json())
        except requests.RequestException as e:
            raise RuntimeError(f"FRED API request failed: {e}") from e

    def fetch_series(
        self,
        series_id: str,
        start_date: str | date,
        end_date: str | date,
    ) -> pd.Series:
        """Fetch a single FRED time series.

        Args:
            series_id: FRED series ID (e.g., 'DGS10' for 10-year Treasury).
            start_date: Start date (YYYY-MM-DD).
            end_date: End date (YYYY-MM-DD).

        Returns:
            Series indexed by date with values.

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if isinstance(start_date, date):
            start_date = start_date.isoformat()
        if isinstance(end_date, date):
            end_date = end_date.isoformat()

        params = {
            "series_id": series_id,
            "observation_start": start_date,
            "observation_end": end_date,
        }

        data = self._make_request("series/observations", params)

        if "observations" not in data:
            raise RuntimeError(f"No observations returned for {series_id}")

        observations = cast(list[dict[str, Any]], data["observations"])
        rows = []
        for obs in observations:
            try:
                date_val = pd.to_datetime(obs["date"])
                value_str = obs["value"]
                if value_str == ".":
                    # FRED uses "." for missing data
                    continue
                value = float(value_str)
                rows.append({"date": date_val, "value": value})
            except (ValueError, TypeError, KeyError) as e:
                logger.debug(f"Skipping invalid observation: {e}")
                continue

        if not rows:
            logger.warning(f"No valid data for {series_id}")
            return pd.Series(dtype=float)

        df = pd.DataFrame(rows).set_index("date").sort_index()
        series = df["value"]
        logger.info(f"Loaded {len(series)} observations for {series_id}")
        return series

    def fetch_yield_curve(self, curve_date: str | date) -> pd.DataFrame:
        """Fetch Treasury yield curve snapshot for a specific date.

        Args:
            curve_date: Date (YYYY-MM-DD).

        Returns:
            DataFrame with columns:
                - tenor: Maturity label (e.g., '1Y', '10Y')
                - months: Maturity in months
                - rate: Yield (annual, as percentage)

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if isinstance(curve_date, date):
            curve_date = curve_date.isoformat()

        tenor_to_months = {
            "1M": 1,
            "3M": 3,
            "6M": 6,
            "1Y": 12,
            "2Y": 24,
            "3Y": 36,
            "5Y": 60,
            "7Y": 84,
            "10Y": 120,
            "20Y": 240,
            "30Y": 360,
        }

        rows = []
        for tenor, series_id in self.YIELD_CURVE_SERIES.items():
            try:
                series = self.fetch_series(series_id, curve_date, curve_date)
                if not series.empty:
                    rate = float(series.iloc[0])
                    rows.append(
                        {
                            "tenor": tenor,
                            "months": tenor_to_months[tenor],
                            "rate": rate,
                        }
                    )
            except (RuntimeError, KeyError, IndexError) as e:
                logger.debug(f"Could not fetch {tenor}: {e}")
                continue

        if not rows:
            raise ValueError(f"No yield curve data available for {curve_date}")

        df = pd.DataFrame(rows).sort_values("months").reset_index(drop=True)
        logger.info(f"Loaded yield curve for {curve_date}: {len(df)} points")
        return df

    def fetch_credit_spreads(
        self,
        start_date: str | date,
        end_date: str | date,
        ratings: list[str] | None = None,
    ) -> pd.DataFrame:
        """Fetch credit spread time series.

        Args:
            start_date: Start date (YYYY-MM-DD).
            end_date: End date (YYYY-MM-DD).
            ratings: List of ratings to fetch (default: ['AAA', 'BBB']).

        Returns:
            DataFrame with date index and columns for each rating.

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if ratings is None:
            ratings = ["AAA", "BBB"]

        if isinstance(start_date, date):
            start_date = start_date.isoformat()
        if isinstance(end_date, date):
            end_date = end_date.isoformat()

        spreads = {}
        for rating in ratings:
            if rating not in self.CREDIT_SPREADS:
                logger.warning(f"Unknown rating: {rating}")
                continue

            series_id = self.CREDIT_SPREADS[rating]
            try:
                series = self.fetch_series(series_id, start_date, end_date)
                spreads[rating] = series
            except RuntimeError as e:
                logger.warning(f"Could not fetch {rating} spreads: {e}")
                continue

        if not spreads:
            raise ValueError(f"No credit spread data available for {start_date} to {end_date}")

        df = pd.DataFrame(spreads).sort_index()
        logger.info(
            f"Loaded credit spreads for {len(spreads)} ratings ({start_date} to {end_date})"
        )
        return df
