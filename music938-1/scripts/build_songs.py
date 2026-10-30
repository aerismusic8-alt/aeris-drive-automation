#!/usr/bin/env python3
"""Build every music938-1 song, resumably, around Flow Music's rate limit.

Flow Music is a shared free service. `POST /__api/producer/tool-call` answers
`429 {"detail":"Too Many Requests"}` with no `Retry-After`, for every generation
tool *and* for a plain UI Generate (measured 2026-10-30). The UI has no separate
path and no model picker.

Availability is intermittent, not a quota: on 2026-10-29 six songs rendered in a
26-minute window (~4.3 min/song) while credits read `free / 6000 tokens`. So the
window is the scarce thing, and a serial batch wastes most of it — one song at a
time sits idle during each render. This runs `--workers` songs at once so a
window is filled. Workers share one browser profile, so each gets its own tab and
they must not sweep each other's tabs (`--keep-tabs`).

Songs already on disk are skipped, so re-running is cheap and an interrupted
batch continues where it stopped.

    python3 scripts/build_songs.py                 # all 20, 2 at a time
    python3 scripts/build_songs.py --workers 3
    python3 scripts/build_songs.py --only 01,02
    python3 scripts/build_songs.py --force
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SONGS = ROOT / "library" / "songs"

# The producer throttle is server-side ("Too Many Requests"), not our quota:
# credits read 6000 tokens / 500 credits while every tool-call 429s. Windows of
# availability do open (six songs rendered in 26 minutes on 2026-10-29), so the
# ladder stays short enough to land inside one.
BACKOFF_STEPS = [120, 180, 240, 300, 420, 600]

_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


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
        log(f"[warn] {slug}: karaoke video failed: {(proc.stderr or '')[-200:]}")


def run_one(slug: str, force: bool) -> tuple[str, dict | None]:
    cmd = [sys.executable, str(ROOT / "scripts" / "flow_song.py"), slug, "--keep-tabs"]
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


def build_one(slug: str, force: bool, gap: int, results: dict, lock: threading.Lock) -> None:
    """Build a single song, retrying through throttle windows.

    Songs stay sequential — one song at a time, start to finish — because that is
    the serialization the API tolerates. The overlap is between *songs*: the next
    worker is already generating while this one encodes stems and karaoke.
    """
    backoff = 0
    errs = 0
    while True:
        log(f"[build] {slug} ...")
        status, data = run_one(slug, force)
        if status == "OK":
            log(f"[ok] {slug} {json.dumps(data, ensure_ascii=False)}")
            render_video(slug)
            with lock:
                results[slug] = "OK"
            return
        if status == "RATE_LIMITED":
            wait = BACKOFF_STEPS[min(backoff, len(BACKOFF_STEPS) - 1)]
            backoff += 1
            log(f"[429] {slug}: throttled, sleeping {wait}s")
            time.sleep(wait)
            continue
        if status == "TOO_SHORT":
            # Rendered but under the floor and Extend did not rescue it.
            backoff += 1
            wait = BACKOFF_STEPS[min(backoff, len(BACKOFF_STEPS) - 1)]
            log(f"[short] {slug}: {data}, retrying in {wait}s")
            time.sleep(wait)
            continue
        errs += 1
        log(f"[err] {slug} (attempt {errs}): {data}")
        if errs >= 3:
            with lock:
                results[slug] = "ERROR"
            return
        time.sleep(60)
        # Fall through to the next attempt; do not reset the throttle ladder
        # here, a transient error is not evidence that the window reopened.
        continue


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", default="", help="comma list of 2-digit numbers, e.g. 01,05")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--workers", type=int, default=2,
                    help="songs generated concurrently (default 2)")
    ap.add_argument("--gap", type=int, default=0,
                    help="seconds to rest between songs per worker (default 0)")
    args = ap.parse_args()
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    todo = [s for s in slugs(only)]
    results: dict[str, str] = {}
    lock = threading.Lock()

    # A song already on disk still needs its karaoke video, so it is not skipped
    # outright; it is handled up front, before the queue of generations.
    pending = []
    for slug in todo:
        if built(slug) and not args.force:
            log(f"[skip] {slug} (done)")
            render_video(slug)
            results[slug] = "SKIP"
        else:
            pending.append(slug)

    queue = list(pending)
    qlock = threading.Lock()

    def worker() -> None:
        while True:
            with qlock:
                if not queue:
                    return
                slug = queue.pop(0)
            build_one(slug, args.force, args.gap, results, lock)

    threads = [threading.Thread(target=worker, daemon=True)
               for _ in range(max(1, min(args.workers, len(pending) or 1)))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    done = sum(1 for v in results.values() if v in ("OK", "SKIP"))
    log(f"\n=== {done}/{len(todo)} built ===")
    for s in todo:
        log(f"  {s}: {results.get(s, 'MISSING')}")
    return 0 if done == len(todo) else 1


if __name__ == "__main__":
    raise SystemExit(main())
