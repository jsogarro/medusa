"""VectorBT backtesting engine for high-speed vectorized research."""

from __future__ import annotations

from collections.abc import Callable
from itertools import product
from typing import Any

import numpy as np
import pandas as pd
from loguru import logger

from medusa.utils.config import get_settings


class VectorBTEngine:
    """Vectorized backtesting engine using VectorBT."""

    def __init__(
        self,
        initial_capital: float | None = None,
        commission: float | None = None,
        slippage: float | None = None,
        asset_class: str = "crypto",
    ) -> None:
        config = get_settings().backtest
        self.initial_capital = (
            initial_capital if initial_capital is not None else config.initial_capital
        )
        self.asset_class = asset_class

        # Asset-class specific defaults
        if asset_class == "equity":
            # Alpaca: $0 commission for stocks unless explicitly overridden
            self.commission = commission if commission is not None else 0.0
            # Equity slippage model: ~2 basis points
            self.slippage = slippage if slippage is not None else 0.0002
        else:
            # Crypto default
            self.commission = commission if commission is not None else config.commission
            self.slippage = slippage if slippage is not None else config.slippage

    def _filter_market_hours(
        self,
        signals: pd.Series | pd.DataFrame,
        extended_hours: bool = False,
    ) -> pd.Series | pd.DataFrame:
        """Filter signals to only allow trading during market hours (equity only).

        Args:
            signals: Boolean signals (entries or exits)
            extended_hours: Allow extended hours trading (4:00-9:30, 16:00-20:00 ET)

        Returns:
            Filtered signals (masked outside market hours)
        """
        if self.asset_class != "equity":
            # Crypto: 24/7 trading, no filtering
            return signals

        # Extract time from index (assumes DatetimeIndex)
        if not isinstance(signals.index, pd.DatetimeIndex):
            logger.warning("Cannot filter market hours without DatetimeIndex")
            return signals

        # Convert to ET timezone (US/Eastern)
        times = (
            signals.index.tz_convert("US/Eastern").time
            if signals.index.tz is not None
            else signals.index.time
        )

        # Regular market hours: 9:30 - 16:00 ET
        regular_open = pd.Timestamp("09:30").time()
        regular_close = pd.Timestamp("16:00").time()

        if extended_hours:
            # Extended hours: 4:00 - 20:00 ET (includes pre-market and after-hours)
            extended_open = pd.Timestamp("04:00").time()
            extended_close = pd.Timestamp("20:00").time()
            mask = (times >= extended_open) & (times < extended_close)
        else:
            # Regular hours only
            mask = (times >= regular_open) & (times < regular_close)

        # Apply mask (zero out signals outside hours)
        filtered = signals.copy()
        filtered[~mask] = False
        return filtered

    @staticmethod
    def _as_signal(signal: Any, price: pd.Series | pd.DataFrame) -> pd.Series | pd.DataFrame:
        """Return ``signal`` as a pandas object on the price index (arrays and lists included)."""
        if isinstance(signal, (pd.Series, pd.DataFrame)):
            return signal
        if isinstance(price, pd.DataFrame):
            return pd.DataFrame(signal, index=price.index, columns=price.columns)
        return pd.Series(np.asarray(signal), index=price.index)

    def run_signals(
        self,
        price: pd.Series | pd.DataFrame,
        entries: pd.Series | pd.DataFrame,
        exits: pd.Series | pd.DataFrame,
        extended_hours: bool = False,
        **kwargs: Any,
    ) -> Any:
        """Run backtest from entry/exit boolean signals.

        Args:
            price: Close price series.
            entries: Boolean entry signals.
            exits: Boolean exit signals.
            extended_hours: Allow extended hours trading (equity only)

        Returns:
            vbt.Portfolio object with results.
        """
        import vectorbt as vbt

        # A signal computed from bar t's close cannot fill at bar t's close:
        # act on the next bar (fills at that bar's close). Short signals passed
        # via kwargs get the same treatment.
        signals = {"entries": entries, "exits": exits}
        for name in ("short_entries", "short_exits"):
            if name in kwargs:
                signals[name] = kwargs.pop(name)
        signals = {
            k: self._as_signal(v, price).shift(1, fill_value=False) for k, v in signals.items()
        }

        # Filter signals by market hours (equity only)
        if self.asset_class == "equity":
            signals = {k: self._filter_market_hours(v, extended_hours) for k, v in signals.items()}

        portfolio = vbt.Portfolio.from_signals(
            close=price,
            **signals,
            init_cash=self.initial_capital,
            fees=self.commission,
            slippage=self.slippage,
            **kwargs,
        )
        logger.info(f"Backtest complete: Return={portfolio.total_return():.2%}")
        return portfolio

    def run_strategy(
        self,
        price: pd.Series | pd.DataFrame,
        strategy: Any,
        data: pd.DataFrame,
        **kwargs: Any,
    ) -> Any:
        """Backtest a strategy, including its short signals when it has any.

        Strategies exposing ``generate_short_signals(data) -> (short_entries, short_exits)``
        have them passed to ``run_signals`` as ``short_entries``/``short_exits``.
        """
        entries, exits = strategy.generate_signals(data)
        if hasattr(strategy, "generate_short_signals"):
            kwargs["short_entries"], kwargs["short_exits"] = strategy.generate_short_signals(data)
        return self.run_signals(price, entries, exits, **kwargs)

    def run_orders(
        self,
        price: pd.Series | pd.DataFrame,
        size: pd.Series | pd.DataFrame,
        **kwargs: Any,
    ) -> Any:
        """Run backtest from order sizes.

        Args:
            price: Close price series.
            size: Order sizes (positive=buy, negative=sell).

        Returns:
            vbt.Portfolio object.
        """
        import vectorbt as vbt

        portfolio = vbt.Portfolio.from_orders(
            close=price,
            size=size,
            init_cash=self.initial_capital,
            fees=self.commission,
            slippage=self.slippage,
            **kwargs,
        )
        logger.info(f"Backtest complete: Return={portfolio.total_return():.2%}")
        return portfolio

    def optimize_params(
        self,
        price: pd.Series,
        signal_func: Callable[..., tuple[pd.Series, pd.Series]],
        param_grid: dict[str, list[Any]],
        metric: str = "sharpe_ratio",
    ) -> tuple[dict[str, Any], pd.DataFrame]:
        """Grid-search parameter optimization.

        Args:
            price: Close price series.
            signal_func: Callable(**params) -> (entries, exits).
            param_grid: {param_name: [values]}.
            metric: Optimization target ('sharpe_ratio', 'total_return', 'sortino_ratio', 'calmar_ratio').

        Returns:
            Tuple of (best_params dict, results DataFrame).
        """
        param_names = list(param_grid.keys())
        combinations = list(product(*param_grid.values()))
        results: list[dict[str, Any]] = []

        for combo in combinations:
            params = dict(zip(param_names, combo))
            try:
                entries, exits = signal_func(price, **params)
                pf = self.run_signals(price, entries, exits)

                metric_extractors = {
                    "sharpe_ratio": lambda p: p.sharpe_ratio(),
                    "total_return": lambda p: p.total_return(),
                    "sortino_ratio": lambda p: p.sortino_ratio(),
                    "calmar_ratio": lambda p: p.calmar_ratio(),
                    "max_drawdown": lambda p: p.max_drawdown(),
                }
                extractor = metric_extractors.get(metric)
                if extractor is None:
                    raise ValueError(f"Unknown metric: {metric}")

                value = extractor(pf)
                results.append({**params, metric: value})
            except Exception as e:
                logger.warning(f"Backtest failed for {params}: {e}")
                results.append({**params, metric: np.nan})

        results_df = pd.DataFrame(results)

        if results_df[metric].isna().all():
            raise ValueError(f"All backtests failed — no valid results for '{metric}'")

        best_idx = results_df[metric].idxmax()
        best_params = {k: results_df.loc[best_idx, k] for k in param_names}

        logger.info(f"Best params: {best_params} ({metric}={results_df.loc[best_idx, metric]:.4f})")
        return best_params, results_df

    def walk_forward(
        self,
        price: pd.Series,
        signal_func: Callable[..., tuple[pd.Series, pd.Series]],
        param_grid: dict[str, list[Any]],
        train_periods: int = 252,
        test_periods: int = 63,
        metric: str = "sharpe_ratio",
    ) -> pd.DataFrame:
        """Walk-forward optimization.

        Args:
            price: Full price series.
            signal_func: Callable(price, **params) -> (entries, exits).
            param_grid: Parameter grid.
            train_periods: Training window size in bars.
            test_periods: Out-of-sample window size.
            metric: Optimization metric.

        Returns:
            DataFrame with per-fold results.
        """
        n = len(price)
        results: list[dict[str, Any]] = []
        pos = 0

        while pos + train_periods + test_periods <= n:
            train_price = price.iloc[pos : pos + train_periods]
            test_price = price.iloc[pos + train_periods : pos + train_periods + test_periods]

            best_params, _ = self.optimize_params(train_price, signal_func, param_grid, metric)

            test_entries, test_exits = signal_func(test_price, **best_params)
            pf = self.run_signals(test_price, test_entries, test_exits)

            results.append(
                {
                    "train_start": train_price.index[0],
                    "train_end": train_price.index[-1],
                    "test_start": test_price.index[0],
                    "test_end": test_price.index[-1],
                    "params": best_params,
                    "test_return": pf.total_return(),
                    "test_sharpe": pf.sharpe_ratio(),
                }
            )
            pos += test_periods

        return pd.DataFrame(results)
