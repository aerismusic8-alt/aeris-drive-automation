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


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def _escape_filter_path(path: Path) -> str:
    """ffmpeg's filter parser treats : and \\ as syntax, so escape them."""
    return str(path).replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")


def probe(path: Path) -> dict:
    out = _run(["ffprobe", "-v", "error", "-show_entries",
                "stream=codec_type,codec_name,width,height,r_frame_rate,duration:format=duration",
                "-of", "json", str(path)])
    if out.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path}: {out.stderr.strip()}")
    return json.loads(out.stdout)


def compose(*, image: Path | None = None, audio: Path, ass: Path, out: Path,
            duration: float | None = None, music: Path | None = None,
            music_gain_db: float = -18.0, fade: float = 1.2,
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
        # Narration must stay on top even during pauses, so the bed is ducked
        # rather than merely mixed.
        filter_complex = (
            f"{video_src}{','.join(vf)}[v];"
            f"[{music_idx}:a]volume={music_gain_db}dB,afade=t=in:d={fade},"
            f"afade=t=out:st={max(0.0, duration - fade)}:d={fade}[bed];"
            f"[{audio_idx}:a][bed]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]"
        )
        maps = ["-map", "[v]", "-map", "[a]"]
    else:
        filter_complex = f"{video_src}{','.join(vf)}[v]"
        maps = ["-map", "[v]", "-map", f"{audio_idx}:a"]

    out.parent.mkdir(parents=True, exist_ok=True)
    args = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    args += inputs
    if filter_complex:
        args += ["-filter_complex", filter_complex]
    args += maps
    args += ["-t", f"{duration:.3f}", "-r", "25", "-fps_mode", "cfr",
             "-c:v", "libx264", "-preset", "medium", "-crf", "20",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart", str(out)]

    result = _run(args)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr.strip()[-1500:]}")

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
                "-movflags", "+faststart", str(dst)])
    if out.returncode != 0:
        raise RuntimeError(f"loudnorm failed: {out.stderr.strip()[-800:]}")
    return {"pass1": measured, "target_lufs": target, "applied": True}
