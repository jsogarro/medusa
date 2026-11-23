"""Validators for values interpolated into q expressions."""

from __future__ import annotations

import re

import numpy as np

_IDENT_RE = re.compile(r"[A-Za-z0-9_.]{1,64}")

TIMEFRAMES = frozenset({"1Min", "5Min", "15Min", "1Hour", "1Day"})
SIDES = frozenset({"buy", "sell"})
ORDER_TYPES = frozenset({"market", "limit", "stop_loss", "take_profit"})


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
    """Return ``value`` as an int if it is an integer (incl. numpy; not bool, float or str)."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (int, np.integer)):
        raise ValueError(f"Invalid {what}: {value!r}. Must be an int")
    return int(value)
