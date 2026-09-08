"""Deterministic risk evaluation for the designated XM account boundary."""
from __future__ import annotations

import math
from typing import Mapping, Any

DEFAULT_MAX_DRAWDOWN_PCT = 5.0
MAX_HEARTBEAT_AGE_SEC = 60.0


def _finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(float(value))


def evaluate_risk(snapshot: Mapping[str, Any], *, max_drawdown_pct: float = DEFAULT_MAX_DRAWDOWN_PCT) -> dict[str, Any]:
    """Return a fail-closed deterministic risk decision for an XM snapshot."""
    reasons: list[str] = []
    equity = snapshot.get("equity")
    balance = snapshot.get("balance")
    heartbeat_age = snapshot.get("heartbeat_age_sec")

    if not _finite_number(equity) or not _finite_number(balance):
        return {"decision": "KILL", "reasons": ["ACCOUNT_VALUE_INVALID"], "drawdown_pct": None}
    if float(equity) < 0 or float(balance) <= 0:
        return {"decision": "KILL", "reasons": ["ACCOUNT_VALUE_UNSAFE"], "drawdown_pct": None}
    if not _finite_number(heartbeat_age) or float(heartbeat_age) > MAX_HEARTBEAT_AGE_SEC:
        reasons.append("HEARTBEAT_STALE")

    drawdown_pct = max(0.0, (float(balance) - float(equity)) / float(balance) * 100.0)
    if drawdown_pct >= float(max_drawdown_pct):
        reasons.append("DRAWDOWN_LIMIT")

    if reasons:
        return {"decision": "KILL", "reasons": reasons, "drawdown_pct": round(drawdown_pct, 6)}
    return {"decision": "ALLOW", "reasons": [], "drawdown_pct": round(drawdown_pct, 6)}
