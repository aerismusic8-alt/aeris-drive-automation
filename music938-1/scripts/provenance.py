#!/usr/bin/env python3
"""Guard the pack against the retired Piper synthesis pipeline.

The first version of this pack synthesised the vocal with a Piper Thai TTS voice
pitch-shifted onto a melody. K ordered all of it destroyed: "งานเพลงแบบนี้คือ
ล้มเหลวมากๆ". It came back once already (2026-11-01), silently: songs 10-20 were
written by `make_song.py` while the Flow Music route sat behind a login, and the
manifest recorded them as `offline-engine` so nothing looked wrong.

The two pipelines leave different fingerprints, and none of them needs an ear:

| pipeline | sample rate | channels |
| --- | --- | --- |
| Flow Music (`flow_song.py`) | 48000 | a real stereo mix |
| Piper (`make_song.py`) | 44100 | one mono signal copied into both |

`make_song.py` builds `mix = np.stack([x, x])`, so its two channels are
*bit-identical*. A real stereo mix never is. That is the test: if the left and
right channels match to the sample over a stretch of audio, the file came from
the retired engine and must not ship.

    python3 scripts/provenance.py --check        # exit 1 if any song is retired
    python3 scripts/provenance.py --quarantine   # move retired media out of library/
    python3 scripts/provenance.py --manifest     # rewrite manifest.json from verified songs
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common  # noqa: E402

ROOT = common.ROOT
LIBRARY = common.LIBRARY
SONGS = LIBRARY / "songs"
SHORTS = LIBRARY / "shorts"
KARAOKE_VID = LIBRARY / "karaoke"
COMPILATIONS = LIBRARY / "compilations"
QUARANTINE = LIBRARY / "quarantine"

SAMPLE_SECONDS = 30.0
# `make_song.py` copies one mono signal into both channels, so the difference is
# exactly zero. A real stereo mix sits orders of magnitude above this.
MONO_EPSILON = 1e-6


def channels(path: Path, *, seconds: float = SAMPLE_SECONDS, sr: int = 44100) -> np.ndarray:
    """Decode `seconds` of stereo float samples, interleaved."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-t", str(seconds),
         "-ac", "2", "-ar", str(sr), "-f", "f32le", "-"],
        capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg could not read {path.name}: "
                           f"{proc.stderr.decode(errors='replace')[-200:]}")
    return np.frombuffer(proc.stdout, dtype=np.float32)


def signature(path: Path) -> dict:
    """Sample rate, channel count and how stereo the file actually is."""
    x = channels(path)
    if x.size < 2048:
        raise RuntimeError(f"{path.name}: too little audio to judge")
    left, right = x[0::2], x[1::2]
    n = min(len(left), len(right))
    left, right = left[:n], right[:n]
    max_diff = float(np.abs(left - right).max()) if n else 0.0
    if left.std() < 1e-9 or right.std() < 1e-9:
        corr = 1.0
    else:
        corr = float(np.corrcoef(left, right)[0, 1])
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate,channels",
         "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    sr, ch = (probe.stdout.strip().split(",") + ["", ""])[:2]
    return {"sample_rate": sr, "channels": ch, "max_diff": max_diff,
            "corr": corr, "mono_duplicated": max_diff <= MONO_EPSILON}


def verdict(path: Path) -> str:
    """"retired" when the file is the rejected engine, else "flow"."""
    try:
        sig = signature(path)
    except Exception as exc:
        print(f"  ? {path.name}: {exc}", file=sys.stderr)
        return "unknown"
    return "retired" if sig["mono_duplicated"] else "flow"


def is_bed(path: Path) -> bool:
    """True when `path` is our offline real-instrument bed, not a Flow render.

    A Flow Music (Lyria) master comes back at 48 kHz; every bed
    `soundfont.render_bed` writes is at `common.SR` (44.1 kHz). Sample rate is
    the discriminator the old mono-duplication test cannot give: that test only
    caught the ffmpeg synth, because the *sampler* bed is a real stereo mix, so
    it read as a Flow song and could be catalogued as one — the same class of bug
    K caught on 2026-11-07 (a bed shipped as a song).
    """
    try:
        sig = signature(path)
    except Exception:  # noqa: BLE001 - unreadable audio is "not a bed", not a crash
        return False
    return sig.get("sample_rate") == str(common.SR)


def song_slugs() -> list[str]:
    return sorted(p.name[len("song-"):-len(".mp3")] for p in SONGS.glob("song-*.mp3"))


def audit() -> dict[str, str]:
    """slug -> verdict, over every song on disk."""
    out: dict[str, str] = {}
    for slug in song_slugs():
        out[slug] = verdict(SONGS / f"song-{slug}.mp3")
    return out


def retired_slugs() -> set[str]:
    """Slugs that are retired now, plus any quarantined earlier.

    A derived file (a Short, a compilation) outlives the song it was cut from,
    so the audit alone would stop seeing it once the song is moved. The
    quarantine ledger keeps the record.
    """
    slugs = {slug for slug, v in audit().items() if v == "retired"}
    for record in QUARANTINE.glob("*/MOVED.json"):
        try:
            moved = json.loads(record.read_text(encoding="utf-8"))["moved"]
        except Exception:
            continue
        for item in moved:
            name = Path(item["from"]).name
            if name.startswith("song-") and name.endswith(".mp3"):
                slugs.add(name[len("song-"):-len(".mp3")])
    return slugs


def retired_media() -> list[Path]:
    """Every file that is derived from a retired song and must not ship."""
    bad = sorted(retired_slugs())
    nums = {slug.split("-")[0] for slug in bad}
    found: list[Path] = []
    for slug in bad:
        for name in (f"song-{slug}.mp3", f"karaoke-{slug}.mp3"):
            p = SONGS / name
            if p.exists():
                found.append(p)
    for p in sorted(SHORTS.glob("*.mp4")):
        if any(p.name.endswith(f"-{slug}.mp4") for slug in bad):
            found.append(p)
    for p in sorted(KARAOKE_VID.glob("*.mp4")):
        if any(p.name.endswith(f"-{slug}.mp4") for slug in bad):
            found.append(p)
    # A compilation that contains a retired track carries the same defect. Only
    # the ones whose video is on disk are touched: a description left behind for
    # an already-uploaded compilation is text, and the live copy may be clean.
    for txt in sorted(COMPILATIONS.glob("*.txt")):
        video = txt.with_suffix(".mp4")
        if not video.exists():
            continue
        listed = {line.split()[1].rstrip(".") for line in txt.read_text(
            encoding="utf-8").splitlines()
            if len(line.split()) > 1 and line.split()[0].count(":") == 1
            and line.split()[1].rstrip(".").isdigit()}
        if listed & nums:
            for suffix in (".mp4", ".txt", ".title"):
                p = txt.with_suffix(suffix)
                if p.exists():
                    found.append(p)
    return found


def quarantine(paths: list[Path]) -> Path:
    """Move the files into library/quarantine/<UTC stamp>/, keeping structure."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest_root = QUARANTINE / stamp
    moved = []
    for p in paths:
        rel = p.relative_to(LIBRARY)
        dest = dest_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(p), str(dest))
        moved.append({"from": str(rel), "bytes": dest.stat().st_size})
    (dest_root / "MOVED.json").write_text(json.dumps(
        {"reason": "retired Piper synthesis pipeline (mono duplicated channels)",
         "at": stamp, "moved": moved}, ensure_ascii=False, indent=1),
        encoding="utf-8")
    return dest_root


def write_manifest() -> Path:
    """Rebuild manifest.json, letting the canonical builder apply the gate.

    `manifest.py` owns the schema (and the index page that reads it); this just
    routes through it so there is one writer and one gate.
    """
    import manifest
    manifest.main()
    return SONGS / "manifest.json"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="exit 1 when a song came from the retired engine")
    ap.add_argument("--quarantine", action="store_true",
                    help="move retired media out of library/ (reversible)")
    ap.add_argument("--manifest", action="store_true",
                    help="rewrite manifest.json from the verified songs")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    if not (args.check or args.quarantine or args.manifest):
        ap.error("pick one of --check / --quarantine / --manifest")

    results = audit()
    retired = sorted(s for s, v in results.items() if v == "retired")
    flow = sorted(s for s, v in results.items() if v == "flow")
    if args.verbose:
        for slug in sorted(results):
            print(f"  {results[slug]:8s} {slug}")
    print(f"{len(flow)} song(s) from Flow Music, {len(retired)} from the retired "
          f"engine (of {len(results)} on disk)")

    if args.quarantine:
        paths = retired_media()
        if paths:
            dest = quarantine(paths)
            print(f"quarantined {len(paths)} file(s) -> {dest.relative_to(ROOT)}")
            for p in paths:
                print(f"  - {p.relative_to(LIBRARY)}")
        else:
            print("nothing to quarantine")
    if args.manifest:
        out = write_manifest()
        data = json.loads(out.read_text(encoding="utf-8"))
        n = len(data.get("songs", data.get("entries", [])))
        print(f"manifest rewritten: {out.relative_to(ROOT)} ({n} entries)")
    return 1 if retired else 0


if __name__ == "__main__":
    raise SystemExit(main())
