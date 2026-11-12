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
COMPILED = ROOT / "library" / "compilations"
THUMB = ROOT / "library" / "thumbs" / "thumb-compilation.png"
STATE = ROOT / "work" / "compilation-state.json"

TITLE = "รวมเพลงไทยเพื่อชีวิต 15 เพลง (เลือกเพลงฟังได้)"
TAGS = ("เพลงไทย,รวมเพลงไทย,เพลงเพื่อชีวิต,เพลงเศร้า,เพลงเพราะ,คาราโอเกะ,"
        "เพลงฟังสบาย,เพลงไทยเพราะๆ,เพลงไทยดัง,เพลงเก่า,AERIS Music,thai music")


def _paths(stem: str) -> tuple[Path, Path, Path]:
    """(mp4, chapters/description, title) for a compilation stem.

    compile_album.py writes `<stem>.mp4/.txt/.title`, so a 20-song build lives
    beside the 15-song one instead of overwriting it. The default stem keeps the
    original single-compilation behaviour.
    """
    return (COMPILED / f"{stem}.mp4", COMPILED / f"{stem}.txt",
            COMPILED / f"{stem}.title")


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


def wait_for_render(mp4: Path, poll: int = 30, max_min: int = 90) -> bool:
    deadline = time.time() + max_min * 60
    last = 0
    while rendering():
        if time.time() > deadline:
            print("render did not finish in time", file=sys.stderr)
            return False
        time.sleep(poll)
        sz = mp4.stat().st_size if mp4.exists() else 0
        if sz != last:
            print(f"  {sz / 1e6:.0f} MB  {datetime.now(timezone.utc):%H:%M:%S}")
            last = sz
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", action="store_true", help="wait for the render first")
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--stem", default="compilation",
                    help="compile_album.py output stem (e.g. compilation-20)")
    ap.add_argument("--thumb", default=None,
                    help="thumbnail png (default: thumb-compilation.png)")
    args = ap.parse_args()

    mp4, txt, title_file = _paths(args.stem)
    state = ROOT / "work" / f"compilation-state-{args.stem}.json"
    if args.watch and not wait_for_render(mp4):
        return 1
    if not mp4.exists():
        print(f"no {mp4.name} yet", file=sys.stderr)
        return 2

    dur = duration(mp4)
    print(f"compilation: {dur / 60:.1f} min, {mp4.stat().st_size / 1e6:.0f} MB")
    # The title's promise is the track count, not the runtime, so a themed album
    # of 8 songs at ~3.7 min each is honest at ~30 minutes. The floor only guards
    # against a truncated render; 25 minutes is well past "album".
    #
    # An ambient/sleep loop is the other shape: it promises *length*, so a short
    # one is the lie. It ships at hours, so only guard against a truncated file.
    is_ambient = args.stem.startswith("ambient-")
    floor = 4 * 60 if is_ambient else 25 * 60
    if dur < floor:
        print(f"refusing to upload: under {floor // 60} minutes, the title would "
              f"over-promise", file=sys.stderr)
        return 3

    # The render's own title is the truth (it counts the tracks); only fall back
    # to the constant when the file is missing.
    title = title_file.read_text(encoding="utf-8").strip() if title_file.exists() else TITLE
    if len(title) > 100:
        title = title[:100]

    if state.exists():
        prev = json.loads(state.read_text())
        if prev.get("video_id"):
            print(f"already uploaded: {prev['video_id']}")
            return 0

    if not args.upload:
        print(f"title: {title}")
        print("(pass --upload to send it)")
        return 0

    desc = txt.read_text(encoding="utf-8").rstrip() if txt.exists() else ""
    sys.path.insert(0, str(ROOT / "scripts"))
    try:
        import monetize
        desc = desc + "\n" + monetize.block("song")
        # The compilation is the long-form upload, so it carries the paid offer
        # (the 2026-11-07 advisor panel's #1 revenue action). Shorts do not.
        desc = desc + monetize.commission_block()
    except Exception as e:
        print("monetize skipped:", e, file=sys.stderr)

    desc_file = ROOT / "work" / "compilation.desc"
    tags_file = ROOT / "work" / "compilation.tags"
    desc_file.write_text(desc, encoding="utf-8")
    # A stem-specific `<stem>.tags` sidecar (written by ambient_loop.py) carries
    # that lane's own search words; without it a sleep video would inherit the
    # song list's คาราโอเกะ/เพลงเศร้า, which describe the wrong video. Fall back
    # to the album tags when there is no sidecar.
    stem_tags = COMPILED / f"{args.stem}.tags"
    tags_file.write_text(
        stem_tags.read_text(encoding="utf-8").strip() if stem_tags.exists() else TAGS,
        encoding="utf-8")

    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", args.ch,
           "--video", str(mp4), "--title", title,
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "10", "--privacy", "public"]
    thumb = Path(args.thumb) if args.thumb else THUMB
    if thumb.exists():
        cmd += ["--thumb", str(thumb)]
    print(" ".join(cmd))
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        return proc.returncode
    m = re.search(r"video id (\S+)", proc.stdout)
    state.write_text(json.dumps({
        "video_id": m.group(1) if m else None,
        "stem": args.stem,
        "title": title,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "minutes": round(dur / 60, 1),
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print("recorded", state.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
