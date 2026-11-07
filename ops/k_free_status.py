#!/usr/bin/env python3
"""Where does the automation still need K? One answer, machine-readable.

K's charter says run 24/7 and never ask K. That is only true if every rail holds a
credential it can refresh without a human. This command is the audit: per surface
it says how the rail authenticates, whether that credential is present here, and
whether losing it would put K back in the loop.

    python3 ops/k_free_status.py            # human table
    python3 ops/k_free_status.py --json     # machine-readable
    python3 ops/k_free_status.py --check    # exit 1 while any rail needs K

`--check` is what a watchdog runs: a red exit means "K is in the loop", and the
JSON names the rail, so the loop attacks the top item instead of guessing.

The distinction that matters, and the reason a rail is not automatically "K-free"
just because it works today:

* **api** — an OAuth/token credential that a scheduled job can refresh. K-free.
* **keyless** — no credential at all: a free endpoint reached over plain HTTP or
  CDP (Duck.ai, Pollinations). Nothing expires, so nothing can put K back.
* **browser** — a Playwright session restored from a snapshot. It works until the
  snapshot expires, and then it is a K sign-in, so it is *not* K-free.
* **none** — no API exists; only a human in the UI. Not K-free.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ax_secrets import get_secret  # noqa: E402

# (surface, rail, auth-kind, [secret names that make it K-free], human note)
RAILS: list[tuple[str, str, str, list[str], str]] = [
    ("youtube", "upload + banner", "api",
     ["YT_CH3_REFRESH_TOKEN"], "OAuth refresh token; re-minted by the token heartbeat"),
    ("youtube", "channel avatar", "none", [],
     "no avatar API exists; a signed-in Studio click, once"),
    ("facebook", "Page Reels", "api",
     ["FB_PAGE_TOKEN"], "Meta System User token (never expires)"),
    ("facebook", "Page Reels (fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"], "expires; a dead snapshot is a K sign-in"),
    ("tiktok", "Short posting", "api",
     ["TT_REFRESH_TOKEN", "TT_CLIENT_KEY", "TT_CLIENT_SECRET"],
     "Content Posting API refresh token"),
    ("tiktok", "Short posting (fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"], "expires; a dead snapshot is a K sign-in"),
    ("lyrics", "Thai lyrics", "keyless", [],
     "Duck.ai drafts with no login; the lint is the quality gate"),
    ("music", "song beds", "browser", [],
     "flowmusic.app has no API; browser session only"),
    ("music", "song beds (offline)", "keyless", [],
     "ffmpeg-synth master via `flow_song --offline`; no login, no key"),
    ("drive", "asset sync", "api", ["GDRIVE_REFRESH_TOKEN"],
     "OAuth refresh token"),
    ("vault", "login/state store", "api", ["OPENHANDS_API_KEY"],
     "the KV store 401s without it, which kills scripts"),
]


def _present(names: list[str]) -> bool:
    return all(bool(get_secret(n)) for n in names)


def audit() -> dict:
    rows = []
    for surface, rail, kind, names, note in RAILS:
        have = _present(names) if names else False
        # An api rail is K-free when its credential is here; a keyless rail needs
        # no credential, so it is K-free by construction. A browser rail is never
        # K-free: the snapshot working today does not stop it expiring.
        k_free = (kind == "keyless") or (have and kind == "api")
        rows.append({"surface": surface, "rail": rail, "auth": kind,
                     "needs": names, "present": have, "k_free": k_free,
                     "note": note})
    blocked = [r for r in rows if not r["k_free"]]
    return {
        "rails": rows,
        "total": len(rows),
        "k_free": len(rows) - len(blocked),
        "blocked": [{"surface": r["surface"], "rail": r["rail"],
                     "auth": r["auth"], "note": r["note"]} for r in blocked],
        "k_free_all": not blocked,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 while any rail still needs K")
    a = ap.parse_args()
    rep = audit()

    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        for r in rep["rails"]:
            mark = "K-FREE " if r["k_free"] else "NEEDS K"
            print(f"{mark}  {r['surface']:<9} {r['rail']:<26} [{r['auth']}]  {r['note']}")
        print(f"\nK-FREE: {rep['k_free']}/{rep['total']} rails")
        for b in rep["blocked"]:
            print(f"  blocked: {b['surface']} — {b['rail']} ({b['auth']})")

    if a.check:
        return 0 if rep["k_free_all"] else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
