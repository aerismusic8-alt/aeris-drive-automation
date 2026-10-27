"""Build a karaoke subtitle track (ASS) from narration timing.

Thai has no spaces between words, so the highlight unit cannot be "the word
between spaces". Each line is segmented with pythainlp and the line's measured
duration is split across the segments in proportion to their character count.
The result is an \\k-timed ASS file that ffmpeg can burn in with libass, which is
what makes the subtitles follow the voice instead of appearing per line.
"""
from __future__ import annotations

import json
from pathlib import Path

from pythainlp.tokenize import word_tokenize

ASS_HEADER = """[Script Info]
ScriptType: v4.00+
PlayResX: {w}
PlayResY: {h}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Karaoke,{font},{size},&H00FFFFFF,&H0000D7FF,&H00202020,&H80000000,-1,0,0,0,100,100,0,0,1,{outline},1,2,{ml},{mr},{mv},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def _ts(seconds: float) -> str:
    seconds = max(0.0, seconds)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    return f"{h:d}:{m:02d}:{s:05.2f}"


def segment(line: str) -> list[str]:
    """Split a Thai line into highlight units."""
    parts = [p for p in word_tokenize(line, keep_whitespace=True) if p]
    return parts or [line]


def _split_duration(parts: list[str], total: float) -> list[float]:
    """Divide a line's duration across segments by character weight."""
    weights = [max(1, len(p.strip())) for p in parts]
    scale = total / sum(weights) if sum(weights) else 0.0
    return [w * scale for w in weights]


def build_ass(timing: dict, out_path: Path, *, width: int = 1920, height: int = 1080,
              font: str = "Noto Sans Thai", size: int = 54, outline: int = 3,
              margin_v: int = 90, tail: float = 0.35) -> dict:
    """Write an ASS karaoke file. Returns a small report of what was written."""
    lines = timing.get("lines") or []
    cues = []
    skipped = []
    for item in lines:
        start, end = item.get("start"), item.get("end")
        text = (item.get("text") or "").strip()
        if start is None or end is None or not text:
            skipped.append(text)
            continue
        if end <= start:
            end = start + 0.5
        parts = segment(text)
        spans = _split_duration(parts, end - start)
        body = "".join(f"{{\\k{max(1, round(sp * 100))}}}{p}" for p, sp in zip(parts, spans))
        cues.append((start, end + tail, body))

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(ASS_HEADER.format(w=width, h=height, font=font, size=size,
                                   outline=outline, ml=120, mr=120, mv=margin_v))
        for start, end, body in cues:
            fh.write(f"Dialogue: 0,{_ts(start)},{_ts(end)},Karaoke,,0,0,0,,{body}\n")

    return {
        "ass": str(out_path),
        "cues": len(cues),
        "skipped_lines": skipped,
        "duration_seconds": timing.get("duration_seconds"),
    }


def from_timing_file(timing_path: Path, out_path: Path, **kwargs) -> dict:
    timing = json.loads(Path(timing_path).read_text(encoding="utf-8"))
    return build_ass(timing, out_path, **kwargs)
