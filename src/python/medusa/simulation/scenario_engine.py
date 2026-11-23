"""Historical and hypothetical scenario analysis for stress testing."""

from __future__ import annotations

import pandas as pd
from loguru import logger


class ScenarioEngine:
    """Historical and hypothetical scenario analysis."""

    HISTORICAL_SCENARIOS = {
        "2008_financial_crisis": {
            "description": "Lehman collapse, global credit freeze",
            "period": ("2008-09-15", "2008-11-20"),
            "shocks": {"SPY": -0.38, "bonds_10y": 0.05, "gold": 0.15},
        },
        "2020_covid_crash": {
            "description": "COVID-19 pandemic market crash",
            "period": ("2020-02-20", "2020-03-23"),
            "shocks": {"SPY": -0.34, "BTC": -0.50, "bonds_10y": -0.02},
        },
        "2022_rate_hike": {
            "description": "Fed aggressive rate hiking cycle",
            "period": ("2022-01-03", "2022-12-30"),
            "shocks": {"SPY": -0.19, "BTC": -0.65, "bonds_10y": -0.15},
        },
        "btc_flash_crash": {
            "description": "Hypothetical: BTC drops 20% in 1 hour",
            "shocks": {"BTC": -0.20, "ETH": -0.25, "SOL": -0.30},
        },
        "rate_shock_200bp": {
            "description": "Hypothetical: rates rise 200bp suddenly",
            "shocks": {
                "bonds_2y": -0.04,
                "bonds_10y": -0.15,
                "bonds_30y": -0.25,
            },
        },
        "black_monday_1987": {
            "description": "October 1987 stock market crash",
            "period": ("1987-10-14", "1987-10-19"),
            "shocks": {"SPY": -0.22, "bonds_10y": -0.04},
        },
        "dotcom_bubble_2000": {
            "description": "Dot-com bubble burst",
            "period": ("2000-03-10", "2002-10-09"),
            "shocks": {"SPY": -0.49, "NASDAQ": -0.78, "bonds_10y": 0.15},
        },
        "greek_debt_crisis_2011": {
            "description": "European sovereign debt crisis",
            "period": ("2011-07-21", "2011-10-04"),
            "shocks": {"SPY": -0.19, "EUR": -0.08, "gold": 0.12},
        },
        "oil_crash_2014": {
            "description": "Oil price collapse from $100 to $30",
            "period": ("2014-06-23", "2016-02-11"),
            "shocks": {"oil": -0.70, "energy_stocks": -0.45, "SPY": -0.11},
        },
        "crypto_winter_2018": {
            "description": "Cryptocurrency bear market",
            "period": ("2018-01-08", "2018-12-15"),
            "shocks": {"BTC": -0.84, "ETH": -0.94, "altcoins": -0.90},
        },
        "repo_crisis_2019": {
            "description": "US repo market disruption",
            "period": ("2019-09-16", "2019-09-17"),
            "shocks": {"repo_rate": 5.00, "overnight_rate": 2.50},
        },
        "svb_collapse_2023": {
            "description": "Silicon Valley Bank failure",
            "period": ("2023-03-08", "2023-03-13"),
            "shocks": {
                "regional_banks": -0.32,
                "SPY": -0.05,
                "bonds_2y": -0.08,
            },
        },
        "ukraine_invasion_2022": {
            "description": "Russia invades Ukraine",
            "period": ("2022-02-24", "2022-03-07"),
            "shocks": {
                "SPY": -0.13,
                "oil": 0.35,
                "wheat": 0.50,
                "RUB": -0.40,
            },
        },
    }

    def run_scenario(
        self,
        portfolio_value: float,
        weights: pd.Series,
        scenario_name: str,
    ) -> dict[str, str | float | tuple[str, str]]:
        """Apply scenario shocks to portfolio and calculate P&L.

        Args:
            portfolio_value: Current portfolio value in dollars.
            weights: Portfolio weights Series (index=assets).
            scenario_name: Name of scenario from HISTORICAL_SCENARIOS.

        Returns:
            Dict with keys: scenario, description, pnl, pnl_pct, period (optional).

        Raises:
            ValueError: If scenario_name not found.

        """
        if scenario_name not in self.HISTORICAL_SCENARIOS:
            raise ValueError(
                f"Scenario '{scenario_name}' not found. "
                f"Available: {list(self.HISTORICAL_SCENARIOS.keys())}"
            )

        scenario = self.HISTORICAL_SCENARIOS[scenario_name]
        shocks = scenario["shocks"]

        # Calculate P&L
        pnl = 0.0
        for asset, shock in shocks.items():
            if asset in weights.index:
                asset_value = portfolio_value * weights[asset]
                asset_pnl = asset_value * shock
                pnl += asset_pnl

        pnl_pct = (pnl / portfolio_value) * 100 if portfolio_value > 0 else 0.0

        result = {
            "scenario": scenario_name,
            "description": scenario["description"],
            "pnl": pnl,
            "pnl_pct": pnl_pct,
        }

        if "period" in scenario:
            result["period"] = scenario["period"]

        logger.info(f"Scenario '{scenario_name}': P&L=${pnl:,.2f} ({pnl_pct:+.2f}%)")

        return result

    def run_all_scenarios(
        self,
        portfolio_value: float,
        weights: pd.Series,
    ) -> pd.DataFrame:
        """Run all scenarios and return comparison table.

        Args:
            portfolio_value: Current portfolio value in dollars.
            weights: Portfolio weights Series (index=assets).

        Returns:
            DataFrame with columns: scenario, description, pnl, pnl_pct, period.
            Sorted by pnl (worst to best).

        """
        results = []

        for scenario_name in self.HISTORICAL_SCENARIOS:
            result = self.run_scenario(portfolio_value, weights, scenario_name)
            results.append(result)

        df = pd.DataFrame(results)

        # Sort by pnl (worst to best)
        df = df.sort_values("pnl")

        logger.info(f"Ran {len(df)} scenarios on portfolio value ${portfolio_value:,.2f}")
        logger.info(f"Worst scenario: {df.iloc[0]['scenario']} (P&L=${df.iloc[0]['pnl']:,.2f})")
        logger.info(f"Best scenario: {df.iloc[-1]['scenario']} (P&L=${df.iloc[-1]['pnl']:,.2f})")

        return df

    def add_custom_scenario(
        self,
        scenario_name: str,
        description: str,
        shocks: dict[str, float],
        period: tuple[str, str] | None = None,
    ) -> None:
        """Add a custom scenario to the engine.

        Args:
            scenario_name: Unique name for the scenario.
            description: Human-readable description.
            shocks: Dict of asset -> shock_return (e.g., {"BTC": -0.30}).
            period: Optional tuple of (start_date, end_date) strings.

        Raises:
            ValueError: If scenario_name already exists.

        """
        if scenario_name in self.HISTORICAL_SCENARIOS:
            raise ValueError(f"Scenario '{scenario_name}' already exists")

        scenario = {
            "description": description,
            "shocks": shocks,
        }

        if period is not None:
            scenario["period"] = period

        self.HISTORICAL_SCENARIOS[scenario_name] = scenario

        logger.info(f"Added custom scenario '{scenario_name}': {description}")

    def get_scenario_details(
        self, scenario_name: str
    ) -> dict[str, str | dict[str, float] | tuple[str, str]]:
        """Get details of a specific scenario.

        Args:
            scenario_name: Name of the scenario.

        Returns:
            Dict with description, shocks, and optional period.

        Raises:
            ValueError: If scenario_name not found.

        """
        if scenario_name not in self.HISTORICAL_SCENARIOS:
            raise ValueError(
                f"Scenario '{scenario_name}' not found. "
                f"Available: {list(self.HISTORICAL_SCENARIOS.keys())}"
            )

        return self.HISTORICAL_SCENARIOS[scenario_name]

    def list_scenarios(self) -> list[str]:
        """List all available scenario names.

        Returns:
            List of scenario names.

        """
        return list(self.HISTORICAL_SCENARIOS.keys())
