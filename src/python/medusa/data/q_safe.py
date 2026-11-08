"""Validators for values interpolated into q expressions."""

from __future__ import annotations

import re

_IDENT_RE = re.compile(r"[A-Za-z0-9_.]{1,64}")

TIMEFRAMES = frozenset({"1Min", "5Min", "15Min", "1Hour", "1Day"})
SIDES = frozenset({"buy", "sell"})
ORDER_TYPES = frozenset({"market", "limit"})


def q_ident(value: object, what: str = "identifier") -> str:
    """Return ``value`` if it is safe to splice after a backtick or as a table name."""
    if not isinstance(value, str) or not _IDENT_RE.fullmatch(value):
        raise ValueError(f"Invalid {what}: {value!r}. Allowed: letters, digits, '_' and '.' (1-64)")
    return value


def q_choice(value: object, allowed: frozenset[str], what: str) -> str:
    """Return ``value`` if it is one of ``allowed``."""
    if not isinstance(value, str) or value not in allowed:
        raise ValueError(f"Invalid {what}: {value!r}. Allowed: {sorted(allowed)}")
    return value


def q_long(value: object, what: str = "value") -> int:
    """Return ``value`` if it is a real int (not bool, float or str)."""
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"Invalid {what}: {value!r}. Must be an int")
    return value
