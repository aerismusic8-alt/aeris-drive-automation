"""Compose a video: stills + narration + burned-in karaoke subtitles.

Thai needs a real shaper. libass (via ffmpeg's subtitles filter) does that
correctly, so the subtitles are burned from the ASS file rather than drawn
frame by frame. The karaoke track is the point of the video, so it is never
dropped silently: a missing ASS file is an error.
"""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

WIDTH, HEIGHT = 1920, 1080
FPS = 25


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def _escape_filter_path(path: Path) -> str:
    """ffmpeg's filter parser treats : and \\ as syntax, so escape them."""
    return str(path).replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")


def probe(path: Path) -> dict:
    out = _run(["ffprobe", "-v", "error", "-show_entries",
                "stream=codec_type,codec_name,width,height,r_frame_rate,duration,"
                "channels,sample_rate:format=duration",
                "-of", "json", str(path)])
    if out.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path}: {out.stderr.strip()}")
    return json.loads(out.stdout)


# The bed must be audible on its own but step aside for the voice. A plain
# `amix` does neither: it leaves the music at whatever gain it was given, so a
# bed set low enough to sit under speech is inaudible in the ~1 s pauses
# between narration lines, and one set high enough to hear fights the voice.
# These are the sidechain settings that resolve that, measured on ep01.
MUSIC_GAIN_DB = -4.0
DUCK = {"threshold": 0.008, "ratio": 18.0, "attack": 15.0, "release": 350.0}


def _audio_filter(audio_idx: int, music_idx: int | None, duration: float,
                  music_gain_db: float, fade: float) -> tuple[str, list[str]]:
    """Narration on top, bed genuinely ducked underneath. Both renderers share it.

    The bed is played at `music_gain_db` and compressed by the narration as a
    sidechain, so it lifts into the pauses and drops under a line. Both sources
    are pinned to the same format first: the voice arrives mono at 24 kHz and
    the bed mono at 48 kHz, and `sidechaincompress` wants a common layout.
    """
    if music_idx is None:
        return f"[{audio_idx}:a]anull[a]", ["-map", "[a]"]
    fmt = "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo"
    fc = (
        f"[{audio_idx}:a]{fmt},asplit=2[narr][sc];"
        f"[{music_idx}:a]{fmt},volume={music_gain_db}dB,"
        f"afade=t=in:d={fade},"
        f"afade=t=out:st={max(0.0, duration - fade)}:d={fade}[bed];"
        f"[bed][sc]sidechaincompress=threshold={DUCK['threshold']}"
        f":ratio={DUCK['ratio']}:attack={DUCK['attack']}"
        f":release={DUCK['release']}:makeup=1[duck];"
        f"[narr][duck]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]"
    )
    return fc, ["-map", "[a]"]


def _preset_for(duration: float) -> str:
    """Trade a little compression for finishing before the pod recycles.

    A quarter-hour render is twenty-five thousand frames through sixteen live
    zoompan branches. At `medium` that runs long enough that a pod recycle can
    kill it partway; `veryfast` costs a few percent of size on near-static
    slideshow content and finishes in a fraction of the time.
    """
    return "medium" if duration <= 600 else "veryfast"


def _encode(out: Path, duration: float) -> list[str]:
    # 48 kHz stereo out. The sources are mono at two different rates (the voice
    # at 24 kHz, the bed at 48 kHz), and mixing without pinning the rate lets
    # ffmpeg pick one per stream, which produced a 96 kHz mono track.
    return ["-t", f"{duration:.3f}", "-r", str(FPS), "-fps_mode", "cfr",
            "-c:v", "libx264", "-preset", _preset_for(duration), "-crf", "20",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
            "-ar", "48000", "-ac", "2",
            "-movflags", "+faststart", str(out)]


def _partial(out: Path) -> Path:
    """A sibling path ffmpeg writes to before the real output is promoted.

    A long render can be killed partway (the sandbox recycles its pod), and
    ffmpeg writes the `moov` atom last, so a truncated file at the real path
    looks finished to anything that only stats it. Writing beside it and
    renaming on success means a half-written file is never mistaken for one.
    """
    return out.with_name(f"{out.stem}.partial{out.suffix}")


def _report(out: Path, music: Path | None) -> dict:
    info = probe(out)
    video = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
    sound = next((s for s in info["streams"] if s["codec_type"] == "audio"), None)
    if not video or not sound:
        raise RuntimeError(f"output is missing a stream: {info['streams']}")
    return {
        "output": str(out),
        "bytes": out.stat().st_size,
        "duration_seconds": round(float(info["format"]["duration"]), 3),
        "video": {"codec": video["codec_name"], "width": video["width"],
                  "height": video["height"], "fps": video["r_frame_rate"]},
        "audio": {"codec": sound["codec_name"]},
        "music_bed": str(music) if music else None,
    }


def _ken_burns(duration: float, direction: str, zoom_to: float = 1.12) -> str:
    """A slow push in or out across one still.

    `settb=AVTB` is required, not cosmetic: xfade refuses an input whose timebase
    is not constant, and zoompan's output reads as `1/0` without it.

    The intermediate scale only needs headroom for `zoom_to`, so it is sized to
    that rather than to a flat 2x. Sixteen scenes are live in one filter graph,
    and a 4K intermediate per input is several times the memory of what the zoom
    actually uses, which is enough to kill a long render.
    """
    frames = max(1, int(duration * FPS))
    step = (zoom_to - 1.0) / frames
    if direction == "in":
        zoom = f"min(1.0+{step:.6f}*on,{zoom_to})"
    else:
        zoom = f"max({zoom_to}-{step:.6f}*on,1.0)"
    work_w = int(WIDTH * zoom_to) + 2
    work_h = int(HEIGHT * zoom_to) + 2
    return (
        f"scale={work_w}:{work_h}:force_original_aspect_ratio=increase,"
        f"crop={work_w}:{work_h},"
        f"zoompan=z='{zoom}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
        f":d={frames}:s={WIDTH}x{HEIGHT}:fps={FPS},"
        f"trim=duration={duration:.3f},setpts=PTS-STARTPTS,"
        f"fps={FPS},settb=AVTB,format=yuv420p"
    )


def compose_scenes(*, scenes: list[dict], audio: Path, ass: Path, out: Path,
                   music: Path | None = None, music_gain_db: float = MUSIC_GAIN_DB,
                   fade: float = 1.2, crossfade: float = 1.5,
                   direction: str = "auto") -> dict:
    """Render a long-form clip: one still per scene, panned, crossfaded, timed.

    `scenes` is `[{"image": Path, "duration": float}, ...]`. Scene durations must
    already add up to the narration length; the caller owns that because only it
    knows where the sentences fall. The first scene is held, each later one fades
    in over the tail of the previous, so the running time is
    `sum(durations) - crossfade * (len(scenes) - 1)`.

    A single still for a quarter-hour is what made the early clips feel dead, so
    each still is given a slow zoom and the joins are crossfades rather than cuts.
    """
    audio, ass, out = Path(audio), Path(ass), Path(out)
    for required, label in ((audio, "audio"), (ass, "karaoke ass")):
        if not required.exists():
            raise FileNotFoundError(f"{label} not found: {required}")
    if not scenes:
        raise ValueError("compose_scenes needs at least one scene")
    for i, s in enumerate(scenes):
        if not Path(s["image"]).exists():
            raise FileNotFoundError(f"scene {i} image not found: {s['image']}")
        if float(s["duration"]) <= 0:
            raise ValueError(f"scene {i} has a non-positive duration: {s['duration']}")
    if len(scenes) > 1 and crossfade >= min(float(s["duration"]) for s in scenes):
        raise ValueError("crossfade must be shorter than the shortest scene")

    total = sum(float(s["duration"]) for s in scenes) - crossfade * (len(scenes) - 1)
    if total <= 0:
        raise ValueError(f"scenes do not add up to a positive duration: {total}")

    inputs: list[str] = []
    for s in scenes:
        inputs += ["-loop", "1", "-i", str(s["image"])]
    audio_idx = len(scenes)
    inputs += ["-i", str(audio)]
    music_idx = None
    if music is not None:
        music_idx = audio_idx + 1
        inputs += ["-stream_loop", "-1", "-i", str(music)]

    parts: list[str] = []
    for i, s in enumerate(scenes):
        if direction == "auto":
            d = "in" if i % 2 == 0 else "out"
        else:
            d = direction
        parts.append(f"[{i}:v]{_ken_burns(float(s['duration']), d)}[s{i}]")

    # Chain the crossfades: each join happens `crossfade` before the previous
    # segment ends, and the running offset accumulates accordingly.
    if len(scenes) == 1:
        vlabel = "s0"
    else:
        prev = "s0"
        offset = float(scenes[0]["duration"]) - crossfade
        for i in range(1, len(scenes)):
            label = f"x{i}"
            parts.append(
                f"[{prev}][s{i}]xfade=transition=fade:duration={crossfade}"
                f":offset={offset:.3f}[{label}]")
            prev = label
            if i < len(scenes) - 1:
                offset += float(scenes[i]["duration"]) - crossfade
        vlabel = prev

    parts.append(f"[{vlabel}]subtitles='{_escape_filter_path(ass)}'[v]")
    afc, amap = _audio_filter(audio_idx, music_idx, total, music_gain_db, fade)
    parts.append(afc)

    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = _partial(out)
    args = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    args += inputs
    args += ["-filter_complex", ";".join(parts)]
    args += ["-map", "[v]"] + amap
    args += _encode(tmp, total)

    result = _run(args)
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(f"ffmpeg failed: {result.stderr.strip()[-2000:]}")
    tmp.replace(out)
    report = _report(out, music)
    report["scenes"] = len(scenes)
    return report


def compose(*, image: Path | None = None, audio: Path, ass: Path, out: Path,
            duration: float | None = None, music: Path | None = None,
            music_gain_db: float = MUSIC_GAIN_DB, fade: float = 1.2,
            font_size: int = 0) -> dict:
    """Render one clip. Returns a report with the MEASURED output properties."""
    image, audio, ass, out = (Path(p) if p else None for p in (image, audio, ass, out))
    for required, label in ((audio, "audio"), (ass, "karaoke ass")):
        if not required.exists():
            raise FileNotFoundError(f"{label} not found: {required}")
    if image is not None and not image.exists():
        raise FileNotFoundError(f"image not found: {image}")

    if duration is None:
        duration = float(probe(audio)["format"]["duration"])

    # Input indices are tracked explicitly: ffmpeg maps by position, and a
    # missing image shifts every later index.
    inputs: list[str] = []
    input_count = 0
    if image is not None:
        inputs += ["-loop", "1", "-i", str(image)]
    else:
        # A solid backdrop keeps the clip valid when no still is available.
        inputs += ["-f", "lavfi", "-i", f"color=c=0x101014:s={WIDTH}x{HEIGHT}:r=25"]
    video_idx = input_count
    input_count += 1
    video_src = f"[{video_idx}:v]"

    audio_idx = input_count
    input_count += 1
    inputs += ["-i", str(audio)]

    music_idx = None
    if music is not None:
        music_idx = input_count
        input_count += 1
        inputs += ["-stream_loop", "-1", "-i", str(music)]

    vf = [
        f"scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=increase",
        f"crop={WIDTH}:{HEIGHT}",
        "format=yuv420p",
    ]
    vf.append(f"subtitles='{_escape_filter_path(ass)}'")

    if music is not None:
        afc, amap = _audio_filter(audio_idx, music_idx, duration, music_gain_db, fade)
        filter_complex = f"{video_src}{','.join(vf)}[v];{afc}"
        maps = ["-map", "[v]"] + amap
    else:
        filter_complex = f"{video_src}{','.join(vf)}[v]"
        maps = ["-map", "[v]", "-map", f"{audio_idx}:a"]

    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = _partial(out)
    args = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    args += inputs
    if filter_complex:
        args += ["-filter_complex", filter_complex]
    args += maps
    args += ["-t", f"{duration:.3f}", "-r", "25", "-fps_mode", "cfr",
             "-c:v", "libx264", "-preset", _preset_for(duration), "-crf", "20",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
             "-ar", "48000", "-ac", "2",
             "-movflags", "+faststart", str(tmp)]

    result = _run(args)
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(f"ffmpeg failed: {result.stderr.strip()[-1500:]}")
    tmp.replace(out)

    info = probe(out)
    video = next((s for s in info["streams"] if s["codec_type"] == "video"), None)
    sound = next((s for s in info["streams"] if s["codec_type"] == "audio"), None)
    if not video or not sound:
        raise RuntimeError(f"output is missing a stream: {info['streams']}")
    return {
        "output": str(out),
        "bytes": out.stat().st_size,
        "duration_seconds": round(float(info["format"]["duration"]), 3),
        "video": {"codec": video["codec_name"], "width": video["width"],
                  "height": video["height"], "fps": video["r_frame_rate"]},
        "audio": {"codec": sound["codec_name"]},
        "music_bed": str(music) if music else None,
    }


def measure_loudness(path: Path) -> dict:
    """EBU R128 integrated loudness and true peak, measured not assumed."""
    out = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                "-filter_complex", "ebur128=peak=true", "-f", "null", "-"])
    text = out.stderr
    integrated = None
    peak = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("I:") and integrated is None:
            integrated = float(line.split()[1])
        elif line.startswith("Peak:") and peak is None:
            peak = float(line.split()[1])
    if integrated is None:
        # Single-pass ebur128 prints a summary block; take the last I: seen.
        for line in text.splitlines():
            if line.strip().startswith("I:"):
                integrated = float(line.strip().split()[1])
    return {"integrated_lufs": integrated, "true_peak_dbfs": peak}


def _loudnorm_pass1(src: Path, target: float, tp: float) -> dict:
    out = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(src),
                "-af", f"loudnorm=I={target}:TP={tp}:LRA=11:print_format=json",
                "-f", "null", "-"])
    start = out.stderr.rfind("{")
    end = out.stderr.rfind("}")
    if start < 0 or end < 0:
        raise RuntimeError("loudnorm did not report measurements")
    return json.loads(out.stderr[start:end + 1])


def normalise_audio(src: Path, dst: Path, *, target: float = -17.0,
                    tp: float = -1.5, lra: float = 11.0) -> dict:
    """Two-pass loudnorm. Single pass misses the target by about 1 LU.

    The video stream is copied, so this only re-encodes audio.
    """
    measured = _loudnorm_pass1(src, target, tp)
    filt = (
        f"loudnorm=I={target}:TP={tp}:LRA={lra}"
        f":measured_I={measured['input_i']}:measured_TP={measured['input_tp']}"
        f":measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}"
        f":offset={measured['target_offset']}:linear=true:print_format=summary"
    )
    out = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(src),
                "-af", filt, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-ar", "48000", "-ac", "2",
                "-movflags", "+faststart", str(dst)])
    if out.returncode != 0:
        raise RuntimeError(f"loudnorm failed: {out.stderr.strip()[-800:]}")
    return {"pass1": measured, "target_lufs": target, "applied": True}
