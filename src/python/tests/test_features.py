"""Tests for feature engineering pipeline."""

import numpy as np
import pandas as pd
import pytest

from medusa.features.pipeline import FeaturePipeline
from medusa.features.preprocessing import (
    FeatureScaler,
    create_sequences,
    train_test_split_temporal,
)
from medusa.features.technical import (
    add_all_indicators,
    atr,
    bollinger_bands,
    ema,
    macd,
    returns,
    rsi,
    sma,
    volatility,
)


class TestTechnicalIndicators:
    def test_sma(self, sample_price):
        result = sma(sample_price, 20)
        assert len(result) == len(sample_price)
        assert result.iloc[:19].isna().all()
        assert not result.iloc[19:].isna().any()

    def test_ema(self, sample_price):
        result = ema(sample_price, 20)
        assert len(result) == len(sample_price)

    def test_rsi(self, sample_price):
        result = rsi(sample_price, 14)
        valid = result.dropna()
        assert (valid >= 0).all() and (valid <= 100).all()

    def test_macd(self, sample_price):
        result = macd(sample_price)
        assert "macd" in result.columns
        assert "signal" in result.columns
        assert "histogram" in result.columns

    def test_bollinger_bands(self, sample_price):
        result = bollinger_bands(sample_price)
        assert "bb_upper" in result.columns
        assert "bb_lower" in result.columns
        valid = result.dropna()
        assert (valid["bb_upper"] >= valid["bb_lower"]).all()

    def test_atr(self, sample_ohlcv):
        result = atr(sample_ohlcv, 14)
        valid = result.dropna()
        assert (valid >= 0).all()

    def test_returns(self, sample_price):
        result = returns(sample_price, 1)
        assert len(result) == len(sample_price)
        assert result.iloc[0] != result.iloc[0]  # first is NaN

    def test_volatility(self, sample_price):
        result = volatility(sample_price, 20)
        valid = result.dropna()
        assert (valid >= 0).all()

    def test_add_all_indicators(self, sample_ohlcv):
        result = add_all_indicators(sample_ohlcv)
        assert "sma_20" in result.columns
        assert "rsi_14" in result.columns
        assert "macd" in result.columns
        assert "bb_upper" in result.columns
        assert "return_1" in result.columns
        assert len(result) == len(sample_ohlcv)


class TestPreprocessing:
    def test_create_sequences(self):
        features = np.random.randn(100, 5)
        target = np.random.randn(100)
        x, y = create_sequences(features, target, sequence_length=10)
        assert x.shape == (90, 10, 5)
        assert y.shape == (90,)

    def test_create_sequences_too_short(self):
        features = np.random.randn(5, 3)
        target = np.random.randn(5)
        with pytest.raises(ValueError, match="Not enough data"):
            create_sequences(features, target, sequence_length=10)

    def test_create_sequences_from_dataframe(self):
        df = pd.DataFrame(np.random.randn(50, 3), columns=["a", "b", "c"])
        target = pd.Series(np.random.randn(50))
        x, y = create_sequences(df, target, sequence_length=10)
        assert x.shape == (40, 10, 3)

    def test_train_test_split_temporal(self, sample_ohlcv):
        train, test = train_test_split_temporal(sample_ohlcv, 0.8)
        assert len(train) == 400
        assert len(test) == 100
        assert train.index[-1] < test.index[0]

    def test_feature_scaler(self, sample_ohlcv):
        numeric = sample_ohlcv[["open", "high", "low", "close"]]
        scaler = FeatureScaler()
        scaled = scaler.fit_transform(numeric)
        assert abs(scaled.mean().mean()) < 0.1
        assert abs(scaled.std().mean() - 1.0) < 0.1

        inversed = scaler.inverse_transform(scaled)
        pd.testing.assert_frame_equal(inversed, numeric, atol=1e-10)

    def test_feature_scaler_not_fitted(self):
        scaler = FeatureScaler()
        df = pd.DataFrame({"a": [1, 2, 3]})
        with pytest.raises(RuntimeError, match="not fitted"):
            scaler.transform(df)


class TestFeaturePipeline:
    def test_pipeline_run(self, sample_ohlcv):
        pipeline = FeaturePipeline(target_col="return_1", train_ratio=0.8)
        result = pipeline.run(sample_ohlcv)

        assert "x_train" in result
        assert "x_test" in result
        assert "y_train" in result
        assert "y_test" in result
        assert "feature_columns" in result
        assert len(result["feature_columns"]) > 10
        assert len(result["x_train"]) > len(result["x_test"])
