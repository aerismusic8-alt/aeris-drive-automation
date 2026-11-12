#!/usr/bin/env python3
"""One measurement contract for the four surfaces: a number is usable only when
it is *valid and fresh*.

Why this module exists (advisor panel, duck + pollinations, 2026-11-12, quorum
PASS): the loop kept making decisions on numbers that were missing or stale. A
row could be written while the cloud desktop was down — every Facebook/TikTok/
Shopee field null — and the next run compared against it, so a week of
"no movement" could really be a week of "no data". A green rail and a lying-green
rail looked identical. The panel's fix: every number carries its value, where it
was observed, and when; a consumer accepts it only when it is valid and fresh,
and a stale or missing read can never produce a verdict.

The freshness window is deliberately wide. `report.py` runs on the dashboard
rail three times a day, and the only loss if a read is wrongly judged stale is
that a verdict waits for the next read. It never turns missing data into a
confident, wrong decision — which is the failure this module exists to prevent.
"""
from __future__ import annotations

from datetime import datetime, timezone

# The number of tracked metrics. Each is read from the latest dashboard row.
SURFACE_KEYS = (
    "yt_subs", "yt_views", "yt_videos",
    "fb_followers", "fb_views_28d",
    "tk_followers", "tk_views_7d",
    "sp_clicks", "sp_orders", "sp_commission",
)

# A reading older than this cannot anchor a decision. The dashboard runs three
# times a day (6h apart), so 2h sits well above any within-job delay yet below a
# cadence, meaning a *missed* tick reads stale while a healthy run reads fresh.
FRESH_MINUTES = 120

# A verdict that is not backed by fresh, valid evidence is inconclusive, never a
# WIN or a FAILED. These are the only statuses that may produce one.
DECISIVE = ("fresh", "stale", "unknown")

STATUS_ORDER = {"fresh": 0, "stale": 1, "unknown": 2}


def parse_ts(ts) -> datetime | None:
    """Parse an ISO-8601 UTC timestamp (with or without a trailing Z)."""
    if not ts or not isinstance(ts, str):
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def age_minutes(observed_at, now=None) -> float | None:
    """Minutes between `observed_at` and `now`, or None when unparseable."""
    obs = parse_ts(observed_at)
    if obs is None:
        return None
    if obs.tzinfo is None:
        obs = obs.replace(tzinfo=timezone.utc)
    now_dt = now if isinstance(now, datetime) else parse_ts(now) if now else None
    if now_dt is None:
        now_dt = datetime.now(timezone.utc)
    if now_dt.tzinfo is None:
        now_dt = now_dt.replace(tzinfo=timezone.utc)
    return (now_dt - obs).total_seconds() / 60.0


def status(value, observed_at, now=None, max_age_minutes: float = FRESH_MINUTES) -> str:
    """fresh | stale | unknown — the only vocabulary a consumer needs.

    * unknown — the value is missing (the surface could not be read);
    * stale   — the value exists but was observed too long ago to trust;
    * fresh   — present and recent, safe to decide on.
    """
    if value is None or value == "UNKNOWN":
        return "unknown"
    if not observed_at:
        # A real value with no observation time cannot be proven fresh.
        return "stale"
    age = age_minutes(observed_at, now)
    if age is None:
        return "stale"
    return "fresh" if age <= max_age_minutes else "stale"


def usable(value, observed_at, now=None, max_age_minutes: float = FRESH_MINUTES) -> bool:
    """True only for a fresh, valid number — what a verdict may be built on."""
    return status(value, observed_at, now, max_age_minutes) == "fresh"


def snapshot(metrics: dict, observed_at, now=None,
             max_age_minutes: float = FRESH_MINUTES) -> dict:
    """Attach a status to each named metric, plus a compact health summary.

    `metrics` maps a key to its value; `observed_at` is when the whole read was
    taken. Returns ``{"keys": {k: {value, status}}, "summary": {fresh, stale,
    unknown}}`` so a caller can both render and gate on one structure.
    """
    keys = {}
    summary = {"fresh": 0, "stale": 0, "unknown": 0}
    for k, v in metrics.items():
        s = status(v, observed_at, now, max_age_minutes)
        keys[k] = {"value": v, "status": s}
        summary[s] += 1
    return {"observed_at": observed_at, "keys": keys, "summary": summary}


def health_text(summary: dict) -> str:
    """A one-line human summary: 'fresh 7 / stale 0 / unknown 3'."""
    return (f"fresh {summary.get('fresh', 0)} / stale {summary.get('stale', 0)}"
            f" / unknown {summary.get('unknown', 0)}")
