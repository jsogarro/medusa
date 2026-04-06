"""Configuration management for Medusa research framework."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class KdbConfig(BaseModel):
    """kdb+ connection configuration."""

    host: str = "localhost"
    hdb_port: int = 5012
    rdb_port: int = 5011
    tp_port: int = 5010
    username: str = ""
    password: str = ""
    timeout: int = 30000


class BacktestConfig(BaseModel):
    """Backtesting configuration."""

    initial_capital: float = 100_000.0
    commission: float = 0.001
    slippage: float = 0.0005


class ModelConfig(BaseModel):
    """Deep learning model configuration."""

    device: str = "cpu"
    batch_size: int = 64
    learning_rate: float = 1e-3
    max_epochs: int = 100
    early_stopping_patience: int = 10
    checkpoint_dir: Path = Path("models/checkpoints")


class Settings(BaseSettings):
    """Global settings for Medusa research framework."""

    model_config = SettingsConfigDict(
        env_prefix="MEDUSA_",
        env_file=".env",
        env_file_encoding="utf-8",
        env_nested_delimiter="__",
        extra="ignore",
    )

    data_dir: Path = Path("data")
    results_dir: Path = Path("results")

    kdb: KdbConfig = Field(default_factory=KdbConfig)
    backtest: BacktestConfig = Field(default_factory=BacktestConfig)
    ml: ModelConfig = Field(default_factory=ModelConfig)

    log_level: str = "INFO"


def get_settings(**overrides: Any) -> Settings:
    """Create settings instance with optional overrides."""
    return Settings(**overrides)
