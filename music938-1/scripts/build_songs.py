#!/usr/bin/env python3
"""Build every music938-1 song, resumably, around Flow Music's rate limit.

Flow Music is a shared free service: it answers `429 Too Many Requests` with the
copy "Slow down! Producer is busy helping others" and no `Retry-After`. A batch
therefore cannot be a tight loop. This walks the lyrics in order, one song at a
time, and when a run comes back RATE_LIMITED it sleeps a long backoff and picks
up at the same song. Songs already on disk are skipped, so re-running is cheap
and an interrupted batch continues where it stopped.

    python3 scripts/build_songs.py              # all 20
    python3 scripts/build_songs.py --only 01,02
    python3 scripts/build_songs.py --force
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SONGS = ROOT / "library" / "songs"

# The producer throttle is server-side ("busy helping others"), not our quota:
# credits read 6000 tokens / 500 credits while every tool-call 429s. Windows of
# availability do open (six songs rendered in 26 minutes on 2026-10-29), so the
# ladder stays short enough to land inside one.
BACKOFF_STEPS = [240, 300, 420, 600, 600]


def slugs(only: set[str]) -> list[str]:
    out = []
    for f in sorted((ROOT / "lyrics").glob("*.txt")):
        if only and f.stem.split("-")[0] not in only:
            continue
        out.append(f.stem)
    return out


def built(slug: str) -> bool:
    return (SONGS / f"song-{slug}.mp3").exists() and (SONGS / f"karaoke-{slug}.mp3").exists()


def karaoke_video(slug: str) -> bool:
    return (ROOT / "library" / "karaoke" / f"karaoke-{slug}.mp4").exists()


def render_video(slug: str) -> None:
    """Burn the karaoke video after the audio exists.

    A failure here is not fatal to the song: the mp3s are the deliverable and
    the video can be re-rendered later from what is already on disk.
    """
    if karaoke_video(slug):
        return
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "make_karaoke.py"), slug],
        capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"[warn] {slug}: karaoke video failed: {(proc.stderr or '')[-200:]}",
              flush=True)


def run_one(slug: str, force: bool) -> tuple[str, dict | None]:
    cmd = [sys.executable, str(ROOT / "scripts" / "flow_song.py"), slug]
    if force:
        cmd.append("--force")
    proc = subprocess.run(cmd, capture_output=True, text=True)
    line = (proc.stdout or "").strip().splitlines()
    data = None
    if line:
        try:
            data = json.loads(line[-1])
        except ValueError:
            data = {"raw": line[-1]}
    if proc.returncode == 4 or (data or {}).get("status") == "RATE_LIMITED":
        return "RATE_LIMITED", data
    if proc.returncode == 5 or (data or {}).get("status") == "TOO_SHORT":
        return "TOO_SHORT", data
    if proc.returncode != 0:
        return "ERROR", {"rc": proc.returncode, "err": (proc.stderr or "")[-300:]}
    return "OK", data


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", default="", help="comma list of 2-digit numbers, e.g. 01,05")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--gap", type=int, default=90,
                    help="seconds to rest between songs (default 90)")
    args = ap.parse_args()
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    todo = slugs(only)
    backoff = 0
    errs: dict[str, int] = {}
    results = {}
    for slug in todo:
        if built(slug) and not args.force:
            print(f"[skip] {slug} (done)", flush=True)
            render_video(slug)
            results[slug] = "SKIP"
            continue
        while True:
            print(f"[build] {slug} ...", flush=True)
            status, data = run_one(slug, args.force)
            if status == "OK":
                print(f"[ok] {slug} {json.dumps(data, ensure_ascii=False)}", flush=True)
                render_video(slug)
                results[slug] = "OK"
                backoff = 0
                # Space the songs out: a tight loop is what earns the throttle.
                if args.gap:
                    print(f"[rest] {args.gap}s before the next song", flush=True)
                    time.sleep(args.gap)
                break
            if status == "RATE_LIMITED":
                wait = BACKOFF_STEPS[min(backoff, len(BACKOFF_STEPS) - 1)]
                backoff += 1
                print(f"[429] {slug}: throttled, sleeping {wait}s", flush=True)
                time.sleep(wait)
                continue
            if status == "TOO_SHORT":
                # The take rendered but came back under the floor and Extend did
                # not rescue it. Re-create from scratch, spaced out.
                backoff += 1
                wait = BACKOFF_STEPS[min(backoff, len(BACKOFF_STEPS) - 1)]
                print(f"[short] {slug}: {data}, retrying in {wait}s", flush=True)
                time.sleep(wait)
                continue
            # A browser hiccup or a crash in the driver is transient: retry the
            # song a few times before moving on, so one bad tab does not skip a
            # track for the rest of the run.
            errs[slug] = errs.get(slug, 0) + 1
            print(f"[err] {slug} (attempt {errs[slug]}): {data}", flush=True)
            if errs[slug] >= 3:
                results[slug] = "ERROR"
                break
            time.sleep(60)

    done = sum(1 for v in results.values() if v in ("OK", "SKIP"))
    print(f"\n=== {done}/{len(todo)} built ===", flush=True)
    for s, v in results.items():
        print(f"  {s}: {v}")
    return 0 if done == len(todo) else 1


if __name__ == "__main__":
    raise SystemExit(main())
