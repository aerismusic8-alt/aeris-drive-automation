"""Control-plane runner health policy for AKATH executor nodes.

The control plane owns liveness decisions. Executor machines only publish
heartbeats; they do not decide that another executor is offline.
"""

from datetime import datetime

HEARTBEAT_SECONDS = 60
DEGRADED_SECONDS = 120
OFFLINE_SECONDS = 300
FAILOVER_SECONDS = 60


def _age_seconds(now: datetime, heartbeat_at: datetime) -> float:
    return max(0.0, (now - heartbeat_at).total_seconds())


def evaluate_runner(
    now: datetime,
    heartbeat_at: datetime | None,
    offline_detected_at: datetime | None = None,
) -> dict:
    if heartbeat_at is None:
        return {
            "status": "UNKNOWN",
            "heartbeat_age_seconds": None,
            "failover_ready": False,
            "reason": "HEARTBEAT_MISSING",
        }

    age = _age_seconds(now, heartbeat_at)

    if age < DEGRADED_SECONDS:
        status = "ONLINE"
    elif age < OFFLINE_SECONDS:
        status = "DEGRADED"
    else:
        status = "OFFLINE"

    failover_ready = False
    if status == "OFFLINE" and offline_detected_at is not None:
        failover_ready = _age_seconds(now, offline_detected_at) >= FAILOVER_SECONDS

    return {
        "status": status,
        "heartbeat_age_seconds": round(age, 1),
        "failover_ready": failover_ready,
        "reason": "FRESH_HEARTBEAT" if status == "ONLINE" else (
            "HEARTBEAT_DELAY" if status == "DEGRADED" else "HEARTBEAT_TIMEOUT"
        ),
    }
