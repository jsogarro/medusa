"""Integration tests for end-to-end research workflows."""



class TestCSVToBacktestWorkflow:
    """Test: load CSV → add features → backtest → risk report."""

    def test_csv_backtest_pipeline(self, tmp_csv, sample_ohlcv):
        from medusa.analytics.risk import RiskAnalytics
        from medusa.data.csv_loader import CsvDataLoader
        from medusa.data.validators import validate_ohlcv
        from medusa.features.technical import add_all_indicators

        # Load
        df = CsvDataLoader.load_ohlcv(tmp_csv)
        validate_ohlcv(df)

        # Features
        enriched = add_all_indicators(df)
        enriched = enriched.dropna()
        assert len(enriched) > 100

        # Simple return-based "backtest"
        returns = enriched["close"].pct_change().dropna()

        # Risk report
        report = RiskAnalytics.full_report(returns)
        assert "sharpe_ratio" in report
        assert "max_drawdown" in report


class TestFeaturePipelineWorkflow:
    """Test: OHLCV → feature pipeline → ML-ready data."""

    def test_pipeline_produces_valid_data(self, sample_ohlcv):
        from medusa.features.pipeline import FeaturePipeline

        pipeline = FeaturePipeline(target_col="return_1", train_ratio=0.8)
        result = pipeline.run(sample_ohlcv)

        assert result["x_train"].shape[0] > 0
        assert result["x_test"].shape[0] > 0
        assert not result["x_train"].isna().any().any()
        assert not result["x_test"].isna().any().any()


class TestSequenceWorkflow:
    """Test: features → sequences → LSTM forward pass."""

    def test_feature_to_lstm_pipeline(self, sample_ohlcv):
        import torch

        from medusa.features.preprocessing import create_sequences
        from medusa.features.technical import add_all_indicators
        from medusa.models.lstm import LSTMModel

        enriched = add_all_indicators(sample_ohlcv).dropna()
        target = enriched["close"].pct_change().dropna()
        features = enriched.loc[target.index].select_dtypes(include="number")

        x, y = create_sequences(features.values, target.values, sequence_length=20)
        x_tensor = torch.tensor(x[:8], dtype=torch.float32)

        model = LSTMModel(input_size=x.shape[2], hidden_size=32, num_layers=1)
        with torch.no_grad():
            out = model(x_tensor)
        assert out.shape == (8, 1)
