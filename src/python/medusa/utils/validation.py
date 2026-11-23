"""Input validation utilities for Medusa.

Provides strict validation for symbols, preventing potential injection attacks.
"""

import re

# Strict symbol validation — uppercase alphanumeric ONLY
STRICT_SYMBOL = re.compile(r"^[A-Z0-9]+$")

# With underscore for options (e.g., AAPL_C_150_20240101)
STRICT_SYMBOL_WITH_UNDERSCORE = re.compile(r"^[A-Z0-9_]+$")

# Maximum symbol length
MAX_SYMBOL_LENGTH = 32


def validate_symbol_strict(symbol: str | None, allow_underscore: bool = False) -> str:
    """Validate and normalize symbol — strict uppercase alphanumeric only.

    This function prevents injection attacks by enforcing a strict whitelist
    of allowed characters. Only uppercase letters and numbers are permitted
    (plus underscore for options if explicitly allowed).

    Args:
        symbol: Symbol to validate
        allow_underscore: If True, allows underscore (for options like AAPL_C_150_20240101)

    Returns:
        Uppercased symbol (validated)

    Raises:
        TypeError: If symbol is not a string or is None
        ValueError: If symbol is invalid (contains disallowed characters or exceeds max length)

    Examples:
        >>> validate_symbol_strict("BTCUSD")
        'BTCUSD'
        >>> validate_symbol_strict("btcusd")  # Auto-uppercased
        'BTCUSD'
        >>> validate_symbol_strict("AAPL_C_150_20240101", allow_underscore=True)
        'AAPL_C_150_20240101'
        >>> validate_symbol_strict("BTC-USD")  # Raises ValueError (hyphen not allowed)
        Traceback (most recent call last):
        ValueError: Invalid symbol: 'BTC-USD' — only [A-Z0-9] allowed
        >>> validate_symbol_strict("BTC;DROP TABLE")  # Raises ValueError (injection attempt)
        Traceback (most recent call last):
        ValueError: Invalid symbol: 'BTC;DROP TABLE' — only [A-Z0-9] allowed
    """
    if symbol is None:
        raise TypeError("Symbol cannot be None")

    if not isinstance(symbol, str):
        raise TypeError(f"Symbol must be string, got {type(symbol)}")

    # Auto-uppercase
    symbol = symbol.upper()

    # Check length
    if len(symbol) > MAX_SYMBOL_LENGTH:
        raise ValueError(f"Symbol exceeds max length {MAX_SYMBOL_LENGTH}: {symbol}")

    # Empty symbol check
    if len(symbol) == 0:
        raise ValueError("Symbol cannot be empty")

    # Pattern matching
    pattern = STRICT_SYMBOL_WITH_UNDERSCORE if allow_underscore else STRICT_SYMBOL

    if not pattern.match(symbol):
        allowed_chars = "[A-Z0-9_]" if allow_underscore else "[A-Z0-9]"
        raise ValueError(f"Invalid symbol: '{symbol}' — only {allowed_chars} allowed")

    return symbol


def validate_symbol_list(symbols: list[str], allow_underscore: bool = False) -> list[str]:
    """Validate a list of symbols.

    Args:
        symbols: List of symbols to validate
        allow_underscore: If True, allows underscore in symbols

    Returns:
        List of validated symbols (uppercased)

    Raises:
        TypeError: If symbols is not a list or contains non-strings
        ValueError: If any symbol is invalid
    """
    if not isinstance(symbols, list):
        raise TypeError(f"Symbols must be a list, got {type(symbols)}")

    return [validate_symbol_strict(sym, allow_underscore=allow_underscore) for sym in symbols]
