#!/usr/bin/env python3
"""Build a long ambient / sleep video from a keyless synth bed.

Why this exists. The 2026-11-09 YouTube scan was blunt: a 4-minute song gets
~500 views, a 2-hour Thai compilation gets 6-17 million, and sleep / ambient
loops of 8-12 hours get 100-221 million. The same channel's singles are the same
songs; the *container* is what the algorithm rewards. This builds the biggest
container we can, for free, with no login and no K action:

  * the music is our own `make_music` synth bed (no Flow Music, no quota),
  * the rain is ffmpeg's own noise generator, so there is no CC0 download and no
    license to track,
  * the picture is one still held for hours, which is what the sleep channels do.

A short bed is looped to the full length with `-stream_loop -1`, so an 8-hour
video costs one short synth pass, not eight hours of synthesis.

    python3 scripts/ambient_loop.py --plan --minutes 30     # what it would build
    python3 scripts/ambient_loop.py --minutes 480 --render  # an 8-hour sleep loop
    python3 scripts/ambient_loop.py --minutes 480 --rain --render

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
RAIN_SECONDS = 60.0

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
    "rain": {
        "name": "เสียงฝน",
        "mood": "mystic",
        "key": "A",
        "use_case": "เสียงฝนตก หลับสบาย",
        "title": "เสียงฝนตก {hours} ชั่วโมง | ฝนตกเบา ๆ หลับสบาย AERIS Music",
    },
}


def _run(args: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, **kw)


def _snap(freq: float, duration: float) -> float:
    """Nearest frequency that completes a whole, even number of cycles in `duration`.

    Even, not odd, so the half-frequency below it (the sub) is also a whole number
    of cycles. A sine whose period does not divide the loop length lands at a
    different phase each time the tile restarts, and the step is a click — every
    loop, all night, on an 8-hour video.
    """
    k = round(freq * duration)
    k += k % 2
    return k / duration


def _stitch(src: str, dst: str, duration: float, xfade: float = 1.0) -> str:
    """A seamless-loop filter tail: the loop starts at `xfade`, tail blended to head.

    Phase-snapping makes the *tones* continuous across the wrap, but the pink
    noise and any filter tail still leave a hairline step. The fix is the standard
    loop crossfade, built so the length is unchanged and the wrap is smooth:

      loop = S[xfade : T]  ++  crossfade(S[T-xfade : T], S[0 : xfade])

    The loop now begins at `S(xfade)` and ends on the crossfade's last sample,
    which is `S(xfade)` again — the two sides of the wrap are the *same value*, so
    it cannot click, and there is no fade in the body (a fade would dip the volume
    once per loop; the finished video gets its own fade at the very ends, in
    `plan`). `acrossfade` concatenates, so the two pieces are joined with
    `concat`, and the three slices come from one `asplit`.
    """
    d = xfade
    return (f"[{src}]asplit=3[{src}a][{src}b][{src}c];"
            f"[{src}a]atrim=start={d},asetpts=PTS-STARTPTS[p1];"
            f"[{src}b]atrim=start={duration - d},asetpts=PTS-STARTPTS[tail];"
            f"[{src}c]atrim=end={d},asetpts=PTS-STARTPTS[head];"
            f"[tail][head]acrossfade=d={d}:c1=tri:c2=tri[xf];"
            f"[p1][xf]concat=n=2:v=0:a=1[{dst}]")


def _synth_drone(mood: str, key: str, out: Path, duration: float) -> None:
    """A sleep drone: low sustained tones that swell slowly, nothing else.

    The story-video bed (`make_music._synthesise`) layers a *plucked arpeggio* —
    one note per beat, cycling the scale — because a story needs a melody. Inside
    an 8-hour sleep loop that melody repeats forever and reads as a "howl": the
    listener is played the same phrase on a 3-second cycle all night. This is a
    different bed for a different job.

    What is here instead: a low root, its fifth and its octave held under a slow
    tremolo (a 10-second breath), a sub an octave below, and a whisper of pink
    noise as "air". The tone is one `aevalsrc` expression, so the layers are
    summed exactly rather than mixed from separate decoders, and the loop is made
    seamless in two ways: every frequency is snapped to a whole number of cycles
    in `duration` (so the wrap is phase-continuous), and the result is
    crossfaded against its own shifted copy (`_stitch`). Loudness is normalised
    to a real target — the first version of this bed sat at -32 LUFS, which is
    barely audible — and the normalise happens *before* the stitch, so the two
    sides of the crossfade carry the same level.
    """
    roots = {"C": 130.81, "D": 146.83, "E": 164.81, "F": 174.61,
             "G": 196.00, "A": 220.00, "B": 246.94}
    r = _snap(roots.get(key, 130.81), duration)
    sub, fifth, octave = _snap(r / 2, duration), _snap(r * 1.5, duration), _snap(r * 2, duration)
    trem = max(0.1, round(0.1 * duration) / duration)   # 0.1 Hz is tremolo's floor
    tone = (f"0.20*sin(2*PI*{sub:.4f}*t)+0.30*sin(2*PI*{r:.4f}*t)"
            f"+0.20*sin(2*PI*{fifth:.4f}*t)+0.12*sin(2*PI*{octave:.4f}*t)")
    expr = f"(0.80+0.20*sin(2*PI*{trem:.5f}*t))*({tone})"
    filt = (
        f"aevalsrc=exprs={expr}:d={duration}:s=44100,"
        f"lowpass=f=700[pad];"
        f"anoisesrc=color=pink:amplitude=0.02:duration={duration},"
        f"lowpass=f=700,highpass=f=60,volume=0.55[air];"
        f"[pad][air]amix=inputs=2:normalize=0,"
        f"loudnorm=I=-16:TP=-2:LRA=5[ln];"
        f"[ln]aresample=44100[full];"
        + _stitch("full", "out", duration)
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    res = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-filter_complex", filt, "-map", "[out]",
                "-c:a", "pcm_s16le", str(out)])
    if res.returncode != 0 or not out.exists() or out.stat().st_size == 0:
        raise RuntimeError(f"drone synthesis failed: {res.stderr.strip()[-600:]}")


def ensure_bed(mood: str, key: str) -> Path:
    """A short sleep drone, synthesised once and cached by mood+key.

    The cache name is `drone-*`, not the old `ambient-*`: the first version of
    this lane cached the story-video bed, and reusing that cache would keep the
    arpeggio (and the howl) even after the synthesis changed. A cached file is
    trusted only if it is a whole tile long — a truncated one from an interrupted
    run would loop a fragment.
    """
    BEDS.mkdir(parents=True, exist_ok=True)
    dest = BEDS / f"drone-{mood}-{key}.wav"
    if dest.exists() and dest.stat().st_size > 44100 * 2 * BED_SECONDS * 0.9:
        return dest
    _synth_drone(mood, key, dest, BED_SECONDS)
    return dest


def ensure_rain() -> Path:
    """A short rain bed from ffmpeg's own noise source — no download, no license.

    No fade in or out: the bed is looped for hours, so a per-tile fade would dip
    the rain once a minute. The end fades are applied to the *finished* video
    instead (see `plan`). Loudness is set once here, before the loop stitch.
    """
    BEDS.mkdir(parents=True, exist_ok=True)
    dest = BEDS / "rain.wav"
    if dest.exists() and dest.stat().st_size > 44100 * 2 * RAIN_SECONDS * 0.9:
        return dest
    # Brown noise through a band-pass reads as steady rain; the light tremolo
    # keeps it from sounding like a hiss.
    filt = (
        f"anoisesrc=color=brown:amplitude=0.06:duration={RAIN_SECONDS},"
        f"lowpass=f=1400,highpass=f=180,tremolo=f=0.2:d=0.15,"
        f"loudnorm=I=-18:TP=-2:LRA=6[ln];"
        f"[ln]aresample=44100[full];"
        + _stitch("full", "out", RAIN_SECONDS)
    )
    res = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-filter_complex", filt, "-map", "[out]",
                "-c:a", "pcm_s16le", str(dest)])
    if res.returncode != 0 or not dest.exists():
        raise RuntimeError(f"rain synth failed: {res.stderr.strip()[-500:]}")
    return dest


def _hours_label(minutes: float) -> str:
    h = minutes / 60.0
    return f"{h:g}"


def plan(name: str, *, mood: str, key: str, minutes: float, rain: bool,
         title_tmpl: str, use_case: str, still: Path | None = None,
         stem: str | None = None) -> dict:
    """The ffmpeg command and the sidecar text, with nothing executed.

    Pure on purpose: a test can assert the shape (length, loops, maps, title)
    without paying for an 8-hour encode. `stem` keys both the output path and the
    state file, so the caller must pass the same one it will later check for.
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
    # Loop the short beds to the full length; the still is held the same way.
    cmd += ["-stream_loop", "-1", "-i", str(BEDS / f"drone-{mood}-{key}.wav")]
    if rain:
        cmd += ["-stream_loop", "-1", "-i", str(BEDS / "rain.wav")]
    cmd += ["-loop", "1", "-framerate", str(FPS), "-i", str(still)]
    cmd += ["-t", f"{secs:.3f}"]

    still_idx = 2 if rain else 1
    vf = (f"[{still_idx}:v]scale={W}:{H},format=yuv420p[v]")
    # Fades belong to the finished video, not to each looped tile: fading the bed
    # would dip the volume once per loop. A final gentle lowpass removes any high
    # ring the layers picked up, so nothing whistles across the eight hours.
    fade = 5.0
    tail = (f"lowpass=f=8000,afade=t=in:d={fade},"
            f"afade=t=out:st={max(0.0, secs - fade):.2f}:d={fade}[a]")
    if rain:
        af = f"[0:a][1:a]amix=inputs=2:normalize=0:duration=first,{tail}"
    else:
        af = f"[0:a]{tail}"
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
    ap.add_argument("--rain", action="store_true")
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
        if args.rain:
            ensure_rain()

    # The still is the video, so make it first and feed it to the render. The
    # title here is the full "N ชั่วโมง" line, which is what the frame should
    # carry.
    title = preset["title"].format(hours=_hours_label(args.minutes))[:100]
    still = thumbnail(stem, title, mood) if args.render else None

    p = plan(name, mood=mood, key=key, minutes=args.minutes, rain=args.rain,
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
