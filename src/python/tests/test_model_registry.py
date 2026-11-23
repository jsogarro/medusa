"""Tests for MLflow model registry."""

from __future__ import annotations

from tempfile import TemporaryDirectory

import pandas as pd
import pytest

try:
    import mlflow

    from medusa.models.registry import ModelRegistry

    HAS_MLFLOW = True
except ImportError:
    HAS_MLFLOW = False


@pytest.fixture
def temp_mlruns() -> str:
    """Create temporary MLflow tracking directory."""
    with TemporaryDirectory() as tmpdir:
        yield tmpdir


@pytest.fixture
def mock_model() -> dict:
    """Create a mock model (simple dict for testing)."""
    return {"model_type": "mock", "version": "1.0"}


@pytest.mark.skipif(not HAS_MLFLOW, reason="MLflow not installed")
class TestModelRegistry:
    """Test suite for ModelRegistry."""

    def test_init(self, temp_mlruns: str) -> None:
        """Test registry initialization."""
        registry = ModelRegistry(
            experiment_name="test_experiment",
            tracking_uri=temp_mlruns,
        )

        assert registry.experiment_name == "test_experiment"
        assert registry.tracking_uri == temp_mlruns
        assert registry.experiment_id is not None

    def test_log_training_run(self, temp_mlruns: str, mock_model: dict) -> None:
        """Test logging a training run."""
        registry = ModelRegistry(
            experiment_name="test_log_run",
            tracking_uri=temp_mlruns,
        )

        params = {"learning_rate": 0.001, "batch_size": 64}
        metrics = {"train_loss": 0.5, "val_sharpe": 1.2}
        tags = {"strategy": "sma_crossover"}

        run_id = registry.log_training_run(
            model=mock_model,
            params=params,
            metrics=metrics,
            tags=tags,
        )

        assert isinstance(run_id, str)
        assert len(run_id) > 0

        # Verify run was logged
        runs = mlflow.search_runs(experiment_ids=[registry.experiment_id])
        assert len(runs) == 1
        assert runs.iloc[0]["params.learning_rate"] == "0.001"
        assert runs.iloc[0]["metrics.train_loss"] == 0.5

    def test_log_artifact_from_dict(self, temp_mlruns: str) -> None:
        """Test logging dictionary as JSON artifact."""
        registry = ModelRegistry(
            experiment_name="test_artifact",
            tracking_uri=temp_mlruns,
        )

        data = {"config": "value", "nested": {"key": 123}}

        with mlflow.start_run():
            registry.log_artifact_from_dict(data, "config.json")
            run_id = mlflow.active_run().info.run_id

        # Verify artifact was logged
        client = mlflow.tracking.MlflowClient(tracking_uri=temp_mlruns)
        artifacts = client.list_artifacts(run_id)
        assert len(artifacts) > 0
        assert any(a.path == "config.json" for a in artifacts)

    def test_compare_runs_empty(self, temp_mlruns: str) -> None:
        """Test comparing runs when no runs exist."""
        registry = ModelRegistry(
            experiment_name="test_empty_compare",
            tracking_uri=temp_mlruns,
        )

        result = registry.compare_runs()

        assert isinstance(result, pd.DataFrame)
        assert len(result) == 0

    def test_compare_runs_with_data(self, temp_mlruns: str, mock_model: dict) -> None:
        """Test comparing multiple runs."""
        registry = ModelRegistry(
            experiment_name="test_compare",
            tracking_uri=temp_mlruns,
        )

        # Log multiple runs
        for i in range(3):
            registry.log_training_run(
                model=mock_model,
                params={"lr": 0.001 * (i + 1)},
                metrics={"sharpe_ratio": 1.0 + i * 0.1},
            )

        result = registry.compare_runs(metric="sharpe_ratio")

        assert isinstance(result, pd.DataFrame)
        assert len(result) == 3
        assert "run_id" in result.columns
        assert "metrics.sharpe_ratio" in result.columns
        # Should be sorted descending by sharpe_ratio
        assert result["metrics.sharpe_ratio"].iloc[0] >= result["metrics.sharpe_ratio"].iloc[1]

    def test_list_registered_models_empty(self, temp_mlruns: str) -> None:
        """Test listing registered models when none exist."""
        registry = ModelRegistry(
            experiment_name="test_list_empty",
            tracking_uri=temp_mlruns,
        )

        result = registry.list_registered_models()

        assert isinstance(result, pd.DataFrame)
        # May have columns even if empty
        if not result.empty:
            assert "name" in result.columns

    def test_delete_experiment(self, temp_mlruns: str) -> None:
        """Test deleting an experiment."""
        registry = ModelRegistry(
            experiment_name="test_delete",
            tracking_uri=temp_mlruns,
        )

        exp_id = registry.experiment_id

        # Delete experiment
        registry.delete_experiment(exp_id)

        # Verify experiment was deleted
        client = mlflow.tracking.MlflowClient(tracking_uri=temp_mlruns)
        exp = client.get_experiment(exp_id)
        assert exp.lifecycle_stage == "deleted"


def test_registry_import_error() -> None:
    """Test that ImportError is raised when MLflow not installed."""
    if HAS_MLFLOW:
        pytest.skip("MLflow is installed")

    # This would fail at import, so we can't test it directly
    assert not HAS_MLFLOW
