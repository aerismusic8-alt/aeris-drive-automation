#!/usr/bin/env python3
"""Read the words of a hit song and measure the lyric craft.

K (2026-11-23): "จับเรื่องเนื้อหาการแต่งเนื้อเพลง พยางค์ที่ใช้ อันนี้สำคัญ ช่วงฮุค
จังหวะริฟ" — syllables per line, where the hook lands, and the riff.

Counting syllables from the mix does not work: an energy envelope over the
250-3500 Hz band is dominated by the instruments, so `lyric_shape.py` reports
hundreds of "syllables" per phrase on real masters. What works is the words.
This transcribes them locally with faster-whisper (free, CPU, no API key), then
counts Thai syllables exactly with pythainlp's syllable tokenizer.

Accuracy, stated plainly: singing degrades ASR. `small` gets the gist and the
line lengths roughly right (a 10-syllable line lands at 9-12), and it mangles
words. So use this for *shape* — syllables per line, how often a line repeats,
where the repeated lines start — and never as a lyric source. For an exact
rhyme reading, feed the real lyric text with `--text`.

    python3 ops/lyric_text.py --dir work/refs --limit 3 --out work/lyric-text.json
    python3 ops/lyric_text.py --text song.txt          # no ASR, exact counts
"""
from __future__ import annotations

import argparse
import json
import re
import statistics as st
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference_profile import AUDIO_EXT, ffmpeg  # noqa: E402

THAI = re.compile(r"[\u0E00-\u0E7F]")


def syllables(line: str) -> int:
    from pythainlp.tokenize import syllable_tokenize
    text = "".join(ch for ch in line if THAI.match(ch) or ch.isspace()).strip()
    if not text:
        return 0
    return len([s for s in syllable_tokenize(text) if s.strip()])


def transcribe(path: Path, model_size: str = "small") -> list[dict]:
    import subprocess

    import numpy as np
    from faster_whisper import WhisperModel

    # faster-whisper's own decoder needs a newer PyAV than this image has, so the
    # audio is decoded here and handed over as a float32 buffer.
    raw = subprocess.run([ffmpeg(), "-v", "error", "-i", str(path), "-ac", "1",
                          "-ar", "16000", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    audio = np.frombuffer(raw, dtype=np.float32)
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    segs, _ = model.transcribe(audio, language="th", vad_filter=False, beam_size=1)
    return [{"start": round(s.start, 1), "end": round(s.end, 1), "text": s.text.strip()}
            for s in segs if s.text.strip()]


def shape(lines: list[str]) -> dict:
    counts = [syllables(t) for t in lines]
    counts = [c for c in counts if c]
    if not counts:
        return {"lines": 0}
    norm = [re.sub(r"\s+", "", t) for t in lines if t.strip()]
    repeats = {}
    for t in norm:
        if len(t) >= 8:
            repeats[t] = repeats.get(t, 0) + 1
    top = sorted(repeats.items(), key=lambda kv: -kv[1])[:3]
    endings = {}
    for t in norm:
        if len(t) >= 4:
            endings[t[-2:]] = endings.get(t[-2:], 0) + 1
    return {
        "lines": len(counts),
        "syllables_median": int(st.median(counts)),
        "syllables_mode": st.mode(counts),
        "syllables_p10_p90": [int(sorted(counts)[len(counts) // 10]),
                              int(sorted(counts)[min(len(counts) - 1, len(counts) * 9 // 10)])],
        "repeated_lines": [{"line": t[:40], "times": n} for t, n in top if n > 1],
        "line_end_sounds": sorted(endings.items(), key=lambda kv: -kv[1])[:5],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--text", help="a lyric file: exact counts, no ASR")
    ap.add_argument("--model", default="small")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out")
    args = ap.parse_args()

    if args.text:
        lines = [ln.strip() for ln in Path(args.text).read_text(encoding="utf-8").splitlines()
                 if ln.strip()]
        print(json.dumps(shape(lines), ensure_ascii=False, indent=2))
        return 0

    files = [Path(f) for f in args.file]
    if args.dir:
        files += sorted(p for p in Path(args.dir).rglob("*") if p.suffix.lower() in AUDIO_EXT)
    if args.limit:
        files = files[:args.limit]
    if not files:
        raise SystemExit("nothing to transcribe")

    rows = []
    for p in files:
        segs = transcribe(p, args.model)
        s = shape([g["text"] for g in segs])
        s.update({"file": p.name, "model": args.model, "segments": segs})
        rows.append(s)
        print(f"  {s.get('syllables_median', 0):3d} syl/line (mode {s.get('syllables_mode', 0):2d}, "
              f"{s.get('lines', 0):3d} lines, repeated {len(s.get('repeated_lines', []))})  "
              f"{p.name[:44]}")
        sys.stdout.flush()

    if args.out and rows:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"songs": rows}, ensure_ascii=False, indent=2), encoding="utf-8")
        print("written:", out)
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
