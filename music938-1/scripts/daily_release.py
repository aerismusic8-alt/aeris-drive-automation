#!/usr/bin/env python3
"""Keep the AERIS Music channel active: one scheduled batch a day, unattended.

The pod that builds the songs is not the pod that stays up, so this is the
durable half. It

1. restores the gitignored media from the `media-938` release assets,
2. uploads the next batch with `release.py --next --count N --spread H`, so the
   uploads land H hours apart and the channel is active around the clock, and
3. commits the updated release ledger, which is the only record of what is
   already on YouTube.

Nothing here needs the browser or Flow Music; it only publishes media that
already exists. YouTube's own `publishAt` does the timing, so no process has to
stay up between uploads.

    python3 scripts/daily_release.py --dry-run
    python3 scripts/daily_release.py --count 6 --spread 4
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"


def run(cmd: list[str], **kw) -> int:
    print("$", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.call(cmd, **kw)


def git(*args: str) -> int:
    return run(["git", "-C", str(ROOT.parent), *args])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--count", type=int, default=int(os.environ.get("AX_RELEASE_COUNT", 6)))
    ap.add_argument("--spread", type=float, default=float(os.environ.get("AX_RELEASE_SPREAD", 4)))
    ap.add_argument("--ch", default=os.environ.get("AX_RELEASE_CH", "ch3"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # 1. media
    rc = run([sys.executable, str(SCRIPTS / "pull_media.py")])
    if rc != 0:
        print("pull_media failed", file=sys.stderr)
        return rc

    # 2. release
    cmd = [sys.executable, str(SCRIPTS / "release.py"), "--next", "--public",
           "--ch", args.ch, "--count", str(args.count), "--spread", str(args.spread)]
    if args.dry_run:
        cmd.append("--dry-run")
    rc = run(cmd)
    if rc == 3:
        # Quota already spent for this Pacific day (another batch ran, or the
        # cron raced a manual run). That is a normal skip, not a failure.
        print("quota already spent today; nothing to do")
        return 0
    if rc != 0:
        print(f"release returned {rc}", file=sys.stderr)
        return rc
    if args.dry_run:
        return 0

    # 3. ledger
    ledger = "music938-1/work/release-state.json"
    git("add", ledger)
    if git("diff", "--cached", "--quiet") == 0:
        print("ledger unchanged")
        return 0
    git("commit", "-m", "release: daily batch (automated)")
    # The sandbox may be ahead of origin; rebase rather than fail, because a
    # dropped ledger is what makes the next run re-upload duplicates.
    git("pull", "--rebase", "--autostash", "origin", "main")
    return git("push", "origin", "main")


if __name__ == "__main__":
    raise SystemExit(main())
