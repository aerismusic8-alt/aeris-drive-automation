#!/usr/bin/env python3
"""The clip quality standard for the whole channel — one gate, every format.

K (2026-11-17): the trivia clip is only a *sample* of the quality wanted; the goal
is a standard for **all** our work — "ห้ามมาตรฐานต่ำกว่านี้เด็ดขาดในช่องของเรา".
So this module defines a **universal technical floor** that every clip must clear,
plus **per-format rules** for the shapes we actually render. A style rule is only
applied where the format calls for it: "no hard cut" is right for the trivia lane,
but a public-domain film cuts by design, and a karaoke lyric sheet is meant to be
almost still.

Universal floor (every format):
    container/codec   h264 video, aac audio, 48 kHz stereo
    frame rate        a real rate (24/25/30/16 per format)
    loudness          -17.0 .. -13.0 LUFS   (raw TTS/voice is ~-22; a finished
                                              master is normalised)
    true peak         <= -0.1 dBTP          (no clipping)
    length            >= 1 s

Per-format profiles (auto-detected from the resolution):

    profile      shape        fps   extra rules
    -----------  -----------  ----  ------------------------------------------
    trivia       1280x720     24    picture must move, no hard cut, caption
    vertical     1080x1920    30    (shorts, MV) picture must move a little
    film         1920x1080    30    cuts allowed, no style check
    horizontal   1920x1080    25    (karaoke, compilation) caption, may be still
    motion       832x480       16    internal asset, format only

Everything is free (Rule #1): ffprobe + ffmpeg only, no key, no account.

CLI:  python3 ops/clip_standard.py <clip.mp4> [--profile trivia] [--json]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess

# --- Universal floor: no format may go below this ---------------------------
FLOOR = {
    "video_codec": "h264",
    "audio_codec": "aac",
    "audio_rate": 48000,
    "audio_channels": 2,
    "pix_fmt": ("yuv420p", "yuvj420p"),
    "min_seconds": 1.0,
    "lufs_min": -16.0,
    "lufs_max": -12.0,
    "true_peak_max": -1.0,
}

# --- Per-format profiles ----------------------------------------------------
# Each profile may tighten any FLOOR value and add style rules. A rule set to
# None is not checked for that format.
PROFILES: dict[str, dict] = {
    "trivia": {
        "label": "trivia (เกร็ดความรู้) — the reference standard",
        "resolutions": [(1280, 720)],
        "fps": (24,),
        "min_seconds": 3.0,
        "lufs_min": -16.5, "lufs_max": -13.5,
        "motion_median_min": 0.15,   # a frozen still frame measures 0.0
        "motion_max": 20.0,          # a hard cut measures ~94
        "text_px_min": 120,          # white Thai + thin dark outline
    },
    "short": {
        "label": "vertical 9:16 Short with burned captions (the hook lane)",
        "resolutions": [(1080, 1920)],
        "fps": (30,),
        "min_seconds": 5.0,
        "motion_median_min": 0.03,
        "motion_max": None,
        # A Short must carry its words on screen: it is watched muted, and a
        # calibration probe with the caption band painted out scored 9/10 from
        # Gemini while every measured rule passed it. K's list names captions and
        # no wasted vertical space, so both are enforced here, on the lane that
        # actually burns them.
        "text_px_min": 60,
        "bar_max_frac": 0.06,
    },
    "vertical": {
        "label": "vertical 9:16 (shorts, MV, affiliate, surreal, concert)",
        "resolutions": [(1080, 1920)],
        "fps": (30,),
        "min_seconds": 5.0,
        "motion_median_min": 0.03,   # zoompan on a still is small but nonzero
        "motion_max": None,          # MVs cut between shots by design
        # No caption rule: an MV shows artwork, not subtitles, and holding it to
        # a text floor would block a finished video. The caption floor lives on
        # the `short` profile, which is the lane that burns text.
        "text_px_min": None,
        "bar_max_frac": 0.06,        # wasted screen is a defect in any 9:16 clip
    },
    "film": {
        "label": "film / long-form landscape (public-domain film MV)",
        "resolutions": [(1920, 1080)],
        "fps": (30,),
        "min_seconds": 20.0,
        "motion_median_min": None,   # a film cuts; style checks do not apply
        "motion_max": None,
        "text_px_min": None,
    },
    "horizontal": {
        "label": "landscape 16:9 (karaoke, compilation)",
        "resolutions": [(1920, 1080)],
        "fps": (25,),
        "min_seconds": 30.0,
        "motion_median_min": None,   # a lyric sheet is almost still on purpose
        "motion_max": None,
        # No text rule: the karaoke lyric is drawn white-on-video and the
        # "bright next to dark" heuristic does not see it (measured 4-15 px on
        # clips whose lyrics are plainly present), so it would be a false block.
        # Lyric presence is guaranteed by the lane and its own tests instead.
        "text_px_min": None,
    },
    "motion": {
        "label": "internal motion asset",
        "resolutions": [(832, 480)],
        "fps": (16,),
        "min_seconds": 1.0,
        "audio_required": False,     # a background loop is silent by design
        "motion_median_min": 0.03,
        "motion_max": None,
        "text_px_min": None,
        # An intermediate is not a clip. Without this, a file under
        # `library/motion/` resolved to this profile and *passed* the gate, so a
        # silent 832x480 fragment could be handed to an uploader and shipped.
        "publishable": False,
    },
}

# Which lane (source dir / script) uses which standard — documentation + tests.
LANE_PROFILE = {
    "trivia": "trivia",
    "short": "short",
    "mv": "vertical", "affiliate": "vertical",
    "surreal": "vertical", "concert": "vertical", "moods": "vertical",
    "film": "film",
    "karaoke": "horizontal", "compilation": "horizontal",
    "motion": "motion",
}

# The profile a shape falls back to when nothing names its lane. `short` and
# `vertical` share 1080x1920 and 30 fps, so without this the caption rule would
# apply to every anonymous vertical clip — including an MV, which carries no
# text by design. An unnamed 9:16 clip gets the permissive standard; the shorts
# lane opts into the caption floor by its path.
SHAPE_DEFAULT = {(1080, 1920): "vertical"}

ANALYZE_W = 480
ANALYZE_MAX_SECONDS = 120.0


def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def ffprobe() -> str:
    exe = shutil.which("ffprobe")
    if exe:
        return exe
    cand = os.path.join(os.path.dirname(ffmpeg()), "ffprobe")
    return cand if os.path.exists(cand) else "ffprobe"


def probe(path: str) -> dict:
    out = subprocess.run(
        [ffprobe(), "-v", "error", "-show_streams", "-show_format",
         "-of", "json", path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path}: {out.stderr[:200]}")
    data = json.loads(out.stdout)
    v = next((s for s in data["streams"] if s["codec_type"] == "video"), {})
    a = next((s for s in data["streams"] if s["codec_type"] == "audio"), {})
    num, den = (v.get("avg_frame_rate") or "0/1").split("/")
    fps = (float(num) / float(den)) if float(den) else 0.0
    rnum, rden = (v.get("r_frame_rate") or "0/1").split("/")
    rfps = (float(rnum) / float(rden)) if float(rden) else 0.0
    return {
        "width": int(v.get("width") or 0),
        "height": int(v.get("height") or 0),
        "fps": round(fps, 3),
        "r_fps": round(rfps, 3),
        "video_codec": v.get("codec_name") or "",
        "pix_fmt": v.get("pix_fmt") or "",
        "audio_codec": a.get("codec_name") or "",
        "audio_rate": int(a.get("sample_rate") or 0),
        "audio_channels": int(a.get("channels") or 0),
        "seconds": float(data.get("format", {}).get("duration") or 0.0),
    }


def profile_for(path: str, hint: str | None = None) -> str | None:
    """The profile for a clip: an explicit hint, else shape + frame rate.

    1920x1080 is shared by the film lane (30 fps) and the karaoke/compilation
    lane (25 fps), so the frame rate disambiguates them. If nothing matches the
    shape, return the first shape match so the frame-rate rule reports the miss
    instead of the vaguer "unknown format".
    """
    if hint:
        return hint if hint in PROFILES else None
    # A file in library/shorts/ is the hook lane, which burns captions; the same
    # 1080x1920 shape in library/mv/ is artwork with no text. Shape alone cannot
    # tell them apart, so the path decides before the shape does.
    posix = str(path).replace("\\", "/")
    for lane, prof in LANE_PROFILE.items():
        if f"/{lane}/" in posix or posix.startswith(f"{lane}/"):
            try:
                info = probe(path)
            except Exception:
                return prof
            if (info["width"], info["height"]) in PROFILES[prof]["resolutions"]:
                return prof
    try:
        info = probe(path)
    except Exception:
        return None
    shape = (info["width"], info["height"])
    by_shape = [n for n, p in PROFILES.items() if shape in p["resolutions"]]
    if not by_shape:
        return None
    if shape in SHAPE_DEFAULT:
        return SHAPE_DEFAULT[shape]
    for n in by_shape:
        if info["fps"] in PROFILES[n]["fps"]:
            return n
    return by_shape[0]



def _frames(path: str):
    import numpy as np
    info = probe(path)
    w = ANALYZE_W
    h = int(round(ANALYZE_W * info["height"] / info["width"])) if info["width"] else 0
    if h % 2:
        h += 1
    args = [ffmpeg(), "-v", "error", "-i", path,
            "-t", f"{min(info['seconds'], ANALYZE_MAX_SECONDS):.3f}",
            "-vf", f"fps=24,scale={w}:{h},format=gray",
            "-f", "rawvideo", "-"]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    n = w * h
    try:
        while True:
            buf = proc.stdout.read(n)
            if len(buf) < n:
                break
            yield np.frombuffer(buf, dtype=np.uint8).reshape(h, w).astype(np.float32)
    finally:
        proc.stdout.close()
        proc.wait()


def motion(path: str):
    """(median, p99, max) consecutive-frame difference. Max ~94 = a hard cut."""
    import numpy as np
    prev, diffs = None, []
    for f in _frames(path):
        if prev is not None:
            diffs.append(float(np.mean(np.abs(f - prev))))
        prev = f
    if not diffs:
        return 0.0, 0.0, 0.0
    return (round(float(np.median(diffs)), 3),
            round(float(np.percentile(diffs, 99)), 3),
            round(float(max(diffs)), 3))


def text_pixels(path: str) -> int:
    """Median count of bright pixels touching a dark pixel, in the middle band."""
    import numpy as np
    vals = []
    for i, f in enumerate(_frames(path)):
        if i % 12:
            continue
        h = f.shape[0]
        band = f[int(h * 0.15):int(h * 0.85)]
        bright = band > 235
        dark = band < 110
        nb = np.zeros_like(dark)
        nb[1:, :] |= dark[:-1, :]
        nb[:-1, :] |= dark[1:, :]
        nb[:, 1:] |= dark[:, :-1]
        nb[:, :-1] |= dark[:, 1:]
        vals.append(int((bright & nb).sum()))
    if not vals:
        return 0
    vals.sort()
    return vals[len(vals) // 2]


def bar_frac(path: str) -> float:
    """Letterbox size: the black band hugging the frame edge, as a fraction.

    A bar is a black band **anchored to the top or bottom edge** and present in
    **most** frames. Measuring the tallest black run anywhere counted a dark
    scene and the follow-card gradient as bars — the good clip measured 14.3%
    and was wrongly blocked. A real letterbox is 33% at an edge in every frame.
    So: per frame take the run touching the top or the bottom edge, then take the
    median across frames. A transient dark scene drops out; a bar cannot.
    """
    import numpy as np
    vals: list[float] = []
    for i, f in enumerate(_frames(path)):
        if i % 12:
            continue
        h = f.shape[0]
        dark = f.reshape(h, -1).max(axis=1) <= 10
        top = 0
        for d in dark:
            if not d:
                break
            top += 1
        bot = 0
        for d in dark[::-1]:
            if not d:
                break
            bot += 1
        vals.append(max(top, bot) / h)
    if not vals:
        return 0.0
    vals.sort()
    return round(vals[len(vals) // 2], 4)


def silence_max(path: str) -> float:
    """Longest silent stretch in seconds (-inf threshold, 1.0 s minimum).

    A phone clip with a dead gap reads as a broken render, and the audio floor
    cannot see it: integrated loudness and true peak both stay in band while two
    seconds of nothing sit in the middle. This is the check that catches it.
    """
    out = subprocess.run(
        [ffmpeg(), "-hide_banner", "-i", path, "-af",
         "silencedetect=n=-45dB:d=1.0", "-f", "null", "-"],
        capture_output=True, text=True)
    best = 0.0
    for m in re.finditer(r"silence_duration:\s*([0-9.]+)", out.stderr or ""):
        best = max(best, float(m.group(1)))
    return round(best, 3)


def loudness(path: str):
    """(integrated LUFS, true peak dBTP) via ffmpeg's EBU R128 meter."""
    out = subprocess.run(
        [ffmpeg(), "-hide_banner", "-i", path,
         "-af", "loudnorm=print_format=summary", "-f", "null", "-"],
        capture_output=True, text=True)
    lufs = peak = None
    for line in out.stderr.splitlines():
        if "Input Integrated:" in line:
            lufs = float(line.split(":")[1].strip().split()[0])
        elif "Input True Peak:" in line:
            peak = float(line.split(":")[1].strip().split()[0])
    return lufs, peak


def _thresh(p: dict, key: str, default=None):
    """A profile value, else the universal FLOOR value, else `default`."""
    v = p.get(key)
    if v is None:
        v = FLOOR.get(key)
    return default if v is None else v


def check(path: str, profile: str | None = None) -> list[tuple[str, bool, str]]:
    """Return [(name, ok, detail)] for every rule. Never raises on a bad clip."""
    res: list[tuple[str, bool, str]] = []

    def add(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    try:
        info = probe(path)
    except Exception as e:
        add("readable file", False, str(e)[:120])
        return res
    add("readable file", True, os.path.basename(path))

    name = profile_for(path, profile)
    if name is None:
        add("known format", False,
            f"no standard for {info['width']}x{info['height']} — "
            f"add a profile in ops/clip_standard.py")
        return res
    p = PROFILES[name]
    add("known format", True, f"{name} ({p['label']})")
    # An intermediate asset can satisfy every numeric rule and still be the wrong
    # thing to publish: `motion` is silent 832x480 by design. The rule is reported
    # so `check()` stays a pure reader, but it fails, so `assert_ok()` and every
    # upload chokepoint that calls it refuse the file.
    if p.get("publishable") is False:
        add("is a publishable format", False,
            f"{name} is an internal intermediate, not a clip — "
            f"render it into a published profile first")

    shape = (info["width"], info["height"])
    want = p["resolutions"][0]
    add(f"shape is {want[0]}x{want[1]}", shape in p["resolutions"],
        f"{info['width']}x{info['height']}")
    add("frame rate", info["fps"] in _thresh(p, "fps"), f"{info['fps']} fps")
    # A variable frame rate means the renderer dropped or duplicated frames. The
    # nominal rate can still read 30 while playback stutters, so compare the
    # average against the real base rate instead of trusting one field.
    if info.get("r_fps"):
        drift = abs(info["fps"] - info["r_fps"]) / max(1e-6, info["r_fps"])
        add("frame rate is constant", drift <= 0.02,
            f"avg {info['fps']} vs real {info['r_fps']} "
            f"({drift:.1%} drift, max 2%)")
    add("video codec", info["video_codec"] == FLOOR["video_codec"],
        info["video_codec"])
    add("pixel format", info["pix_fmt"] in FLOOR["pix_fmt"], info["pix_fmt"])

    audio_required = p.get("audio_required", True)
    if audio_required:
        add("audio aac 48k stereo",
            info["audio_codec"] == FLOOR["audio_codec"]
            and info["audio_rate"] == FLOOR["audio_rate"]
            and info["audio_channels"] == FLOOR["audio_channels"],
            f"{info['audio_codec']} {info['audio_rate']}Hz {info['audio_channels']}ch")
    else:
        add("audio is optional", True, "silent asset")
    add("long enough", info["seconds"] >= _thresh(p, "min_seconds"),
        f"{info['seconds']:.1f}s (min {_thresh(p, 'min_seconds')})")

    if audio_required:
        lo, hi = _thresh(p, "lufs_min"), _thresh(p, "lufs_max")
        lufs, peak = loudness(path)
        add("loudness normalised", lufs is not None and lo <= lufs <= hi,
            f"{lufs} LUFS (want {lo}..{hi})")
        add("no clipping", peak is not None and peak <= FLOOR["true_peak_max"],
            f"{peak} dBTP (max {FLOOR['true_peak_max']})")
        # Integrated loudness and true peak both stay in band across a dead gap,
        # so a silent stretch is invisible to the two rules above. The limit is
        # generous on purpose: a song intro or a held note is not a defect, and
        # the value is per-profile so a lane can tighten it.
        limit = _thresh(p, "silence_max_seconds", 3.0)
        if limit is not None:
            sm = silence_max(path)
            add("no dead silence", sm <= limit,
                f"longest gap {sm}s (max {limit}s)")

    if (p.get("motion_median_min") is not None or p.get("motion_max") is not None
            or p.get("text_px_min") is not None):
        med, p99, mx = motion(path)
        if p.get("motion_max") is not None:
            add("no hard cut", mx <= p["motion_max"],
                f"max {mx} (limit {p['motion_max']})")
        if p.get("motion_median_min") is not None:
            add("picture is not frozen", med >= p["motion_median_min"],
                f"median {med} (min {p['motion_median_min']})")
        if p.get("text_px_min") is not None:
            tx = text_pixels(path)
            add("caption is present and big", tx >= p["text_px_min"],
                f"{tx} text px (min {p['text_px_min']})")
    if p.get("bar_max_frac") is not None:
        bf = bar_frac(path)
        add("no wasted black bars", bf <= p["bar_max_frac"],
            f"tallest black band {bf:.1%} of height (max {p['bar_max_frac']:.0%})")
    return res


def assert_ok(path: str, profile: str | None = None) -> None:
    """Raise unless every rule passes. Used on the publish path."""
    failed = [n for n, ok, _ in check(path, profile) if not ok]
    if failed:
        raise SystemExit("clip below the standard: " + "; ".join(failed))


# Loudness a repair normalises to: the middle of the universal band, matching
# the masterer's -14 LUFS target, with the true-peak ceiling the floor demands.
REPAIR_TARGET_LUFS = -14.0
REPAIR_TRUE_PEAK = -1.5


def needs_audio_repair(path: str, profile: str | None = None) -> bool:
    """True when a clip's audio fails the loudness/peak floor (nothing else).

    Only the two audio rules are inspected, and the band is read straight from
    the profile rather than through `check()` — a clip that fails a *style* rule
    (frozen picture, missing caption) is a different problem a re-mux cannot fix,
    so it is left for the gate to refuse. When the file cannot be probed (ffprobe
    missing) this returns False and the gate fails closed, as it already does.
    """
    try:
        probe(path)
    except Exception:
        return False
    p = PROFILES.get(profile_for(path, profile) or "", {})
    if p.get("audio_required") is False:
        return False
    lufs, peak = loudness(path)
    if lufs is None or peak is None:
        return False
    lo, hi = _thresh(p, "lufs_min"), _thresh(p, "lufs_max")
    return not (lo <= lufs <= hi and peak <= FLOOR["true_peak_max"])


def repair_audio(path: str, out: str | None = None) -> str:
    """Re-normalise a clip's audio to the floor, copying the video untouched.

    Why this exists (K, 2026-11-18): a video rendered before a song master was
    re-mastered keeps the old, clipped audio. The floor gate then refuses it and
    the whole release batch goes red — three releases in a row shipped nothing
    (2026-11-16..18) because `song-14` carried +0.4 dBTP from a 2026-11-06
    render. Gemini's advice was to fix this at the source in the pipeline rather
    than re-render by hand: normalise the audio at the chokepoint, so a stale
    clip self-heals instead of blocking. The video stream is stream-copied, so
    this is fast and lossless for the picture.

    Writes to a temp file by default (never into `library/`, which
    `publish_media.py` sweeps to the release, so a repaired copy must not become
    a new asset) unless `out` is given, and returns the path that now clears the
    audio floor.
    """
    import os
    import tempfile
    src = path
    if out is None:
        fd, out = tempfile.mkstemp(suffix=".fixed.mp4")
        os.close(fd)
    dst = out
    measured = _measure_loudnorm(src, target=REPAIR_TARGET_LUFS)
    filt = (f"loudnorm=I={REPAIR_TARGET_LUFS}:TP={REPAIR_TRUE_PEAK}:LRA=11:"
            f"linear=true:measured_I={measured.get('input_i')}:"
            f"measured_TP={measured.get('input_tp')}:"
            f"measured_LRA={measured.get('input_lra')}:"
            f"measured_thresh={measured.get('input_thresh')}:"
            f"offset={measured.get('target_offset', 0)}:print_format=summary")
    subprocess.run(
        [ffmpeg(), "-y", "-v", "error", "-i", src,
         "-c:v", "copy", "-af", filt, "-ar", "48000", "-ac", "2",
         "-c:a", "aac", "-b:a", "192k", dst], check=True)
    return dst


def _measure_loudnorm(src: str, *, target: float) -> dict:
    """First pass of a two-pass loudnorm: the source's own measurements."""
    out = subprocess.run(
        [ffmpeg(), "-hide_banner", "-i", src,
         "-af", f"loudnorm=I={target}:TP={REPAIR_TRUE_PEAK}:LRA=11:print_format=json",
         "-f", "null", "-"], capture_output=True, text=True)
    blob = out.stderr[out.stderr.rfind("{"):]
    blob = blob[:blob.rfind("}") + 1]
    return json.loads(blob)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clip")
    ap.add_argument("--profile", choices=list(PROFILES),
                    help="override auto-detection by resolution")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = check(a.clip, a.profile)
    if a.json:
        print(json.dumps([{"rule": n, "ok": ok, "detail": d} for n, ok, d in rows],
                         ensure_ascii=False, indent=2))
    else:
        for n, ok, d in rows:
            print(f"  {'ok  ' if ok else 'FAIL'} {n:30s} {d}")
    bad = [n for n, ok, _ in rows if not ok]
    print(f"\n{'PASS' if not bad else 'FAIL'} — {len(rows)-len(bad)}/{len(rows)} rules")
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
