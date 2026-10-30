"""Render a 1920x1080 karaoke MP4 from a Flow Music song.

Inputs are the ones the Flow Music pipeline actually produces:

    library/songs/karaoke-<slug>.mp3    the real-stem instrumental
    library/covers/cover-<slug>.jpg     the clip's cover art
    lyrics/<slug>.txt                   title, subtitle and the sung lines

The old version of this script read a `timing.json` that the retired Piper
builder wrote: it knew every note, so the `\\kf` sweep was exact. Flow Music does
not hand us per-syllable timing on the compose path. Measured in the app bundle
(2026-10-30): the only source of real markers is the *Lyria agent* path — a clip
whose `operation.op_type` is `lyria__generate_song` carries `operation.timing_markers`,
and `lyrics_timing.value.markers` appears once its status is `completed`. A clip
made through the compose form (this pipeline) has neither, so line timing is
*estimated* from the song length and each line's length, and the highlight sweeps
proportionally inside a line. That is the honest description of what this renders:
a lyric video with a karaoke sweep, not a note-accurate one. If a clip does carry
markers, pass them in with `--timing` and the sweep uses the real times instead.

Run:  python3 scripts/make_karaoke.py 01-khon-di-thi-chak-pai [--preview 20]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

W, H = 1920, 1080
FPS = 25
FONT = "Noto Sans Thai"
PRIMARY = "&H0000C8FF"    # after a word is sung: warm amber
SECONDARY = "&H00FFFFFF"  # before: white
OUTLINE = "&H00101010"
BACK = "&H80000000"

# Silence assumed at each end, so the first line does not start on frame 0.
LEAD = 5.0
TAIL = 8.0

SKIP_SECTIONS = {"intro", "outro", "solo", "instrumental", "break", "end"}


def _ts(t: float) -> str:
    t = max(0.0, t)
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = t % 60
    return f"{h:d}:{m:02d}:{s:05.2f}"


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}")


def _duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip()
    return float(out)


def load_lyrics(slug: str) -> tuple[dict, list[str]]:
    """Read the header block and the sung lines out of lyrics/<slug>.txt."""
    text = (ROOT / "lyrics" / f"{slug}.txt").read_text(encoding="utf-8")
    meta, lines, section = {}, [], ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            m = re.match(r"#\s*([A-Z]+)\s*:\s*(.+)", line)
            if m:
                meta[m.group(1).lower()] = m.group(2).strip()
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section in SKIP_SECTIONS:
            continue
        lines.append(line)
    return meta, lines


def _words(line: str) -> list[str]:
    """Split a Thai line into singable words for the sweep.

    pythainlp does a real Thai segmentation when it is installed; otherwise fall
    back to space-separated chunks, which the lyric files already use.
    """
    try:
        from pythainlp.tokenize import word_tokenize
        toks = [t for t in word_tokenize(line, keep_whitespace=True) if t.strip()]
        return toks or [line]
    except Exception:
        return [w for w in re.split(r"(\s+)", line) if w]


def estimate(lines: list[str], duration: float) -> list[dict]:
    """Give each line a start/end from its share of the sung span."""
    if not lines:
        return []
    span = max(1.0, duration - LEAD - TAIL)
    weights = [max(1, len(l.replace(" ", ""))) for l in lines]
    total = sum(weights)
    out, t = [], LEAD
    for line, w in zip(lines, weights):
        dur = span * w / total
        out.append({"text": line, "start": t, "end": t + dur})
        t += dur
    return out


def _from_markers(lines: list[str], markers: list[dict]) -> list[dict]:
    """Pair the lyric lines with real timing markers when the clip has them."""
    out = []
    for line, mk in zip(lines, markers):
        out.append({"text": line,
                    "start": float(mk["start"]), "end": float(mk["end"])})
    return out


def build_ass(timed: list[dict], meta: dict, duration: float) -> str:
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Lyric,{FONT},66,{PRIMARY},{SECONDARY},{OUTLINE},{BACK},0,0,0,0,100,100,0.5,0,1,4,2,2,140,140,130,1
Style: Title,{FONT},104,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,5,3,5,140,140,0,1
Style: Tag,{FONT},34,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,0,0,0,0,100,100,2,0,1,3,2,2,140,140,90,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events: list[str] = []
    first = timed[0]["start"] if timed else LEAD
    title = _escape(meta.get("title", ""))
    sub = _escape(meta.get("subtitle", ""))
    end_card = _ts(max(0.5, first - 0.3))
    events.append(f"Dialogue: 0,{_ts(0.4)},{end_card},Title,,0,0,0,,"
                  f"{{\\fad(500,600)}}{title}")
    if sub:
        events.append(f"Dialogue: 0,{_ts(0.4)},{end_card},Tag,,0,0,0,,"
                      f"{{\\fad(500,600)}}{sub}")

    for item in timed:
        start, end, line = item["start"], item["end"], item["text"]
        words = _words(line)
        weights = [max(1, len(w.replace(" ", ""))) for w in words]
        total = sum(weights)
        parts = []
        for w, wt in zip(words, weights):
            cs = max(1, int(round((end - start) * 100 * wt / total)))
            parts.append(f"{{\\kf{cs}}}{_escape(w)}")
        events.append(f"Dialogue: 0,{_ts(start)},{_ts(end + 0.25)},Lyric,,0,0,0,,"
                      f"{{\\fad(120,160)}}{''.join(parts)}")

    # Closing card so the video does not just stop on the last lyric.
    if duration > TAIL + 2:
        events.append(f"Dialogue: 0,{_ts(duration - TAIL + 1)},{_ts(duration - 0.5)},"
                      f"Tag,,0,0,0,,{{\\fad(400,600)}}ขอบคุณที่รับฟัง")

    return head + "\n".join(events) + "\n"


def _ass_escape(p: Path) -> str:
    return str(p).replace("\\", "\\\\").replace(":", "\\:")


def render(slug: str, *, preview: float | None = None,
           timing: Path | None = None) -> Path:
    kara = ROOT / "library" / "songs" / f"karaoke-{slug}.mp3"
    cover = ROOT / "library" / "covers" / f"cover-{slug}.jpg"
    for p in (kara, cover):
        if not p.exists():
            raise FileNotFoundError(f"missing {p}; run flow_song.py first")

    meta, lines = load_lyrics(slug)
    duration = _duration(kara)
    if timing and timing.exists():
        markers = json.loads(timing.read_text(encoding="utf-8")).get("markers") or []
        timed = _from_markers(lines, markers) if markers else estimate(lines, duration)
    else:
        timed = estimate(lines, duration)

    work = ROOT / "work" / slug
    work.mkdir(parents=True, exist_ok=True)
    ass_path = work / "karaoke.ass"
    ass_path.write_text(build_ass(timed, meta, duration), encoding="utf-8")

    out = ROOT / "library" / "karaoke" / f"karaoke-{slug}.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)

    zoom = ("scale=2400:-1,zoompan=z='min(zoom+0.00035,1.18)':d=1:"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=%dx%d:fps=%d" % (W, H, FPS))
    args = ["-loop", "1", "-i", str(cover), "-i", str(kara),
            "-filter_complex", f"[0:v]{zoom},ass={_ass_escape(ass_path)}[v]",
            "-map", "[v]", "-map", "1:a",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "192k", "-shortest"]
    if preview:
        args += ["-t", str(preview)]
    args += ["-movflags", "+faststart", str(out)]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("slug")
    ap.add_argument("--preview", type=float, default=None,
                    help="render only the first N seconds")
    ap.add_argument("--timing", type=Path, default=None,
                    help="JSON with real markers from the clip's lyrics_timing")
    args = ap.parse_args()
    print(render(args.slug, preview=args.preview, timing=args.timing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
