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

# The pack's length floor, the same one flow_song and report.py enforce. A file
# below this is not a finished song and must be rebuilt, not skipped.
MIN_SECONDS = 210.0

# The producer throttle is server-side ("Too Many Requests"), not our quota:
# credits read 6000 tokens / 500 credits while every tool-call 429s. Windows of
# availability do open (six songs rendered in 26 minutes on 2026-10-29), so the
# ladder stays short enough to land inside one.

# Probing. The windows were mined from the account's own clip history
# (`GET /__api/clips/auth-user`): every create_song landed in UTC 23, 0, 1, 2, 6
# or 18, and 07:00-17:00 saw none. That is a *sample*, not a schedule - the six
# that landed on 2026-10-29 all fell inside 26 minutes, so a window is short and
# opens without warning. K freed the timing, so the batch no longer naps the
# afternoon away waiting for a predicted hour: it probes continuously at a
# retry cadence. A probe is not free (it opens the composer, fills the lyrics and
# clicks Generate, ~40s of browser work), so PROBE_SLEEP_S is a floor, not a
# hammer - roughly one attempt every 2-3 minutes, all hours.
PROBE_SLEEP_S = 150
# Ladder for repeated throttling: back off, but never past PROBE_SLEEP_S, so a
# window that opens is caught within a couple of minutes rather than missed.
BACKOFF_STEPS = [120, PROBE_SLEEP_S]
# Kept for the record; no longer gates probing.
LIKELY_WINDOW_HOURS = {23, 0, 1, 2, 6, 18}


def _hour_utc() -> int:
    return time.gmtime().tm_hour

_print_lock = threading.Lock()
LOG_FILE = ROOT / "work" / "batch.log"


def log(msg: str) -> None:
    with _print_lock:
        line = f"{time.strftime('%H:%M:%SZ', time.gmtime())} {msg}"
        print(line, flush=True)
        # Mirror to work/, which is on persistent /workspace: a pod recycle wipes
        # /tmp, and the progress record is what a fresh session needs to resume.
        try:
            LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            with LOG_FILE.open("a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        except OSError:
            pass


def slugs(only: set[str]) -> list[str]:
    out = []
    for f in sorted((ROOT / "lyrics").glob("*.txt")):
        if only and f.stem.split("-")[0] not in only:
            continue
        out.append(f.stem)
    return out


def _mp3_seconds(path: Path) -> float:
    try:
        return float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", str(path)],
            capture_output=True, text=True, check=True).stdout.strip())
    except Exception:
        return 0.0


def built(slug: str) -> bool:
    """True only when both mixes exist *and* the song clears the 3.5-minute floor.

    Checking existence alone let song 01, a 178.7s take from before the floor was
    enforced, count as done forever: the batch skipped it and it could never be
    regenerated. A short file is not a song for this pack, so it is rebuilt.
    """
    song = SONGS / f"song-{slug}.mp3"
    kar = SONGS / f"karaoke-{slug}.mp3"
    if not (song.exists() and kar.exists()):
        return False
    return _mp3_seconds(song) >= MIN_SECONDS


def karaoke_video(slug: str) -> bool:
    return (ROOT / "library" / "karaoke" / f"karaoke-{slug}.mp4").exists()


def render_video(slug: str) -> None:
    """Burn the karaoke and song videos after the audio exists.

    Two videos per song, from one generation: the karaoke mix is the sing-along
    version, the song mix is the main release. A failure here is not fatal to
    the song: the mp3s are the deliverable and a video can be re-rendered later
    from what is already on disk.
    """
    mixes = [m for m in ("karaoke", "song")
             if not (ROOT / "library" / "karaoke" / f"{m}-{slug}.mp4").exists()]
    for mix in mixes:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "make_karaoke.py"), slug,
             "--mix", mix],
            capture_output=True, text=True)
        if proc.returncode != 0:
            log(f"[warn] {slug}: {mix} video failed: {(proc.stderr or '')[-200:]}")
    # A Short is the discovery video: a zero-sub channel gets reach from Shorts
    # and almost none from long-form. Each song yields one Short per chorus.
    if not list((ROOT / "library" / "shorts").glob(f"short-song*-{slug}.mp4")):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "make_short.py"), slug,
             "--hooks"],
            capture_output=True, text=True)
        if proc.returncode != 0:
            log(f"[warn] {slug}: short failed: {(proc.stderr or '')[-200:]}")


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
            # One attempt every PROBE_SLEEP_S at most, all hours. A window is
            # short and unpredictable, so the cost of a missed one is a whole song
            # while the cost of a probe is ~40s of browser work; the floor keeps
            # that trade sane without ever sleeping through an opening.
            wait = BACKOFF_STEPS[min(backoff, len(BACKOFF_STEPS) - 1)]
            backoff += 1
            log(f"[429] {slug}: throttled, retrying in {int(wait)}s "
                f"(hour {_hour_utc()}Z)")
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
    ap.add_argument("--workers", type=int, default=1,
                    help="songs generated concurrently (default 1: the throttle "
                         "is per account, so a second create in flight just gets "
                         "429'd and wastes the window)")
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

    # A generation window is scarce (six songs landed in 26 minutes on
    # 2026-10-29, then nothing for a day), so spend it on the songs that add
    # something. A song with no take at all grows the pack by one; a song with an
    # under-length take already has audio to cut Shorts and karaoke from, so its
    # rebuild is worth less and goes last. Without this, song 01's rebuild sits
    # first in the queue and every window before it clears is spent on a song the
    # pack already has.
    pending.sort(key=lambda s: (SONGS / f"song-{s}.mp3").exists())
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
