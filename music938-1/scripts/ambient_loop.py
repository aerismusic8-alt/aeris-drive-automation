#!/usr/bin/env python3
"""Build a long ambient / sleep video from a real-instrument bed.

Why this exists. The 2026-11-09 YouTube scan was blunt: a 4-minute song gets
~500 views, a 2-hour Thai compilation gets 6-17 million, and sleep / ambient
loops of 8-12 hours get 100-221 million. The same channel's singles are the same
songs; the *container* is what the algorithm rewards. This builds the biggest
container we can, for free, with no login and no K action:

  * the music is a real-instrument SoundFont bed rendered with `soundfont` (no
    Flow Music, no quota, no login),
  * the picture is one still held for hours, which is what the sleep channels do.

K (2026-11-09): the audio must be music only. An earlier version mixed in a
rain/wave bed; that is gone, so nothing here adds a sound the instruments did not
make.

A short bed is looped to the full length with `-stream_loop -1`, so an 8-hour
video costs one short synth pass, not eight hours of synthesis.

    python3 scripts/ambient_loop.py --plan --minutes 30     # what it would build
    python3 scripts/ambient_loop.py --minutes 480 --render  # an 8-hour sleep loop

The output lands in `library/compilations/` with a `.title` and a `.txt`, so the
existing `upload_compilation.py --stem ambient-<name>` publishes it unchanged.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

_BIN = "/workspace/ax-tools/bin"
if Path(_BIN, "ffmpeg").exists() and _BIN not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _BIN + os.pathsep + os.environ.get("PATH", "")

ROOT = Path(__file__).resolve().parent.parent
AERIS = ROOT.parent / "aeris938-1"
COMPILED = ROOT / "library" / "compilations"
BEDS = ROOT / "library" / "ambient"
COVERS = ROOT / "library" / "covers"
THUMBS = ROOT / "library" / "thumbs"

W, H = 1920, 1080
# A held still does not need 25 frames a second; 1 fps keeps an 8-hour encode to
# minutes instead of hours and the file to a few hundred MB. The player holds the
# frame, so nothing is lost.
FPS = 1
BED_SECONDS = 180.0  # the loop unit; the bed is synthesised once and tiled

# The sleep lane is its own search intent, and the winning videos name it: calm
# music plus a length. Keep the title in Thai, say the length, and promise the
# one thing a sleeper wants.
PRESETS: dict[str, dict] = {
    "sleep": {
        "name": "เพลงกล่อมนอน",
        "mood": "calm",
        "key": "C",
        "use_case": "หลับสบาย ผ่อนคลาย นอนไม่หลับ",
        "title": "เพลงกล่อมนอน {hours} ชั่วโมง | เพลงผ่อนคลายหลับสบาย AERIS Music",
    },
    "relax": {
        "name": "เพลงผ่อนคลาย",
        "mood": "warm",
        "key": "F",
        "use_case": "ทำงาน อ่านหนังสือ นั่งสมาธิ",
        "title": "เพลงผ่อนคลาย {hours} ชั่วโมง | ทำงาน อ่านหนังสือ นั่งสมาธิ AERIS Music",
    },
}


def _run(args: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, **kw)


def _render_bed(mood: str, key: str, out: Path, duration: float) -> None:
    """Render the sleep bed with REAL instruments (see `soundfont`).

    K (2026-11-09): the ffmpeg sine drone this replaced "sounds fake — stop using
    it." `soundfont` plays a SoundFont of recorded instruments (music box, warm
    pad, piano, nylon guitar, contrabass) through fluidsynth, writes the MIDI so
    the harmony actually moves, and returns a crossfaded, seamless loop. It needs
    no login and no quota; `fluidsynth` and the soundfonts are apt packages.

    Imported lazily so `--plan` (and the test that only checks the plan shape)
    does not require the sampler to be installed.
    """
    import soundfont  # noqa: PLC0415

    soundfont.render_bed(mood, key, out, seconds=duration)


def ensure_bed(mood: str, key: str) -> Path:
    """A short real-instrument bed, rendered once and cached by mood+key.

    The cache name is `instrument-*`, not `drone-*`: the earlier lane cached a
    sine drone (and before that the story-video arpeggio), and reusing either
    cache would keep the fake timbre even after the synthesis changed. A cached
    file is trusted only if it is close to a whole tile long — a truncated one
    from an interrupted run would loop a fragment.
    """
    BEDS.mkdir(parents=True, exist_ok=True)
    dest = BEDS / f"instrument-{mood}-{key}.wav"
    floor = 44100 * 2 * 2 * (BED_SECONDS - 3) * 0.9   # stereo 16-bit, minus the xfade
    if dest.exists() and dest.stat().st_size > floor:
        return dest
    _render_bed(mood, key, dest, BED_SECONDS)
    return dest


def _hours_label(minutes: float) -> str:
    h = minutes / 60.0
    return f"{h:g}"


def plan(name: str, *, mood: str, key: str, minutes: float,
         title_tmpl: str, use_case: str, still: Path | None = None,
         stem: str | None = None) -> dict:
    """The ffmpeg command and the sidecar text, with nothing executed.

    Pure on purpose: a test can assert the shape (length, loops, maps, title)
    without paying for an 8-hour encode. `stem` keys both the output path and the
    state file, so the caller must pass the same one it will later check for.

    The audio is the instrument bed and nothing else (K, 2026-11-09: music only),
    so there is no second input to mix.
    """
    if minutes <= 0:
        raise ValueError("minutes must be positive")
    secs = minutes * 60.0
    hours = _hours_label(minutes)
    stem = stem or f"ambient-{name}"
    out = COMPILED / f"{stem}.mp4"
    still = still or (THUMBS / f"thumb-{stem}.png")
    if not Path(still).exists():
        still = COVERS / "cover-01-khon-di-thi-chak-pai.jpg"

    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    # Loop the short bed to the full length; the still is held the same way.
    cmd += ["-stream_loop", "-1", "-i", str(BEDS / f"instrument-{mood}-{key}.wav")]
    cmd += ["-loop", "1", "-framerate", str(FPS), "-i", str(still)]
    cmd += ["-t", f"{secs:.3f}"]

    vf = f"[1:v]scale={W}:{H},format=yuv420p[v]"
    # Fades belong to the finished video, not to each looped tile: fading the bed
    # would dip the volume once per loop. A final gentle lowpass removes any high
    # ring the layers picked up, so nothing whistles across the eight hours.
    fade = 5.0
    af = (f"[0:a]lowpass=f=8000,afade=t=in:d={fade},"
          f"afade=t=out:st={max(0.0, secs - fade):.2f}:d={fade}[a]")
    cmd += ["-filter_complex", f"{vf};{af}", "-map", "[v]", "-map", "[a]"]
    cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
            "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "160k", "-ac", "2", "-ar", "44100",
            "-movflags", "+faststart", str(out)]

    title = title_tmpl.format(hours=hours)[:100]
    desc = "\n".join([
        f"{title}",
        "",
        f"เพลงผ่อนคลายจาก AERIS Music ยาว {hours} ชั่วโมง เปิดฟังยาว ๆ ได้เลย",
        "ทุกเพลงทำเองในสตูดิโอของเรา",
        "",
        f"#{name} #เพลงผ่อนคลาย #AERISMusic #ambient #sleepmusic",
    ])
    return {"cmd": cmd, "out": out, "title": title, "desc": desc,
            "minutes": minutes, "stem": stem, "use_case": use_case}


def render(p: dict) -> Path:
    COMPILED.mkdir(parents=True, exist_ok=True)
    res = _run(p["cmd"])
    if res.returncode != 0 or not p["out"].exists():
        raise RuntimeError(
            f"ambient render failed rc={res.returncode}: "
            f"{(res.stderr or res.stdout or '').strip()[-800:]}")
    (COMPILED / f"{p['stem']}.txt").write_text(p["desc"], encoding="utf-8")
    (COMPILED / f"{p['stem']}.title").write_text(p["title"], encoding="utf-8")
    return p["out"]


def thumbnail(stem: str, title: str, mood: str) -> Path | None:
    """A 16:9 thumbnail for the loop, reusing the cover art pipeline."""
    try:
        sys.path.insert(0, str(ROOT / "scripts"))
        import covers  # noqa: PLC0415

        dest = covers.make_thumbnail(stem, title, mood, kind="song")
        THUMBS.mkdir(parents=True, exist_ok=True)
        want = THUMBS / f"thumb-{stem}.png"
        if dest != want and Path(dest).exists():
            Path(dest).replace(want)
        return want
    except Exception as e:  # noqa: BLE001 — a thumbnail must not block the video
        print(f"thumbnail skipped: {e}", file=sys.stderr)
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preset", choices=sorted(PRESETS), default="sleep")
    ap.add_argument("--name", default=None, help="overrides the preset name")
    ap.add_argument("--mood", default=None)
    ap.add_argument("--key", default=None)
    ap.add_argument("--minutes", type=float, default=480.0, help="target length")
    ap.add_argument("--plan", action="store_true", help="print, render nothing")
    ap.add_argument("--render", action="store_true")
    args = ap.parse_args()

    preset = PRESETS[args.preset]
    name = args.name or preset["name"]
    mood = args.mood or preset["mood"]
    key = args.key or preset["key"]
    stem = f"ambient-{args.preset}"

    if args.render:
        ensure_bed(mood, key)

    # The still is the video, so make it first and feed it to the render. The
    # title here is the full "N ชั่วโมง" line, which is what the frame should
    # carry.
    title = preset["title"].format(hours=_hours_label(args.minutes))[:100]
    still = thumbnail(stem, title, mood) if args.render else None

    p = plan(name, mood=mood, key=key, minutes=args.minutes,
             title_tmpl=preset["title"], use_case=preset["use_case"],
             still=still, stem=stem)
    print(f"length : {args.minutes / 60:g} h ({args.minutes:g} min)")
    print(f"title  : {p['title']}")
    print(f"out    : {p['out'].name}")
    if not args.render:
        print("(pass --render to build it)")
        return 0
    out = render(p)
    print(json.dumps({"out": str(out), "thumb": str(still) if still else None,
                      "mb": round(out.stat().st_size / 1e6, 1)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
