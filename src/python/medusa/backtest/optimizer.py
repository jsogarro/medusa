"""Bayesian hyperparameter optimization using Optuna."""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from loguru import logger

try:
    import optuna
    from optuna.pruners import MedianPruner
    from optuna.samplers import CmaEsSampler, TPESampler
    from optuna.visualization import (
        plot_optimization_history,
        plot_parallel_coordinate,
        plot_param_importances,
    )

    HAS_OPTUNA = True
except ImportError:
    HAS_OPTUNA = False

from medusa.backtest.vectorbt_engine import VectorBTEngine


class OptunaOptimizer:
    """Bayesian optimization for strategy and model hyperparameters using Optuna.

    Advantages over grid search:
    - Faster convergence with intelligent parameter sampling (TPE/CMA-ES)
    - Early stopping of unpromising trials (pruning)
    - Supports continuous, discrete, and categorical parameters
    - Built-in visualization and study persistence

    Note:
        This optimizer is intentionally coupled to VectorBTEngine for performance.
        For NautilusTrader optimization, use a separate optimizer class.
    """

    def __init__(
        self,
        engine: VectorBTEngine,
        n_trials: int = 100,
        study_name: str = "medusa_optimization",
        storage: str | None = None,
        sampler: str = "tpe",
        pruner: str = "median",
    ) -> None:
        """Initialize optimizer.

        Args:
            engine: VectorBT backtesting engine.
            n_trials: Number of optimization trials.
            study_name: Name for the Optuna study.
            storage: SQLite database path for persistence (e.g., "sqlite:///optuna.db").
                     If None, uses in-memory storage.
            sampler: Sampling algorithm ("tpe" or "cmaes").
            pruner: Pruning algorithm ("median", "percentile", or "none").

        Raises:
            ImportError: If optuna is not installed.
        """
        if not HAS_OPTUNA:
            raise ImportError("Optuna not installed. Install with: pip install optuna>=3.5.0")

        self.engine = engine
        self.n_trials = n_trials
        self.study_name = study_name
        self.storage = storage or "sqlite:///optuna_medusa.db"

        # Select sampler
        if sampler == "tpe":
            self.sampler = TPESampler()
        elif sampler == "cmaes":
            self.sampler = CmaEsSampler()
        else:
            raise ValueError(f"Unknown sampler: {sampler}")

        # Select pruner
        if pruner == "median":
            self.pruner = MedianPruner()
        elif pruner == "percentile":
            from optuna.pruners import PercentilePruner

            self.pruner = PercentilePruner(25.0)
        elif pruner == "none":
            self.pruner = optuna.pruners.NopPruner()
        else:
            raise ValueError(f"Unknown pruner: {pruner}")

        self.study: optuna.Study | None = None

    def optimize_strategy(
        self,
        price: pd.Series,
        signal_func: Callable[..., tuple[pd.Series, pd.Series]],
        param_space: dict[str, dict[str, Any]],
        metric: str = "sharpe_ratio",
        direction: str = "maximize",
    ) -> dict[str, Any]:
        """Optimize strategy parameters using Bayesian optimization.

        Args:
            price: Close price series.
            signal_func: Callable(price, **params) -> (entries, exits).
            param_space: Dictionary defining parameter search space.
                Example:
                {
                    "fast_period": {"type": "int", "low": 5, "high": 50},
                    "slow_period": {"type": "int", "low": 20, "high": 200},
                    "threshold": {"type": "float", "low": 0.0, "high": 0.1},
                }
            metric: Optimization target metric.
            direction: "maximize" or "minimize".

        Returns:
            Dictionary with best parameters.
        """

        def objective(trial: optuna.Trial) -> float:
            # Suggest parameters
            params = {}
            for name, spec in param_space.items():
                param_type = spec["type"]
                if param_type == "int":
                    params[name] = trial.suggest_int(name, spec["low"], spec["high"])
                elif param_type == "float":
                    params[name] = trial.suggest_float(name, spec["low"], spec["high"])
                elif param_type == "categorical":
                    params[name] = trial.suggest_categorical(name, spec["choices"])
                else:
                    raise ValueError(f"Unknown parameter type: {param_type}")

            # Run backtest
            try:
                entries, exits = signal_func(price, **params)
                pf = self.engine.run_signals(price, entries, exits)

                # Extract metric
                metric_extractors = {
                    "sharpe_ratio": lambda p: p.sharpe_ratio(),
                    "total_return": lambda p: p.total_return(),
                    "sortino_ratio": lambda p: p.sortino_ratio(),
                    "calmar_ratio": lambda p: p.calmar_ratio(),
                    "max_drawdown": lambda p: -p.max_drawdown(),  # Negative for minimization
                }
                extractor = metric_extractors.get(metric)
                if extractor is None:
                    raise ValueError(f"Unknown metric: {metric}")

                value = extractor(pf)

                # Handle NaN/inf
                if np.isnan(value) or np.isinf(value):
                    raise optuna.TrialPruned()

                return float(value)

            except Exception as e:
                logger.warning(f"Trial failed with params {params}: {e}")
                raise optuna.TrialPruned()

        # Create or load study
        self.study = optuna.create_study(
            study_name=self.study_name,
            storage=self.storage,
            sampler=self.sampler,
            pruner=self.pruner,
            direction=direction,
            load_if_exists=True,
        )

        # Run optimization
        logger.info(
            f"Starting Optuna optimization: {self.n_trials} trials, "
            f"metric={metric}, direction={direction}"
        )
        self.study.optimize(objective, n_trials=self.n_trials, show_progress_bar=True)

        best_params = self.study.best_params
        best_value = self.study.best_value

        logger.info(f"Optimization complete: Best {metric}={best_value:.4f}, params={best_params}")

        return best_params

    def optimize_model(
        self,
        model_class: type,
        param_space: dict[str, dict[str, Any]],
        data: pd.DataFrame,
        metric: str = "val_loss",
        direction: str = "minimize",
        max_epochs: int = 50,
    ) -> dict[str, Any]:
        """Optimize ML model hyperparameters.

        Args:
            model_class: Model class (e.g., LSTMModel).
            param_space: Parameter search space (same format as optimize_strategy).
            data: Training data dictionary with keys: x_train, y_train, x_val, y_val.
            metric: Metric to optimize ("val_loss", "val_accuracy", etc).
            direction: "maximize" or "minimize".
            max_epochs: Maximum training epochs per trial.

        Returns:
            Dictionary with best parameters.
        """

        def objective(trial: optuna.Trial) -> float:
            # Suggest parameters
            params = {}
            for name, spec in param_space.items():
                param_type = spec["type"]
                if param_type == "int":
                    params[name] = trial.suggest_int(name, spec["low"], spec["high"])
                elif param_type == "float":
                    params[name] = trial.suggest_float(
                        name, spec["low"], spec["high"], log=spec.get("log", False)
                    )
                elif param_type == "categorical":
                    params[name] = trial.suggest_categorical(name, spec["choices"])
                else:
                    raise ValueError(f"Unknown parameter type: {param_type}")

            # Train model
            try:
                import lightning

                model = model_class(**params)
                trainer = lightning.Trainer(
                    max_epochs=max_epochs,
                    enable_checkpointing=False,
                    logger=False,
                    enable_progress_bar=False,
                )

                # Prepare data loaders (simplified for example)
                from torch.utils.data import DataLoader, TensorDataset

                train_dataset = TensorDataset(data["x_train"], data["y_train"])
                val_dataset = TensorDataset(data["x_val"], data["y_val"])

                train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)
                val_loader = DataLoader(val_dataset, batch_size=64)

                trainer.fit(model, train_loader, val_loader)

                # Extract metric
                if metric == "val_loss":
                    value = trainer.callback_metrics.get("val_loss", float("inf"))
                elif metric == "val_accuracy":
                    value = trainer.callback_metrics.get("val_acc", 0.0)
                else:
                    raise ValueError(f"Unknown metric: {metric}")

                return float(value)

            except Exception as e:
                logger.warning(f"Trial failed with params {params}: {e}")
                raise optuna.TrialPruned()

        # Create or load study
        self.study = optuna.create_study(
            study_name=f"{self.study_name}_model",
            storage=self.storage,
            sampler=self.sampler,
            pruner=self.pruner,
            direction=direction,
            load_if_exists=True,
        )

        # Run optimization
        logger.info(
            f"Starting model optimization: {self.n_trials} trials, "
            f"metric={metric}, direction={direction}"
        )
        self.study.optimize(objective, n_trials=self.n_trials, show_progress_bar=True)

        best_params = self.study.best_params
        best_value = self.study.best_value

        logger.info(
            f"Model optimization complete: Best {metric}={best_value:.4f}, params={best_params}"
        )

        return best_params

    def plot_optimization_history(self, output_path: Path | str | None = None) -> None:
        """Visualize optimization progress over trials.

        Args:
            output_path: Path to save plot (HTML). If None, displays interactively.
        """
        if self.study is None:
            raise ValueError("No study available. Run optimization first.")

        fig = plot_optimization_history(self.study)

        if output_path:
            fig.write_html(str(output_path))
            logger.info(f"Saved optimization history to {output_path}")
        else:
            fig.show()

    def plot_param_importances(self, output_path: Path | str | None = None) -> None:
        """Show which parameters matter most for optimization.

        Args:
            output_path: Path to save plot (HTML). If None, displays interactively.
        """
        if self.study is None:
            raise ValueError("No study available. Run optimization first.")

        fig = plot_param_importances(self.study)

        if output_path:
            fig.write_html(str(output_path))
            logger.info(f"Saved parameter importances to {output_path}")
        else:
            fig.show()

    def plot_parallel_coordinate(self, output_path: Path | str | None = None) -> None:
        """Visualize parameter combinations and their objective values.

        Args:
            output_path: Path to save plot (HTML). If None, displays interactively.
        """
        if self.study is None:
            raise ValueError("No study available. Run optimization first.")

        fig = plot_parallel_coordinate(self.study)

        if output_path:
            fig.write_html(str(output_path))
            logger.info(f"Saved parallel coordinate plot to {output_path}")
        else:
            fig.show()

    def get_trials_dataframe(self) -> pd.DataFrame:
        """Get all trials as a DataFrame for analysis.

        Returns:
            DataFrame with columns: number, value, params, state, duration.
        """
        if self.study is None:
            raise ValueError("No study available. Run optimization first.")

        return self.study.trials_dataframe()
