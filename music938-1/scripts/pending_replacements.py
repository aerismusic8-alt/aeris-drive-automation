#!/usr/bin/env python3
"""Spend leftover upload slots on the wrong-render backlog, unattended.

`work/pending-replacements.json` lists videos whose first render was wrong (tofu
text). Each replacement costs one upload slot, so it belongs inside the same
Pacific-day budget as the daily release rather than in a human's hands. This
runs after the release, fixes as many as the day allows, and writes both the
shrunk backlog and the release ledger back to the repository, so the next pod
sees the work that was already done.

    python3 scripts/pending_replacements.py --root <extracted repo root>
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import daily_release  # noqa: E402  (api, token, REPO)

PENDING = "music938-1/work/pending-replacements.json"
LEDGER = "music938-1/work/release-state.json"


def put_file(tok: str, path: str, content: bytes, message: str) -> bool:
    """Create or update a repository file through the Contents API."""
    st, cur = daily_release.api(f"/repos/{daily_release.REPO}/contents/{path}", tok)
    sha = cur.get("sha") if st == 200 else None
    body = {"message": message, "content": base64.b64encode(content).decode(),
            "branch": "main"}
    if sha:
        body["sha"] = sha
    st, res = daily_release.api(f"/repos/{daily_release.REPO}/contents/{path}",
                                tok, "PUT", body)
    print(f"{path} write: {st} {res.get('commit', {}).get('sha', res.get('error', ''))}")
    return st in (200, 201)


def run_replace(music: Path, tok: str, slug: str, kind: str, old: str,
                variant: str) -> int:
    cmd = [sys.executable, str(music / "scripts" / "replace_video.py"),
           "--slug", slug, "--kind", kind, "--old", old, "--yes"]
    if variant:
        cmd += ["--variant", variant]
    return subprocess.call(cmd, env=dict(os.environ, AX_GH_TOKEN=tok,
                                         PYTHONPATH=str(music / "scripts")),
                           cwd=str(music))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", required=True, help="an extracted repo root")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    music = root / "music938-1"
    path = music / "work" / "pending-replacements.json"
    if not path.exists():
        print("no pending-replacements.json; nothing to do")
        return 0

    doc = json.loads(path.read_text(encoding="utf-8"))
    entries = list(doc.get("pending", []))
    if not entries:
        print("the wrong-render backlog is empty")
        return 0

    tok = daily_release.token()
    done, left = 0, list(entries)
    for e in entries:
        # Each entry carries its own slug; the document-level `slug` is a
        # fallback for the single-song backlog this started as.
        slug = e.get("slug") or doc.get("slug")
        rc = run_replace(music, tok, slug, e["kind"], e["old"],
                         e.get("variant", ""))
        if rc == 3:
            print("quota spent; the rest waits for tomorrow")
            break
        if rc != 0:
            print(f"replace failed rc={rc}; keeping {e['old']} in the list",
                  file=sys.stderr)
            continue
        left.remove(e)
        done += 1

    if done:
        doc["pending"] = left
        payload = json.dumps(doc, ensure_ascii=False, indent=1).encode()
        # Update the working copy too. The Contents API write below only touches
        # the remote; a run against a real workspace (not a temp extract) would
        # otherwise leave a stale backlog that lists already-fixed videos.
        path.write_bytes(payload)
        put_file(tok, PENDING, payload,
                 f"replacements: {done} wrong-render video(s) fixed")
        ledger = music / "work" / "release-state.json"
        if ledger.exists():
            # Merge into the version on `main` rather than PUT a raw snapshot:
            # this step's checkout predates the repair step's own write, so a
            # bare overwrite would drop rows that step just recorded.
            daily_release.write_ledger(
                tok, ledger.read_bytes(),
                "release: ledger after replacements")
    print(f"{done} replaced, {len(left)} left")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
