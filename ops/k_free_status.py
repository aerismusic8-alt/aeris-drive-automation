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
* **oneshot** — K authorizes exactly once (provisions a token, or signs in once so
  the vault can hold the session) and never again. Not "K in the loop", but not
  zero-K either, so it is reported separately rather than hidden.

Three questions, because "K-free" alone was too coarse:

* **k_free** — needs no K at all.
* **needs K once** — a one-time authorization. Every platform's terms require the
  owner to consent at least once; no amount of automation removes this (consult
  2026-11-07, both vendors agreed).
* **needs K repeatedly** — a browser snapshot that expires, or an unprovisioned
  token, so K is pulled back in. This is what must be zero.

A **fallback** only counts against you when its primary path is missing: if the
Meta token is present, the browser Reels fallback is not a K-dependency. Each
rail can name the primary that supersedes it.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ax_secrets import get_secret  # noqa: E402

# (surface, rail, auth-kind, [secret names that make it K-free], human note,
#  superseded_by: (surface, rail) of the primary that covers this fallback)
RAILS: list[tuple[str, str, str, list[str], str, tuple[str, str] | None]] = [
    ("youtube", "upload + banner", "api",
     ["YT_CH3_REFRESH_TOKEN"], "OAuth refresh token; re-minted by the token heartbeat", None),
    ("youtube", "channel avatar", "oneshot", [],
     "no avatar API exists; one Studio click, then the vault keeps the session", None),
    ("facebook", "Page Reels", "api",
     ["FB_PAGE_TOKEN"], "Meta System User token: K provisions it once, then never. "
     "Preferred when live; the account-level block (2026-11-08) is what makes the "
     "browser fallback matter again",
     None),
    ("facebook", "Reels (browser fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"],
     "the signed-in desktop; `login_vault.py` restores the session on a fresh pod",
     ("facebook", "Page Reels")),
    ("tiktok", "Short posting", "api",
     ["TT_REFRESH_TOKEN", "TT_CLIENT_KEY", "TT_CLIENT_SECRET"],
     "Content Posting API; K authorizes the app once, a job rotates the token", None),
    ("tiktok", "Short posting (fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"], "expires; a dead snapshot is a K sign-in",
     ("tiktok", "Short posting")),
    ("lyrics", "Thai lyrics", "keyless", [],
     "Duck.ai drafts with no login; the lint is the quality gate", None),
    ("music", "song beds (Flow render)", "browser", [],
     "flowmusic.app has no API; session only — an upgrade over the synth bed",
     ("music", "song beds (offline)")),
    ("music", "song beds (offline)", "keyless", [],
     "real-instrument SoundFont master via `flow_song --offline`; no login, no key",
     None),
    ("drive", "asset sync", "api", ["GDRIVE_REFRESH_TOKEN"],
     "OAuth refresh token", None),
    ("vault", "login/state store", "api", ["OPENHANDS_API_KEY"],
     "the KV store 401s without it, which kills scripts", None),
]


def _present(names: list[str]) -> bool:
    return all(bool(get_secret(n)) for n in names)


def audit() -> dict:
    rows = []
    for surface, rail, kind, names, note, sup in RAILS:
        have = _present(names) if names else False
        # keyless needs nothing; api/oneshot are K-free once the credential is
        # here. A browser rail is never K-free: the snapshot working today does
        # not stop it expiring.
        k_free = (kind == "keyless") or (have and kind in ("api", "oneshot"))
        rows.append({"surface": surface, "rail": rail, "auth": kind,
                     "needs": names, "present": have, "k_free": k_free,
                     "note": note, "superseded_by": sup})

    by_key = {(r["surface"], r["rail"]): r for r in rows}

    def covered(r: dict) -> bool:
        """A fallback is not a K-dependency while its primary path is K-free."""
        sup = r["superseded_by"]
        return bool(sup) and by_key.get(sup, {}).get("k_free", False)

    for r in rows:
        r["covered"] = covered(r)
        # An api/oneshot rail with its credential missing needs K *once* (to
        # provision it), not repeatedly. A browser rail with no K-free primary is
        # the only thing that pulls K back again and again.
        r["one_time"] = (r["auth"] in ("api", "oneshot") and not r["k_free"]
                         and not r["covered"])
        r["needs_k"] = not r["k_free"] and not r["one_time"] and not r["covered"]

    recurring = [r for r in rows if r["needs_k"]]
    once = [r for r in rows if r["one_time"]]
    k_free = [r for r in rows if r["k_free"]]

    def brief(r: dict) -> dict:
        return {"surface": r["surface"], "rail": r["rail"], "auth": r["auth"],
                "note": r["note"]}

    return {
        "rails": rows,
        "total": len(rows),
        "k_free": len(k_free),
        "needs_k_once": len(once),
        "needs_k": len(recurring),
        "blocked": [brief(r) for r in recurring],
        "one_time": [brief(r) for r in once],
        # The invariant K asked for: nothing pulls K back in repeatedly.
        "k_free_all": not recurring,
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
            if r["k_free"]:
                mark = "K-FREE "
            elif r["one_time"]:
                mark = "K x1   "
            elif r["covered"]:
                mark = "covered"
            else:
                mark = "NEEDS K"
            print(f"{mark}  {r['surface']:<9} {r['rail']:<26} [{r['auth']}]  {r['note']}")
        print(f"\nK-FREE: {rep['k_free']}/{rep['total']} rails"
              f"  |  K once: {rep['needs_k_once']}"
              f"  |  K repeatedly: {rep['needs_k']}")
        for b in rep["blocked"]:
            print(f"  needs K again: {b['surface']} — {b['rail']} ({b['auth']})")
        for b in rep["one_time"]:
            print(f"  one-time setup: {b['surface']} — {b['rail']}")

    if a.check:
        return 0 if rep["k_free_all"] else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
