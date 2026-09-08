"""Real-time-style portfolio safety sentinel for the designated XM account."""
from __future__ import annotations

from typing import Mapping, Any


def sentinel_decision(snapshot: Mapping[str, Any]) -> dict[str, Any]:
    """Fail closed whenever the terminal, account, or risk snapshot is unsafe."""
    reasons: list[str] = []
    terminal_connected = snapshot.get("terminal_connected")
    equity = snapshot.get("equity")
    balance = snapshot.get("balance")
    heartbeat_age = snapshot.get("heartbeat_age_sec", 0)

    if terminal_connected is not True:
        reasons.append("TERMINAL_DISCONNECTED")
    if not isinstance(equity, (int, float)) or not isinstance(balance, (int, float)):
        reasons.append("ACCOUNT_STATE_INVALID")
    if isinstance(equity, (int, float)) and isinstance(balance, (int, float)) and balance <= 0:
        reasons.append("ACCOUNT_BALANCE_UNSAFE")
    if not isinstance(heartbeat_age, (int, float)) or heartbeat_age > 60:
        reasons.append("HEARTBEAT_STALE")

    decision = "KILL" if reasons else "ALLOW"
    return {"decision": decision, "kill_switch": decision == "KILL", "reasons": reasons}
