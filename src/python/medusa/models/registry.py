"""MLflow experiment tracking and model registry for ML training runs."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pandas as pd
from loguru import logger

try:
    import mlflow
    import mlflow.pytorch
    from mlflow.tracking import MlflowClient

    HAS_MLFLOW = True
except ImportError:
    HAS_MLFLOW = False


class ModelRegistry:
    """MLflow experiment tracking and model registry for Medusa ML models.

    Features:
    - Auto-log training params, metrics, and artifacts
    - Compare experiments across runs
    - Retrieve best model by metric
    - Register and stage models (staging → production)
    """

    def __init__(
        self,
        experiment_name: str = "medusa",
        tracking_uri: str = "mlruns/",
    ) -> None:
        """Initialize MLflow registry.

        Args:
            experiment_name: Name of the MLflow experiment.
            tracking_uri: Path to MLflow tracking directory (local or remote).

        Raises:
            ImportError: If mlflow is not installed.
        """
        if not HAS_MLFLOW:
            raise ImportError("MLflow not installed. Install with: pip install mlflow>=2.10.0")

        self.experiment_name = experiment_name
        self.tracking_uri = tracking_uri

        # Set tracking URI and experiment
        mlflow.set_tracking_uri(tracking_uri)
        mlflow.set_experiment(experiment_name)

        self.client = MlflowClient(tracking_uri=tracking_uri)
        self.experiment = mlflow.get_experiment_by_name(experiment_name)

        if self.experiment:
            self.experiment_id = self.experiment.experiment_id
        else:
            self.experiment_id = mlflow.create_experiment(experiment_name)

        logger.info(
            f"MLflow registry initialized: experiment={experiment_name}, "
            f"tracking_uri={tracking_uri}"
        )

    def log_training_run(
        self,
        model: Any,
        params: dict[str, Any],
        metrics: dict[str, float],
        artifacts: list[str] | None = None,
        tags: dict[str, str] | None = None,
        model_name: str | None = None,
    ) -> str:
        """Log a training run with params, metrics, and model artifacts.

        Args:
            model: Trained model object (PyTorch, sklearn, etc).
            params: Hyperparameters dictionary.
            metrics: Metrics dictionary (e.g., {"train_loss": 0.5, "val_sharpe": 1.2}).
            artifacts: List of file paths to log as artifacts.
            tags: Optional tags for the run (e.g., {"strategy": "sma_crossover"}).
            model_name: Optional model name for logging.

        Returns:
            MLflow run ID.
        """
        with mlflow.start_run() as run:
            # Log parameters
            mlflow.log_params(params)

            # Log metrics
            mlflow.log_metrics(metrics)

            # Log tags
            if tags:
                mlflow.set_tags(tags)

            # Log model
            if model_name:
                try:
                    mlflow.pytorch.log_model(model, model_name)
                except Exception:
                    # Fallback for non-PyTorch models
                    mlflow.sklearn.log_model(model, model_name)

            # Log artifacts
            if artifacts:
                for artifact_path in artifacts:
                    if Path(artifact_path).exists():
                        mlflow.log_artifact(artifact_path)
                    else:
                        logger.warning(f"Artifact not found: {artifact_path}")

            run_id = run.info.run_id
            logger.info(f"Logged MLflow run: {run_id}")

            return run_id

    def compare_runs(
        self,
        metric: str = "sharpe_ratio",
        max_results: int = 20,
    ) -> pd.DataFrame:
        """Compare all runs in current experiment by a metric.

        Args:
            metric: Metric name to sort by (e.g., "sharpe_ratio", "val_loss").
            max_results: Maximum number of runs to return.

        Returns:
            DataFrame with columns: run_id, params, metrics, tags.
        """
        runs = mlflow.search_runs(
            experiment_ids=[self.experiment_id],
            order_by=[f"metrics.{metric} DESC"],
            max_results=max_results,
        )

        if runs.empty:
            logger.warning("No runs found in experiment")
            return pd.DataFrame()

        # Select relevant columns
        cols = ["run_id", "start_time", "status"]
        param_cols = [c for c in runs.columns if c.startswith("params.")]
        metric_cols = [c for c in runs.columns if c.startswith("metrics.")]

        result = runs[cols + param_cols + metric_cols].copy()

        logger.info(f"Retrieved {len(result)} runs for comparison")
        return result

    def get_best_model(
        self,
        metric: str = "sharpe_ratio",
        model_name: str = "model",
    ) -> Any:
        """Load the best model by a metric from the registry.

        Args:
            metric: Metric to optimize (e.g., "sharpe_ratio", "val_loss").
            model_name: Name of the logged model artifact.

        Returns:
            Model object — may be PyTorch nn.Module, sklearn estimator, or custom model.
            Type depends on what was logged during training.

        Raises:
            ValueError: If no runs found or model not logged.
        """
        # Find best run
        runs = mlflow.search_runs(
            experiment_ids=[self.experiment_id],
            order_by=[f"metrics.{metric} DESC"],
            max_results=1,
        )

        if runs.empty:
            raise ValueError("No runs found in experiment")

        best_run_id = runs.iloc[0]["run_id"]
        best_metric_value = runs.iloc[0][f"metrics.{metric}"]

        logger.info(f"Best run: {best_run_id} ({metric}={best_metric_value:.4f})")

        # Load model
        try:
            model_uri = f"runs:/{best_run_id}/{model_name}"
            model = mlflow.pytorch.load_model(model_uri)
        except Exception:
            # Fallback for sklearn models
            model = mlflow.sklearn.load_model(model_uri)

        return model

    def register_model(
        self,
        run_id: str,
        model_name: str,
        registered_model_name: str,
        stage: str = "staging",
    ) -> None:
        """Promote a model to the registry with a stage.

        Args:
            run_id: MLflow run ID.
            model_name: Name of the model artifact in the run.
            registered_model_name: Name for the registered model.
            stage: Model stage ("staging", "production", "archived").

        Raises:
            ValueError: If invalid stage specified.
        """
        valid_stages = {"staging", "production", "archived", "none"}
        if stage.lower() not in valid_stages:
            raise ValueError(f"Invalid stage: {stage}. Must be one of {valid_stages}")

        # Register model
        model_uri = f"runs:/{run_id}/{model_name}"
        registered_model = mlflow.register_model(model_uri, registered_model_name)

        # Transition to stage
        self.client.transition_model_version_stage(
            name=registered_model_name,
            version=registered_model.version,
            stage=stage.capitalize(),
        )

        logger.info(
            f"Registered model '{registered_model_name}' "
            f"(version {registered_model.version}) to stage '{stage}'"
        )

    def get_production_model(self, model_name: str) -> Any:
        """Load the production version of a registered model.

        Args:
            model_name: Registered model name.

        Returns:
            Loaded production model.
        """
        model_uri = f"models:/{model_name}/production"
        try:
            model = mlflow.pytorch.load_model(model_uri)
        except Exception:
            model = mlflow.sklearn.load_model(model_uri)

        logger.info(f"Loaded production model: {model_name}")
        return model

    def delete_experiment(self, experiment_id: str | None = None) -> None:
        """Delete an experiment and all its runs.

        Args:
            experiment_id: Experiment ID to delete. If None, deletes current experiment.

        Warning:
            This is a destructive operation and cannot be undone.
        """
        exp_id = experiment_id or self.experiment_id
        self.client.delete_experiment(exp_id)
        logger.warning(f"Deleted experiment: {exp_id}")

    def list_registered_models(self) -> pd.DataFrame:
        """List all registered models in the registry.

        Returns:
            DataFrame with model names, versions, and stages.
        """
        models = self.client.search_registered_models()

        data = []
        for model in models:
            for version in model.latest_versions:
                data.append(
                    {
                        "name": model.name,
                        "version": version.version,
                        "stage": version.current_stage,
                        "run_id": version.run_id,
                    }
                )

        return pd.DataFrame(data)

    def log_artifact_from_dict(self, data: dict[str, Any], filename: str) -> None:
        """Log a dictionary as a JSON artifact.

        Args:
            data: Dictionary to log.
            filename: Filename for the artifact (e.g., "config.json").
        """
        import json
        from tempfile import TemporaryDirectory

        with TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / filename
            with open(path, "w") as f:
                json.dump(data, f, indent=2)

            mlflow.log_artifact(str(path))
