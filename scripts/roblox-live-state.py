#!/usr/bin/env python3
"""Pull the live state of every AX experience and append it to a time series.

Run hourly. No credential is used, because every endpoint here is public and a
key would only add a way to fail.

Why this exists: the reach question ("can people actually get in?") was answered
wrong twice by reading one number out of context. The fix is to record the whole
picture on a schedule, so a change shows up as a trend instead of as a surprise.

The important column is `reach`, and it is computed here, not eyeballed:

  * `maturity` is the content label Roblox generated from the Maturity &
    Compliance questionnaire. It is the thing that decides which ages can join.
    `content-may-vary` means 16+ only; `minimal`/`mild`/`moderate` are eligible
    for the younger tiers once the evaluation below is passed.
  * `playability` is recorded for reference only. For a logged-out caller every
    Roblox experience answers `GuestProhibited`, including Adopt Me, so this
    field says nothing about the game. See the control note below.

Usage:
    python3 scripts/roblox-live-state.py                 # print and append
    python3 scripts/roblox-live-state.py --no-append      # print only
    python3 scripts/roblox-live-state.py --json           # machine output
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HISTORY = REPO_ROOT / "data" / "roblox-live-state.jsonl"

# The experiences this project owns, plus one control that is not ours.
#
# The control is the whole point. `Adopt Me!` is the most-played experience on
# Roblox and carries a `minimal` label, so if it ever reports "not playable" from
# this probe then the probe is broken, not the game. Without the control, an
# unauthenticated API call reads as a broken build.
UNIVERSES = {
    10773483379: {"name": "AX Arena 2: Monster Fields", "role": "primary"},
    10771844216: {"name": "AX Garden Legends", "role": "legacy"},
    10772257179: {"name": "Breachline: Two Sites", "role": "legacy"},
    383310974: {"name": "Adopt Me!", "role": "control"},
}

UA = {"User-Agent": "ax-live-state/1 (+aeris-drive-automation)"}

# Labels that let the younger account tiers in once the evaluation passes.
#
# Keyed off the *display* label, not `contentMaturity`. The API answers
# `contentMaturity: "moderate"` for both the `Moderate` label and the
# `Content May Vary` label, so that field cannot tell them apart, and
# `Content May Vary` is the 16+ one. Matching on the wrong field would report
# the strictest label in the game as the most open.
OPEN_LABELS = {"minimal", "mild", "moderate"}


def get(url: str, timeout: int = 20):
    """GET and parse JSON. Returns (data, error_string)."""
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode()), None
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001 - any failure is just a missing field
        return None, type(exc).__name__


def post(url: str, payload: dict, timeout: int = 20):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={**UA, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode()), None
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001
        return None, type(exc).__name__


def fetch_one(universe_id: int, meta: dict) -> dict:
    rec: dict = {
        "universeId": universe_id,
        "role": meta["role"],
        "name": meta["name"],
    }

    games, err = get(f"https://games.roblox.com/v1/games?universeIds={universe_id}")
    if err or not games or not games.get("data"):
        rec["error"] = err or "no data"
        return rec

    g = games["data"][0]
    rec.update(
        {
            "name": g.get("name"),
            "rootPlaceId": g.get("rootPlaceId"),
            "creator": (g.get("creator") or {}).get("name"),
            "playing": g.get("playing"),
            "visits": g.get("visits"),
            "maxPlayers": g.get("maxPlayers"),
            "created": g.get("created"),
            "updated": g.get("updated"),
        }
    )

    votes, _ = get(f"https://games.roblox.com/v1/games/votes?universeIds={universe_id}")
    if votes and votes.get("data"):
        v = votes["data"][0]
        rec["upVotes"] = v.get("upVotes")
        rec["downVotes"] = v.get("downVotes")

    fav, _ = get(f"https://games.roblox.com/v1/games/{universe_id}/favorites/count")
    if fav:
        rec["favorites"] = fav.get("favoritesCount")

    # The reach signal. Public, and the only field that decides which ages may join.
    age, _ = post(
        "https://apis.roblox.com/experience-guidelines-api/"
        "experience-guidelines/get-age-recommendation",
        {"universeId": universe_id},
    )
    if age:
        det = age.get("ageRecommendationDetails") or {}
        summ = (det.get("summary") or {}).get("ageRecommendation") or {}
        rec["maturityLabel"] = summ.get("displayName")
        rec["maturity"] = summ.get("contentMaturity")
        rec["minAge"] = summ.get("minimumAge")
        rec["descriptors"] = [
            (d.get("descriptor") or {}).get("name")
            for d in det.get("descriptorUsages", [])
        ]
        rec["reach"] = (
            "eligible_for_under_16_after_evaluation"
            if (summ.get("displayName") or "").strip().lower() in OPEN_LABELS
            else "16_plus_only"
        )

    # Recorded, but never read as a verdict: see the module docstring.
    play, _ = get(
        "https://games.roblox.com/v1/games/multiget-playability-status"
        f"?universeIds={universe_id}"
    )
    if play:
        rec["playabilityAnonymousProbe"] = (play[0] or {}).get("playabilityStatus")

    return rec


def build_record() -> dict:
    return {
        "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "note": (
            "playabilityAnonymousProbe is the logged-out caller's own state, not the "
            "game's. Every Roblox experience answers GuestProhibited to it."
        ),
        "universes": [
            fetch_one(uid, meta) for uid, meta in sorted(UNIVERSES.items())
        ],
    }


def render(record: dict) -> str:
    lines = [f"capturedAt {record['capturedAt']}", ""]
    head = f"{'universe':>13} {'role':<8} {'playing':>7} {'visits':>8} {'favs':>5}  {'maturity':<16} {'reach':<40} name"
    lines.append(head)
    lines.append("-" * len(head))
    for u in record["universes"]:
        if "error" in u:
            lines.append(f"{u['universeId']:>13} {u['role']:<8} ERROR: {u['error']}")
            continue
        lines.append(
            f"{u['universeId']:>13} {u['role']:<8} "
            f"{str(u.get('playing', '?')):>7} {str(u.get('visits', '?')):>8} "
            f"{str(u.get('favorites', '?')):>5}  "
            f"{str(u.get('maturityLabel', '?')):<16} "
            f"{str(u.get('reach', '?')):<40} {u.get('name')}"
        )

    primary = next((u for u in record["universes"] if u["role"] == "primary"), None)
    control = next((u for u in record["universes"] if u["role"] == "control"), None)
    lines.append("")
    if control and control.get("playabilityAnonymousProbe") == "GuestProhibited":
        lines.append(
            "CONTROL ok: Adopt Me also reads GuestProhibited, so that field is the "
            "probe's own logged-out state and not a fault in our game."
        )
    if primary and primary.get("reach") == "16_plus_only":
        lines.append(
            "REACH: the primary experience is 16+ only. Completing the full Maturity "
            "& Compliance questionnaire is the free fix; see roblox/ROBLOX938-1-STATUS.md."
        )
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-append", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    record = build_record()

    if args.json:
        print(json.dumps(record, indent=2, ensure_ascii=False))
    else:
        print(render(record))

    if not args.no_append:
        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        with HISTORY.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"\nappended -> {HISTORY.relative_to(REPO_ROOT)}")

    # Never fail the caller: a scheduled job that goes red every hour is noise.
    return 0


if __name__ == "__main__":
    sys.exit(main())
