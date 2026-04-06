"""Tests for configuration system."""

from medusa.utils.config import BacktestConfig, KdbConfig, ModelConfig, Settings, get_settings


def test_kdb_config_defaults():
    cfg = KdbConfig()
    assert cfg.host == "localhost"
    assert cfg.hdb_port == 5012
    assert cfg.rdb_port == 5011
    assert cfg.tp_port == 5010
    assert cfg.timeout == 30000


def test_backtest_config_defaults():
    cfg = BacktestConfig()
    assert cfg.initial_capital == 100_000.0
    assert cfg.commission == 0.001
    assert cfg.slippage == 0.0005


def test_model_config_defaults():
    cfg = ModelConfig()
    assert cfg.device == "cpu"
    assert cfg.batch_size == 64
    assert cfg.max_epochs == 100


def test_get_settings():
    s = get_settings()
    assert isinstance(s, Settings)
    assert s.log_level == "INFO"


def test_settings_override():
    s = get_settings(log_level="DEBUG")
    assert s.log_level == "DEBUG"
