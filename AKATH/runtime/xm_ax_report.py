"""AX decision/report layer for the XM trading subsystem."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping, Any


def build_report(state: Mapping[str, Any]) -> dict[str, Any]:
    sentinel = state.get("sentinel") or {}
    strategy = state.get("strategy") or {}
    decision = str(sentinel.get("decision", "KILL"))

    if decision == "KILL":
        next_action = "KILL"
    elif strategy.get("accepted") is True:
        next_action = "KEEP"
    elif strategy:
        next_action = "RETEST"
    else:
        next_action = "DISABLE"

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "next_action": next_action,
        "sentinel": dict(sentinel),
        "strategy": dict(strategy),
    }
