"""Data loading and validation utilities."""

from medusa.data.csv_loader import CsvDataLoader
from medusa.data.kdb_loader import KdbDataLoader
from medusa.data.loader import DataLoader
from medusa.data.parquet_loader import ParquetDataLoader
from medusa.data.validators import check_data_quality, validate_ohlcv

try:
    from medusa.data.alpaca_loader import AlpacaHistoricalLoader
    from medusa.data.equity_kdb_loader import EquityKdbLoader
    from medusa.data.fred_loader import FREDDataLoader
    from medusa.data.treasury_loader import TreasuryDataLoader

    __all__ = [
        "AlpacaHistoricalLoader",
        "CsvDataLoader",
        "DataLoader",
        "EquityKdbLoader",
        "FREDDataLoader",
        "KdbDataLoader",
        "ParquetDataLoader",
        "TreasuryDataLoader",
        "check_data_quality",
        "validate_ohlcv",
    ]
except ImportError:
    # Alpaca/PyKX not available - optional dependencies
    try:
        from medusa.data.fred_loader import FREDDataLoader
        from medusa.data.treasury_loader import TreasuryDataLoader

        __all__ = [
            "CsvDataLoader",
            "DataLoader",
            "FREDDataLoader",
            "KdbDataLoader",
            "ParquetDataLoader",
            "TreasuryDataLoader",
            "check_data_quality",
            "validate_ohlcv",
        ]
    except ImportError:
        __all__ = [
            "CsvDataLoader",
            "DataLoader",
            "KdbDataLoader",
            "ParquetDataLoader",
            "check_data_quality",
            "validate_ohlcv",
        ]
