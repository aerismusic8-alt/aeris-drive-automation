#!/usr/bin/env python3
"""Wait for the compilation render, then upload it.

Kept separate from compile_album.py so the long ffmpeg run and the upload are
not one process: if the pod recycles mid-render, the finished mp4 is already in
/workspace and this watcher can be restarted.

    python3 scripts/upload_compilation.py --watch
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
MP4 = ROOT / "library" / "compilations" / "compilation.mp4"
TXT = ROOT / "library" / "compilations" / "compilation.txt"
THUMB = ROOT / "library" / "thumbs" / "thumb-compilation.png"
TITLE_FILE = ROOT / "library" / "compilations" / "compilation.title"
STATE = ROOT / "work" / "compilation-state.json"

TITLE = "รวมเพลงไทยเพื่อชีวิต 15 เพลง (เลือกเพลงฟังได้)"
TAGS = ("เพลงไทย,รวมเพลงไทย,เพลงเพื่อชีวิต,เพลงเศร้า,เพลงเพราะ,คาราโอเกะ,"
        "เพลงฟังสบาย,เพลงไทยเพราะๆ,เพลงไทยดัง,เพลงเก่า,AERIS Music,thai music")


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", str(path)],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def rendering() -> bool:
    r = subprocess.run(["pgrep", "-f", "compile_album.py"], capture_output=True)
    return r.returncode == 0


def wait_for_render(poll: int = 30, max_min: int = 90) -> bool:
    deadline = time.time() + max_min * 60
    last = 0
    while rendering():
        if time.time() > deadline:
            print("render did not finish in time", file=sys.stderr)
            return False
        time.sleep(poll)
        sz = MP4.stat().st_size if MP4.exists() else 0
        if sz != last:
            print(f"  {sz / 1e6:.0f} MB  {datetime.now(timezone.utc):%H:%M:%S}")
            last = sz
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", action="store_true", help="wait for the render first")
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--ch", default="ch3")
    args = ap.parse_args()

    if args.watch and not wait_for_render():
        return 1
    if not MP4.exists():
        print("no compilation.mp4 yet", file=sys.stderr)
        return 2

    dur = duration(MP4)
    print(f"compilation: {dur / 60:.1f} min, {MP4.stat().st_size / 1e6:.0f} MB")
    if dur < 30 * 60:
        print("refusing to upload: under 30 minutes, the title would over-promise",
              file=sys.stderr)
        return 3

    if STATE.exists():
        prev = json.loads(STATE.read_text())
        if prev.get("video_id"):
            print(f"already uploaded: {prev['video_id']}")
            return 0

    if not args.upload:
        print("(pass --upload to send it)")
        return 0

    # The title file carries the render's --name; normalise to the one shape.
    TITLE_FILE.write_text(TITLE, encoding="utf-8")
    desc = TXT.read_text(encoding="utf-8").rstrip()
    sys.path.insert(0, str(ROOT / "scripts"))
    try:
        import monetize
        desc = desc + "\n" + monetize.block("song")
    except Exception as e:
        print("monetize skipped:", e, file=sys.stderr)

    desc_file = ROOT / "work" / "compilation.desc"
    tags_file = ROOT / "work" / "compilation.tags"
    desc_file.write_text(desc, encoding="utf-8")
    tags_file.write_text(TAGS, encoding="utf-8")

    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", args.ch,
           "--video", str(MP4), "--title", TITLE,
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "10", "--privacy", "public"]
    if THUMB.exists():
        cmd += ["--thumb", str(THUMB)]
    print(" ".join(cmd))
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        return proc.returncode
    m = re.search(r"video id (\S+)", proc.stdout)
    STATE.write_text(json.dumps({
        "video_id": m.group(1) if m else None,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "minutes": round(dur / 60, 1),
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print("recorded", STATE.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
