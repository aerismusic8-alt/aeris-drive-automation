#!/usr/bin/env python3
"""Keep the Facebook/TikTok API tokens alive so K never has to sign in again.

The whole point of the Graph/Content API route is that a token outlives a cookie
session. But a 60-day Page token still expires, and TikTok's refresh token
expires too, so "set it once and forget it" is not quite true — something has to
renew them on a schedule. That is this job, run hourly.

It is deliberately quiet when there is nothing to do:
  * no tokens configured  -> print "browser route" and exit 0 (not an alert)
  * token healthy         -> print the expiry, exit 0
  * token missing/expired -> exit 1 so the workflow's ntfy step pings K, because
                             at that point K genuinely is needed once more.

`--refresh` is a separate, agent-side action. It is NOT the default and must not
run in CI: TikTok *rotates* the refresh token on every refresh, and a GitHub
Actions job cannot write a new secret back, so refreshing there would consume the
stored refresh token and break the next run. CI only *checks*; the agent (which
can write the vault) refreshes.

`--refresh --push-secrets --repo owner/name` is the agent's one command: it renews
the tokens from the vault *and* writes the rotated values back to the repo's
Actions secrets, so the next CI run is not left holding a spent token. That is the
piece that keeps the Facebook/TikTok rails K-free after the one-time setup.

That last line is the honest boundary the advisors drew: an *unattended* pipeline
can renew credentials, but it cannot create them, and TikTok cannot be made fully
unattended at all. This job narrows K's job to "do the one-time provisioning" and
then reports the day that provisioning lapses.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    import fb_graph  # noqa: E402
except Exception:  # noqa: BLE001
    fb_graph = None
try:
    import tiktok_api  # noqa: E402
except Exception:  # noqa: BLE001
    tiktok_api = None

WARN_DAYS = 7


def check_facebook(*, refresh: bool) -> dict:
    if fb_graph is None or not fb_graph.available():
        return {"surface": "facebook", "state": "browser", "detail": "no FB_PAGE_TOKEN"}
    if not fb_graph.token_alive(refresh=True):
        # Present but rejected. This is what K must see: the token is not absent,
        # it is blocked, so no amount of waiting fixes it — a fresh System User
        # token does. Reported as its own state, not as "expired".
        return {"surface": "facebook", "state": "blocked",
                "detail": "token rejected by Graph (API access blocked / OAuthException) — "
                          "re-provision the Page token"}
    new = fb_graph.refresh() if refresh else ""
    info = fb_graph.debug_token()
    data = info.get("data", {}) if info.get("ok") else {}
    expires = data.get("expires_at", 0)
    if expires == 0:
        return {"surface": "facebook", "state": "ok", "detail": "never expires (System User token)"}
    if not expires:
        return {"surface": "facebook", "state": "ok",
                "detail": f"expiry unknown; refreshed={bool(new)}"}
    days = (expires - int(time.time())) / 86400
    if days < 0:
        return {"surface": "facebook", "state": "expired",
                "detail": "token has expired — K must re-provision"}
    if days < WARN_DAYS:
        return {"surface": "facebook", "state": "warning",
                "detail": f"expires in {days:.1f} days — re-provision a System User token"}
    return {"surface": "facebook", "state": "ok", "detail": f"valid {days:.0f} more days"}


def check_tiktok(*, refresh: bool) -> dict:
    if tiktok_api is None or not tiktok_api.available():
        return {"surface": "tiktok", "state": "browser", "detail": "no TikTok app tokens"}
    if refresh:
        tok = tiktok_api.refresh()
        if not tok:
            return {"surface": "tiktok", "state": "expired",
                    "detail": "refresh failed — K must re-authorise @aeris.music4"}
    info = tiktok_api.creator_info()
    if not info.get("ok"):
        return {"surface": "tiktok", "state": "warning",
                "detail": f"token set but query failed: {info.get('error')}"}
    level = tiktok_api._privacy(info)
    if level == "SELF_ONLY":
        return {"surface": "tiktok", "state": "warning",
                "detail": "token ok but account is unaudited (SELF_ONLY only); browser route stays"}
    return {"surface": "tiktok", "state": "ok", "detail": f"valid; privacy={level}"}


def push_secrets(repo: str) -> int:
    """Write the currently-effective tokens back to the repo's Actions secrets.

    TikTok rotates its refresh token on every refresh, and a GitHub Actions job
    cannot write a new secret back — so without this, the *next* CI run would
    authenticate with a token that was already spent. The agent is the only
    component that can write, so `--refresh --push-secrets` closes the loop: it
    renews from the vault and publishes the rotated values to CI in one step.
    That is what keeps the rail K-free between authorizations.
    """
    import os
    import subprocess
    tok = os.environ.get("AX_GH_TOKEN") or os.environ.get("GH_PAT") or ""
    if not tok:
        print("push-secrets: no AX_GH_TOKEN (need repo scope); skipping")
        return 1
    vals = {}
    if fb_graph is not None:
        vals["FB_PAGE_TOKEN"] = fb_graph.page_token()
    if tiktok_api is not None:
        vals["TT_ACCESS_TOKEN"] = tiktok_api.access_token()
        vals["TT_REFRESH_TOKEN"] = tiktok_api.refresh_token()
    names = [k for k, v in vals.items() if v]
    if not names:
        print("push-secrets: no tokens configured; nothing to push")
        return 0
    env = dict(os.environ, GITHUB_TOKEN=tok, **{k: vals[k] for k in names})
    root = Path(__file__).resolve().parent.parent
    r = subprocess.run(
        [sys.executable, str(root / "scripts" / "gh-put-secrets.py"),
         "--repo", repo, *names],
        env=env, cwd=str(root), capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())
    return r.returncode


def main(argv: list[str]) -> int:
    refresh = "--refresh" in argv
    push = "--push-secrets" in argv
    repo = ""
    for i, a in enumerate(argv):
        if a == "--repo" and i + 1 < len(argv):
            repo = argv[i + 1]
    rows = [check_facebook(refresh=refresh), check_tiktok(refresh=refresh)]
    for r in rows:
        print(f"{r['surface']:9} {r['state']:8} {r['detail']}")
    if push and refresh and repo:
        push_secrets(repo)
    # A "browser" state is not a failure: the rail is still running, just without
    # the API. An *expired* credential means K is needed. So does a *blocked* one:
    # the token is present but rejected, the surface is parked with work waiting,
    # and only a fresh token fixes it — leaving it green hid 120 stuck posts.
    bad = [r for r in rows if r["state"] in ("expired", "blocked")]
    if bad:
        print("::error::" + "; ".join(f"{r['surface']} {r['detail']}" for r in bad))
        print(json.dumps({"needs_human": [r["surface"] for r in bad]}))
        return 1
    if all(r["state"] == "browser" for r in rows):
        print("no API tokens configured — crosspost runs on the browser session")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
