"""One-cycle XM portfolio observation and fail-closed decision pipeline."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping, Any, Callable
from urllib.request import Request, urlopen
import json

from xm_portfolio_sentinel import sentinel_decision
from xm_risk_engine import evaluate_risk
from xm_ax_report import build_report


def _age_seconds(received_at: str | None, now: datetime) -> float | None:
    if not received_at:
        return None
    try:
        stamp = datetime.fromisoformat(received_at.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        return max(0.0, (now - stamp.astimezone(timezone.utc)).total_seconds())
    except ValueError:
        return None


def normalize_status(status: Mapping[str, Any], *, now: datetime | None = None) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    heartbeat = status.get("heartbeat") if isinstance(status.get("heartbeat"), Mapping) else None
    snapshot = {
        "equity": heartbeat.get("equity") if heartbeat else None,
        "balance": heartbeat.get("balance") if heartbeat else None,
        "terminal_connected": heartbeat.get("terminal_connected") is True if heartbeat else False,
        "heartbeat_age_sec": _age_seconds(str(heartbeat.get("received_at")) if heartbeat and heartbeat.get("received_at") else None, now),
    }
    risk = evaluate_risk(snapshot)
    sentinel = sentinel_decision(snapshot)
    report = build_report({"sentinel": sentinel, "strategy": {"accepted": False, "reason": "NO_VERIFIED_STRATEGY"}})
    return {"snapshot": snapshot, "risk": risk, "sentinel": sentinel, "report": report}


def fetch_status(runtime_url: str, *, opener: Callable[..., Any] = urlopen) -> dict[str, Any]:
    request = Request(runtime_url.rstrip("/") + "/xm/status", headers={"Accept": "application/json"}, method="GET")
    with opener(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("XM_STATUS_NOT_OBJECT")
    return payload


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-url", required=True)
    args = parser.parse_args()
    try:
        raw = fetch_status(args.runtime_url)
        result = normalize_status(raw)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["sentinel"]["kill_switch"] is False else 2
    except Exception as exc:
        print(json.dumps({"sentinel": {"decision": "KILL", "kill_switch": True, "reasons": ["XM_STATUS_FETCH_FAILED"], "detail": str(exc)}}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
