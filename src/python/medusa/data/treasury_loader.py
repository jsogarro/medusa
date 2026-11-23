"""U.S. Treasury data loader via Fiscal Data API.

Loads Treasury yield curves, auction results, and historical rates
from the U.S. Department of Treasury Fiscal Data API.

API Documentation: https://fiscaldata.treasury.gov/api-documentation/
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

import pandas as pd
from loguru import logger

try:
    import requests  # type: ignore[import-untyped]

    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    logger.warning("requests not available - Treasury data loader disabled")


class TreasuryDataLoader:
    """Load U.S. Treasury data from Fiscal Data API."""

    BASE_URL = "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/"

    # Daily Treasury Par Yield Curve Rates endpoint
    YIELD_CURVE_ENDPOINT = "v2/accounting/od/avg_interest_rates"

    # Treasury auction results endpoint
    AUCTION_ENDPOINT = "v1/accounting/od/auctions_query"

    @staticmethod
    def _make_request(
        endpoint: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Make API request to Fiscal Data.

        Args:
            endpoint: API endpoint path.
            params: Query parameters.

        Returns:
            JSON response as dictionary.

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if not REQUESTS_AVAILABLE:
            raise ImportError("requests library required for Treasury data loader")

        url = f"{TreasuryDataLoader.BASE_URL}{endpoint}"
        logger.debug(f"Treasury API request: {url} with params {params}")

        try:
            response = requests.get(url, params=params or {}, timeout=30)
            response.raise_for_status()
            return response.json()  # type: ignore[no-any-return]
        except requests.RequestException as e:
            raise RuntimeError(f"Treasury API request failed: {e}") from e

    @staticmethod
    def fetch_yield_curve(curve_date: str | date) -> pd.DataFrame:
        """Fetch Treasury yield curve for a specific date.

        Args:
            curve_date: Date in 'YYYY-MM-DD' format or date object.

        Returns:
            DataFrame with columns:
                - tenor: Maturity in months (1, 2, 3, 6, 12, 24, 36, etc.)
                - rate: Yield (annual, as percentage)

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
            ValueError: If no data available for date.
        """
        if isinstance(curve_date, date):
            curve_date = curve_date.isoformat()

        params = {
            "fields": "record_date,security_desc,avg_interest_rate_amt",
            "filter": f"record_date:eq:{curve_date}",
            "format": "json",
        }

        data = TreasuryDataLoader._make_request(
            TreasuryDataLoader.YIELD_CURVE_ENDPOINT,
            params,
        )

        if not data.get("data"):
            raise ValueError(f"No yield curve data available for {curve_date}")

        records = data["data"]

        # Parse tenor from security description
        tenor_map = {
            "1-MONTH": 1,
            "2-MONTH": 2,
            "3-MONTH": 3,
            "6-MONTH": 6,
            "1-YEAR": 12,
            "2-YEAR": 24,
            "3-YEAR": 36,
            "5-YEAR": 60,
            "7-YEAR": 84,
            "10-YEAR": 120,
            "20-YEAR": 240,
            "30-YEAR": 360,
        }

        rows = []
        for record in records:
            desc = record["security_desc"].upper()
            rate_str = record["avg_interest_rate_amt"]

            # Find matching tenor
            tenor = None
            for key, months in tenor_map.items():
                if key in desc:
                    tenor = months
                    break

            if tenor is None:
                logger.debug(f"Skipping unknown security: {desc}")
                continue

            try:
                rate = float(rate_str)
            except (ValueError, TypeError):
                logger.warning(f"Invalid rate for {desc}: {rate_str}")
                continue

            rows.append({"tenor": tenor, "rate": rate})

        if not rows:
            raise ValueError(f"No valid yield curve points for {curve_date}")

        df = pd.DataFrame(rows).sort_values("tenor").reset_index(drop=True)
        logger.info(f"Loaded Treasury yield curve for {curve_date}: {len(df)} points")
        return df

    @staticmethod
    def fetch_auction_results(
        security_type: str,
        start_date: str | date | None = None,
        end_date: str | date | None = None,
    ) -> pd.DataFrame:
        """Fetch Treasury auction results.

        Args:
            security_type: Security type (e.g., 'Bill', 'Note', 'Bond').
            start_date: Start date (default: 30 days ago).
            end_date: End date (default: today).

        Returns:
            DataFrame with auction results (date, cusip, term, rate, etc.).

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if start_date is None:
            start_date = (datetime.now().date() - pd.Timedelta(days=30)).isoformat()
        elif isinstance(start_date, date):
            start_date = start_date.isoformat()

        if end_date is None:
            end_date = datetime.now().date().isoformat()
        elif isinstance(end_date, date):
            end_date = end_date.isoformat()

        params = {
            "filter": f"security_type:eq:{security_type},"
            f"auction_date:gte:{start_date},auction_date:lte:{end_date}",
            "sort": "-auction_date",
            "format": "json",
        }

        data = TreasuryDataLoader._make_request(
            TreasuryDataLoader.AUCTION_ENDPOINT,
            params,
        )

        if not data.get("data"):
            logger.warning(
                f"No auction results for {security_type} between {start_date} and {end_date}"
            )
            return pd.DataFrame()

        df = pd.DataFrame(data["data"])
        logger.info(
            f"Loaded {len(df)} auction results for {security_type} ({start_date} to {end_date})"
        )
        return df

    @staticmethod
    def fetch_historical_rates(
        tenor: str,
        start_date: str | date,
        end_date: str | date,
    ) -> pd.DataFrame:
        """Fetch historical Treasury rates for a specific tenor.

        Args:
            tenor: Tenor description (e.g., '10-YEAR', '2-YEAR').
            start_date: Start date.
            end_date: End date.

        Returns:
            DataFrame with columns:
                - date: Record date
                - rate: Yield (annual, as percentage)

        Raises:
            ImportError: If requests not available.
            RuntimeError: If API request fails.
        """
        if isinstance(start_date, date):
            start_date = start_date.isoformat()
        if isinstance(end_date, date):
            end_date = end_date.isoformat()

        params = {
            "fields": "record_date,avg_interest_rate_amt",
            "filter": f"security_desc:eq:{tenor},"
            f"record_date:gte:{start_date},record_date:lte:{end_date}",
            "sort": "record_date",
            "format": "json",
        }

        data = TreasuryDataLoader._make_request(
            TreasuryDataLoader.YIELD_CURVE_ENDPOINT,
            params,
        )

        if not data.get("data"):
            logger.warning(f"No historical data for {tenor} between {start_date} and {end_date}")
            return pd.DataFrame()

        records = data["data"]
        rows = []
        for record in records:
            try:
                date_val = pd.to_datetime(record["record_date"])
                rate = float(record["avg_interest_rate_amt"])
                rows.append({"date": date_val, "rate": rate})
            except (ValueError, TypeError, KeyError) as e:
                logger.debug(f"Skipping invalid record: {e}")
                continue

        df = pd.DataFrame(rows).set_index("date").sort_index()
        logger.info(f"Loaded {len(df)} historical rates for {tenor} ({start_date} to {end_date})")
        return df
