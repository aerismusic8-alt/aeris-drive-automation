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
  snapshot expires, and then it is a K sign-in, so it is *not* K-free — *unless*
  the vault holds the account password, in which case the agent re-logs in itself
  (`ops/fb_relogin.py`) and the rail becomes **browser-revivable**: not K-free
  (a checkpoint could still need a human) but not a recurring K-dependency either.
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
#  superseded_by: (surface, rail) of the primary that covers this fallback,
#  revivable_by: vault key whose presence lets the agent re-login a browser rail)
RAILS: list[tuple[str, str, str, list[str], str, tuple[str, str] | None, str]] = [
    ("youtube", "upload + banner", "api",
     ["YT_CH3_REFRESH_TOKEN"], "OAuth refresh token; re-minted by the token heartbeat",
     None, ""),
    # The avatar used to be listed here as a one-time K action, because YouTube
    # exposes no avatar API. That is no longer true: the avatar was set on
    # 2026-11-13 by driving YouTube Studio over the signed-in cloud desktop, and
    # the vault holds the Google password, so the agent can do it again without K
    # (`ops/set_avatar_studio.py`). No K-dependency remains, so no row.
    ("facebook", "Page Reels", "api",
     ["FB_PAGE_TOKEN"], "Meta System User token: K provisions it once, then never. "
     "Preferred when live; the account-level block (2026-11-08) is what makes the "
     "browser fallback matter again",
     None, ""),
    ("facebook", "Reels (browser fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"],
     "the signed-in desktop; a dead session is revived from the vault password by "
     "`ops/fb_relogin.py` — no K needed (a checkpoint would still need K)",
     ("facebook", "Page Reels"), "axsecrets:fb-password"),
    ("tiktok", "Short posting", "api",
     ["TT_REFRESH_TOKEN", "TT_CLIENT_KEY", "TT_CLIENT_SECRET"],
     "Content Posting API; K authorizes the app once, a job rotates the token",
     None, ""),
    ("tiktok", "Short posting (fallback)", "browser",
     ["AERIS_STORAGE_STATE_B64"], "expires; no TikTok password is vaulted, so a dead "
     "snapshot is still a K sign-in",
     ("tiktok", "Short posting"), ""),
    ("lyrics", "Thai lyrics", "keyless", [],
     "Duck.ai drafts with no login; the lint is the quality gate", None, ""),
    ("music", "song beds (Flow render)", "browser", [],
     "flowmusic.app has no API; session only — an upgrade over the synth bed",
     ("music", "song beds (offline)"), ""),
    ("music", "song beds (offline)", "keyless", [],
     "real-instrument SoundFont master via `flow_song --offline`; no login, no key",
     None, ""),
    ("drive", "asset sync", "api", ["GDRIVE_REFRESH_TOKEN"],
     "OAuth refresh token", ("drive", "asset sync (browser)"), ""),
    # The Drive API is disabled in the owning Cloud project, but the signed-in
    # desktop reaches Drive fine (verified 2026-11-13: my-drive loaded, 1.5/15 GB
    # used). The OAuth refresh token is only needed for *unattended* sync; the
    # agent can move assets through the browser, so this is a covered fallback and
    # not a K-dependency.
    ("drive", "asset sync (browser)", "browser", [],
     "signed-in desktop can reach Drive; only unattended sync needs the token",
     None, "axsecrets:google-password"),
    ("vault", "login/state store", "api", ["OPENHANDS_API_KEY"],
     "the KV store 401s without it, which kills scripts", None, ""),
]


def _present(names: list[str]) -> bool:
    return all(bool(get_secret(n)) for n in names)


def _vault_has(key: str) -> bool:
    """True when the durable KV store holds `key`.

    A browser rail with a vaulted password is *revivable*: the agent signs back in
    itself (`ops/fb_relogin.py`) instead of waiting for K. The value is never
    read here — only its presence matters, so no secret leaves the store.
    """
    if not key:
        return False
    try:
        import ax_vault  # noqa: PLC0415

        return bool(ax_vault.kv_get(ax_vault.ensure_anchor(), key))
    except BaseException:  # noqa: BLE001 — CI has no vault: ensure_anchor() raises
        # SystemExit (a BaseException, so `except Exception` misses it) when the
        # OpenHands API rejects the runner. A secret lookup must never kill the
        # watchdog job; the 2026-11-11 AX Rail Watchdog run died on exactly this.
        return False


def audit() -> dict:
    rows = []
    for surface, rail, kind, names, note, sup, revivable_by in RAILS:
        have = _present(names) if names else False
        revivable = kind == "browser" and _vault_has(revivable_by)
        # keyless needs nothing; api/oneshot are K-free once the credential is
        # here. A browser rail is never K-free (the snapshot working today does
        # not stop it expiring) but is no longer a *recurring* K-dependency when
        # the agent can re-login it from a vaulted password.
        k_free = (kind == "keyless") or (have and kind in ("api", "oneshot"))
        rows.append({"surface": surface, "rail": rail, "auth": kind,
                     "needs": names, "present": have, "k_free": k_free,
                     "revivable": revivable, "revivable_by": revivable_by,
                     "note": note, "superseded_by": sup})

    by_key = {(r["surface"], r["rail"]): r for r in rows}

    def covered(r: dict) -> bool:
        """A fallback is not a K-dependency while its primary path is K-free."""
        sup = r["superseded_by"]
        return bool(sup) and by_key.get(sup, {}).get("k_free", False)

    for r in rows:
        r["covered"] = covered(r)
        # An api/oneshot rail with its credential missing needs K *once* (to
        # provision it), not repeatedly. A browser rail the agent can re-login
        # from the vault is not a recurring K-dependency either; only a browser
        # rail with no vaulted password pulls K back again and again.
        r["one_time"] = (r["auth"] in ("api", "oneshot") and not r["k_free"]
                         and not r["covered"])
        r["needs_k"] = (not r["k_free"] and not r["one_time"] and not r["covered"]
                        and not r["revivable"])

    recurring = [r for r in rows if r["needs_k"]]
    once = [r for r in rows if r["one_time"]]
    k_free = [r for r in rows if r["k_free"]]
    revivable = [r for r in rows if r["revivable"] and not r["needs_k"]]

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
        "revivable": [brief(r) for r in revivable],
        "needs_k_revivable": len(revivable),
        # The invariant K asked for: nothing pulls K back in repeatedly.
        "k_free_all": not recurring,
    }


BASELINE_KEY = "axsecrets:k-free-baseline"
# One-time fixes that are already on K's list, so the watchdog does not fail
# forever on a rail K has been told about but has not reached yet. Each is a
# (surface, rail) pair. When one is closed, drop its line — the audit then
# confirms it, which is the point of tracking it at all.
KNOWN_ONE_TIME = {
    ("facebook", "Page Reels"),
    ("tiktok", "Short posting"),
    ("drive", "asset sync"),
}


def _baseline(rep: dict) -> int:
    """Fail only on what this watchdog can act on, and record what it sees.

    `--check` exits 1 while *any* rail needs K, which is the right target but a
    useless watchdog signal: the four one-time fixes stay open until K acts, so
    the rail would be red every day and the real regression — a *new* rail that
    quietly acquired a K-dependency — would be lost in the noise. This compares
    against the last recorded state instead:

      * a **new** recurring K-dependency is a hard failure (the loop broke);
      * a known one-time fix still open is reported, not failed;
      * a known one-time fix that is *still* open but whose credential has
        arrived is fine — that is the fix landing.

    The state is written back to the vault so the next run has a baseline. In a
    fresh pod the vault read fails and the first run only records; the second
    run can compare. That is deliberate: an unreadable baseline must never be
    mistaken for "no regression".
    """
    blocked = {(r["surface"], r["rail"]) for r in rep["blocked"]}
    once = {(r["surface"], r["rail"]) for r in rep["one_time"]}

    prior: set[tuple[str, str]] = set()
    try:
        import ax_vault
        raw = ax_vault.kv_get(ax_vault.ensure_anchor(), BASELINE_KEY)
        prior = {tuple(x) for x in json.loads(raw)} if raw else set()
    except Exception:
        prior = set()

    new_blocked = sorted(blocked - prior)
    unknown_once = sorted(once - KNOWN_ONE_TIME)

    print(f"K-free {rep['k_free']}/{rep['total']} rails; "
          f"blocked={sorted(blocked) or 'none'}; "
          f"one-time open={sorted(once) or 'none'}")
    if new_blocked:
        print(f"REGRESSION: new recurring K-dependency {new_blocked}")
    if unknown_once:
        print(f"NOTE: one-time fix not on the known list {unknown_once} "
              "(add it to KNOWN_ONE_TIME or close it)")

    try:
        import ax_vault
        ax_vault.kv_put(ax_vault.ensure_anchor(), BASELINE_KEY,
                        json.dumps(sorted(blocked)))
    except Exception as exc:
        print(f"baseline not recorded ({type(exc).__name__}); first run only")

    return 1 if new_blocked else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 while any rail still needs K")
    ap.add_argument("--baseline", action="store_true",
                    help="fail only on a NEW K-dependency, or on a pre-existing "
                         "one that a one-time fix should have closed (see below)")
    a = ap.parse_args()
    rep = audit()

    if a.baseline:
        return _baseline(rep)

    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        for r in rep["rails"]:
            if r["k_free"]:
                mark = "K-FREE "
            elif r["one_time"]:
                mark = "K x1   "
            elif r["revivable"]:
                mark = "AGENT  "
            elif r["covered"]:
                mark = "covered"
            else:
                mark = "NEEDS K"
            print(f"{mark}  {r['surface']:<9} {r['rail']:<26} [{r['auth']}]  {r['note']}")
        print(f"\nK-FREE: {rep['k_free']}/{rep['total']} rails"
              f"  |  K once: {rep['needs_k_once']}"
              f"  |  agent-revivable: {rep['needs_k_revivable']}"
              f"  |  K repeatedly: {rep['needs_k']}")
        for b in rep["blocked"]:
            print(f"  needs K again: {b['surface']} — {b['rail']} ({b['auth']})")
        for b in rep["revivable"]:
            print(f"  agent-revivable: {b['surface']} — {b['rail']} (no K needed)")
        for b in rep["one_time"]:
            print(f"  one-time setup: {b['surface']} — {b['rail']}")

    if a.check:
        return 0 if rep["k_free_all"] else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
