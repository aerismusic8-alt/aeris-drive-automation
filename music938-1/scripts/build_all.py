"""Build every song and its karaoke video.

Resumable: a song is skipped when the manifest already records it with the same
lyric hash, so an interrupted run continues where it stopped. `--force` rebuilds
everything.

Run:  python3 scripts/build_all.py [--only 05,06] [--skip-karaoke] [--force]
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common  # noqa: E402
import make_karaoke  # noqa: E402
import make_song  # noqa: E402


def lyric_hash(path: Path) -> str:
    return common.sha256_file(path)[:16]


def manifest_index() -> dict:
    man = common.LIBRARY / "songs" / "manifest.json"
    if not man.exists():
        return {}
    data = common.read_json(man)
    return {e["id"]: e for e in data.get("entries", [])}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated slug prefixes")
    ap.add_argument("--skip-karaoke", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    only = [s.strip() for s in args.only.split(",") if s.strip()]
    lyrics = sorted(common.LYRICS.glob("*.txt"))
    if only:
        lyrics = [p for p in lyrics if any(p.stem.startswith(o) for o in only)]
    if not lyrics:
        print("no lyric files matched", file=sys.stderr)
        return 2

    print(f"building {len(lyrics)} songs", flush=True)
    started = time.time()
    results = []
    for i, path in enumerate(lyrics, 1):
        slug = path.stem
        lh = lyric_hash(path)
        idx = manifest_index()
        entry = idx.get(f"song-{slug}")
        if entry and entry.get("lyric_sha") == lh and not args.force:
            kara = common.LIBRARY / "karaoke" / f"karaoke-{slug}.mp4"
            if args.skip_karaoke or kara.exists():
                print(f"[{i:2}/{len(lyrics)}] {slug}: cached", flush=True)
                results.append({"slug": slug, "status": "CACHED",
                                "duration": entry.get("duration_seconds")})
                continue

        t0 = time.time()
        try:
            res = make_song.build(path, force=args.force)
            entry = res["entry"]
            entry["lyric_sha"] = lh
            make_song._record(entry)
        except Exception as exc:
            print(f"[{i:2}/{len(lyrics)}] {slug}: FAILED {exc}", flush=True)
            results.append({"slug": slug, "status": "FAILED", "error": str(exc)})
            continue

        status = "CREATED"
        if not args.skip_karaoke:
            try:
                make_karaoke.render(slug)
            except Exception as exc:
                status = f"SONG_OK_KARAOKE_FAILED: {exc}"
                print(f"[{i:2}/{len(lyrics)}] {slug}: karaoke failed: {exc}", flush=True)
        dur = entry.get("duration_seconds")
        print(f"[{i:2}/{len(lyrics)}] {slug}: {status} {dur:.1f}s "
              f"in {time.time() - t0:.0f}s", flush=True)
        results.append({"slug": slug, "status": status, "duration": dur})

    summary = {
        "songs": len(results),
        "created": sum(1 for r in results if r["status"] == "CREATED"),
        "cached": sum(1 for r in results if r["status"] == "CACHED"),
        "failed": sum(1 for r in results if "FAIL" in str(r["status"])),
        "total_seconds": round(time.time() - started, 1),
        "results": results,
    }
    common.write_json(common.WORK / "build-summary.json", summary)
    print(json.dumps({k: v for k, v in summary.items() if k != "results"},
                     ensure_ascii=False), flush=True)
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
