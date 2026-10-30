#!/usr/bin/env python3
"""Drive the PC1 desktop from the sandbox, by looking at it.

The skill K remembers, wrapped so it cannot be lost again. The mechanism is a
GitHub Actions **self-hosted runner on PC1**, not a browser tool and not a
tunnel:

  * PC1's `winremote-mcp` binds `127.0.0.1:8090`, so only something already on
    PC1 can call it. The self-hosted runner is on PC1, so it is the shortest
    path: no tailnet, no port forward, no credential handed over.
  * `.github/workflows/ax-pc1-desktop-control.yml` (branch
    `ax-arena-roblox-game`) dispatches a tool call and uploads the result,
    including a **PNG screenshot**, as the artifact `pc1-desktop-control`.

Reading the artifact works with a read-only token. **Dispatching needs Actions
write**, which this account's GitHub App token does not have, so `call` reports
the 403 plainly instead of pretending.

  python3 ops/pc1_desktop.py shot                 # dispatch Snapshot, fetch PNG
  python3 ops/pc1_desktop.py call GetSystemInfo
  python3 ops/pc1_desktop.py call Shell '{"command":"hostname"}'
  python3 ops/pc1_desktop.py latest               # fetch the newest artifact only
  python3 ops/pc1_desktop.py doctor               # check every precondition
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile

class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Surface the 302 instead of following it, so the token is not forwarded."""
    def redirect_request(self, *a, **k):
        return None

REPO = "aerismusic8-alt/aeris-drive-automation"
BRANCH = "ax-arena-roblox-game"
WORKFLOW = "ax-pc1-desktop-control.yml"
ARTIFACT = "pc1-desktop-control"
API = "https://api.github.com"
OUT = "out/pc1-desktop"


def token():
    t = os.environ.get("GITHUB_TOKEN")
    if not t:
        raise SystemExit("no GITHUB_TOKEN in this session")
    return t


def gh(path, method="GET", body=None, raw=False):
    req = urllib.request.Request(
        f"{API}{path}" if path.startswith("/") else path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as f:
            data = f.read()
            return f.status, (data if raw else json.loads(data or b"{}"))
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300].decode(errors="replace")
    except Exception as e:
        return None, str(e)[:200]


def newest_artifact():
    st, d = gh(f"/repos/{REPO}/actions/artifacts?per_page=100")
    if not isinstance(d, dict):
        raise SystemExit(f"artifact list failed: {st} {d}")
    arts = [a for a in d.get("artifacts", []) if a["name"] == ARTIFACT]
    if not arts:
        raise SystemExit(f"no '{ARTIFACT}' artifact yet — has the workflow ever run?")
    return max(arts, key=lambda a: a["id"])


def fetch(artifact_id, dest=OUT):
    os.makedirs(dest, exist_ok=True)
    zp = os.path.join(dest, f"artifact-{artifact_id}.zip")
    # GitHub answers with a redirect to blob storage. The GitHub token must NOT
    # be sent to that other host: Azure rejects it with 401. urllib forwards the
    # Authorization header across the redirect, so take the Location and follow
    # it with no auth at all.
    req = urllib.request.Request(
        f"{API}/repos/{REPO}/actions/artifacts/{artifact_id}/zip",
        headers={"Authorization": f"Bearer {token()}",
                 "Accept": "application/vnd.github+json"})
    opener = urllib.request.build_opener(NoRedirect)
    try:
        resp = opener.open(req, timeout=120)
        blob = resp.read()
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            raise SystemExit(f"artifact download failed: {e.code} {e.read()[:200]}")
        loc = e.headers.get("Location")
        with urllib.request.urlopen(loc, timeout=180) as f:
            blob = f.read()
    if len(blob) < 100:
        raise SystemExit(f"artifact download too small: {len(blob)} B")
    open(zp, "wb").write(blob)
    with zipfile.ZipFile(zp) as z:
        z.extractall(dest)
        names = z.namelist()
    shots = [n for n in names if n.lower().endswith((".png", ".jpg", ".jpeg"))]
    print(f"artifact {artifact_id}: {len(blob):,} B -> {dest}")
    for n in names:
        print("   ", n)
    for s in shots:
        p = os.path.join(dest, s)
        print(f"screenshot: {p}  ({os.path.getsize(p):,} B)")
    return shots


def doctor():
    print("PC1 desktop control — preconditions\n")
    ok = True

    st, d = gh(f"/repos/{REPO}")
    live = isinstance(d, dict) and d.get("full_name")
    print(f"  repo reachable       : {'yes' if live else 'NO'} ({st})")
    ok &= bool(live)

    st, d = gh(f"/repos/{REPO}/contents/.github/workflows/{WORKFLOW}?ref={BRANCH}")
    registered = isinstance(d, dict) and d.get("name") == WORKFLOW
    print(f"  workflow on {BRANCH[:18]:18}: {'yes' if registered else 'NO'} ({st})")
    ok &= registered

    st, _ = gh(f"/repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
               method="POST", body={"ref": BRANCH, "inputs": {"tool": "GetSystemInfo"}})
    can_dispatch = st in (204, 201)
    print(f"  can dispatch (write) : {'yes' if can_dispatch else 'NO'} ({st})")
    if not can_dispatch:
        print("      -> needs a GitHub App/PAT with Actions:write. The App key died")
        print("         with the sandbox; K must restore a write credential.")

    try:
        a = newest_artifact()
        print(f"  can read artifacts   : yes (newest id {a['id']}, {a['created_at']})")
    except SystemExit as e:
        print(f"  can read artifacts   : no ({e})")

    print(f"\n  verdict: {'can drive PC1' if (ok and can_dispatch) else 'PARTIAL — see above'}")
    return 0 if (ok and can_dispatch) else 1


def call(tool, args="{}", wait=300):
    st, d = gh(f"/repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
               method="POST", body={"ref": BRANCH, "inputs": {"tool": tool, "args": args}})
    if st not in (204, 201):
        print(f"dispatch refused: {st} {d}")
        if st == 403:
            print("The token is read-only for Actions. Run `doctor` for the full picture.")
        return 1
    print(f"dispatched {tool} on {BRANCH}; waiting for the artifact ...")
    before = None
    try:
        before = newest_artifact()["id"]
    except SystemExit:
        pass
    deadline = time.time() + wait
    while time.time() < deadline:
        time.sleep(15)
        try:
            a = newest_artifact()
        except SystemExit:
            continue
        if a["id"] != before:
            return 0 if fetch(a["id"]) or True else 0
    print("timed out waiting for a new artifact")
    return 1


def main():
    ap = argparse.ArgumentParser(description="Drive the PC1 desktop via its self-hosted runner.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("doctor")
    sub.add_parser("latest")
    s = sub.add_parser("shot")
    s.add_argument("--wait", type=int, default=300)
    c = sub.add_parser("call")
    c.add_argument("tool")
    c.add_argument("args", nargs="?", default="{}")
    c.add_argument("--wait", type=int, default=300)
    a = ap.parse_args()

    if a.cmd == "doctor":
        return doctor()
    if a.cmd == "latest":
        return 0 if fetch(newest_artifact()["id"]) else 1
    if a.cmd == "shot":
        return call("Snapshot", "{}", a.wait)
    if a.cmd == "call":
        return call(a.tool, a.args, a.wait)
    return 1


if __name__ == "__main__":
    sys.exit(main())
