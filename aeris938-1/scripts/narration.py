"""Thai narration synthesis with edge-tts, plus the timing needed for karaoke.

edge-tts fails intermittently with NoAudioReceived for perfectly good text, so
every line is retried. Timing comes from the boundary events the Thai voices
emit; the per-line boundaries are the only reliable clock, and the per-character
offsets let a karaoke track be built without a second pass.
"""
from __future__ import annotations

import asyncio
import json
import subprocess
from pathlib import Path

import edge_tts

from thai_text import prepare, script_lines

VOICE_MALE = "th-TH-NiwatNeural"
VOICE_FEMALE = "th-TH-PremwadeeNeural"
DEFAULT_RATE = "-8%"
MAX_ATTEMPTS = 4


def _mp3_duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(out.stdout.strip())


async def _synth_once(text: str, out_path: Path, voice: str, rate: str) -> list[dict]:
    comm = edge_tts.Communicate(text, voice, rate=rate)
    boundaries: list[dict] = []
    audio = bytearray()
    async for chunk in comm.stream():
        if chunk["type"] == "audio":
            audio.extend(chunk["data"])
        elif chunk["type"] in ("SentenceBoundary", "WordBoundary"):
            boundaries.append({
                "type": chunk["type"],
                "offset": chunk["offset"] / 10_000_000,
                "duration": chunk["duration"] / 10_000_000,
                "text": chunk.get("text", ""),
            })
    if not audio:
        raise RuntimeError("NoAudioReceived")
    out_path.write_bytes(bytes(audio))
    return boundaries


async def _synth_retry(text: str, out_path: Path, voice: str, rate: str) -> list[dict]:
    last: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            return await _synth_once(text, out_path, voice, rate)
        except Exception as exc:  # noqa: BLE001 - retried by design
            last = exc
            if attempt < MAX_ATTEMPTS:
                await asyncio.sleep(2 + 3 * attempt)
    raise RuntimeError(f"edge-tts failed after {MAX_ATTEMPTS} attempts: {last}")


def _map_lines(boundaries: list[dict], lines: list[str]) -> list[dict]:
    """Attach each script line to the boundary that spoke it.

    A boundary may cover a clause and a line may be split across boundaries, so
    walk the concatenated boundary text and consume each line from it in order.
    That stays stable even when the voice merges two short lines into one event.
    """
    joined = ""
    spans: list[tuple[int, int, dict]] = []
    for b in boundaries:
        start = len(joined)
        joined += b["text"]
        spans.append((start, len(joined), b))

    out: list[dict] = []
    cursor = 0
    for line in lines:
        needle = line.strip()
        if not needle:
            continue
        idx = joined.find(needle, cursor)
        if idx < 0:
            idx = joined.find(needle)
        if idx < 0:
            out.append({"text": line, "start": None, "end": None, "matched": False})
            continue
        end = idx + len(needle)
        cursor = end
        hit = [b for (s, e, b) in spans if s < end and e > idx]
        if hit:
            start_t = hit[0]["offset"]
            end_t = hit[-1]["offset"] + hit[-1]["duration"]
        else:
            start_t = end_t = None
        out.append({
            "text": line,
            "start": start_t,
            "end": end_t,
            "matched": start_t is not None,
        })
    return out


def narrate(script_text: str, out_dir: Path, voice: str = VOICE_MALE,
            rate: str = DEFAULT_RATE, name: str = "narration") -> dict:
    """Synthesise a script to audio + timing.json. Returns the timing payload."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    audio_path = out_dir / f"{name}.mp3"
    timing_path = out_dir / f"{name}.timing.json"

    prepared = prepare(script_text)
    lines = script_lines(prepared)
    if not lines:
        raise ValueError("script has no speakable lines")

    boundaries = asyncio.run(_synth_retry(prepared, audio_path, voice, rate))
    duration = _mp3_duration(audio_path)
    mapped = _map_lines(boundaries, lines)

    matched = sum(1 for m in mapped if m["matched"])
    payload = {
        "name": name,
        "voice": voice,
        "rate": rate,
        "audio": audio_path.name,
        "duration_seconds": round(duration, 3),
        "line_count": len(mapped),
        "matched_lines": matched,
        "unmatched_lines": [m["text"] for m in mapped if not m["matched"]],
        "lines": mapped,
        "prepared_text": prepared,
    }
    timing_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return payload
