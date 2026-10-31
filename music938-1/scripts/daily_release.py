#!/usr/bin/env python3
"""Keep the AERIS Music channel active: one scheduled batch a day, unattended.

The pod that builds the songs is not the pod that stays up, so this is the
durable half. Two things make it robust on a machine with no git transport:

* The repository is fetched as a **tarball** over HTTPS, not cloned. A sandbox
  with no git transport hangs forever on `git clone`, and the media is not in
  the repo anyway, so the tarball is all the code that is needed.
* The media is gitignored and a fresh pod has an empty `library/`. `release.py`
  reads the `media-938` release to see what exists and downloads each file only
  as it is about to be uploaded, so a run pulls tens of MB, not the whole 500 MB.

The batch is uploaded with `release.py --next --count N --spread H`, so the
uploads land H hours apart and the channel is active around the clock; YouTube's
own `publishAt` does the timing. The updated release ledger is written back
through the GitHub Contents API — the ledger is the only record of what is
already on YouTube, so losing it means re-uploading duplicates.

    python3 scripts/daily_release.py --dry-run
    python3 scripts/daily_release.py --count 6 --spread 4
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"
LEDGER = "music938-1/work/release-state.json"


def token() -> str:
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        raise SystemExit("no AX_GH_TOKEN")
    return tok


def api(path: str, tok: str, method="GET", data=None, raw=None, ctype="application/json"):
    req = urllib.request.Request(
        API + path,
        data=raw if raw is not None else (json.dumps(data).encode() if data is not None else None),
        method=method,
        headers={"Authorization": f"token {tok}", "Accept": "application/vnd.github+json",
                 "User-Agent": "ax-daily-release", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def fetch_tree(tok: str, dest: Path) -> None:
    """Download the repo tarball over HTTPS and extract it. No git needed."""
    url = f"{API}/repos/{REPO}/tarball/main"
    req = urllib.request.Request(url, headers={
        "Authorization": f"token {tok}", "User-Agent": "ax-daily-release"})
    with urllib.request.urlopen(req, timeout=180) as r, tempfile.NamedTemporaryFile(
            suffix=".tar.gz", delete=False) as fh:
        fh.write(r.read())
        tmp = fh.name
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tmp) as t:
        t.extractall(dest)
    os.unlink(tmp)


def write_ledger(tok: str, content: bytes, message: str) -> bool:
    """Create or update the release ledger through the Contents API."""
    st, cur = api(f"/repos/{REPO}/contents/{LEDGER}", tok)
    sha = cur.get("sha") if st == 200 else None
    body = {"message": message, "content": base64.b64encode(content).decode(), "branch": "main"}
    if sha:
        body["sha"] = sha
    st, res = api(f"/repos/{REPO}/contents/{LEDGER}", tok, "PUT", body)
    print(f"ledger write: {st} {res.get('commit', {}).get('sha', res.get('error', ''))}")
    return st in (200, 201)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--count", type=int, default=int(os.environ.get("AX_RELEASE_COUNT", 6)))
    ap.add_argument("--spread", type=float, default=float(os.environ.get("AX_RELEASE_SPREAD", 4)))
    ap.add_argument("--ch", default=os.environ.get("AX_RELEASE_CH", "ch3"))
    ap.add_argument("--root", help="an already-extracted repo root; skips the tarball fetch")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    tok = token()
    if args.root:
        work = Path(args.root)
        root = work if (work / "music938-1").is_dir() else next(work.iterdir())
    else:
        work = Path(tempfile.mkdtemp(prefix="ax-music-"))
        fetch_tree(tok, work)
        root = next(work.iterdir())  # tarball extracts into one top dir
    music = root / "music938-1"
    ledger = music / "work" / "release-state.json"
    before = ledger.read_bytes() if ledger.exists() else b"{}"

    prog = work / "progress.txt"
    cmd = [sys.executable, str(music / "scripts" / "release.py"), "--next", "--public",
           "--ch", args.ch, "--count", str(args.count), "--spread", str(args.spread),
           "--progress-file", str(prog)]
    if args.dry_run:
        cmd.append("--dry-run")
    env = dict(os.environ, AX_GH_TOKEN=tok, PYTHONPATH=str(music / "scripts"))
    print("$", " ".join(cmd), flush=True)
    try:
        rc = subprocess.call(cmd, env=env, cwd=music, timeout=1500)
    except subprocess.TimeoutExpired:
        print("release timed out; leaving the ledger untouched", file=sys.stderr)
        return 1
    if prog.exists():
        print("--- progress ---")
        print(prog.read_text(encoding="utf-8").strip())

    if rc == 3:
        print("quota already spent today; nothing to do")
        return 0
    if rc != 0:
        print(f"release returned {rc}", file=sys.stderr)
        return rc
    if args.dry_run:
        return 0

    after = ledger.read_bytes() if ledger.exists() else before
    if after == before:
        print("ledger unchanged")
        return 0
    return 0 if write_ledger(tok, after, "release: daily batch (automated)") else 1


if __name__ == "__main__":
    raise SystemExit(main())
