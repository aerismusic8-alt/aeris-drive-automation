#!/usr/bin/env python3
"""How fast will this grow? Answer with a range, and refuse to answer on bad data.

K asks the same question about every surface: *"จะสร้างผู้ติดตามได้เร็วแค่ไหน"* —
how fast will this actually build followers? A single "you'll hit 1,000 in N
weeks" is a lie: the honest answer is a range, and it is only as good as the
data under it.

This module answers with three numbers and the caveat attached:

* **pace** — followers gained per day, measured over the window (7 days default),
  from the *history* the dashboard rail writes.
* **range** — a projection to a gate (1,000 followers/subs) as best/likely/worst
  using the observed variance, never a single point.
* **confidence** — `measured` (a real non-zero slope over a real window),
  `too-new` (no follower movement yet), or `unknown` (no fresh data — refuse).

It deliberately does NOT forecast from zero. On 2026-11-13 every surface sat at
0-8 followers with no movement, so any slope is noise; the module says `too-new`
and names what would make a forecast possible, instead of inventing a date.

    python3 scripts/follower_forecast.py                 # all surfaces, 7 days
    python3 scripts/follower_forecast.py --days 14
    python3 scripts/follower_forecast.py --surface facebook
    python3 scripts/follower_forecast.py --assert-fresh   # exit 1 on stale data
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evidence  # noqa: E402
import report  # noqa: E402
import surfaces  # noqa: E402

# Which history key grows toward which gate, per surface. The gate is the number
# that unlocks that platform's own revenue route, from report.py.
SURFACE_SPEC = {
    "youtube":  ("yt_subs", report.YT_GATE_SUBS, "subs"),
    "tiktok":   ("tk_followers", report.TT_GATE_FOLLOWERS, "followers"),
    "facebook": ("fb_followers", None, "followers"),
}


def _at(row: dict) -> datetime | None:
    try:
        return datetime.fromisoformat(str(row["at"]).replace("Z", "+00:00"))
    except Exception:  # noqa: BLE001
        return None


def load(path: Path | None = None) -> list[dict]:
    p = path or report.HISTORY
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def _points(rows: list[dict], key: str, days: float,
            now: datetime | None = None) -> list[tuple[datetime, float]]:
    """The (time, value) pairs for one key inside the window, oldest first.

    A row whose key is missing or None is skipped, not read as zero: a null
    reading is "not measured", and treating it as 0 would invent a drop.
    """
    now = now or datetime.now(timezone.utc)
    cut = now.timestamp() - days * 86400
    out = []
    for r in rows:
        t = _at(r)
        v = r.get(key)
        if t is None or not isinstance(v, (int, float)):
            continue
        if t.timestamp() >= cut:
            out.append((t, float(v)))
    out.sort(key=lambda x: x[0])
    return out


def pace_per_day(points: list[tuple[datetime, float]]) -> float | None:
    """Followers gained per day, as a least-squares slope over the window.

    A slope, not (last - first) / days: the dashboard writes rows at irregular
    times, and two rows minutes apart would otherwise swing the estimate wildly.
    Returns None when there are fewer than two distinct timestamps.
    """
    if len(points) < 2:
        return None
    t0 = points[0][0].timestamp()
    xs = [(t.timestamp() - t0) / 86400.0 for t, _ in points]
    ys = [v for _, v in points]
    if max(xs) <= 0:
        return None
    mx = statistics.fmean(xs)
    my = statistics.fmean(ys)
    denom = sum((x - mx) ** 2 for x in xs)
    if denom == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / denom


def _daily_gains(points: list[tuple[datetime, float]]) -> list[float]:
    """Per-day gains between consecutive readings, for the spread."""
    gains = []
    for (t1, v1), (t2, v2) in zip(points, points[1:]):
        dt = (t2 - t1).total_seconds() / 86400.0
        if dt > 0:
            gains.append((v2 - v1) / dt)
    return gains


def project(points: list[tuple[datetime, float]], gate: int | None,
            now: datetime | None = None) -> dict:
    """Turn a series into a verdict: pace, a range, and a confidence.

    The range uses the observed spread of daily gains so it is honest about a
    noisy week. With no movement at all it returns `too-new` and a range of
    None — the correct answer when the account is days old.
    """
    now = now or datetime.now(timezone.utc)
    out = {"pace_per_day": None, "current": None, "confidence": "unknown",
           "days_to_gate": None, "range_days": None, "note": ""}
    if len(points) < 2:
        out["note"] = "fewer than two readings in the window"
        return out

    current = points[-1][1]
    out["current"] = current
    slope = pace_per_day(points)
    out["pace_per_day"] = slope

    gains = _daily_gains(points)
    total = points[-1][1] - points[0][1]
    if slope is None or total <= 0:
        out["confidence"] = "too-new"
        out["note"] = ("no net follower growth in the window; a forecast from "
                       "zero is noise, not a projection")
        return out

    out["confidence"] = "measured"
    if gate is None or current >= gate:
        out["note"] = ("no gate on this surface; pace is the whole answer"
                       if gate is None else "gate already reached")
        return out

    remaining = gate - current
    best = max(slope, max(gains) if gains else slope)
    likely = slope
    worst = min([g for g in gains if g > 0], default=slope)
    # best = fastest sustained pace; likely = the fitted slope; worst = the
    # slowest *positive* day, so a zero day does not read as "never".
    out["days_to_gate"] = round(remaining / likely, 1) if likely > 0 else None
    out["range_days"] = (round(remaining / best, 1) if best > 0 else None,
                         out["days_to_gate"],
                         round(remaining / worst, 1) if worst > 0 else None)
    return out


def build(rows: list[dict], days: float, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    newest = _at(rows[-1]) if rows else None
    age = evidence.age_minutes(newest, now) if newest else None
    fresh = newest is not None and age is not None and age <= evidence.FRESH_MINUTES
    out = {"at": now.isoformat().replace("+00:00", "Z"), "days": days,
           "data_age_minutes": None if age is None else round(age, 1),
           "data_fresh": fresh, "surfaces": {}}
    for name, (key, gate, unit) in SURFACE_SPEC.items():
        pts = _points(rows, key, days, now)
        proj = project(pts, gate, now)
        proj["unit"] = unit
        proj["gate"] = gate
        proj["readings"] = len(pts)
        out["surfaces"][name] = proj
    return out


def _fmt(v, nd=1):
    return "—" if v is None else (f"{v:.{nd}f}")


def render(rep: dict) -> str:
    lines = []
    lines.append(f"Follower forecast — window {rep['days']:.0f}d, "
                 f"data age {_fmt(rep['data_age_minutes'], 0)} min "
                 f"({'fresh' if rep['data_fresh'] else 'STALE/UNKNOWN'})")
    if not rep["data_fresh"]:
        lines.append("  ⚠ data is not fresh: this is a REFUSAL, not a forecast. "
                     "Fix the read before deciding (evidence.py).")
    lines.append("")
    lines.append(f"{'surface':10} {'now':>5} {'gate':>6} {'/day':>7} "
                 f"{'confidence':10} {'range to gate (days)':>22}")
    for name, s in rep["surfaces"].items():
        gate = "—" if s["gate"] is None else f"{s['gate']:,}"
        rng = "—"
        if s["range_days"]:
            b, l, w = s["range_days"]
            rng = f"{_fmt(b,0)} … {_fmt(l,0)} … {_fmt(w,0)}"
        lines.append(f"{name:10} {_fmt(s['current'],0):>5} {gate:>6} "
                     f"{_fmt(s['pace_per_day'],2):>7} {s['confidence']:10} "
                     f"{rng:>22}")
    for name, s in rep["surfaces"].items():
        if s["note"]:
            lines.append(f"  · {name}: {s['note']}")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=float, default=7.0)
    ap.add_argument("--surface", choices=sorted(SURFACE_SPEC))
    ap.add_argument("--assert-fresh", action="store_true",
                    help="exit 1 when the newest reading is stale/unknown")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)

    rows = load()
    rep = build(rows, a.days)
    if a.surface:
        rep["surfaces"] = {a.surface: rep["surfaces"][a.surface]}
    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        print(render(rep))
    if a.assert_fresh and not rep["data_fresh"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
