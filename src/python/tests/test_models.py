"""Tests for ML/DL models."""

from __future__ import annotations

import subprocess
import sys

import numpy as np
import pytest
import torch

from medusa.models.base import BaseAlphaModel


def _xgboost_works() -> bool:
    """Check if XGBoost can actually create a DMatrix without segfault."""
    try:
        result = subprocess.run(
            [sys.executable, "-c", "import xgboost; xgboost.DMatrix([[1.0]])"],
            capture_output=True,
            timeout=10,
        )
        return result.returncode == 0
    except Exception:
        return False


xgboost_available = _xgboost_works()


class TestBaseAlphaModel:
    def test_has_abstract_forward(self):
        """BaseAlphaModel defines forward() as abstract."""
        assert hasattr(BaseAlphaModel, "forward")
        assert getattr(BaseAlphaModel.forward, "__isabstractmethod__", False)


class TestLSTMModel:
    def test_forward_shape(self):
        from medusa.models.lstm import LSTMModel
        model = LSTMModel(input_size=10, hidden_size=32, num_layers=1)
        x = torch.randn(4, 20, 10)
        out = model(x)
        assert out.shape == (4, 1)

    def test_different_output_size(self):
        from medusa.models.lstm import LSTMModel
        model = LSTMModel(input_size=5, output_size=3)
        x = torch.randn(2, 10, 5)
        out = model(x)
        assert out.shape == (2, 3)


class TestMultiAssetTransformer:
    def test_forward_shape(self):
        from medusa.models.transformer import MultiAssetTransformer
        model = MultiAssetTransformer(
            input_size=20, num_assets=5, d_model=64, nhead=4, num_layers=2
        )
        x = torch.randn(3, 5, 20)
        out = model(x)
        assert out.shape == (3, 5, 1)


@pytest.mark.skipif(not xgboost_available, reason="XGBoost segfaults on this platform")
class TestXGBoostModel:
    def test_train_and_predict(self):
        import pandas as pd

        from medusa.models.xgboost_model import XGBoostSignalModel

        np.random.seed(42)
        x = pd.DataFrame(np.random.randn(100, 5), columns=[f"f{i}" for i in range(5)])
        y = pd.Series(np.random.randn(100))

        model = XGBoostSignalModel(n_estimators=10)
        model.train(x, y)
        preds = model.predict(x)
        assert len(preds) == 100
        assert preds.index.equals(x.index)

    def test_cross_validate(self):
        import pandas as pd

        from medusa.models.xgboost_model import XGBoostSignalModel

        np.random.seed(42)
        x = pd.DataFrame(np.random.randn(200, 3), columns=["a", "b", "c"])
        y = pd.Series(np.random.randn(200))

        model = XGBoostSignalModel(n_estimators=10)
        results = model.cross_validate(x, y, n_splits=3)
        assert len(results) == 3
        assert "mse" in results.columns

    def test_save_load(self, tmp_path):
        import pandas as pd

        from medusa.models.xgboost_model import XGBoostSignalModel

        np.random.seed(42)
        x = pd.DataFrame(np.random.randn(50, 2), columns=["a", "b"])
        y = pd.Series(np.random.randn(50))

        model = XGBoostSignalModel(n_estimators=5)
        model.train(x, y)

        path = tmp_path / "model.json"
        model.save(path)
        assert path.exists()

        model2 = XGBoostSignalModel(n_estimators=5)
        model2.load(path)
        preds = model2.predict(x)
        assert len(preds) == 50
