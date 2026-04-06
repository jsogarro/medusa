"""Performance tearsheet generation using QuantStats."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd
from loguru import logger


class PerformanceTearsheet:
    """Generate QuantStats performance tearsheets and extract metrics."""

    @staticmethod
    def generate_html(
        returns: pd.Series,
        benchmark: pd.Series | None = None,
        output_path: Path | str | None = None,
        title: str = "Medusa Strategy Report",
    ) -> None:
        """Generate an HTML tearsheet report.

        Args:
            returns: Daily strategy returns series.
            benchmark: Optional benchmark returns for comparison.
            output_path: File path to save the HTML report.
            title: Report title.
        """
        import quantstats as qs

        path = str(output_path) if output_path else None
        if benchmark is not None:
            qs.reports.html(returns, benchmark, output=path, title=title)
        else:
            qs.reports.html(returns, output=path, title=title)

        if path:
            logger.info(f"Tearsheet saved to {path}")

    @staticmethod
    def get_metrics(
        returns: pd.Series,
        benchmark: pd.Series | None = None,
    ) -> dict[str, Any]:
        """Extract key performance metrics.

        Args:
            returns: Daily strategy returns.
            benchmark: Optional benchmark returns.

        Returns:
            Dictionary of performance metrics.
        """
        import quantstats as qs

        metrics: dict[str, Any] = {
            "total_return": float(qs.stats.comp(returns)),
            "cagr": float(qs.stats.cagr(returns)),
            "sharpe": float(qs.stats.sharpe(returns)),
            "sortino": float(qs.stats.sortino(returns)),
            "max_drawdown": float(qs.stats.max_drawdown(returns)),
            "calmar": float(qs.stats.calmar(returns)),
            "volatility": float(qs.stats.volatility(returns)),
            "avg_return": float(returns.mean()),
            "win_rate": float((returns > 0).mean()),
        }

        if benchmark is not None:
            metrics["beta"] = float(qs.stats.greeks(returns, benchmark).get("beta", 0))
            metrics["alpha"] = float(qs.stats.greeks(returns, benchmark).get("alpha", 0))
            metrics["information_ratio"] = float(
                qs.stats.information_ratio(returns, benchmark)
            )

        return metrics

    @staticmethod
    def print_summary(returns: pd.Series) -> None:
        """Print a quick summary to stdout."""
        import quantstats as qs

        qs.reports.basic(returns)
