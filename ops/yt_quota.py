#!/usr/bin/env python3
"""A durable, project-wide ledger for the YouTube Data API's shared quota pool.

Why this exists. `videos.insert` has its own bucket of 100 calls/day, so an
upload always succeeds. `thumbnails.set`, `playlistItems.insert`, `videos.update`
and `videos.list` draw on ONE shared pool of 10,000 units/day for the whole
Google Cloud project. That pool is spent early in the Pacific day, so a video
uploads (HTTP 200) and its thumbnail and playlist insert return 403 in the same
run — it goes live with YouTube's auto frame and no playlist row, which is a
video nobody clicks.

The free API cannot be asked how much of the pool is left, so this is a
reservation ledger, not a reader. Every shared-pool call is written against the
current Pacific day *before* it is made. A caller that cannot reserve its budget
refuses to start instead of producing a video that can never be finished. The
ledger is committed to the repo through the Contents API, so every workflow and
every pod reads the same numbers.

    python3 ops/yt_quota.py                 # show today
    python3 ops/yt_quota.py --json
    python3 ops/yt_quota.py --reset         # after a deliberate quota reset
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "music938-1" / "work" / "yt-quota.json"
REPO = "aerismusic8-alt/aeris-drive-automation"
BRANCH = "main"

# The daily allocation for the shared pool, and the units each method costs.
# Verified against https://developers.google.com/youtube/v3/determine_quota_cost
# on 2026-11-07: the pool is 10,000/day and thumbnails.set / playlistItems.insert
# / videos.update are 50 units each; videos.insert is a separate 100/day bucket
# and is deliberately NOT priced here, because it cannot starve the pool.
POOL = 10_000
COST = {
    "thumbnails.set": 50,
    "playlistItems.insert": 50,
    "playlists.insert": 50,
    "videos.update": 50,
    "playlists.update": 50,
    "videos.list": 1,
    "playlistItems.list": 1,
    "playlists.list": 1,
    "channels.list": 1,
    "search.list": 100,
}

# A caller reserves a budget before it starts, so a run that cannot finish every
# video never begins. The default reserve is what one full release costs: six
# videos, each a thumbnail (50) + a playlist insert (50), plus a margin for the
# reads that surround them.
UNITS_PER_RELEASE = 100
DEFAULT_RESERVE = 6 * UNITS_PER_RELEASE + 500


def pac_day(now: datetime | None = None) -> str:
    """The quota day key. The pool resets at midnight Pacific, not UTC."""
    now = now or datetime.now(timezone.utc)
    try:
        from zoneinfo import ZoneInfo
        return now.astimezone(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m-%d")
    except Exception:  # no zoneinfo/tzdata on this image
        from datetime import timedelta
        return (now.astimezone(timezone.utc) - timedelta(hours=8)).strftime("%Y-%m-%d")


def _empty() -> dict:
    return {"days": {}}


def load(path: Path | None = None) -> dict:
    p = path or LEDGER
    if not p.exists():
        return _empty()
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) and "days" in d else _empty()
    except ValueError:
        return _empty()


def save(data: dict, path: Path | None = None) -> None:
    p = path or LEDGER
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def _gh_token() -> str | None:
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    return tok or None


def commit(message: str = "quota: ledger") -> bool:
    """Write the ledger back to the repo so every worker shares one count."""
    tok = _gh_token()
    if not tok:
        return False
    api = f"https://api.github.com/repos/{REPO}/contents/music938-1/work/yt-quota.json"
    hdr = {"Authorization": f"token {tok}", "Accept": "application/vnd.github+json",
           "User-Agent": "ax-yt-quota"}
    sha = None
    try:
        with urllib.request.urlopen(urllib.request.Request(api, headers=hdr), timeout=60) as r:
            sha = json.load(r).get("sha")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            return False
    body = {"message": message, "branch": BRANCH,
            "content": base64.b64encode(LEDGER.read_bytes()).decode()}
    if sha:
        body["sha"] = sha
    try:
        req = urllib.request.Request(api, data=json.dumps(body).encode(), method="PUT",
                                     headers={**hdr, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status in (200, 201)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return False


def used(data: dict | None = None, day: str | None = None) -> int:
    d = data if data is not None else load()
    return int((d.get("days", {}).get(day or pac_day()) or {}).get("units", 0))


def remaining(data: dict | None = None, day: str | None = None) -> int:
    return max(0, POOL - used(data, day))


def can_afford(n: int, data: dict | None = None, day: str | None = None) -> bool:
    return used(data, day) + n <= POOL


def reserve(n: int, purpose: str = "", commit_it: bool = True,
            data: dict | None = None, day: str | None = None) -> bool:
    """Pre-flight: may this run spend `n` units of the shared pool?

    This does NOT add `n` to the counter — the actual cost is written by
    `record()` as each call is made, so the ledger counts what really happened and
    never double-counts a reservation. What it does write is the *intent*, so a
    later reader can see which worker claimed the day's headroom and why. Refusing
    here is the point: a run that cannot cover its whole batch does not start, so
    it can never leave an uploaded video without its thumbnail.
    """
    day = day or pac_day()
    d = data if data is not None else load()
    if not can_afford(n, d, day):
        return False
    entry = d.setdefault("days", {}).setdefault(day, {"units": 0, "calls": {}})
    entry.setdefault("reserves", []).append(
        {"purpose": purpose, "units": n,
         "at": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    entry["updated"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if data is None:
        save(d)
    if commit_it:
        commit(f"quota: reserve {n} for {purpose or 'a run'}")
    return True


def record(call: str, n: int = 1, commit_it: bool = False,
           data: dict | None = None, day: str | None = None) -> int:
    """Log `n` calls to `call`, pricing them at the official unit cost."""
    day = day or pac_day()
    units = COST.get(call, 1) * n
    d = data if data is not None else load()
    entry = d.setdefault("days", {}).setdefault(day, {"units": 0, "calls": {}})
    entry["units"] = int(entry.get("units", 0)) + units
    calls = entry.setdefault("calls", {})
    calls[call] = int(calls.get(call, 0)) + n
    entry["updated"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if data is None:
        save(d)
    if commit_it:
        commit(f"quota: {call} x{n}")
    return units


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--reset", action="store_true", help="zero today's counter")
    ap.add_argument("--reserve", type=int, metavar="N")
    ap.add_argument("--purpose", default="")
    ap.add_argument("--push", action="store_true",
                    help="also write the ledger back to the repo (a manual run "
                         "does not commit by default)")
    args = ap.parse_args()

    d = load()
    if args.reset:
        d.setdefault("days", {}).pop(pac_day(), None)
        save(d)
        if args.push:
            commit("quota: manual reset")
        print("reset", pac_day())
        return 0
    if args.reserve is not None:
        ok = reserve(args.reserve, args.purpose or "manual", commit_it=args.push)
        print("reserved" if ok else "REFUSED — not enough left in the pool")
        return 0 if ok else 1
    if args.json:
        print(json.dumps(d, ensure_ascii=False, indent=1))
        return 0
    day = pac_day()
    e = d.get("days", {}).get(day) or {}
    print(f"quota day {day}  (Pacific)")
    print(f"  used      {used(d, day):>6} / {POOL}")
    print(f"  remaining {remaining(d, day):>6}")
    for call, n in sorted((e.get("calls") or {}).items()):
        print(f"    {call:<24} x{n}  = {COST.get(call, 1) * n} units")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
