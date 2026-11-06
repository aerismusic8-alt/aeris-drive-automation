#!/usr/bin/env python3
"""Put the songbook on Google Drive so K can listen from anywhere.

K (2026-11-06): "เพลงสร้างแล้วอัพไว้กูเกิ้ลไดร์ฟได้ไหมจะได้ไปดูง่ายๆ สร้างโฟลเดอร์
ไว้กันปนกันด้วย" — upload the songs to Drive and keep them in their own folders.

The Drive API is disabled in the Cloud project this repo's OAuth client belongs
to (403 on every call), so this uses the browser uploader, which is the same
upload a human does and needs no API. The desktop browser must be signed in to
Google; `ops/phone_login.py` is the tap-first page for that.

Each media type gets its own subfolder, so a full song never mixes with a
karaoke mix or a Short:

    AX Content Lab/music938/AERIS Music — คลังเพลง/
      01 เพลงเต็ม/       song-*.mp3
      02 คาราโอเกะ/       karaoke-*.mp3
      03 ปก/              cover-*.jpg
      04 ชอร์ต/           short-*.mp4

    python3 scripts/drive_share.py                 # everything that is on disk
    python3 scripts/drive_share.py --only songs    # one group
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
LIB = ROOT / "library"
PULL = ROOT / "scripts" / "pull_media.py"
UPLOADER = REPO / "scripts" / "gdrive-upload-browser.py"
BASE = "AX Content Lab/music938/AERIS Music — คลังเพลง"

# group -> (library subdir, filename glob, Drive subfolder)
GROUPS = {
    "songs": ("songs", "song-*.mp3", "01 เพลงเต็ม"),
    "karaoke": ("songs", "karaoke-*.mp3", "02 คาราโอเกะ"),
    "covers": ("covers", "cover-*.jpg", "03 ปก"),
    "shorts": ("shorts", "short-*.mp4", "04 ชอร์ต"),
}


def run(cmd: list[str]) -> int:
    print("+", " ".join(cmd), flush=True)
    return subprocess.call(cmd)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", action="append", choices=sorted(GROUPS))
    ap.add_argument("--no-pull", action="store_true", help="do not pull media first")
    args = ap.parse_args()

    groups = args.only or sorted(GROUPS)
    if not args.no_pull:
        # A fresh pod has an empty library/; the release assets are the source.
        for g in groups:
            run([sys.executable, str(PULL), "--only", g])

    rc = 0
    for g in groups:
        sub, pattern, folder = GROUPS[g]
        files = sorted((LIB / sub).glob(pattern))
        if not files:
            print(f"  {g}: nothing on disk, skipped")
            continue
        print(f"\n== {g}: {len(files)} file(s) -> {BASE}/{folder}")
        rc |= run([sys.executable, str(UPLOADER), "--folder", f"{BASE}/{folder}",
                   "--resume", "--batch", "8", *[str(f) for f in files]])

    print(f"\nopen in Drive: https://drive.google.com/drive/search?q={BASE.split('/')[-1]}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
