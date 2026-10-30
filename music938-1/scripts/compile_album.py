#!/usr/bin/env python3
"""Build a long-form album compilation from the songs already on disk.

Why this is the main lever for monetization. The watch-hour bar is 4,000 hours
in 12 months. A 3-minute song watched once earns 0.05 of an hour, so clearing the
bar on songs alone needs ~80,000 song views. One 60-minute compilation watched
once earns a whole hour, so it needs ~4,000 views. Same songs, same generation
cost, 20x less audience required. Music channels live on this.

A compilation reuses the songs already built, so it costs no Flow Music
generation and no extra quota beyond one upload.

    python3 scripts/compile_album.py --list                 # what would go in
    python3 scripts/compile_album.py --name "รวมเพลงไทยเพื่อชีวิต" --max 60
    python3 scripts/compile_album.py --name ... --max 60 --render
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
SONGS = ROOT / "library" / "songs"
COVERS = ROOT / "library" / "covers"
COMPILED = ROOT / "library" / "compilations"
LYRICS = ROOT / "lyrics"

W, H, FPS = 1920, 1080, 25
CROSSFADE = 4.0  # seconds of overlap between tracks
# Below this the `N เพลง` in the title is not credible. The scan's winning
# compilations carry 32-110 songs; 12 is a floor for a "รวมเพลง" to feel real.
MIN_TRACKS = 12


def parse_lyrics(slug: str) -> dict:
    hdr: dict[str, str] = {}
    for line in (LYRICS / f"{slug}.txt").read_text(encoding="utf-8").splitlines():
        m = re.match(r"#\s*(TITLE|MOOD|KEY|VOICE)\s*:\s*(.+)", line)
        if m:
            hdr[m.group(1)] = m.group(2).strip()
            continue
        if line.strip() and not line.startswith("#"):
            break
    return hdr


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", str(path)],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def available_songs() -> list[str]:
    slugs = []
    for f in sorted(SONGS.glob("song-*.mp3")):
        slug = f.stem[len("song-"):]
        if (COVERS / f"cover-{slug}.jpg").exists():
            slugs.append(slug)
    return slugs


def pick(max_minutes: float) -> list[str]:
    """Fill up to max_minutes with songs, in catalogue order."""
    chosen, total = [], 0.0
    for slug in available_songs():
        d = duration(SONGS / f"song-{slug}.mp3")
        if not d:
            continue
        # Each added track overlaps the previous by CROSSFADE, so the real cost
        # is d - CROSSFADE once something is already in the list.
        cost = d if not chosen else max(0.0, d - CROSSFADE)
        if total + cost > max_minutes * 60:
            break
        chosen.append(slug)
        total += cost
    return chosen


def build_tracklist(slugs: list[str]) -> str:
    lines = []
    for i, slug in enumerate(slugs, 1):
        h = parse_lyrics(slug)
        lines.append(f"{i:02d}. {h.get('TITLE', slug)}")
    return "\n".join(lines)


def build_chapters(slugs: list[str]) -> str:
    """A YouTube chapter list, so a viewer can jump to the song they want.

    This is the part that makes the `(เลือกเพลงฟังได้)` promise in the title real.
    The competitor scan found it is the single strongest signal in the whole
    dataset: 37 of the videos past 100k views carry that phrase and **none** of
    the sub-1k videos do. It only works if the timestamps are in the description,
    so the chapters are built from the same durations the render uses.
    """
    lines, t = [], 0.0
    for i, slug in enumerate(slugs, 1):
        h = parse_lyrics(slug)
        total = int(round(t))
        lines.append(f"{total // 60:02d}:{total % 60:02d} {i:02d}. {h.get('TITLE', slug)}")
        t += duration(SONGS / f"song-{slug}.mp3") - CROSSFADE
    return "\n".join(lines)


def compilation_title(name: str, n_tracks: int) -> str:
    """The title shape the scan says wins: `<theme> <n> เพลง (เลือกเพลงฟังได้)`.

    The three highest-viewed videos in the dataset are all this shape and all run
    past 2 hours. Keep it under 60 characters so nothing is truncated.
    """
    title = f"{name} {n_tracks} เพลง (เลือกเพลงฟังได้)"
    return title[:100]


def compilation_description(name: str, slugs: list[str]) -> str:
    """Description with the chapter list, which is what enables song skipping."""
    return (
        f"🎵 {name} — รวม {len(slugs)} เพลงไทย ร้องด้วยเสียงจริง\n\n"
        f"👉 กดเลือกเพลงที่อยากฟังได้จากรายการด้านล่าง\n\n"
        f"⏱️ รายการเพลง\n{build_chapters(slugs)}\n\n"
        f"🎧 ฟังเพลิน ๆ ได้ทั้งวัน ไม่ต้องกดเปลี่ยน\n"
        f"🎤 ทุกเพลงมีเวอร์ชันคาราโอเกะในช่อง\n"
        f"✨ AERIS Music — เพลงไทยที่ตั้งใจทำ\n\n"
        f"#เพลงไทย #รวมเพลงไทย #เพลงเพื่อชีวิต #เพลงเศร้า #เพลงเพราะ "
        f"#คาราโอเกะ #AERISMusic #เพลงฟังสบาย\n"
    )


def render(name: str, slugs: list[str], *, out_name: str | None = None) -> Path:
    if not slugs:
        raise SystemExit("no songs to compile — nothing built yet")
    COMPILED.mkdir(parents=True, exist_ok=True)

    inputs: list[str] = []
    for slug in slugs:
        inputs += ["-i", str(SONGS / f"song-{slug}.mp3")]

    # Acrossfade the whole chain, then hold one still under all of it.
    parts, prev = [], "[0:a]"
    for i in range(1, len(slugs)):
        label = f"[a{i}]"
        parts.append(f"{prev}[{i}:a]acrossfade=d={CROSSFADE}:c1=tri:c2=tri{label}")
        prev = label
    # A single track needs no filter, and `-map [0:a]` would fail: brackets name
    # a filter output, not an input stream. Map the stream directly instead.
    audio_map = prev if parts else "0:a"

    # The still is the last input, after all the audio.
    still_idx = len(slugs)
    cover = COVERS / f"cover-{slugs[0]}.jpg"
    inputs += ["-loop", "1", "-i", str(cover)]
    fc = ";".join(parts + [
        f"[{still_idx}:v]scale={W}:{H},"
        f"zoompan=z='min(zoom+0.00012,1.10)':d=1:x='iw/2-(iw/zoom/2)':"
        f"y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS},format=yuv420p[v]"
    ])

    out = COMPILED / f"{out_name or 'compilation'}.mp4"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs,
           "-filter_complex", fc, "-map", "[v]", "-map", audio_map,
           "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
           "-pix_fmt", "yuv420p", "-r", str(FPS),
           "-c:a", "aac", "-b:a", "192k", "-shortest",
           "-movflags", "+faststart", str(out)]
    subprocess.run(cmd, check=True)

    (COMPILED / f"{out_name or 'compilation'}.txt").write_text(
        f"{name}\n\n{build_tracklist(slugs)}\n", encoding="utf-8")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", default="รวมเพลงไทยเพื่อชีวิต")
    ap.add_argument("--max", type=float, default=60.0, help="target minutes")
    ap.add_argument("--list", action="store_true", help="show the tracklist, render nothing")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    slugs = pick(args.max)
    if not slugs:
        print("nothing built yet — no song-*.mp3 with a cover on disk")
        return 0
    # A compilation of one or two songs is not a compilation: the title says
    # "N เพลง" and a viewer who opens it for 3 minutes feels misled. The scan's
    # winning compilations carry 32-110 songs. Hold the shape until the
    # catalogue can support it rather than shipping a thin one under a big title.
    if len(slugs) < MIN_TRACKS:
        print(f"only {len(slugs)} song(s) on disk; a compilation needs at least "
              f"{MIN_TRACKS} for the title to be honest. Nothing written.")
        return 0
    total = sum(duration(SONGS / f"song-{s}.mp3") for s in slugs) - CROSSFADE * (len(slugs) - 1)
    title = compilation_title(args.name, len(slugs))
    print(f"{title}\n{len(slugs)} tracks, ~{total/60:.1f} min\n")
    print(build_tracklist(slugs))
    # The description and the chapter list are what let a viewer skip to a song,
    # so they are written next to the render and handed to yt_publish.py.
    desc_file = COMPILED / f"{args.out or 'compilation'}.txt"
    desc_file.parent.mkdir(parents=True, exist_ok=True)
    desc_file.write_text(compilation_description(args.name, slugs), encoding="utf-8")
    (COMPILED / f"{args.out or 'compilation'}.title").write_text(title, encoding="utf-8")
    print(f"\ntitle: {title}\ndesc -> {desc_file}")
    if args.list or not args.render:
        print("\n(pass --render to build it)")
        return 0
    out = render(args.name, slugs, out_name=args.out)
    print(f"\n{out}  ({out.stat().st_size/1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
