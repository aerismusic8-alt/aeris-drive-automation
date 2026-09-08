"""One-cycle XM portfolio observation and fail-closed decision pipeline."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping, Any, Callable
from urllib.request import Request, urlopen
import json

from xm_portfolio_sentinel import sentinel_decision
from xm_risk_engine import evaluate_risk
from xm_ax_report import build_report

DEFAULT_MARKET_MAX_AGE_SEC = 120


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


def normalize_market_data(raw: Mapping[str, Any]) -> dict[str, Any]:
    market = raw.get("market_data") if isinstance(raw.get("market_data"), Mapping) else None
    snapshots = market.get("snapshots") if market and isinstance(market.get("snapshots"), list) else []
    candidates = [item for item in snapshots if isinstance(item, Mapping) and isinstance(item.get("bars"), list)]
    if not candidates:
        return {"available": False, "bars_count": 0, "latest_timestamp": None, "symbol": None, "timeframe": None}
    preferred = next((item for item in candidates if item.get("symbol") == "XAUUSD"), candidates[0])
    bars = [bar for bar in preferred.get("bars", []) if isinstance(bar, Mapping) and "timestamp" in bar]
    latest = max((int(bar["timestamp"]) for bar in bars), default=None)
    return {
        "available": True,
        "bars_count": len(bars),
        "latest_timestamp": latest,
        "symbol": str(preferred.get("symbol")),
        "timeframe": str(preferred.get("timeframe")),
        "source": preferred.get("source"),
        "read_only": preferred.get("read_only") is True,
    }


def market_context(raw: Mapping[str, Any], *, now: datetime | None = None, max_age_sec: float = DEFAULT_MARKET_MAX_AGE_SEC) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    market = raw.get("market_data") if isinstance(raw.get("market_data"), Mapping) else None
    if not market:
        return {"usable": False, "reason": "MARKET_DATA_MISSING", "age_sec": None, **normalize_market_data(raw)}
    age = _age_seconds(str(market.get("received_at")) if market.get("received_at") else None, now)
    if age is None or age > max_age_sec:
        return {"usable": False, "reason": "MARKET_DATA_STALE", "age_sec": age, **normalize_market_data(raw)}
    normalized = normalize_market_data(raw)
    if not normalized["available"] or normalized["bars_count"] < 2:
        return {"usable": False, "reason": "MARKET_DATA_INSUFFICIENT", "age_sec": age, **normalized}
    return {"usable": True, "reason": "MARKET_DATA_READY", "age_sec": age, **normalized}


def normalize_status(status: Mapping[str, Any], market: Mapping[str, Any] | None = None, *, now: datetime | None = None) -> dict[str, Any]:
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
    market_state = market_context(market or {}, now=now)
    strategy = {"accepted": False, "reason": "NO_VERIFIED_STRATEGY"}
    if market_state["usable"]:
        strategy = {"accepted": False, "reason": "MARKET_DATA_READY_STRATEGY_RESEARCH_REQUIRED", "market": market_state}
    else:
        strategy = {"accepted": False, "reason": market_state["reason"], "market": market_state}
    report = build_report({"sentinel": sentinel, "strategy": strategy})
    return {"snapshot": snapshot, "risk": risk, "sentinel": sentinel, "market": market_state, "report": report}


def _fetch_json(path: str, runtime_url: str, *, opener: Callable[..., Any]) -> dict[str, Any]:
    request = Request(runtime_url.rstrip("/") + path, headers={"Accept": "application/json"}, method="GET")
    with opener(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path.strip('/').upper()}_NOT_OBJECT")
    return payload


def fetch_status(runtime_url: str, *, opener: Callable[..., Any] = urlopen) -> dict[str, Any]:
    return _fetch_json("/xm/status", runtime_url, opener=opener)


def fetch_market_data(runtime_url: str, *, opener: Callable[..., Any] = urlopen) -> dict[str, Any]:
    return _fetch_json("/xm/market-data", runtime_url, opener=opener)


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-url", required=True)
    args = parser.parse_args()
    try:
        raw_status = fetch_status(args.runtime_url)
        raw_market = fetch_market_data(args.runtime_url)
        result = normalize_status(raw_status, raw_market)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["sentinel"]["kill_switch"] is False else 2
    except Exception as exc:
        print(json.dumps({"sentinel": {"decision": "KILL", "kill_switch": True, "reasons": ["XM_RUNTIME_FETCH_FAILED"], "detail": str(exc)}}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
