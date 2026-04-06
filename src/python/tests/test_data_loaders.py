"""Tests for data loaders (CSV, Parquet) and validators."""


import numpy as np
import pandas as pd
import pytest

from medusa.data.csv_loader import CsvDataLoader
from medusa.data.parquet_loader import ParquetDataLoader
from medusa.data.validators import check_data_quality, validate_ohlcv


class TestCsvDataLoader:
    def test_load_ohlcv(self, tmp_csv):
        df = CsvDataLoader.load_ohlcv(tmp_csv)
        assert len(df) == 500
        assert "close" in df.columns
        assert df.index.name == "timestamp"

    def test_load_missing_file(self):
        with pytest.raises(FileNotFoundError):
            CsvDataLoader.load_ohlcv("/nonexistent/path.csv")

    def test_load_missing_columns(self, tmp_path):
        csv = tmp_path / "bad.csv"
        pd.DataFrame({"timestamp": [1], "foo": [2]}).to_csv(csv, index=False)
        with pytest.raises(ValueError, match="missing required columns"):
            CsvDataLoader.load_ohlcv(csv)


class TestParquetDataLoader:
    def test_load_ohlcv(self, tmp_parquet):
        df = ParquetDataLoader.load_ohlcv(tmp_parquet)
        assert len(df) == 500
        assert "close" in df.columns

    def test_load_missing_file(self):
        with pytest.raises(FileNotFoundError):
            ParquetDataLoader.load_ohlcv("/nonexistent/path.parquet")


class TestValidators:
    def test_validate_ohlcv_valid(self, sample_ohlcv):
        validate_ohlcv(sample_ohlcv)  # Should not raise

    def test_validate_ohlcv_missing_cols(self):
        df = pd.DataFrame({"a": [1], "b": [2]})
        with pytest.raises(ValueError, match="Missing required"):
            validate_ohlcv(df)

    def test_validate_ohlcv_nan_values(self, sample_ohlcv):
        bad = sample_ohlcv.copy()
        bad.iloc[5, 0] = np.nan  # NaN in open
        with pytest.raises(ValueError, match="NaN"):
            validate_ohlcv(bad)

    def test_validate_ohlcv_high_lt_low(self, sample_ohlcv):
        bad = sample_ohlcv.copy()
        bad.iloc[10, 1] = bad.iloc[10, 2] - 1  # high < low
        with pytest.raises(ValueError, match="High < Low"):
            validate_ohlcv(bad)

    def test_validate_ohlcv_negative_volume(self, sample_ohlcv):
        bad = sample_ohlcv.copy()
        bad.iloc[0, 4] = -1  # negative volume
        with pytest.raises(ValueError, match="Negative volume"):
            validate_ohlcv(bad)

    def test_check_data_quality(self, sample_ohlcv):
        report = check_data_quality(sample_ohlcv)
        assert report["rows"] == 500
        assert "price_range" in report
        assert report["duplicate_index"] == 0
